-- metadata.lua
-- Plugin metadata for fstar-stack tool
-- This plugin installs both F* and KaRaMeL together as a cohesive stack
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#metadata-lua

PLUGIN = { -- luacheck: ignore
	-- Tool name (lowercase, no spaces)
	name = "fstar-stack",

	-- Plugin version (not the tool version)
	version = "0.1.0",

	-- Brief description of the tool
	description = "F* toolchain stack (F* + KaRaMeL) with pinned compatible versions",

	-- Plugin author/maintainer
	author = "asimihsan",

	-- Repository URL for plugin updates
	updateUrl = "https://github.com/asimihsan/mise-fstar-stack-plugin",

	-- Minimum mise runtime version required
	minRuntimeVersion = "2024.0.0",
}
