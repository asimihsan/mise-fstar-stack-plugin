-- lib/shell.lua
-- Small shell/process helpers shared across hooks and lib modules.
-- Keep Lua 5.1 compatible (mise plugin runtime).

local M = {}

local function is_windows()
	return (RUNTIME and RUNTIME.osType) == "windows" -- luacheck: ignore
end

-- Shell-escape a string for safe use in os.execute()/io.popen().
function M.quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Quote a string for cmd.exe (double quotes).
-- Note: we keep this minimal; most paths should not contain quotes.
local function quote_cmd(value)
	return '"' .. tostring(value):gsub('"', '""') .. '"'
end

-- Escape a string for inclusion in a cmd.exe double-quoted argument.
-- This is primarily used to pass a bash -lc "<cmd>" payload on Windows.
local function escape_cmd_double_quotes(value)
	-- cmd.exe uses " to delimit arguments; escape by backslash for bash.
	-- We avoid introducing double quotes in our bash payload where possible,
	-- but still defensively escape them.
	return tostring(value):gsub('"', '\\"')
end

-- Convert Windows paths to a form understood by Unix-y shells on Windows.
-- Cygwin/MSYS generally accept "C:/path/to/dir" reliably (forward slashes).
function M.to_mixed_path(path)
	if not is_windows() then
		return path
	end
	return tostring(path):gsub("\\", "/")
end

-- Check if os.execute succeeded (handles both Lua 5.1 and 5.2+ return values).
function M.exec_succeeded(result)
	return result == true or result == 0
end

-- Check if a command exists in PATH.
function M.command_exists(cmd_name)
	if not cmd_name or cmd_name == "" then
		return false
	end

	if is_windows() then
		local result = os.execute("where.exe " .. cmd_name .. " > NUL 2>&1")
		return M.exec_succeeded(result)
	end

	local result = os.execute("command -v " .. M.quote(cmd_name) .. " >/dev/null 2>&1")
	return M.exec_succeeded(result)
end

-- Run a command and return success/failure with captured output on failure.
--
-- Returns: ok (boolean), err (string|nil)
function M.run_command(cmd, description)
	local output_file = os.tmpname()
	local full_cmd
	if is_windows() then
		-- On Windows, Lua's os.execute() uses cmd.exe, which does not understand
		-- POSIX quoting or /dev/null. We run our payload in bash (Git Bash,
		-- MSYS2, or Cygwin), and keep redirection in cmd.exe.
		-- MSYS2 provides toolchain binaries under /mingw64/bin. When running `bash -c`
		-- non-interactively (and especially from cmd.exe), PATH can be missing these,
		-- so we defensively prepend it.
		local bash_payload = escape_cmd_double_quotes("export PATH=/mingw64/bin:/usr/bin:$PATH; " .. cmd)
		-- Avoid `-l` (login shell) because it can reset PATH and hide MSYS2/MINGW tools.
		full_cmd = 'bash -c "' .. bash_payload .. '" > ' .. quote_cmd(output_file) .. " 2>&1"
	else
		full_cmd = "(" .. cmd .. ") > " .. M.quote(output_file) .. " 2>&1"
	end
	local result = os.execute(full_cmd)

	if M.exec_succeeded(result) then
		os.remove(output_file)
		return true, nil
	end

	local f = io.open(output_file, "r")
	local output = ""
	if f then
		output = f:read("*a") or ""
		f:close()
	end
	os.remove(output_file)

	-- Include enough context for build tools like opam, but avoid multi-megabyte logs.
	local max_chars = 8000
	local head_chars = 2000
	local tail_chars = max_chars - head_chars

	if #output > max_chars then
		local head = output:sub(1, head_chars)
		local tail = output:sub(#output - tail_chars + 1)
		output = head .. "\n... (truncated) ...\n" .. tail
	end

	return false, (description or "command") .. " failed:\n" .. output
end

-- Run a command and return its stdout (or nil on failure).
-- Note: stderr is redirected to /dev/null.
function M.read_stdout(cmd)
	local full_cmd
	if is_windows() then
		-- Avoid `-l` for the same reason as run_command() above.
		full_cmd = 'bash -c "'
			.. escape_cmd_double_quotes("export PATH=/mingw64/bin:/usr/bin:$PATH; " .. cmd .. " 2>/dev/null")
			.. '"'
	else
		full_cmd = cmd .. " 2>/dev/null"
	end

	local f = io.popen(full_cmd)
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

-- Compute sha256 of a file, returning the lowercase hex digest.
-- Tries common tools available on macOS/Linux runners.
function M.sha256_file(path)
	local quoted = M.quote(path)

	local out = M.read_stdout("shasum -a 256 " .. quoted)
	if not out or out == "" then
		out = M.read_stdout("sha256sum " .. quoted)
	end
	if not out or out == "" then
		out = M.read_stdout("openssl dgst -sha256 " .. quoted)
	end
	if not out or out == "" then
		return nil
	end

	-- shasum/sha256sum format: "<hash>  <file>"
	local hash = out:match("^(%x+)%s")
	-- openssl format: "SHA256(<file>)= <hash>"
	if not hash then
		hash = out:match("=%s*(%x+)$")
	end
	if not hash then
		return nil
	end
	return hash:lower()
end

return M
