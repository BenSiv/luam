-- Path manipulation, directory creation, and atomic file I/O helpers.

const lfs = require("lfs")

const paths = {}

function normalize_path(path)
    return (string.gsub(path, "\\", "/"))
end

function get_parent_dir(path)
    norm_path = normalize_path(path)
    norm_path = string.gsub(norm_path, "([^/]+)/+$", "%1")
    parent = string.match(norm_path, "^(.*)/[^/]*$")
    if parent == nil then
        return "."
    end
    if parent == "" then
        return "/"
    end
    return parent
end

function get_file_name(path)
    norm_path = normalize_path(path)
    norm_path = string.gsub(norm_path, "([^/]+)/+$", "%1")
    return string.match(norm_path, "([^/]+)$")
end

function get_dir_name(path)
    return get_file_name(path)
end

function get_script_path()
    info = debug.getinfo(2, "S")
    if info != nil and info.source != nil and string.sub(info.source, 1, 1) == "@" then
        raw_path = string.sub(info.source, 2)
        if string.sub(raw_path, 1, 1) == "/" or string.match(raw_path, "^%a:[/\\]") != nil then
            return normalize_path(raw_path)
        end
        cwd = lfs.currentdir()
        if cwd != nil then
            raw_path = string.gsub(raw_path, "^%./", "")
            return normalize_path(cwd .. "/" .. raw_path)
        end
        return normalize_path(raw_path)
    end
    return nil
end

function get_script_dir()
    script_path = get_script_path()
    if script_path == nil then
        return nil
    end
    return get_parent_dir(script_path)
end

function joinpath(...)
    parts = {...}
    separator = string.sub(package.config, 1, 1)
    joined_path = table.concat(parts, separator)
    if separator == "\\" then
        joined_path = string.gsub(joined_path, "[\\/]+", "\\")
    else
        joined_path = string.gsub(joined_path, "[\\/]+", "/")
    end
    return joined_path
end

function add_to_path(path)
    path_to_add = joinpath(path, "?.lua;")
    package.path = path_to_add .. package.path
end

function expand_home(path)
    if type(path) != "string" then
        return path
    end
    home = os.getenv("HOME")
    if home == nil or home == "" then
        return path
    end
    if path == "~" then
        return home
    end
    if string.starts_with(path, "~/") then
        return home .. string.sub(path, 2)
    end
    return path
end

-- stat() via lfs rather than io.open + io.close: closing any descriptor to
-- a file on POSIX releases all fcntl advisory locks this process holds on
-- that inode (including SQLite WAL locks).
function file_exists(path)
    if type(path) != "string" or path == "" then
        return false
    end
    return lfs.attributes(path, "mode") != nil
end

-- True when `path` exists, including a broken symlink (lstat).
function exists(path)
    if type(path) != "string" or path == "" then
        return false
    end
    return lfs.symlinkattributes(path, "mode") != nil
end

function is_dir(path)
    if type(path) != "string" or path == "" then
        return false
    end
    return lfs.attributes(path, "mode") == "directory"
end

-- Pure-lfs recursive `mkdir -p`.
function ensure_dir(dir_path)
    if dir_path == nil or dir_path == "" or dir_path == "." or dir_path == "/" then
        return true
    end
    clean = string.gsub(normalize_path(dir_path), "/+$", "")
    if clean == "" then
        return true
    end
    if lfs.attributes(clean, "mode") == "directory" then
        return true
    end
    parent = get_parent_dir(clean)
    if parent != nil and parent != "" and parent != clean and parent != "." then
        ok_p, err_p = ensure_dir(parent)
        if not ok_p then
            return false, err_p
        end
    end
    ok_mk, err_mk = lfs.mkdir(clean)
    if ok_mk == true then
        return true
    end
    if lfs.attributes(clean, "mode") == "directory" then
        return true
    end
    return false, "cannot create directory '" .. clean .. "': " .. tostring(err_mk)
end

function read_file(path)
    file = io.open(path, "rb")
    if file == nil then
        return nil
    end
    source = io.read(file, "*all")
    io.close(file)
    return source
end

function write_file(path, data)
    parent = get_parent_dir(path)
    if parent != nil and parent != "." then
        ok_dir, err_dir = ensure_dir(parent)
        if not ok_dir then
            return false, err_dir
        end
    end
    file, err = io.open(path, "wb")
    if file == nil then
        return false, "cannot open '" .. tostring(path) .. "' for writing: " .. tostring(err)
    end
    ok_w, err_w = pcall(io.write, file, data)
    io.close(file)
    if not ok_w then
        return false, tostring(err_w)
    end
    return true
end

_atomic_seq = 0

-- Writes `data` to a unique sibling temp file and atomically renames it
-- over `path` so crashes or concurrent readers never observe partial bytes.
function write_atomic(path, data)
    parent = get_parent_dir(path)
    if parent != nil and parent != "." then
        ok_dir, err_dir = ensure_dir(parent)
        if not ok_dir then
            return false, err_dir
        end
    end
    _atomic_seq = _atomic_seq + 1
    tmp = string.format("%s.tmp.%d.%d", path, os.time(), _atomic_seq)
    file, err = io.open(tmp, "wb")
    if file == nil then
        return false, "cannot create temp file '" .. tmp .. "': " .. tostring(err)
    end
    ok_w, err_w = pcall(io.write, file, data)
    io.close(file)
    if not ok_w then
        os.remove(tmp)
        return false, tostring(err_w)
    end
    ok_rn, err_rn = os.rename(tmp, path)
    if ok_rn == nil then
        os.remove(tmp)
        return false, "cannot rename '" .. tmp .. "' to '" .. path .. "': " .. tostring(err_rn)
    end
    return true
end

function create_dir_if_not_exists(path)
    ok_dir, err_dir = ensure_dir(path)
    if not ok_dir then
        print("Error creating directory:", err_dir)
        return nil
    end
    return true
end

function create_file_if_not_exists(path)
    if file_exists(path) then
        return true
    end
    ok_w, err_w = write_file(path, "")
    if not ok_w then
        print("Error creating file:", err_w)
        return nil
    end
    return true
end

paths.get_parent_dir = get_parent_dir
paths.get_file_name = get_file_name
paths.get_dir_name = get_dir_name
paths.get_script_path = get_script_path
paths.get_script_dir = get_script_dir
paths.joinpath = joinpath
paths.add_to_path = add_to_path
paths.expand_home = expand_home
paths.file_exists = file_exists
paths.exists = exists
paths.is_dir = is_dir
paths.ensure_dir = ensure_dir
paths.read_file = read_file
paths.write_file = write_file
paths.write_atomic = write_atomic
paths.create_dir_if_not_exists = create_dir_if_not_exists
paths.create_file_if_not_exists = create_file_if_not_exists

return paths
