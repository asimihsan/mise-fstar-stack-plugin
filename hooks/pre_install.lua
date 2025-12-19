-- hooks/pre_install.lua
-- Returns download information for fstar-stack
-- Downloads F* binary; KaRaMeL is built from source in post_install (Phase 2)

local versions = require("lib.versions")

-- Pre-built asset suffixes for each supported platform.
-- We construct the download URL directly instead of querying the GitHub API
-- (CI runners sometimes fail to reach api.github.com reliably).
local PLATFORM_ASSET_SUFFIX = {
	["darwin_arm64"] = "Darwin-arm64.tar.gz",
	["linux_amd64"] = "Linux-x86_64.tar.gz",
	["windows_amd64"] = "Windows_NT-x86_64.zip",
}

-- Supported platforms message for error output
local SUPPORTED_PLATFORMS = "darwin_arm64, linux_amd64, windows_amd64"

local function get_platform_key()
	local os_type = RUNTIME.osType -- luacheck: ignore
	local arch_type = RUNTIME.archType -- luacheck: ignore
	return os_type .. "_" .. arch_type
end

local function github_release_asset_url(tag, asset_name)
	return "https://github.com/FStarLang/FStar/releases/download/" .. tag .. "/" .. asset_name
end

function PLUGIN:PreInstall(ctx) -- luacheck: ignore
	local version = ctx.version
	local platform_key = get_platform_key()

	-- Look up stack version
	local stack_config = versions.get_stack_config(version)
	if stack_config == nil then
		local available = versions.get_available_versions()
		error(
			"Unknown stack version: "
				.. version
				.. "\nAvailable versions: "
				.. table.concat(available, ", ")
				.. "\nRun 'mise ls-remote fstar-stack' to see all versions."
		)
	end

	local fstar_config = stack_config.fstar
	local fstar_tag = fstar_config.tag

	-- For platforms without pre-built binaries, return the source tarball
	-- F* will be built from source in post_install
	if versions.needs_fstar_source_build(platform_key) then
		if not fstar_config.source_url or not fstar_config.source_sha256 then
			error(
				"Source build required for "
					.. platform_key
					.. " but source tarball URL/SHA256 not configured.\n"
					.. "Please update lib/versions.lua with source_url and source_sha256."
			)
		end
		return {
			version = version,
			url = fstar_config.source_url,
			sha256 = fstar_config.source_sha256,
			note = "fstar-stack "
				.. version
				.. " (F* "
				.. fstar_tag
				.. " source - will build from source for "
				.. platform_key
				.. ")",
		}
	end

	local suffix = PLATFORM_ASSET_SUFFIX[platform_key]
	if not suffix then
		error("Unsupported platform: " .. platform_key .. "\nSupported platforms: " .. SUPPORTED_PLATFORMS)
	end

	-- We require a pinned SHA256 in lib/versions.lua for deterministic installs.
	local sha256 = fstar_config.sha256 and fstar_config.sha256[platform_key] or nil
	if not sha256 or sha256 == "" then
		error(
			"Missing SHA256 checksum for " .. platform_key .. " (update lib/versions.lua)\n" .. "F* tag: " .. fstar_tag
		)
	end

	local asset_name = "fstar-" .. fstar_tag .. "-" .. suffix
	local url = github_release_asset_url(fstar_tag, asset_name)

	return {
		version = version,
		url = url,
		sha256 = sha256,
		note = "fstar-stack " .. version .. " (F* " .. fstar_tag .. ")",
	}
end
