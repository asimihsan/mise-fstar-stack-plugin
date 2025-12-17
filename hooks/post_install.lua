-- hooks/post_install.lua
-- Performs setup after fstar-stack installation
-- Installs F* binary and builds KaRaMeL from source

local file = require("file")
local prerequisites = require("lib.prerequisites")
local versions = require("lib.versions")
local find_install = require("lib.find_install")
local platform = require("lib.platform")
local shell = require("lib.shell")

local quote = shell.quote
local exec_succeeded = shell.exec_succeeded
local run_command = shell.run_command

-- Build environment string for opam commands
local function opam_env(opam_root)
	return "OPAMROOT=" .. quote(opam_root) .. " OPAMYES=1 OPAMCOLOR=never "
end

-- Download a file using curl
local function download_file(url, dest_path, description)
	local cmd = "curl -fsSL " .. quote(url) .. " -o " .. quote(dest_path)
	local ok, err = run_command(cmd, description or "download")
	return ok, err
end

-- Extract a zip file
local function extract_zip(zip_path, dest_dir, description)
	local cmd = "unzip -q " .. quote(zip_path) .. " -d " .. quote(dest_dir)
	local ok, err = run_command(cmd, description or "extract zip")
	return ok, err
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
		return 'CC="clang -arch '
			.. arch
			.. '" '
			.. 'AS="clang -arch '
			.. arch
			.. ' -c" '
			.. 'CFLAGS="-arch '
			.. arch
			.. '" '
			.. 'LDFLAGS="-arch '
			.. arch
			.. '" '
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

	-- Check if this platform requires building F* from source
	local platform_key = platform.platform_key()
	local is_source_build = versions.needs_fstar_source_build(platform_key)

	-- For source builds, we need to build F* before verification
	if is_source_build then
		-- Get stack configuration early
		local stack_config = versions.get_stack_config(version)
		if not stack_config then
			error("Unknown stack version: " .. tostring(version))
		end

		local fstar_config = stack_config.fstar
		local z3_config = stack_config.z3
		local ocaml_config = stack_config.ocaml
		local karamel_config = stack_config.karamel

		-- Check prerequisites before doing any work
		local prereq_err = prerequisites.check_all_prerequisites(os_type)
		if prereq_err then
			error(prereq_err)
		end

		-- Get make command
		local make_cmd = prerequisites.get_make_command(os_type)

		-- Paths
		local opam_root = file.join_path(path, "opam")
		local opam_prefix = opam_env(opam_root)

		-- Mise extracts tarball and moves contents of FStar-{version}/ directly to install path
		-- (it strips the top-level directory, so files are directly at `path`)
		local fstar_src = path

		print("=== Building F* from source (this will take 30+ minutes) ===")
		print("Platform: " .. platform_key)
		print("F* version: " .. fstar_config.tag)

		-- Step 1: Download and install Z3
		print("Step 1/7: Downloading Z3...")
		local z3_url = z3_config.urls[platform_key]
		if not z3_url then
			error("No Z3 binary URL configured for " .. platform_key)
		end

		local z3_zip = file.join_path(path, "z3.zip")
		local ok, err = download_file(z3_url, z3_zip, "download Z3")
		if not ok then
			error(err)
		end

		-- Extract Z3 to temp location
		local z3_extract_dir = file.join_path(path, "z3_extract")
		ok, err = extract_zip(z3_zip, z3_extract_dir, "extract Z3")
		if not ok then
			error(err)
		end

		-- Z3 extracts to z3-{version}-{platform}/ directory, move contents to lib/fstar/z3-{version}/
		local z3_version = z3_config.version
		local z3_dest = file.join_path(path, "lib", "fstar", "z3-" .. z3_version)
		ok, err = run_command("mkdir -p " .. quote(file.join_path(path, "lib", "fstar")), "create lib/fstar")
		if not ok then
			error(err)
		end
		-- Find the extracted directory (should be z3-4.13.3-arm64-glibc-2.34 or similar)
		ok, err = run_command("mv " .. quote(z3_extract_dir) .. "/z3-* " .. quote(z3_dest), "move Z3 to lib/fstar")
		if not ok then
			error(err)
		end

		-- Cleanup
		os.remove(z3_zip)
		os.execute("rm -rf " .. quote(z3_extract_dir))

		-- Make Z3 executable
		os.execute("chmod +x " .. quote(z3_dest) .. "/bin/* 2>/dev/null")

		local z3_bin_path = file.join_path(z3_dest, "bin")

		-- Step 2: Initialize opam
		print("Step 2/7: Initializing opam...")
		ok, err = run_command(opam_prefix .. "opam init --bare --no-setup --disable-sandboxing", "opam init")
		if not ok then
			error(err)
		end

		-- Step 3: Create OCaml switch
		print("Step 3/7: Creating OCaml switch (this takes several minutes)...")
		local ocaml_version = ocaml_config.version
		ok, err = run_command(
			opam_prefix .. "opam switch create default " .. ocaml_version .. " --no-switch",
			"opam switch create"
		)
		if not ok then
			error(err)
		end

		-- Step 4: Install F* opam dependencies
		print("Step 4/7: Installing F* dependencies...")
		-- Need to set OPAMSWITCH explicitly for nested opam commands
		local opam_switch_prefix = opam_prefix .. "OPAMSWITCH=default "
		ok, err = run_command(
			"cd " .. quote(fstar_src) .. " && " .. opam_switch_prefix .. "opam install --deps-only .",
			"install F* dependencies"
		)
		if not ok then
			error(err)
		end

		-- Step 5: Build F* with Z3 in PATH
		print("Step 5/7: Building F* (this takes 15-30 minutes)...")
		local path_prefix = "PATH=" .. quote(z3_bin_path) .. ":$PATH "
		ok, err = run_command(
			"cd "
				.. quote(fstar_src)
				.. " && "
				.. path_prefix
				.. opam_switch_prefix
				.. "opam exec -- "
				.. make_cmd
				.. " -j$(nproc 2>/dev/null || echo 4)",
			"build F*"
		)
		if not ok then
			error(err)
		end

		-- Step 6: Install F* to mise path
		print("Step 6/7: Installing F*...")
		ok, err = run_command(
			"cd "
				.. quote(fstar_src)
				.. " && "
				.. opam_switch_prefix
				.. "opam exec -- "
				.. make_cmd
				.. " install PREFIX="
				.. quote(path),
			"install F*"
		)
		if not ok then
			error(err)
		end

		-- Cleanup source directory (optional - saves ~500MB)
		-- Keeping it for now for debugging
		-- os.execute("rm -rf " .. quote(fstar_src))

		-- Now verify F* installation and build KaRaMeL
		print("Step 7/7: Building KaRaMeL...")

		-- Paths for verification (now F* is installed)
		local bin_dir = file.join_path(path, "bin")
		local ulib_dir = file.join_path(path, "lib", "fstar", "ulib")
		local fstar_exe = file.join_path(bin_dir, "fstar.exe")

		-- Set executable permissions
		os.execute("chmod +x " .. quote(bin_dir) .. "/* 2>/dev/null")

		-- Verify F* installation
		if not file.exists(fstar_exe) then
			error("F* build incomplete: bin/fstar.exe not found. Expected at: " .. fstar_exe)
		end

		local test_result = os.execute(quote(fstar_exe) .. " --version > /dev/null 2>&1")
		if not exec_succeeded(test_result) then
			error("F* binary verification failed")
		end

		if not file.exists(ulib_dir) then
			error("F* installation incomplete: lib/fstar/ulib not found. Expected at: " .. ulib_dir)
		end

		-- Build KaRaMeL
		local karamel_dir = file.join_path(path, "karamel")
		local karamel_commit = karamel_config.commit
		local karamel_repo = karamel_config.repository

		ok, err =
			run_command("git clone --recursive " .. quote(karamel_repo) .. " " .. quote(karamel_dir), "git clone karamel")
		if not ok then
			error(err)
		end

		ok, err =
			run_command("cd " .. quote(karamel_dir) .. " && git checkout " .. karamel_commit, "git checkout commit")
		if not ok then
			error(err)
		end

		ok, err = run_command(
			"cd " .. quote(karamel_dir) .. " && git submodule update --init --recursive",
			"git submodule update"
		)
		if not ok then
			error(err)
		end

		-- Install KaRaMeL OCaml packages (merge with F* packages that are already installed)
		local packages = table.concat(ocaml_config.packages, " ")
		ok, err = run_command(opam_switch_prefix .. "opam install " .. packages, "opam install karamel packages")
		if not ok then
			error(err)
		end

		-- Build KaRaMeL
		local build_env = opam_switch_prefix .. "FSTAR_EXE=" .. quote(fstar_exe) .. " FSTAR_HOME=" .. quote(path) .. " "
		ok, err = run_command(
			"cd "
				.. quote(karamel_dir)
				.. " && "
				.. build_env
				.. "opam exec -- "
				.. make_cmd
				.. " -j$(nproc 2>/dev/null || echo 4)",
			"karamel build"
		)
		if not ok then
			error(err)
		end

		-- Build krmllib
		ok, err = run_command(
			"cd " .. quote(karamel_dir) .. " && " .. build_env .. "opam exec -- " .. make_cmd .. " -C krmllib",
			"krmllib build"
		)
		if not ok then
			error(err)
		end

		-- Verify KaRaMeL installation
		local krml_exe = file.join_path(karamel_dir, "_build", "default", "src", "Karamel.exe")
		if not file.exists(krml_exe) then
			error("KaRaMeL build incomplete: Karamel.exe not found. Expected at: " .. krml_exe)
		end

		local krml_test_cmd = opam_switch_prefix .. "opam exec -- " .. quote(krml_exe) .. " -version"
		local krml_test = os.execute(krml_test_cmd .. " > /dev/null 2>&1")
		if not exec_succeeded(krml_test) then
			error("KaRaMeL binary verification failed")
		end

		print("=== F* source build complete ===")
		return -- Done with source build path
	end

	-- ========================================
	-- Pre-built binary path (darwin_*, linux_amd64)
	-- ========================================

	-- Step 1: Detect and normalize installation structure
	-- Mise may or may not strip the top-level directory from tarballs
	-- We use reference files (fstar.exe, ulib/) to find the actual root
	print("Step 1/5: Detecting installation structure...")
	local actual_root, is_normalized = find_install.find_fstar_root(path)

	if not actual_root then
		-- Provide helpful debugging info
		local contents = find_install.list_directory(path)
		error(
			"Could not find F* installation in extracted contents.\n"
				.. "Expected to find bin/fstar.exe or lib/fstar/ulib/ in:\n"
				.. path
				.. "\n\n"
				.. "Extracted contents:\n"
				.. contents
		)
	end

	if not is_normalized then
		print("  Found F* at: " .. actual_root)
		print("  Moving to expected location...")
		local ok, err = find_install.normalize_structure(path, actual_root)
		if not ok then
			error("Failed to normalize installation structure: " .. (err or "unknown error"))
		end
		print("  Structure normalized successfully")
	end

	-- Paths for verification (now guaranteed to be at expected location)
	local bin_dir = file.join_path(path, "bin")
	local ulib_dir = file.join_path(path, "lib", "fstar", "ulib")
	local fstar_exe = file.join_path(bin_dir, "fstar.exe")

	-- Step 2: Set permissions and remove quarantine
	print("Step 2/5: Setting permissions...")

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

	-- Step 3: Verify F* installation
	print("Step 3/5: Verifying F* installation...")
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
		print("Step 4/5: Skipping KaRaMeL build (MISE_FSTAR_STACK_SKIP_KARAMEL=1)")
		print("Step 5/5: Installation complete (F* only)")
		return -- F* only installation
	end

	-- Step 4: Build KaRaMeL
	print("Step 4/5: Building KaRaMeL (this takes several minutes)...")

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
	-- Include arch_cc_flags to ensure krmllib C code is also built for the correct architecture
	-- (krmllib calls the system C compiler directly, not through OCaml's wrapped compiler)
	local build_env = arch_cc_flags
		.. opam_prefix
		.. "FSTAR_EXE="
		.. quote(fstar_exe)
		.. " "
		.. "FSTAR_HOME="
		.. quote(path)
		.. " "

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

	-- Step 6b: Verify krmllib architecture on macOS
	-- This catches build environment issues (e.g., running under Rosetta) early
	if os_type == "darwin" and native_arch then
		local krmllib_path = file.join_path(karamel_dir, "krmllib", "dist", "generic", "libkrmllib.a")
		local arch_check_file = os.tmpname()
		os.execute(
			"lipo -info "
				.. quote(krmllib_path)
				.. " 2>/dev/null | grep -q "
				.. native_arch
				.. " && echo ok > "
				.. quote(arch_check_file)
		)
		local af = io.open(arch_check_file, "r")
		local arch_ok = af and (af:read("*a") or ""):match("ok")
		if af then
			af:close()
		end
		os.remove(arch_check_file)
		if not arch_ok then
			error(
				"krmllib architecture mismatch: expected "
					.. native_arch
					.. " but got wrong architecture.\n"
					.. "This may indicate a build environment issue. Check that you're not running under Rosetta."
			)
		end
	end

	-- Step 5: Verify KaRaMeL installation
	print("Step 5/5: Verifying KaRaMeL installation...")
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
	print("=== fstar-stack installation complete ===")
end
