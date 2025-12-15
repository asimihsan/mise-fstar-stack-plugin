-- hooks/post_install.lua
-- Performs setup after fstar-stack installation
-- Installs F* binary and builds KaRaMeL from source

local file = require("file")
local prerequisites = require("lib.prerequisites")
local versions = require("lib.versions")

-- Shell-escape a path for safe use in os.execute()
local function quote(path)
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Check if os.execute succeeded (handles both Lua 5.1 and 5.2+ return values)
local function exec_succeeded(result)
	return result == true or result == 0
end

-- Run a command and return success/failure with captured output on failure
local function run_command(cmd, description)
	-- Create temp file for output capture
	local output_file = os.tmpname()
	-- Wrap entire command in parentheses so redirect captures all output
	-- (including compound commands like "cd x && git y")
	local full_cmd = "(" .. cmd .. ") > " .. quote(output_file) .. " 2>&1"
	local result = os.execute(full_cmd)

	if exec_succeeded(result) then
		os.remove(output_file)
		return true, nil
	end

	-- Read output for error message
	local f = io.open(output_file, "r")
	local output = ""
	if f then
		output = f:read("*a") or ""
		f:close()
	end
	os.remove(output_file)

	-- Truncate long output
	if #output > 500 then
		output = output:sub(1, 500) .. "\n... (truncated)"
	end

	return false, description .. " failed:\n" .. output
end

-- Build environment string for opam commands
local function opam_env(opam_root)
	return "OPAMROOT=" .. quote(opam_root) .. " OPAMYES=1 OPAMCOLOR=never "
end

-- Get native architecture on macOS
-- Returns "arm64", "x86_64", or nil
local function get_native_arch(os_type)
	if os_type ~= "darwin" then
		return nil
	end
	local f = io.popen("uname -m 2>/dev/null")
	if f then
		local arch = f:read("*a"):gsub("%s+", "")
		f:close()
		if arch == "arm64" or arch == "x86_64" then
			return arch
		end
	end
	return nil
end

-- Get C compiler/assembler flags to hardwire architecture into OCaml's toolchain
-- This is the key fix for OCaml issue #10374: bake -arch into CC/AS/CFLAGS/LDFLAGS
-- so ocamlopt always calls clang and the assembler with the correct architecture
-- See: https://github.com/ocaml/ocaml/issues/10374
local function get_arch_cc_flags(os_type)
	local arch = get_native_arch(os_type)
	if arch then
		return 'CC="clang -arch ' .. arch .. '" '
			.. 'AS="clang -arch ' .. arch .. ' -c" '
			.. 'CFLAGS="-arch ' .. arch .. '" '
			.. 'LDFLAGS="-arch ' .. arch .. '" '
	end
	return ""
end

