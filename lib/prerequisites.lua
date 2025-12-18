-- lib/prerequisites.lua
-- Checks for required system dependencies before building KaRaMeL

local M = {}

local versions = require("lib.versions")
local shell = require("lib.shell")

-- Prerequisites with platform-specific hints
M.PREREQUISITES = {
	{
		name = "bash",
		command = "bash --version",
		hint = {
			windows = "Install Git for Windows (includes bash) or MSYS2/Cygwin",
			darwin = "bash is included with macOS",
			linux = "bash is included with most Linux distributions",
		},
	},
	{
		name = "opam",
		command = "opam --version",
		hint = {
			windows = "winget install OCaml.opam  # or use ocaml/setup-ocaml in CI",
			darwin = "brew install opam",
			linux = "See https://opam.ocaml.org/doc/Install.html",
		},
	},
	{
		name = "git",
		command = "git --version",
		hint = {
			windows = "Install Git for Windows",
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
			windows = "Install GNU make via MSYS2/Cygwin (e.g., pacman -S make)",
			darwin = "brew install make  # provides gmake (GNU make required)",
			linux = "apt install make  # or your package manager",
		},
	},
	{
		name = "pkg-config",
		command = "pkg-config --version",
		hint = {
			windows = "Install pkg-config via MSYS2/Cygwin (e.g., pacman -S mingw-w64-x86_64-pkgconf)",
			darwin = "brew install pkg-config",
			linux = "apt install pkg-config  # or your package manager",
		},
	},
	{
		name = "gmp",
		command = "pkg-config --exists gmp && echo gmp found",
		hint = {
			windows = "Install gmp via MSYS2/Cygwin (e.g., pacman -S mingw-w64-x86_64-gmp)",
			darwin = "brew install gmp",
			linux = "apt install libgmp-dev  # or your package manager",
		},
	},
	{
		name = "libffi",
		command = "pkg-config --exists libffi && echo libffi found",
		hint = {
			windows = "Install libffi via MSYS2/Cygwin (e.g., pacman -S mingw-w64-x86_64-libffi)",
			darwin = "brew install libffi",
			linux = "apt install libffi-dev  # or your package manager",
		},
	},
	{
		name = "C compiler",
		command = "cc --version 2>/dev/null || gcc --version 2>/dev/null || clang --version",
		hint = {
			windows = "Install a MinGW toolchain via MSYS2/Cygwin (gcc) or Visual Studio (cl)",
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
			windows = "Install GNU time via MSYS2/Cygwin (e.g., pacman -S time)",
			darwin = "brew install gnu-time  # provides gtime",
			linux = "apt install time  # or your package manager",
		},
	},
}

-- Additional prerequisites required for F* source builds (linux_arm64)
M.SOURCE_BUILD_PREREQUISITES = {
	{
		name = "unzip",
		command = "unzip -v",
		hint = {
			linux = "apt install unzip  # or your package manager",
		},
	},
	{
		name = "m4",
		command = "m4 --version",
		hint = {
			linux = "apt install m4  # or your package manager",
		},
	},
	{
		name = "rsync",
		command = "rsync --version",
		hint = {
			linux = "apt install rsync  # or your package manager",
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

	local ok = shell.run_command(check_cmd, "check " .. prereq.name)
	if ok then
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

	-- Check source build prerequisites for platforms that need them
	local arch_type = RUNTIME and RUNTIME.archType or "amd64" -- luacheck: ignore
	local platform_key = os_type .. "_" .. arch_type
	if versions.needs_fstar_source_build(platform_key) then
		for _, prereq in ipairs(M.SOURCE_BUILD_PREREQUISITES) do
			local ok, err = M.check_prerequisite(prereq, os_type)
			if not ok then
				table.insert(missing, err)
			end
		end

		-- Check glibc version on Linux (Z3 ARM64 requires glibc 2.34+)
		if os_type == "linux" then
			local glibc_err = M.check_glibc_version()
			if glibc_err then
				table.insert(missing, glibc_err)
			end
		end
	end

	if #missing > 0 then
		local build_type = versions.needs_fstar_source_build(platform_key) and "F* source" or "KaRaMeL"
		return build_type
			.. " build requires the following prerequisites:\n\n"
			.. table.concat(missing, "\n\n")
			.. "\n\nAfter installing prerequisites, run: mise install fstar-stack"
	end

	return nil
end

-- Check glibc version on Linux
-- Z3 ARM64 binary requires glibc 2.34+ (Ubuntu 22.04+)
function M.check_glibc_version()
	-- Check if we're on musl (Alpine) - not supported
	local f = io.popen("ldd --version 2>&1")
	if f then
		local output = f:read("*a") or ""
		f:close()

		-- Check for musl (Alpine Linux)
		if output:match("musl") then
			return "Alpine Linux (musl) detected.\n"
				.. "  The Z3 ARM64 binary requires glibc.\n"
				.. "  Please use Ubuntu 22.04+ or another glibc-based distribution."
		end

		-- Extract glibc version (e.g., "ldd (GNU libc) 2.35")
		local major, minor = output:match("(%d+)%.(%d+)")
		if major and minor then
			local version = tonumber(major) * 100 + tonumber(minor)
			if version < 234 then
				return "glibc version too old (found "
					.. major
					.. "."
					.. minor
					.. ", need 2.34+).\n"
					.. "  Z3 ARM64 requires glibc 2.34+ (Ubuntu 22.04+).\n"
					.. "  Please upgrade your distribution."
			end
		end
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

-- Return an environment prefix string for macOS builds that rely on Homebrew.
-- This is primarily to make opam "conf-*" packages locate dependencies reliably
-- on CI runners and fresh machines.
function M.get_build_env(os_type)
	if os_type ~= "darwin" then
		return ""
	end

	local libffi_prefix = shell.read_stdout("brew --prefix libffi")
	if not libffi_prefix or libffi_prefix == "" then
		return ""
	end

	local pkgconfig_dir = libffi_prefix .. "/lib/pkgconfig"

	return 'PKG_CONFIG_PATH="' .. pkgconfig_dir .. ':${PKG_CONFIG_PATH:-}" '
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
