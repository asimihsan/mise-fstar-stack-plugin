-- lib/find_install.lua
-- Resilient file discovery for fstar-stack plugin
-- Handles varying tarball extraction structures by locating key reference files

local file = require("file")
local shell = require("lib.shell")

local M = {}

local function is_windows()
	return (RUNTIME and RUNTIME.osType) == "windows" -- luacheck: ignore
end

local function ps_escape_single_quoted(value)
	-- PowerShell single-quoted string literal escaping: '' represents a literal '.
	return tostring(value):gsub("'", "''")
end

local function ps_quote_single_quoted(value)
	return "'" .. ps_escape_single_quoted(value) .. "'"
end

local function powershell_command(script)
	-- Wrap the -Command payload in double quotes for cmd.exe, and avoid using
	-- any double quotes in the script (or escape them).
	local escaped = tostring(script):gsub('"', '\\"')
	return 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' .. escaped .. '"'
end

local function read_powershell_stdout(script)
	local cmd = powershell_command(script)
	local f = io.popen(cmd)
	if not f then
		return nil
	end
	local out = f:read("*a")
	f:close()
	if not out then
		return nil
	end
	return (out:gsub("%s+$", ""))
end

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
	if is_windows() then
		-- Use PowerShell to locate bin\\fstar.exe anywhere under the extracted tree.
		-- We prefer fstar.exe because it is always present in binary distributions.
		local script = "$base = "
			.. ps_quote_single_quoted(base_path)
			.. "; "
			.. "$match = Get-ChildItem -LiteralPath $base -Recurse -File -Filter fstar.exe -ErrorAction SilentlyContinue "
			.. "| Where-Object { $_.FullName -match '\\\\bin\\\\fstar\\.exe$' } "
			.. "| Select-Object -First 1 -ExpandProperty FullName; "
			.. "if ($match) { Split-Path -Parent (Split-Path -Parent $match) }"

		local result = read_powershell_stdout(script)
		if result and result ~= "" then
			return result
		end
		return nil
	end

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
	if is_windows() then
		local script = "$p = "
			.. ps_quote_single_quoted(path)
			.. "; "
			.. "Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue "
			.. "| ForEach-Object { $_.Mode + ' ' + $_.Length + ' ' + $_.Name }"
		return read_powershell_stdout(script) or "(unable to list)"
	end

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

	if is_windows() then
		local script = "$src = "
			.. ps_quote_single_quoted(actual_root)
			.. "; "
			.. "$dst = "
			.. ps_quote_single_quoted(install_path)
			.. "; "
			.. "Get-ChildItem -LiteralPath $src -Force -ErrorAction Stop "
			.. "| ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $dst -Force }; "
			.. "Remove-Item -LiteralPath $src -Force -Recurse -ErrorAction SilentlyContinue"
		read_powershell_stdout(script)

		local fstar_exe = file.join_path(install_path, "bin", "fstar.exe")
		if not file.exists(fstar_exe) then
			return false, "Move completed but bin/fstar.exe not found at expected location (Windows)."
		end
		return true, nil
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
