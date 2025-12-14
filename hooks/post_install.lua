-- hooks/post_install.lua
-- Performs setup after fstar-stack installation
-- Installs F* binary; KaRaMeL build will be added in Phase 2

local file = require("file")

-- Shell-escape a path for safe use in os.execute()
local function quote(path)
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Check if os.execute succeeded (handles both Lua 5.1 and 5.2+ return values)
local function exec_succeeded(result)
	return result == true or result == 0
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

	-- TODO (Phase 2): Add KaRaMeL build here
	-- 1. Check prerequisites (opam, gmake, git, pkg-config, gmp)
	-- 2. Create isolated opam root at {path}/opam/
	-- 3. opam init && opam switch create
	-- 4. Install opam packages
	-- 5. Clone KaRaMeL at pinned commit to {path}/karamel/
	-- 6. Build KaRaMeL with FSTAR_EXE pointing to installed F*
end
