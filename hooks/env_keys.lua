-- hooks/env_keys.lua
-- Configures environment variables for fstar-stack
-- Exposes both F* and KaRaMeL (when available)

local file = require("file")

-- Z3 versions bundled with F* releases, in preference order
local Z3_VERSIONS = {
	"4.13.3", -- F*'s default
	"4.15.3",
	"4.8.5",
}

-- Find the first available Z3 version in the installation
local function find_z3_bin(main_path)
	local fstar_lib = file.join_path(main_path, "lib", "fstar")

	for _, version in ipairs(Z3_VERSIONS) do
		local z3_bin = file.join_path(fstar_lib, "z3-" .. version, "bin")
		if file.exists(z3_bin) then
			return z3_bin
		end
	end

	-- Fallback: return default path
	return file.join_path(fstar_lib, "z3-4.13.3", "bin")
end

function PLUGIN:EnvKeys(ctx) -- luacheck: ignore
	local main_path = ctx.path

	-- Mise extracts F* directly to main_path (no fstar/ subdirectory)
	-- Structure: {main_path}/bin/fstar.exe, {main_path}/lib/fstar/...

	local env_vars = {
		-- FSTAR_HOME points to the installation root
		{
			key = "FSTAR_HOME",
			value = main_path,
		},
		-- Add F* binary directory to PATH
		{
			key = "PATH",
			value = file.join_path(main_path, "bin"),
		},
	}

	-- Add bundled Z3 to PATH
	local z3_bin = find_z3_bin(main_path)
	table.insert(env_vars, {
		key = "PATH",
		value = z3_bin,
	})

	-- TODO (Phase 2): Add KaRaMeL paths
	-- KaRaMeL will be installed under {main_path}/karamel/
	local karamel_path = file.join_path(main_path, "karamel")
	if file.exists(karamel_path) then
		table.insert(env_vars, {
			key = "KRML_HOME",
			value = karamel_path,
		})
		-- KaRaMeL binary is in _build/default/src/
		table.insert(env_vars, {
			key = "PATH",
			value = file.join_path(karamel_path, "_build", "default", "src"),
		})
	end

	return env_vars
end
