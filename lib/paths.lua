-- Define a module table
paths = {}

-- Capture the path of the file that required this module
do
    info = debug.getinfo(4, "S") or debug.getinfo(3, "S")
    if info and info.source.sub(source, 1, 1) == "@" then
        paths._caller_script = info.source.sub(source, 2)
    else
        paths._caller_script = nil
    end
end

function get_script_path()
    return paths._caller_script
end

function get_parent_dir(path)
    path = path.gsub(path, "[\\/]+$", "")
    parent_dir = path.match(path, "(.*/)")
    return parent_dir
end

function remove_trailing_slash(path)
    -- Remove the trailing slash if it exists
    return path.gsub(path, "[\\/]+$", "")
end

function get_file_name(path)
    return path.match(path, "([^\\/]+)$")
end

function get_dir_name(path)
	path = "/" .. path
	dir_name = nil 
	file_name = get_file_name(path)
	if file_name then
		dir_name = path.match(path, ".*/([^/]*)/[^/]+$")
	else
		path = remove_trailing_slash(path)
		dir_name = get_file_name(path)
	end
	return dir_name
end

function get_script_dir()
    script_path = get_script_path()
    script_dir = get_parent_dir(script_path)
    return script_dir
end

-- Function to join paths
function joinpath(...)
    parts = {...}
    separator = package.config.sub(config, 1,1)

    joined_path = table.concat(parts, separator)

    if separator == '\\' then
        joined_path = joined_path.gsub(joined_path, '[\\/]+', '\\')
    else
        joined_path = joined_path.gsub(joined_path, '[\\/]+', '/')
    end

    return joined_path
end

-- Function to add relative path to package.path
-- function add_to_path(script_path, relative_path)
--     script_dir = get_parent_dir(script_path)
--     path_to_add = joinpath(script_dir, relative_path, "?.lua;")
--     package.path = path_to_add .. package.path
-- end

-- Function to add absolute path to package.path
function add_to_path(path)
    path_to_add = joinpath(path, "?.lua;")
    package.path = path_to_add .. package.path
end

function file_exists(path)
	answer = false
	file = io.open(path, "r")
	if file then
		answer = true
		file.close(file)
	end
	return answer
end

function create_dir_if_not_exists(path)
	dir_path = joinpath(path)
	-- Check if the directory exists
	attr = lfs.attributes(path)
	if not attr then
	    -- Directory does not exist; create it
	    success, err = lfs.mkdir(path)
	    if not success then
	        print("Error creating directory:", err)
	        return 
	    end
	end
	return true
end

function create_file_if_not_exists(path)
	-- Check if the file exists
	file = io.open(path, "r")
	if not file then
	    -- File does not exist; create it
	    file, err = io.open(path, "w")
	    if not file then
	        print("Error creating file:", err)
	        return
	    else
	        file.close(file)  -- Close the file after creating it
	    end
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
paths.file_exists = file_exists
paths.create_dir_if_not_exists = create_dir_if_not_exists
paths.create_file_if_not_exists = create_file_if_not_exists

-- Export the module
return paths