function PLUGIN:PostInstall(ctx) -- luacheck: ignore
	-- Defensive checks for context structure
	if not ctx then
		error("PostInstall received nil context")
	end
	if not ctx.sdkInfo then
		error("PostInstall context missing sdkInfo")
	end
	if not ctx.sdkInfo[PLUGIN.name] then
		error("PostInstall context missing sdkInfo for " .. PLUGIN.name)
	end

	local sdk_info = ctx.sdkInfo[PLUGIN.name]
	local path = sdk_info.path
	if not path or path == "" then
		error("PostInstall context missing install path for " .. PLUGIN.name)
	end
	-- Use sdk_info.version for the version being installed
	-- (ctx.runtimeVersion returns plugin version, not tool version)
	local version = sdk_info.version
	if not version or version == "" then
		error("PostInstall context missing sdk_info.version")
	end
	local os_type = RUNTIME.osType -- luacheck: ignore

	if os_type == "windows" then
		error(
			"Windows is not yet supported.\n"
				.. "The plugin uses Unix shell commands (chmod, xattr).\n"
				.. "Please install F* manually from: https://github.com/FStarLang/FStar/releases"
		)
	end

	-- Mise extracts tarball contents directly to install path
	-- (strips the top-level fstar/ directory)
	-- Structure: {path}/bin/fstar.exe, {path}/lib/fstar/ulib/...

	-- Paths for verification
	local bin_dir = file.join_path(path, "bin")
	local ulib_dir = file.join_path(path, "lib", "fstar", "ulib")
	local fstar_exe = file.join_path(bin_dir, "fstar.exe")

	-- On macOS: Remove quarantine attributes (can be skipped with env var)
	if os_type == "darwin" then
		local skip_unquarantine = os.getenv("MISE_FSTAR_STACK_SKIP_UNQUARANTINE")
		if skip_unquarantine ~= "1" then
			os.execute("xattr -rd com.apple.quarantine " .. quote(bin_dir) .. " 2>/dev/null")
			os.execute("xattr -rd com.apple.quarantine " .. quote(path) .. "/lib/fstar/z3-*/bin 2>/dev/null")
		end
	end

	-- Set executable permissions
	os.execute("chmod +x " .. quote(bin_dir) .. "/* 2>/dev/null")
	os.execute("chmod +x " .. quote(path) .. "/lib/fstar/z3-*/bin/* 2>/dev/null")

	-- Verify installation
	if not file.exists(ulib_dir) then
		error("F* installation incomplete: lib/fstar/ulib not found. Expected at: " .. ulib_dir)
	end

	if not file.exists(fstar_exe) then
		error("F* installation incomplete: bin/fstar.exe not found. Expected at: " .. fstar_exe)
	end

	local test_result = os.execute(quote(fstar_exe) .. " --version > /dev/null 2>&1")
	if not exec_succeeded(test_result) then
		error("F* binary verification failed")
	end

	-- ========================================
	-- Phase 2: Build KaRaMeL from source
	-- ========================================

	-- Allow skipping KaRaMeL build via environment variable
	local skip_karamel = os.getenv("MISE_FSTAR_STACK_SKIP_KARAMEL")
	if skip_karamel == "1" then
		return -- F* only installation
	end

	-- Get stack configuration for KaRaMeL/OCaml versions
	local stack_config = versions.get_stack_config(version)
	if not stack_config then
		error("Unknown stack version: " .. tostring(version))
	end

	local karamel_config = stack_config.karamel
	local ocaml_config = stack_config.ocaml

	-- Check prerequisites before doing any work
	local prereq_err = prerequisites.check_all_prerequisites(os_type)
	if prereq_err then
		error(prereq_err)
	end

	-- Check architecture consistency on macOS (arm64 vs x86_64 mismatch causes assembler errors)
	local arch_err = prerequisites.check_architecture(os_type)
	if arch_err then
		error(arch_err)
	end

	-- Get appropriate make command (gmake on macOS if available)
	local make_cmd = prerequisites.get_make_command(os_type)

	-- Paths for KaRaMeL build
	local opam_root = file.join_path(path, "opam")
	local karamel_dir = file.join_path(path, "karamel")
	local krml_exe = file.join_path(karamel_dir, "_build", "default", "src", "Karamel.exe")

	-- Environment for opam commands
	local opam_prefix = opam_env(opam_root)

	-- Get architecture-specific compiler flags for macOS
	-- This bakes -arch arm64/x86_64 into OCaml's C toolchain configuration
	local arch_cc_flags = get_arch_cc_flags(os_type)
	local native_arch = get_native_arch(os_type)

	-- Step 1: Initialize opam (isolated root, no shell setup)
	local ok, err = run_command(opam_prefix .. "opam init --bare --no-setup --disable-sandboxing", "opam init")
	if not ok then
		error(err)
	end

	-- Step 1b: Set opam arch variable for macOS (ensures opam knows the target architecture)
	-- This matches the OCaml community guidance for handling dual-arch situations
	if native_arch then
		ok, err = run_command(opam_prefix .. "opam var --global arch=" .. native_arch, "opam var arch")
		if not ok then
			error(err)
		end
	end

	-- Step 2: Create OCaml switch with architecture-specific compiler flags
	-- The key fix for OCaml issue #10374: bake -arch into CC/CFLAGS/LDFLAGS
	-- so ocamlopt always calls clang with the correct architecture
	local ocaml_version = ocaml_config.version
	local switch_cmd = arch_cc_flags .. opam_prefix .. "opam switch create default " .. ocaml_version .. " --no-switch"
	ok, err = run_command(switch_cmd, "opam switch create")
	if not ok then
		error(err)
	end

	-- Step 3: Install OCaml packages
	-- Build package install command (let opam solve versions)
	local packages = table.concat(ocaml_config.packages, " ")
	ok, err = run_command(opam_prefix .. "opam install --switch=default " .. packages, "opam install packages")
	if not ok then
		error(err)
	end

	-- Step 4: Clone KaRaMeL at pinned commit
	local karamel_commit = karamel_config.commit
	local karamel_repo = karamel_config.repository

	ok, err =
		run_command("git clone --recursive " .. quote(karamel_repo) .. " " .. quote(karamel_dir), "git clone karamel")
	if not ok then
		error(err)
	end

	-- Checkout pinned commit
	ok, err = run_command("cd " .. quote(karamel_dir) .. " && git checkout " .. karamel_commit, "git checkout commit")
	if not ok then
		error(err)
	end

	-- Update submodules for the checked-out commit
	ok, err = run_command(
		"cd " .. quote(karamel_dir) .. " && git submodule update --init --recursive",
		"git submodule update"
	)
	if not ok then
		error(err)
	end

	-- Verify we're at the right commit
	local verify_file = os.tmpname()
	os.execute("cd " .. quote(karamel_dir) .. " && git rev-parse HEAD > " .. quote(verify_file) .. " 2>&1")
	local vf = io.open(verify_file, "r")
	local actual_commit = ""
	if vf then
		actual_commit = (vf:read("*l") or ""):gsub("%s+", "")
		vf:close()
	end
	os.remove(verify_file)

	if actual_commit ~= karamel_commit then
		error(
			"KaRaMeL commit verification failed.\n"
				.. "Expected: "
				.. karamel_commit
				.. "\n"
				.. "Actual: "
				.. actual_commit
		)
	end

	-- Step 5: Build KaRaMeL
	-- Need to use opam exec to have the right OCaml environment
	-- Architecture is already baked into OCaml's toolchain via CC/CFLAGS/LDFLAGS at switch creation
	local build_env = opam_prefix .. "FSTAR_EXE=" .. quote(fstar_exe) .. " " .. "FSTAR_HOME=" .. quote(path) .. " "

	ok, err = run_command(
		"cd "
			.. quote(karamel_dir)
			.. " && "
			.. build_env
			.. "opam exec --switch=default -- "
			.. make_cmd
			.. " -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)",
		"karamel build"
	)
	if not ok then
		error(err)
	end

	-- Step 6: Build krmllib
	ok, err = run_command(
		"cd "
			.. quote(karamel_dir)
			.. " && "
			.. build_env
			.. "opam exec --switch=default -- "
			.. make_cmd
			.. " -C krmllib",
		"krmllib build"
	)
	if not ok then
		error(err)
	end

	-- Verify KaRaMeL installation
	if not file.exists(krml_exe) then
		error("KaRaMeL build incomplete: Karamel.exe not found. Expected at: " .. krml_exe)
	end

	-- Test krml works (need opam environment for OCaml libs)
	-- Note: KaRaMeL uses single-dash flags (-version, not --version)
	local krml_test_cmd = opam_prefix .. "opam exec --switch=default -- " .. quote(krml_exe) .. " -version"
	local test_output_file = os.tmpname()
	local krml_test = os.execute(krml_test_cmd .. " > " .. quote(test_output_file) .. " 2>&1")
	if not exec_succeeded(krml_test) then
		-- Read output for error message
		local tf = io.open(test_output_file, "r")
		local test_output = ""
		if tf then
			test_output = tf:read("*a") or ""
			tf:close()
		end
		os.remove(test_output_file)
		error("KaRaMeL binary verification failed:\n" .. test_output)
	end
	os.remove(test_output_file)
end
