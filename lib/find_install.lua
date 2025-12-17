-- lib/find_install.lua
-- Resilient file discovery for fstar-stack plugin
-- Handles varying tarball extraction structures by locating key reference files

local file = require("file")
local shell = require("lib.shell")

local M = {}

-- Reference markers to identify F* installation root (ordered by reliability)
-- We look for these files/directories to determine where F* is actually installed
local MARKERS = {
	{ path = "bin/fstar.exe", type = "file" },
	{ path = "lib/fstar/ulib", type = "dir" },
}

-- Common intermediate directories that tarballs may extract to
-- Check these prefixes before falling back to find command
local PREFIXES = {
	"", -- Direct (mise stripped top-level directory)
	"fstar", -- Common: fstar/ subdirectory not stripped
}

-- Shell-escape a path for safe use in os.execute() / io.popen()
function M.quote(path)
	return shell.quote(path)
end

-- Find actual F* root by locating reference markers
-- Returns: root_path (string or nil), found_at_expected (boolean)
--
-- The function checks common prefixes first (fast path), then falls back
-- to using find command for unusual directory structures like FStar-v2025.12.15/
function M.find_fstar_root(install_path)
	-- Fast path: check common prefixes
	for _, prefix in ipairs(PREFIXES) do
		local candidate
		if prefix == "" then
			candidate = install_path
		else
			candidate = file.join_path(install_path, prefix)
		end

		for _, marker in ipairs(MARKERS) do
			local marker_path = file.join_path(candidate, marker.path)
			if file.exists(marker_path) then
				return candidate, (prefix == "")
			end
		end
	end

	-- Slow path: use find command for glob patterns (handles FStar-*, fstar-v*, etc.)
	local find_result = M.find_with_glob(install_path)
	if find_result then
		return find_result, false
	end

	return nil, false
end

-- Find F* root using shell find command (fallback for unusual structures)
-- Searches for bin/fstar.exe up to 3 levels deep
function M.find_with_glob(base_path)
	-- Use find to locate bin/fstar.exe, limit depth to 3 levels
	local cmd = "find "
		.. shell.quote(base_path)
		.. " -maxdepth 4 -type f -name 'fstar.exe' -path '*/bin/fstar.exe' -print -quit 2>/dev/null"
	local f = io.popen(cmd)
	if f then
		local result = f:read("*l")
		f:close()
		if result and result ~= "" then
			-- Extract root from found path: /path/to/fstar/bin/fstar.exe -> /path/to/fstar
			return result:gsub("/bin/fstar%.exe$", "")
		end
	end
	return nil
end

-- List directory contents for debugging
function M.list_directory(path)
	local output_file = os.tmpname()
	os.execute("ls -la " .. shell.quote(path) .. " > " .. shell.quote(output_file) .. " 2>&1")
	local f = io.open(output_file, "r")
	local contents = "(unable to list)"
	if f then
		contents = f:read("*a") or contents
		f:close()
	end
	os.remove(output_file)
	return contents
end

-- Move contents from actual_root to install_path (normalize structure)
-- This is used when files are found in an unexpected location (e.g., fstar/ subdirectory)
-- Returns: success (boolean), error_message (string or nil)
function M.normalize_structure(install_path, actual_root)
	if actual_root == install_path then
		return true, nil -- Already normalized
	end

	-- Move all contents from actual_root to install_path
	-- Using shell glob to move contents, not the directory itself
	local cmd = "mv " .. M.quote(actual_root) .. "/* " .. M.quote(install_path) .. "/ 2>&1"
	local f = io.popen(cmd)
	local output = ""
	if f then
		output = f:read("*a") or ""
		f:close()
	end

	-- Verify the move worked by checking for expected structure
	local fstar_exe = file.join_path(install_path, "bin", "fstar.exe")
	if not file.exists(fstar_exe) then
		return false, "Move command ran but bin/fstar.exe not found at expected location. Output: " .. output
	end

	-- Remove the now-empty source directory
	os.execute("rmdir " .. shell.quote(actual_root) .. " 2>/dev/null")

	return true, nil
end

return M
