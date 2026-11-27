-- Test suite for `lib/poll`, `lib/net`, async `lib/proc` (`proc.spawn`),
-- `lib/task` cooperative coroutines, `laws.state_machine` poller model,
-- and standalone `luam check` + `luam build` (`with = {"poll", "net", "proc"}`).

const ext = require("external_tool")
const git = require("git")
const laws = require("laws")
const lfs = require("lfs")
const net = require("net")
const paths = require("paths")
const poll = require("poll")
const proc = require("proc")
const t = require("test")
const task = require("task")

tmp_dir = os.tmpname()
os.remove(tmp_dir)
paths.ensure_dir(tmp_dir)

-- ---- 1. Procedural handle isolation & idempotent close ----
t.run("procedural_handle_safety", function()
    p = poll.open()
    t.check(p != nil, "poll.open returns handle")
    t.throws(function()
        _ = p.wait
    end, nil, "poller userdata has no __index")

    srv, err_s = net.listen_tcp("127.0.0.1", 0, {nonblocking = true})
    t.eq(err_s, nil, "listen_tcp err nil")
    t.throws(function()
        _ = srv.accept
    end, nil, "net.sock userdata has no __index")
    t.throws(function()
        net.local_port(p)
    end, nil, "net rejects foreign userdata")

    t.eq(poll.close(p), true, "poll.close 1")
    t.eq(poll.close(p), true, "poll.close 2 idempotent")
    t.throws(function()
        poll.wait(p, 0)
    end, "closed", "closed poller raises")

    t.eq(net.close(srv), true, "net.close 1")
    t.eq(net.close(srv), true, "net.close 2 idempotent")
    t.throws(function()
        net.local_port(srv)
    end, "closed", "closed socket raises")
end)

