-- hooks/pre_install.lua
-- Returns download information for fstar-stack
-- For the minimal spike, this downloads F* only (no KaRaMeL yet)

local http = require("http")
local json = require("json")

-- Stack version manifest - maps stack versions to component versions
-- This will move to lib/versions.lua in the full implementation
local STACK_VERSIONS = {
	["2025.10.06-stack.1"] = {
		fstar_tag = "v2025.10.06",
	},
}

-- Platform patterns for matching F* release asset names
local PLATFORM_PATTERNS = {
	["darwin_arm64"] = "Darwin%-arm64",
	["darwin_amd64"] = "Darwin%-x86_64",
	["linux_amd64"] = "Linux%-x86_64",
	["linux_arm64"] = "Linux%-arm64",
	["windows_amd64"] = "Windows_NT%-x86_64",
}

local function get_platform_key()
	local os_type = RUNTIME.osType -- luacheck: ignore
	local arch_type = RUNTIME.archType -- luacheck: ignore
	return os_type .. "_" .. arch_type
end

local function extract_sha256(digest)
	if digest and digest:match("^sha256:") then
		return digest:gsub("^sha256:", "")
	end
	return nil
end

function PLUGIN:PreInstall(ctx) -- luacheck: ignore
	local version = ctx.version
	local platform_key = get_platform_key()

	-- Look up stack version
	local stack_config = STACK_VERSIONS[version]
	if stack_config == nil then
		error("Unknown stack version: " .. version .. ". Available: 2025.10.06-stack.1")
	end

	local fstar_tag = stack_config.fstar_tag

	-- Get the pattern for this platform
	local pattern = PLATFORM_PATTERNS[platform_key]
	if pattern == nil then
		error("Unsupported platform: " .. platform_key)
	end

	-- Query GitHub releases API for F* assets
	local release_url = "https://api.github.com/repos/FStarLang/FStar/releases/tags/" .. fstar_tag
	local resp, err = http.get({
		url = release_url,
		headers = {
			["Accept"] = "application/vnd.github.v3+json",
			["User-Agent"] = "mise-fstar-stack-plugin",
		},
	})

	if err ~= nil then
		error("Failed to fetch release info: " .. tostring(err))
	end

	if resp.status_code ~= 200 then
		error("GitHub API error (status " .. resp.status_code .. ")")
	end

	local release = json.decode(resp.body)

	-- Find matching asset for this platform
	for _, asset in ipairs(release.assets) do
		if asset.name:match(pattern) and not asset.name:match("%-src") then
			local sha256 = extract_sha256(asset.digest)

			return {
				version = version,
				url = asset.browser_download_url,
				sha256 = sha256,
				note = "fstar-stack " .. version .. " (F* " .. fstar_tag .. ")",
			}
		end
	end

	error("No F* release available for " .. platform_key)
end
