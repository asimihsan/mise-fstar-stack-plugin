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
		name = "gmake",
		-- On macOS, GNU make (gmake) is required - BSD make won't work
		-- On Linux, make is typically GNU make
		command = "gmake --version 2>/dev/null || make --version",
		darwin_check = "gmake --version", -- macOS requires gmake specifically
		hint = {
			darwin = "brew install make  # provides gmake (GNU make required)",
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
	{
		name = "gtime",
		-- GNU time is required by KaRaMeL's krmllib build on macOS
		-- On Linux, /usr/bin/time works fine (use -v to test, not --version)
		command = "gtime --version 2>/dev/null || /usr/bin/time -v true 2>/dev/null",
		darwin_check = "gtime --version", -- macOS requires gtime specifically
		hint = {
			darwin = "brew install gnu-time  # provides gtime",
			linux = "apt install time  # or your package manager",
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
	-- Use platform-specific check if available (e.g., macOS requires gmake specifically)
	local check_cmd = prereq.command
	if os_type == "darwin" and prereq.darwin_check then
		check_cmd = prereq.darwin_check
	end

	-- Wrap command in parentheses to capture all output from compound commands
	local result = os.execute("(" .. check_cmd .. ") > /dev/null 2>&1")
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

-- Check architecture consistency on macOS (arm64 vs x86_64)
-- The assembler error "unknown token in expression" with ARM64 instructions
-- is typically caused by feeding ARM64 assembly to an x86_64 assembler
-- See: https://github.com/ocaml/ocaml/issues/10374
function M.check_architecture(os_type)
	if os_type ~= "darwin" then
		return nil -- Only relevant on macOS
	end

	-- Check if running under Rosetta (x86_64 emulation on arm64)
	local f = io.popen("sysctl -n sysctl.proc_translated 2>/dev/null")
	if f then
		local translated = f:read("*a"):gsub("%s+", "")
		f:close()
		if translated == "1" then
			return "Running under Rosetta (x86_64 emulation on arm64 Mac).\n"
				.. "This can cause assembler errors due to architecture mismatch.\n"
				.. "Please run in a native arm64 terminal.\n"
				.. "Hint: Check your terminal app's 'Open using Rosetta' setting in Get Info."
		end
	end

	-- Check Homebrew is arm64 (should be at /opt/homebrew, not /usr/local)
	local f2 = io.popen("which brew 2>/dev/null")
	if f2 then
		local brew_path = f2:read("*a"):gsub("%s+", "")
		f2:close()
		if brew_path:find("/usr/local") then
			return "Intel Homebrew detected at /usr/local.\n"
				.. "On Apple Silicon, this can cause architecture mismatch errors.\n"
				.. "Please use arm64 Homebrew at /opt/homebrew.\n"
				.. "Hint: Install arm64 Homebrew with:\n"
				.. '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
		end
	end

	return nil
end

return M
