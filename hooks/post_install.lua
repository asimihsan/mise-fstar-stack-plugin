-- hooks/post_install.lua
-- Performs setup after fstar-stack installation
-- For the minimal spike, this only installs F* (no KaRaMeL yet)

local file = require("file")

-- Shell-escape a path for safe use in os.execute()
local function quote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Check if os.execute succeeded
local function exec_succeeded(result)
    return result == true or result == 0
end

function PLUGIN:PostInstall(ctx) -- luacheck: ignore
    local sdk_info = ctx.sdkInfo[PLUGIN.name]
    local path = sdk_info.path
    local os_type = RUNTIME.osType -- luacheck: ignore

    if os_type == "windows" then
        error("Windows is not yet supported")
    end

    -- Create subdirectory for F* (to separate from future KaRaMeL)
    local fstar_dir = file.join_path(path, "fstar")
    os.execute("mkdir -p " .. quote(fstar_dir))

    -- F* tarball extracts to a "fstar" subdirectory within the extraction point
    -- Structure after mise extracts: {path}/fstar/bin/fstar.exe
    -- We want: {path}/fstar/bin/fstar.exe (keep it there for organization)

    -- The tarball creates {path}/fstar/... so the structure is already correct
    -- Just need to verify it exists
    local extracted_fstar = file.join_path(path, "fstar")

    if not file.exists(extracted_fstar) then
        -- Maybe it extracted differently, try to find and move
        local move_result = os.execute("ls " .. quote(path) .. "/*/bin/fstar.exe 2>/dev/null")
        if exec_succeeded(move_result) then
            -- Find the actual directory and move contents
            os.execute("mv " .. quote(path) .. "/fstar-*/* " .. quote(fstar_dir) .. "/ 2>/dev/null")
        end
    end

    -- Paths for verification
    local bin_dir = file.join_path(fstar_dir, "bin")
    local ulib_dir = file.join_path(fstar_dir, "lib", "fstar", "ulib")
    local fstar_exe = file.join_path(bin_dir, "fstar.exe")

    -- On macOS: Remove quarantine attributes
    if os_type == "darwin" then
        os.execute("xattr -rd com.apple.quarantine " .. quote(bin_dir) .. " 2>/dev/null")
        os.execute("xattr -rd com.apple.quarantine " .. quote(fstar_dir) .. "/lib/fstar/z3-*/bin 2>/dev/null")
    end

    -- Set executable permissions
    os.execute("chmod +x " .. quote(bin_dir) .. "/* 2>/dev/null")
    os.execute("chmod +x " .. quote(fstar_dir) .. "/lib/fstar/z3-*/bin/* 2>/dev/null")

    -- Verify installation
    if not file.exists(ulib_dir) then
        error("F* installation incomplete: lib/fstar/ulib not found")
    end

    if not file.exists(fstar_exe) then
        error("F* installation incomplete: bin/fstar.exe not found")
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
    -- 5. Clone KaRaMeL at pinned commit
    -- 6. Build KaRaMeL with FSTAR_EXE pointing to installed F*
end
