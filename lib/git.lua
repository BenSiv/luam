-- Git plumbing helpers over `external_tool`.
-- Every function accepts an optional `dir` argument (`git -C <dir>`).

const ext = require("external_tool")

const git = {}

function git_cmd(subcmd, dir)
    if dir != nil and dir != "" then
        return "git -C " .. ext.shell_quote(dir) .. " " .. subcmd
    end
    return "git " .. subcmd
end

function git.is_repo(dir)
    out, ok, _ = ext.exec(git_cmd("rev-parse --is-inside-work-tree", dir))
    return ok and string.trim(out) == "true"
end

function git.rev_parse(rev, dir)
    target = rev
    if target == nil or target == "" then
        target = "HEAD"
    end
    out, ok, _ = ext.exec(git_cmd("rev-parse --verify " .. ext.shell_quote(target .. "^{commit}"), dir))
    if not ok then
        return nil
    end
    return string.trim(out)
end

function git.short_head(dir)
    out, ok, _ = ext.exec(git_cmd("rev-parse --short HEAD", dir))
    if not ok then
        return nil
    end
    return string.trim(out)
end

function git.describe(dir)
    out, ok, _ = ext.exec(git_cmd("describe --always --dirty", dir))
    if not ok then
        return nil
    end
    return string.trim(out)
end

function git.is_ancestor(ancestor, descendant, dir)
    if type(ancestor) != "string" or ancestor == "" then
        return false
    end
    desc = descendant
    if desc == nil or desc == "" then
        desc = "HEAD"
    end
    return ext.ok(git_cmd(
        "merge-base --is-ancestor " .. ext.shell_quote(ancestor) .. " " .. ext.shell_quote(desc),
        dir
    ))
end

function git.is_clean(dir)
    if not ext.ok(git_cmd("diff --quiet", dir)) then
        return false
    end
    return ext.ok(git_cmd("diff --cached --quiet", dir))
end

function git.status_porcelain(dir)
    out, ok, _ = ext.exec(git_cmd("status --porcelain", dir))
    if not ok then
        return nil
    end
    return out
end

function git.current_branch(dir)
    out, ok, _ = ext.exec(git_cmd("branch --show-current", dir))
    if not ok then
        return nil
    end
    branch = string.trim(out)
    if branch == "" then
        return nil
    end
    return branch
end

function git.local_branches(dir)
    out, ok, _ = ext.exec(git_cmd("for-each-ref refs/heads --format='%(refname:short)'", dir))
    if not ok then
        return {}
    end
    branches = {}
    for _, line in ipairs(string.lines(out)) do
        trimmed = string.trim(line)
        if trimmed != "" then
            table.insert(branches, trimmed)
        end
    end
    return branches
end

function git.clone(url, dest, opts)
    flags = "--quiet"
    if opts != nil then
        if opts.quiet == false then
            flags = ""
        end
        if opts.depth != nil then
            flags = flags .. " --depth " .. tostring(opts.depth)
        end
        if opts.branch != nil and opts.branch != "" then
            flags = flags .. " --branch " .. ext.shell_quote(opts.branch)
        end
    end
    cmd = "git clone " .. flags .. " " .. ext.shell_quote(url) .. " " .. ext.shell_quote(dest)
    out, ok, _ = ext.exec(cmd)
    return ok, out
end

function git.fetch(remote, dir)
    rem = remote
    if rem == nil or rem == "" then
        rem = "--all"
    else
        rem = ext.shell_quote(rem)
    end
    out, ok, _ = ext.exec(git_cmd("fetch --prune " .. rem, dir))
    return ok, out
end

return git
