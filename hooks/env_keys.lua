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

	-- KaRaMeL paths (required; fail fast if missing)
	local karamel_path = file.join_path(main_path, "karamel")
	local opam_root = file.join_path(main_path, "opam")
	local krml_exe = file.join_path(karamel_path, "_build", "default", "src", "Karamel.exe")

	-- Fail if KaRaMeL is missing. This stack requires extraction support.
	if not file.exists(krml_exe) then
		error(
			"KaRaMeL not found (expected "
				.. krml_exe
				.. "). "
				.. "Installation is incomplete; re-run `mise install` for this version."
		)
	end

	table.insert(env_vars, {
		key = "KRML_HOME",
		value = karamel_path,
	})
	-- KaRaMeL binary is in _build/default/src/
	table.insert(env_vars, {
		key = "PATH",
		value = file.join_path(karamel_path, "_build", "default", "src"),
	})
	-- krmllib headers and C files
	table.insert(env_vars, {
		key = "KRML_INCLUDE",
		value = file.join_path(karamel_path, "krmllib", "dist", "minimal"),
	})

	-- Set up opam root for KaRaMeL's OCaml dependencies
	if file.exists(opam_root) then
		table.insert(env_vars, {
			key = "OPAMROOT",
			value = opam_root,
		})
		-- Set default switch so users don't get "no switch set" errors
		table.insert(env_vars, {
			key = "OPAMSWITCH",
			value = "default",
		})
	end

	return env_vars
end
