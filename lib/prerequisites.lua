-- lib/prerequisites.lua
-- Checks for required system dependencies before building KaRaMeL

local M = {}

-- Prerequisites with platform-specific hints
M.PREREQUISITES = {
	{
		name = "opam",
		command = "opam --version",
		hint = {
			darwin = "brew install opam",
			linux = "See https://opam.ocaml.org/doc/Install.html",
		},
	},
	{
		name = "git",
		command = "git --version",
		hint = {
			darwin = "xcode-select --install",
			linux = "apt install git  # or your package manager",
		},
	},
	{
		name = "make",
		command = "gmake --version 2>/dev/null || make --version",
		-- On macOS, we prefer gmake (GNU make) over BSD make
		darwin_prefer = "gmake",
		hint = {
			darwin = "brew install make  # provides gmake",
			linux = "apt install make  # or your package manager",
		},
	},
	{
		name = "pkg-config",
		command = "pkg-config --version",
		hint = {
			darwin = "brew install pkg-config",
			linux = "apt install pkg-config  # or your package manager",
		},
	},
	{
		name = "gmp",
		command = "pkg-config --exists gmp && echo gmp found",
		hint = {
			darwin = "brew install gmp",
			linux = "apt install libgmp-dev  # or your package manager",
		},
	},
	{
		name = "C compiler",
		command = "cc --version 2>/dev/null || gcc --version 2>/dev/null || clang --version",
		hint = {
			darwin = "xcode-select --install",
			linux = "apt install build-essential  # or your package manager",
		},
	},
}

-- Check if os.execute succeeded (handles both Lua 5.1 and 5.2+ return values)
local function exec_succeeded(result)
	return result == true or result == 0
end

-- Check if a single prerequisite is available
-- Returns true if available, false and error message if not
function M.check_prerequisite(prereq, os_type)
	local result = os.execute(prereq.command .. " > /dev/null 2>&1")
	if exec_succeeded(result) then
		return true, nil
	end

	-- Build helpful error message
	local hint = prereq.hint[os_type] or prereq.hint.linux or "Install " .. prereq.name
	return false, "Missing prerequisite: " .. prereq.name .. "\n  Install with: " .. hint
end

-- Check all prerequisites and return list of missing ones
-- Returns nil if all prerequisites are met, or error string listing missing ones
function M.check_all_prerequisites(os_type)
	local missing = {}

	for _, prereq in ipairs(M.PREREQUISITES) do
		local ok, err = M.check_prerequisite(prereq, os_type)
		if not ok then
			table.insert(missing, err)
		end
	end

	if #missing > 0 then
		return "KaRaMeL build requires the following prerequisites:\n\n"
			.. table.concat(missing, "\n\n")
			.. "\n\nAfter installing prerequisites, run: mise install fstar-stack"
	end

	return nil
end

-- Get the make command to use (gmake on macOS if available, otherwise make)
function M.get_make_command(os_type)
	if os_type == "darwin" then
		-- Prefer gmake on macOS for GNU make compatibility
		local result = os.execute("which gmake > /dev/null 2>&1")
		if exec_succeeded(result) then
			return "gmake"
		end
	end
	return "make"
end

return M
