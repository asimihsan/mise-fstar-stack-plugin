-- lib/shell.lua
-- Small shell/process helpers shared across hooks and lib modules.
-- Keep Lua 5.1 compatible (mise plugin runtime).

local M = {}

-- Shell-escape a string for safe use in os.execute()/io.popen().
function M.quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Check if os.execute succeeded (handles both Lua 5.1 and 5.2+ return values).
function M.exec_succeeded(result)
	return result == true or result == 0
end

-- Run a command and return success/failure with captured output on failure.
--
-- Returns: ok (boolean), err (string|nil)
function M.run_command(cmd, description)
	local output_file = os.tmpname()
	local full_cmd = "(" .. cmd .. ") > " .. M.quote(output_file) .. " 2>&1"
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

	if #output > 500 then
		output = output:sub(1, 500) .. "\n... (truncated)"
	end

	return false, (description or "command") .. " failed:\n" .. output
end

-- Run a command and return its stdout (or nil on failure).
-- Note: stderr is redirected to /dev/null.
function M.read_stdout(cmd)
	local f = io.popen(cmd .. " 2>/dev/null")
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

return M

