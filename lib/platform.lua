-- lib/platform.lua
-- Centralized platform utilities for fstar-stack plugin
-- Following mise Lua best practices: thin hooks, rich libs

local M = {}

-- Get OS type from mise runtime
function M.os_type()
	return RUNTIME.osType -- luacheck: ignore
end

-- Get architecture type from mise runtime
function M.arch_type()
	return RUNTIME.archType -- luacheck: ignore
end

-- Get platform key (os_arch format)
function M.platform_key()
	return M.os_type() .. "_" .. M.arch_type()
end

-- Check if running on macOS
function M.is_darwin()
	return M.os_type() == "darwin"
end

-- Check if running on Linux
function M.is_linux()
	return M.os_type() == "linux"
end

-- Check if running on Windows
function M.is_windows()
	return M.os_type() == "windows"
end

return M