-- ---- 2. TCP loopback, non-blocking accept, binary NUL streaming & SIGPIPE immunity ----
t.run("tcp_and_sigpipe", function()
    srv, err = net.listen_tcp("127.0.0.1", 0, {nonblocking = true})
    t.eq(err, nil, "tcp listen ok")
    port = net.local_port(srv)
    t.check(type(port) == "number" and port > 0, "ephemeral TCP port > 0")

    c_none, why_none = net.accept(srv)
    t.eq(c_none, nil, "nonblocking accept idle returns nil")
    t.eq(why_none, "again", "nonblocking accept idle returns 'again'")

    cli, err_c = net.connect_tcp("127.0.0.1", port, 1000)
    t.eq(err_c, nil, "tcp connect ok")
    t.eq(net.set_nonblocking(cli, true), true, "cli set_nonblocking")

    p = poll.open()
    t.eq(poll.add(p, net.fd(srv), "r"), true, "poll.add srv")
    evs = poll.wait(p, 500)
    t.eq(#evs, 1, "srv ready to accept")
    peer_conn, peer_addr = net.accept(srv)
    t.check(peer_conn != nil, "accepted peer connection")
    t.check(string.starts_with(peer_addr, "127.0.0.1:"), "peer address formatted: " .. tostring(peer_addr))

    -- 128 KB binary payload with NUL bytes multiplexed via poll
    raw_parts = {}
    for i = 0, 255 do
        raw_parts[i + 1] = string.char(i)
    end
    payload = string.rep(table.concat(raw_parts), 512)
    t.eq(#payload, 131072, "128 KB payload")

    cli_fd = net.fd(cli)
    peer_fd = net.fd(peer_conn)
    t.eq(poll.del(p, net.fd(srv)), true, "poll.del srv")
    t.eq(poll.add(p, cli_fd, "w"), true, "poll.add cli w")
    t.eq(poll.add(p, peer_fd, "r"), true, "poll.add peer r")

    sent = 0
    recvd = {}
    recvd_len = 0
    peer_eof = false

    while not peer_eof do
        ready = poll.wait(p, 1000)
        t.check(#ready > 0, "poll progressed during 128 KB transfer")
        for _, ev in ipairs(ready) do
            if ev.fd == cli_fd and ev.w and sent < #payload then
                nw, werr = net.write(cli, payload, sent + 1)
                t.eq(werr, nil, "net.write error nil")
                sent = sent + nw
                if sent >= #payload then
                    poll.del(p, cli_fd)
                    net.close(cli)
                end
            elseif ev.fd == peer_fd and (ev.r or ev.hup) then
                chunk, eof = net.read(peer_conn, 16384)
                if #chunk > 0 then
                    table.insert(recvd, chunk)
                    recvd_len = recvd_len + #chunk
                end
                if eof then
                    peer_eof = true
                end
            end
        end
    end

    t.eq(recvd_len, #payload, "received all 128 KB")
    t.eq(table.concat(recvd) == payload, true, "binary NUL payload intact")

    -- Writing to peer_conn after cli closed and RST/FIN settles must return error, never SIGPIPE crash
    c2, _ = net.connect_tcp("127.0.0.1", port, 500)
    s2, _ = net.accept(srv)
    net.close(c2)
    os.sleep(15)
    saw_err = false
    for _ = 1, 20 do
        nw, werr = net.write(s2, string.rep("X", 32768))
        if nw == nil and werr != nil then
            saw_err = true
            break
        end
        os.sleep(5)
    end
    t.eq(saw_err, true, "writing to closed peer surfaces error without SIGPIPE death")

    net.close(s2)
    net.close(peer_conn)
    net.close(srv)
    poll.close(p)
end)

-- ---- 3. AF_UNIX domain sockets & regular-file safety guard ----
t.run("af_unix_sockets", function()
    reg_file = paths.joinpath(tmp_dir, "not_a_socket.txt")
    paths.write_file(reg_file, "precious data")

    bad_srv, bad_err = net.listen_unix(reg_file)
    t.eq(bad_srv, nil, "listen_unix refuses to unlink regular file")
    t.check(string.contains(tostring(bad_err), "not a socket"), "regular file guard message")
    t.eq(paths.read_file(reg_file), "precious data", "regular file untouched")

    sock_path = paths.joinpath(tmp_dir, "warden_test.sock")
    u_srv, u_err = net.listen_unix(sock_path, {mode = 384}) -- 0600
    t.eq(u_err, nil, "listen_unix 1 ok")
    net.close(u_srv)

    -- Re-binding over stale socket inode succeeds automatically
    u_srv2, u_err2 = net.listen_unix(sock_path, {nonblocking = false})
    t.eq(u_err2, nil, "listen_unix unlinks stale socket inode cleanly")

    u_cli, uc_err = net.connect_unix(sock_path, 500)
    t.eq(uc_err, nil, "connect_unix ok")
    u_peer, u_peer_kind = net.accept(u_srv2)
    t.eq(u_peer_kind, "unix", "unix peer label")

    nw, _ = net.write(u_cli, "ping\x00warden")
    t.eq(nw, 11, "unix write")
    net.close(u_cli)

    msg, eof = net.read(u_peer, 64)
    t.eq(msg, "ping\x00warden", "unix read payload")
    t.eq(eof, false, "first read before EOF")
    msg2, eof2 = net.read(u_peer, 64)
    t.eq(msg2, "", "second read empty")
    t.eq(eof2, true, "second read reports EOF")

    net.close(u_peer)
    net.close(u_srv2)
    os.remove(sock_path)
end)

-- ---- 4. proc.spawn streaming, CLOEXEC sibling isolation, new_pgid kill, and signalfd ----
t.run("proc_spawn_and_signals", function()
    bad_ch, bad_err = proc.spawn({"/nonexistent/warden_missing_bin"})
    t.eq(bad_ch, nil, "missing binary returns nil")
    t.check(bad_err != nil and #bad_err > 0, "missing binary returns error string")

    -- Open signalfd BEFORE spawning children so CHLD and USR1 are captured
    sig_h, sig_err = poll.signal_open({"USR1", "CHLD"})
    t.eq(sig_err, nil, "signal_open ok")

    -- Send SIGUSR1 to our own PID via sh $PPID
    ok_usr1, _, _ = proc.run({"sh", "-c", "kill -USR1 $PPID"})
    t.eq(ok_usr1, true, "sent USR1 to parent")

    seen_usr1 = false
    seen_chld = false
    for _ = 1, 10 do
        sname = poll.signal_read(sig_h)
        if sname == nil then
            break
        end
        if sname == "USR1" then
            seen_usr1 = true
        elseif sname == "CHLD" then
            seen_chld = true
        end
    end
    t.eq(seen_usr1, true, "signalfd delivered USR1")
    t.eq(seen_chld, true, "signalfd delivered CHLD")

    -- Sibling CLOEXEC test: child1 (`cat`) must hit stdin EOF even while child2 (`sleep 10`) runs
    ch1, e1 = proc.spawn({"cat"}, {stdin_pipe = true, stdout_pipe = true, stderr_pipe = false})
    t.eq(e1, nil, "spawn cat ok")
    ch2, e2 = proc.spawn({"sleep", "10"}, {stdout_pipe = false, stderr_pipe = false, new_pgid = true})
    t.eq(e2, nil, "spawn sleep ok")

    st_run = proc.wait(ch1, true)
    t.eq(st_run.done, false, "cat initially running")

    nw_in, _ = proc.write(ch1, "hello-async-proc")
    t.eq(nw_in, 16, "proc.write to cat")
    t.eq(proc.close_stdin(ch1), true, "close_stdin on ch1")

    -- Read ch1 stdout via poll without hanging on ch2
    p = poll.open()
    ch1_out_fd = proc.stdout_fd(ch1)
    poll.add(p, ch1_out_fd, "r")
    out_chunks = {}
    got_eof = false
    deadline = os.clock_ms() + 1500
    while not got_eof and os.clock_ms() < deadline do
        evs = poll.wait(p, 200)
        for _, ev in ipairs(evs) do
            if ev.fd == ch1_out_fd then
                chunk, eof = proc.read(ch1, "stdout", 4096)
                if #chunk > 0 then
                    table.insert(out_chunks, chunk)
                end
                if eof then
                    got_eof = true
                end
            end
        end
    end
    t.eq(got_eof, true, "ch1 reached EOF without sibling fd leak")
    t.eq(table.concat(out_chunks), "hello-async-proc", "ch1 echoed exact bytes")

    w1 = proc.wait(ch1, false)
    t.eq(w1.done, true, "ch1 wait done")
    t.eq(w1.ok, true, "ch1 exit ok")
    t.eq(w1.why, "exit", "ch1 why=exit")
    t.eq(w1.code, 0, "ch1 code=0")

    -- Idempotent second wait returns cached status
    w1_again = proc.wait(ch1, true)
    t.eq(w1_again, w1, "second proc.wait returns cached status")
    poll.del(p, ch1_out_fd)
    proc.close(ch1)

    -- Process-group kill: shell spawns a grandchild holding a write pipe; group TERM kills both
    pg_ch, pg_err = proc.spawn({"sh", "-c", "sleep 30 & wait"}, {
        stdout_pipe = true,
        stderr_pipe = false,
        new_pgid = true,
    })
    t.eq(pg_err, nil, "spawn pgid leader ok")
    os.sleep(30)
    t.eq(proc.kill(pg_ch, "TERM", true), true, "group SIGTERM sent")
    w_pg = proc.wait(pg_ch, false)
    t.eq(w_pg.done, true, "pgid leader reaped")
    t.eq(w_pg.ok, false, "killed process ok=false")

    -- Because the grandchild in the same pgid also died, stdout pipe hits EOF immediately!
    poll.add(p, proc.stdout_fd(pg_ch), "r")
    evs_pg = poll.wait(p, 500)
    t.check(#evs_pg == 1, "grandchild pipe closed on group kill")
    _, pg_eof = proc.read(pg_ch, "stdout", 64)
    t.eq(pg_eof, true, "grandchild pipe reports EOF")

    proc.kill(ch2, "KILL", true)
    proc.wait(ch2, false)
    proc.close(ch2)
    proc.close(pg_ch)
    poll.close(p)
    poll.signal_close(sig_h)
end)

-- ---- 5. lib/task cooperative coroutine scheduler (full-duplex TCP + timeouts) ----
t.run("task_coroutine_scheduler", function()
    loop = task.new()
    srv, _ = net.listen_tcp("127.0.0.1", 0, {nonblocking = true})
    port = net.local_port(srv)

    results = {}
    N_CLIENTS = 4

    -- Server coroutine accepting N_CLIENTS and spawning per-connection echo handlers
    task.spawn(loop, function()
        accepted = 0
        while accepted < N_CLIENTS do
            conn, why = net.accept(srv)
            if conn != nil then
                accepted = accepted + 1
                task.spawn(loop, function(c)
                    buf = {}
                    while true do
                        chunk, eof = net.read(c, 4096)
                        if #chunk > 0 then
                            table.insert(buf, chunk)
                        elseif eof then
                            break
                        else
                            task.wait_fd(net.fd(c), "r", 1000)
                        end
                    end
                    reply = "ECHO:" .. table.concat(buf)
                    pos = 1
                    while pos <= #reply do
                        nw, werr = net.write(c, reply, pos)
                        if nw == nil then
                            error(werr)
                        end
                        if nw > 0 then
                            pos = pos + nw
                        else
                            task.wait_fd(net.fd(c), "w", 1000)
                        end
                    end
                    net.close(c)
                end, conn)
            elseif why == "again" then
                task.wait_fd(net.fd(srv), "r", 1000)
            else
                error(why)
            end
        end
        net.close(srv)
    end)

    for i = 1, N_CLIENTS do
        task.spawn(loop, function(idx)
            task.sleep_ms((idx % 3) * 5)
            c, cerr = net.connect_tcp("127.0.0.1", port, 1000)
            t.eq(cerr, nil, "client connect " .. tostring(idx))
            net.set_nonblocking(c, true)

            msg = "client-" .. tostring(idx) .. "-payload"
            pos = 1
            while pos <= #msg do
                nw, _ = net.write(c, msg, pos)
                if nw > 0 then
                    pos = pos + nw
                else
                    task.wait_fd(net.fd(c), "w", 1000)
                end
            end
            -- Half-close not exposed yet; instead test wait_fd timeout on unread socket, then send marker?
            -- Wait: server reads until EOF, so let's test wait_fd timeout on a separate idle socket below!
            -- Wait: TCP client closing closes both directions! Let's check!
            net.close(c)
            results[idx] = "sent"
        end, i)
    end

    -- Also spawn a coroutine testing task.wait_fd timeout expiry
    timeout_observed = false
    idle_srv, _ = net.listen_tcp("127.0.0.1", 0, {nonblocking = true})
    task.spawn(loop, function()
        ev, reason = task.wait_fd(net.fd(idle_srv), "r", 20)
        if ev == nil and reason == "timeout" then
            timeout_observed = true
        end
        net.close(idle_srv)
    end)

    t.eq(task.run(loop), true, "task.run drained all coroutines")
    t.eq(task.active_count(loop), 0, "zero active tasks remaining")
    t.eq(timeout_observed, true, "task.wait_fd timeout fired cleanly")
    for i = 1, N_CLIENTS do
        t.eq(results[i], "sent", "client " .. tostring(i) .. " completed")
    end
    task.close(loop)

    -- Full bidirectional framing over task coroutines (length-prefixed request/response)
    loop2 = task.new()
    srv2, _ = net.listen_tcp("127.0.0.1", 0, {nonblocking = true})
    port2 = net.local_port(srv2)

    task.spawn(loop2, function()
        while true do
            c, why = net.accept(srv2)
            if c != nil then
                got = ""
                while #got < 4 do
                    ch, eof = net.read(c, 4 - #got)
                    if #ch > 0 then
                        got = got .. ch
                    elseif eof then
                        break
                    else
                        task.wait_fd(net.fd(c), "r", 1000)
                    end
                end
                net.write(c, string.upper(got))
                net.close(c)
                break
            elseif why == "again" then
                task.wait_fd(net.fd(srv2), "r", 1000)
            end
        end
        net.close(srv2)
    end)

    echo_reply = nil
    task.spawn(loop2, function()
        c, _ = net.connect_tcp("127.0.0.1", port2, 1000)
        net.set_nonblocking(c, true)
        -- Concurrent reader & writer coroutines sharing the SAME socket fd!
        task.spawn(loop2, function()
            task.sleep_ms(5)
            net.write(c, "luam")
        end)
        chunks = {}
        while true do
            ch, eof = net.read(c, 64)
            if #ch > 0 then
                table.insert(chunks, ch)
            elseif eof then
                break
            else
                task.wait_fd(net.fd(c), "r", 1000)
            end
        end
        echo_reply = table.concat(chunks)
        net.close(c)
    end)

    task.run(loop2)
    t.eq(echo_reply, "LUAM", "full-duplex shared-fd coroutines exchanged request & reply")
    task.close(loop2)
end)

-- ---- 6. laws.state_machine verification of poll registration & readiness ----
t.run("laws_poll_state_machine", function()
    POOL_N = 4

    function sm_init()
        p = poll.open()
        socks = {}
        peers = {}
        srv, _ = net.listen_tcp("127.0.0.1", 0, {nonblocking = false})
        port = net.local_port(srv)
        for i = 1, POOL_N do
            c, _ = net.connect_tcp("127.0.0.1", port, 500)
            s, _ = net.accept(srv)
            net.set_nonblocking(c, true)
            net.set_nonblocking(s, true)
            socks[i] = c
            peers[i] = s
        end
        net.close(srv)
        sut = {poller = p, socks = socks, peers = peers}
        model = {reg = {}, has_data = {}}
        for i = 1, POOL_N do
            model.has_data[i] = false
        end
        return sut, model
    end

    function sm_teardown(sut)
        poll.close(sut.poller)
        for i = 1, POOL_N do
            net.close(sut.socks[i])
            net.close(sut.peers[i])
        end
    end

    idx_and_mode = laws.tuple(laws.int(1, POOL_N), laws.one_of({"r", "w", "rw"}))

    laws.state_machine({
        name = "poll_fd_registry_and_readiness",
        trials = 40,
        max_steps = 30,
        init = sm_init,
        teardown = sm_teardown,
        commands = {
            {
                name = "add",
                args = function(_) return idx_and_mode end,
                run = function(sut, pair)
                    idx = pair[1]
                    mode = pair[2]
                    ok, _ = poll.add(sut.poller, net.fd(sut.socks[idx]), mode)
                    return ok == true
                end,
                next_model = function(m, pair, res)
                    idx = pair[1]
                    mode = pair[2]
                    if m.reg[idx] == nil then
                        assert(res == true, "poll.add must succeed for unregistered fd")
                        m.reg[idx] = mode
                    else
                        assert(res == false, "poll.add must reject duplicate fd")
                    end
                end,
            },
            {
                name = "mod",
                args = function(_) return idx_and_mode end,
                run = function(sut, pair)
                    ok, _ = poll.mod(sut.poller, net.fd(sut.socks[pair[1]]), pair[2])
                    return ok == true
                end,
                next_model = function(m, pair, res)
                    idx = pair[1]
                    if m.reg[idx] != nil then
                        assert(res == true, "poll.mod must succeed for registered fd")
                        m.reg[idx] = pair[2]
                    else
                        assert(res == false, "poll.mod must reject unregistered fd")
                    end
                end,
            },
            {
                name = "del",
                args = function(_) return laws.int(1, POOL_N) end,
                run = function(sut, idx)
                    ok, _ = poll.del(sut.poller, net.fd(sut.socks[idx]))
                    return ok == true
                end,
                next_model = function(m, idx, res)
                    if m.reg[idx] != nil then
                        assert(res == true, "poll.del must succeed for registered fd")
                        m.reg[idx] = nil
                    else
                        assert(res == false, "poll.del must reject unregistered fd")
                    end
                end,
            },
            {
                name = "produce_byte",
                args = function(_) return laws.int(1, POOL_N) end,
                run = function(sut, idx)
                    nw, _ = net.write(sut.peers[idx], "x")
                    return nw == 1
                end,
                next_model = function(m, idx, res)
                    if res then
                        m.has_data[idx] = true
                    end
                end,
            },
            {
                name = "drain_sock",
                args = function(_) return laws.int(1, POOL_N) end,
                run = function(sut, idx)
                    while true do
                        ch, _ = net.read(sut.socks[idx], 1024)
                        if #ch == 0 then
                            break
                        end
                    end
                end,
                next_model = function(m, idx, _)
                    m.has_data[idx] = false
                end,
            },
        },
        invariants = {
            {
                name = "poll_wait_matches_registered_read_write_state",
                check = function(sut, m)
                    evs, err = poll.wait(sut.poller, 0)
                    if evs == nil then
                        return false, "poll.wait error: " .. tostring(err)
                    end
                    by_fd = {}
                    for _, ev in ipairs(evs) do
                        if by_fd[ev.fd] != nil then
                            return false, "duplicate fd in poll.wait output"
                        end
                        by_fd[ev.fd] = ev
                    end
                    for i = 1, POOL_N do
                        fd = net.fd(sut.socks[i])
                        mode = m.reg[i]
                        ev = by_fd[fd]
                        if mode == nil then
                            if ev != nil then
                                return false, "unregistered fd reported by poll.wait"
                            end
                        else
                            want_w = string.contains(mode, "w")
                            want_r = string.contains(mode, "r")
                            if want_w and (ev == nil or not ev.w) then
                                return false, "registered 'w' socket with empty sendbuf not reported writable"
                            end
                            if want_r and m.has_data[i] and (ev == nil or not ev.r) then
                                return false, "registered 'r' socket with queued bytes not reported readable"
                            end
                            if want_r and not m.has_data[i] and ev != nil and ev.r then
                                return false, "drained socket falsely reported readable"
                            end
                        end
                    end
                    return true
                end,
            },
        },
    })
    t.check(true, "laws.state_machine poll model passed")
end)

-- ---- 7. Standalone `luam check` + `luam build` (`with = {"poll", "net", "proc", "lfs"}`) ----
t.run("static_build_with_poll_net_proc", function()
    luam_root = package.luam_root
    if luam_root == nil or luam_root == "" then
        luam_root = lfs.currentdir()
    end
    luam_bin = paths.joinpath(luam_root, "bin", "luam")
    luam_head = git.rev_parse("HEAD", luam_root)

    proj_dir = paths.joinpath(tmp_dir, "io_static_proj")
    paths.ensure_dir(paths.joinpath(proj_dir, "src"))
    paths.ensure_dir(paths.joinpath(proj_dir, "bld"))

    paths.write_file(paths.joinpath(proj_dir, "bld", "package.lua"), string.format("""
return {
    bin = "io_app",
    entry = "main.lua",
    luam = %q,
    with = {"lfs", "poll", "net", "proc"},
}
""", luam_head))

    paths.write_file(paths.joinpath(proj_dir, "src", "main.lua"), """
const net = require("net")
const poll = require("poll")
const proc = require("proc")
const task = require("task")

loop = task.new()
srv, err = net.listen_tcp("127.0.0.1", 0, {nonblocking = true})
if srv == nil then error(err) end
port = net.local_port(srv)

got = nil
task.spawn(loop, function()
    while true do
        c, why = net.accept(srv)
        if c != nil then
            ch, _ = net.read(c, 32)
            while #ch == 0 do
                task.wait_fd(net.fd(c), "r", 500)
                ch, _ = net.read(c, 32)
            end
            got = ch
            net.close(c)
            break
        elseif why == "again" then
            task.wait_fd(net.fd(srv), "r", 500)
        end
    end
    net.close(srv)
end)

task.spawn(loop, function()
    ch_proc, _ = proc.spawn({"printf", "STATIC_OK"})
    while proc.wait(ch_proc, true).done == false do
        task.sleep_ms(5)
    end
    msg, _ = proc.read(ch_proc, "stdout", 64)
    proc.close(ch_proc)

    cli, _ = net.connect_tcp("127.0.0.1", port, 500)
    net.write(cli, msg)
    net.close(cli)
end)

task.run(loop)
task.close(loop)
io.write(tostring(got))
""")

    clean_env = "env -u LUA_PATH -u LUA_CPATH -u LUAM_DIR "
    chk_out, chk_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " check -C " .. ext.shell_quote(proj_dir))
    t.eq(chk_ok, true, "luam check accepts with={poll,net,proc}: " .. tostring(chk_out))

    bld_out, bld_ok, _ = ext.exec(clean_env .. ext.shell_quote(luam_bin) .. " build -C " .. ext.shell_quote(proj_dir))
    t.eq(bld_ok, true, "luam build links poll, net, proc: " .. tostring(bld_out))

    bin_path = paths.joinpath(proj_dir, "bin", "io_app")
    run_out, run_ok, _ = ext.exec(clean_env .. ext.shell_quote(bin_path))
    t.eq(run_ok, true, "standalone io_app exited 0")
    t.eq(run_out, "STATIC_OK", "standalone io_app ran task + poll + net + proc.spawn")
end)

ext.exec("rm -rf " .. ext.shell_quote(tmp_dir))
t.finish("test_io_primitives")
