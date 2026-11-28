-- Cooperative coroutine scheduler multiplexed over `lib/poll`.
--
-- Functions:
--   async.new([opts])                        -> loop | nil, err
--   async.spawn(loop, fn, ...)               -> handle
--   async.yield()                            -> true
--   async.sleep_ms(ms)                       -> true
--   async.wait_fd(fd, events [, timeout_ms]) -> ev_tbl | nil, "timeout"
--   async.active_count(loop)                 -> integer
--   async.step(loop [, max_wait_ms])         -> active_count
--   async.run(loop)                          -> true
--   async.close(loop)                        -> true

const poll = require("poll")

const async = {}

function check_events_str(events)
    if events == "r" then
        return true, false
    end
    if events == "w" then
        return false, true
    end
    if events == "rw" or events == "wr" then
        return true, true
    end
    error("async.wait_fd: events must be \"r\", \"w\", or \"rw\"", 0)
end

function sync_poller_fd(loop, fd)
    waiters = loop.fd_waiters[fd]
    want_r = false
    want_w = false
    if waiters != nil then
        for _, w in ipairs(waiters) do
            if w.want_r then
                want_r = true
            end
            if w.want_w then
                want_w = true
            end
        end
    end

    prev_mask = loop.poller_masks[fd]
    if not want_r and not want_w then
        loop.fd_waiters[fd] = nil
        if prev_mask != nil then
            poll.del(loop.poller, fd)
            loop.poller_masks[fd] = nil
        end
        return
    end

    mask = "rw"
    if want_r and not want_w then
        mask = "r"
    elseif want_w and not want_r then
        mask = "w"
    end

    if prev_mask == nil then
        ok, err = poll.add(loop.poller, fd, mask)
        if ok != true then
            error("async: poll.add failed for fd " .. tostring(fd) .. ": " .. tostring(err), 0)
        end
        loop.poller_masks[fd] = mask
    elseif prev_mask != mask then
        ok, err = poll.mod(loop.poller, fd, mask)
        if ok != true then
            error("async: poll.mod failed for fd " .. tostring(fd) .. ": " .. tostring(err), 0)
        end
        loop.poller_masks[fd] = mask
    end
end

function enqueue_ready(loop, handle, a1, a2)
    table.insert(loop.ready, {handle = handle, a1 = a1, a2 = a2})
end

function async.new(opts)
    p, err = poll.open()
    if p == nil then
        return nil, err
    end
    on_err = nil
    if opts != nil and type(opts.on_error) == "function" then
        on_err = opts.on_error
    end
    return {
        poller = p,
        ready = {},
        sleepers = {},
        fd_waiters = {},
        poller_masks = {},
        live_count = 0,
        first_err = nil,
        on_error = on_err,
        closed = false,
    }
end

function async.close(loop)
    if loop != nil and not loop.closed then
        loop.closed = true
        poll.close(loop.poller)
        loop.ready = {}
        loop.sleepers = {}
        loop.fd_waiters = {}
        loop.poller_masks = {}
        loop.live_count = 0
    end
    return true
end

function async.active_count(loop)
    return loop.live_count
end

function async.spawn(loop, fn, ...)
    if loop.closed then
        error("attempt to spawn on a closed async loop", 0)
    end
    if type(fn) != "function" then
        error("async.spawn: fn must be a function", 0)
    end
    init_args = table.pack(...)
    co = coroutine.create(function()
        return fn(table.unpack(init_args, 1, init_args.n))
    end)
    handle = {
        co = co,
        done = false,
        ok = false,
        result = nil,
        err = nil,
    }
    loop.live_count = loop.live_count + 1
    enqueue_ready(loop, handle, nil, nil)
    return handle
end

function async.yield()
    return coroutine.yield("yield")
end

function async.sleep_ms(ms)
    wait_ms = 0
    if ms != nil and ms > 0 then
        wait_ms = ms
    end
    return coroutine.yield("sleep", os.clock_ms() + wait_ms)
end

function async.wait_fd(fd, events, timeout_ms)
    if type(fd) != "number" or fd < 0 then
        error("async.wait_fd: fd must be a non-negative integer", 0)
    end
    want_r, want_w = check_events_str(events)
    deadline = nil
    if timeout_ms != nil and timeout_ms >= 0 then
        deadline = os.clock_ms() + timeout_ms
    end
    return coroutine.yield("fd", fd, want_r, want_w, deadline)
end

