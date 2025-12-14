-- hooks/available.lua
-- Returns available stack versions from the versions manifest

local versions = require("lib.versions")

function PLUGIN:Available(ctx) -- luacheck: ignore
	local available = versions.get_available_versions()
	local result = {}

	for _, version in ipairs(available) do
		local note = nil
		if version == versions.LATEST_STACK then
			note = "latest"
		end

		table.insert(result, {
			version = version,
			note = note,
		})
	end

	-- Return array directly, not wrapped in { versions = ... }
	return result
end
