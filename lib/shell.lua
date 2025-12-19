-- lib/shell.lua
-- Small shell/process helpers shared across hooks and lib modules.
-- Keep Lua 5.1 compatible (mise plugin runtime).

local M = {}

local cmd = require("cmd")

local function is_windows()
	return (RUNTIME and RUNTIME.osType) == "windows" -- luacheck: ignore
end

local function trim_end(value)
	return (tostring(value or ""):gsub("%s+$", ""))
end

local function windows_inline_shell_args()
	if not is_windows() then
		return nil
	end
	local args = os.getenv("MISE_WINDOWS_DEFAULT_INLINE_SHELL_ARGS")
	if args == nil or args == "" then
		return nil
	end
	return args
end

local function normalize_windows_path_list(path_value)
	if not is_windows() then
		return path_value
	end
	if not path_value or path_value == "" then
		return ""
	end
	if not path_value:find(";") then
		return path_value
	end
	local parts = {}
	for part in path_value:gmatch("[^;]+") do
		local p = part:gsub("\\", "/")
		local drive, rest = p:match("^([A-Za-z]):/(.*)")
		if drive then
			p = "/" .. drive:lower() .. "/" .. rest
		end
		table.insert(parts, p)
	end
	return table.concat(parts, ":")
end

local function wrap_windows_command(command)
	local shell_args = windows_inline_shell_args()
	if not shell_args then
		return command
	end
	local env_path = normalize_windows_path_list(os.getenv("PATH") or "")
	local injected = "export PATH=" .. M.quote(env_path) .. "; " .. command
	local function quote_for_cmd(arg)
		local escaped = tostring(arg):gsub('"', '\\"')
		return '"' .. escaped .. '"'
	end
	return shell_args .. " " .. quote_for_cmd(injected)
end

-- Shell-escape a string for safe use in shell commands.
function M.quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Convert Windows paths to a form understood by Unix-y shells on Windows.
-- Cygwin/MSYS generally accept "C:/path/to/dir" reliably (forward slashes).
function M.to_mixed_path(path)
	if not is_windows() then
		return path
	end
	return tostring(path):gsub("\\", "/")
end

-- Check if a command execution succeeded (os.execute or cmd.exec pcall).
function M.exec_succeeded(result)
	return result == true or result == 0
end

-- Check if a command exists in PATH.
function M.command_exists(cmd_name)
	if not cmd_name or cmd_name == "" then
		return false
	end
	local probe = "command -v " .. M.quote(cmd_name)
	local ok = pcall(cmd.exec, wrap_windows_command(probe))
	return ok == true
end

-- Run a command and return success/failure with captured output on failure.
-- Returns: ok (boolean), err (string|nil)
function M.run_command(command, description, opts)
	opts = opts or {}
	local ok, out = pcall(cmd.exec, wrap_windows_command(command), opts)
	if ok then
		return true, nil
	end

	out = tostring(out or "")
	local max_chars = 8000
	if #out > max_chars then
		local head = out:sub(1, 2000)
		local tail = out:sub(#out - (max_chars - 2000) + 1)
		out = head .. "\n... (truncated) ...\n" .. tail
	end

	return false, (description or "command") .. " failed:\n" .. out
end

-- Run a command and return its stdout (or nil on failure).
function M.read_stdout(command, opts)
	opts = opts or {}
	local ok, out = pcall(cmd.exec, wrap_windows_command(command), opts)
	if not ok then
		return nil
	end
	return trim_end(out)
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