function handle_yield(loop, handle, ok, kind, p1, p2, p3, p4)
    if not ok then
        handle.done = true
        handle.ok = false
        handle.err = tostring(kind)
        loop.live_count = loop.live_count - 1
        if loop.on_error != nil then
            loop.on_error(handle.err, handle)
        elseif loop.first_err == nil then
            loop.first_err = handle.err
        end
        return
    end

    if coroutine.status(handle.co) == "dead" then
        handle.done = true
        handle.ok = true
        handle.result = kind
        loop.live_count = loop.live_count - 1
        return
    end

    if kind == "yield" then
        enqueue_ready(loop, handle, true, nil)
    elseif kind == "sleep" then
        table.insert(loop.sleepers, {handle = handle, deadline_ms = p1})
    elseif kind == "fd" then
        fd = p1
        list = loop.fd_waiters[fd]
        if list == nil then
            list = {}
            loop.fd_waiters[fd] = list
        end
        table.insert(list, {
            handle = handle,
            want_r = p2,
            want_w = p3,
            deadline_ms = p4,
        })
        sync_poller_fd(loop, fd)
    else
        handle.done = true
        handle.ok = false
        handle.err = "unsupported yield tag: " .. tostring(kind)
        loop.live_count = loop.live_count - 1
        if loop.on_error != nil then
            loop.on_error(handle.err, handle)
        elseif loop.first_err == nil then
            loop.first_err = handle.err
        end
    end
end

function drain_ready_batch(loop)
    batch = loop.ready
    if #batch == 0 then
        return
    end
    loop.ready = {}
    for _, item in ipairs(batch) do
        if loop.closed then
            return
        end
        ok, r1, r2, r3, r4, r5 = coroutine.resume(item.handle.co, item.a1, item.a2)
        handle_yield(loop, item.handle, ok, r1, r2, r3, r4, r5)
    end
end

function next_deadline_wait_ms(loop, now_ms, max_wait_ms)
    if #loop.ready > 0 then
        return 0
    end
    earliest = nil
    for _, s in ipairs(loop.sleepers) do
        if earliest == nil or s.deadline_ms < earliest then
            earliest = s.deadline_ms
        end
    end
    for _, waiters in pairs(loop.fd_waiters) do
        for _, w in ipairs(waiters) do
            if w.deadline_ms != nil and (earliest == nil or w.deadline_ms < earliest) then
                earliest = w.deadline_ms
            end
        end
    end

    wait_ms = -1
    if earliest != nil then
        diff = math.ceil(earliest - now_ms)
        if diff < 0 then
            diff = 0
        end
        wait_ms = diff
    end
    if max_wait_ms != nil and max_wait_ms >= 0 then
        if wait_ms < 0 or max_wait_ms < wait_ms then
            wait_ms = max_wait_ms
        end
    end
    return wait_ms
end

function wake_expired(loop, now_ms)
    if #loop.sleepers > 0 then
        kept_sleepers = {}
        for _, s in ipairs(loop.sleepers) do
            if s.deadline_ms <= now_ms then
                enqueue_ready(loop, s.handle, true, nil)
            else
                table.insert(kept_sleepers, s)
            end
        end
        loop.sleepers = kept_sleepers
    end

    dirty_fds = {}
    for fd, waiters in pairs(loop.fd_waiters) do
        kept_w = {}
        changed = false
        for _, w in ipairs(waiters) do
            if w.deadline_ms != nil and w.deadline_ms <= now_ms then
                enqueue_ready(loop, w.handle, nil, "timeout")
                changed = true
            else
                table.insert(kept_w, w)
            end
        end
        if changed then
            loop.fd_waiters[fd] = kept_w
            table.insert(dirty_fds, fd)
        end
    end
    for _, fd in ipairs(dirty_fds) do
        sync_poller_fd(loop, fd)
    end
end

function async.step(loop, max_wait_ms)
    if loop.closed then
        return 0
    end

    drain_ready_batch(loop)
    if loop.closed or loop.live_count == 0 then
        return loop.live_count
    end

    now = os.clock_ms()
    wake_expired(loop, now)
    if #loop.ready > 0 then
        drain_ready_batch(loop)
        return loop.live_count
    end

    wait_ms = next_deadline_wait_ms(loop, os.clock_ms(), max_wait_ms)
    events, err = poll.wait(loop.poller, wait_ms)
    if events == nil then
        error("async: poll.wait failed: " .. tostring(err), 0)
    end

    for _, ev in ipairs(events) do
        waiters = loop.fd_waiters[ev.fd]
        if waiters != nil then
            kept = {}
            woke = false
            for _, w in ipairs(waiters) do
                r_hit = w.want_r and (ev.r or ev.hup or ev.err)
                w_hit = w.want_w and (ev.w or ev.hup or ev.err)
                if r_hit or w_hit then
                    enqueue_ready(loop, w.handle, ev, nil)
                    woke = true
                else
                    table.insert(kept, w)
                end
            end
            if woke then
                loop.fd_waiters[ev.fd] = kept
                sync_poller_fd(loop, ev.fd)
            end
        end
    end

    wake_expired(loop, os.clock_ms())
    if #loop.ready > 0 then
        drain_ready_batch(loop)
    end
    return loop.live_count
end

function async.run(loop)
    while not loop.closed and loop.live_count > 0 and loop.first_err == nil do
        has_fd = next(loop.fd_waiters) != nil
        if #loop.ready == 0 and #loop.sleepers == 0 and not has_fd then
            err_msg = "async.run: deadlock (active coroutines waiting on nothing)"
            async.close(loop)
            error(err_msg, 0)
        end
        async.step(loop, nil)
    end
    if loop.first_err != nil then
        err_msg = loop.first_err
        async.close(loop)
        error(err_msg, 0)
    end
    return true
end

return async
