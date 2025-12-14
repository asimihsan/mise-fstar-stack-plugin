-- hooks/pre_install.lua
-- Returns download information for fstar-stack
-- Downloads F* binary; KaRaMeL is built from source in post_install (Phase 2)

local http = require("http")
local json = require("json")
local versions = require("lib.versions")

-- Platform patterns for matching F* release asset names
-- Note: Windows is not currently supported (post_install uses Unix commands)
local PLATFORM_PATTERNS = {
	["darwin_arm64"] = "Darwin%-arm64",
	["darwin_amd64"] = "Darwin%-x86_64",
	["linux_amd64"] = "Linux%-x86_64",
	["linux_arm64"] = "Linux%-arm64",
}

-- Supported platforms message for error output
local SUPPORTED_PLATFORMS = "darwin_arm64, darwin_amd64, linux_amd64, linux_arm64"

local function get_platform_key()
	local os_type = RUNTIME.osType -- luacheck: ignore
	local arch_type = RUNTIME.archType -- luacheck: ignore
	return os_type .. "_" .. arch_type
end

-- Extract SHA256 from GitHub digest field (format: "sha256:hexstring")
local function extract_sha256(digest)
	if digest and digest:match("^sha256:") then
		return digest:gsub("^sha256:", "")
	end
	return nil
end

-- Build HTTP headers, including GitHub token if available
local function get_github_headers()
	local headers = {
		["Accept"] = "application/vnd.github.v3+json",
		["User-Agent"] = "mise-fstar-stack-plugin",
	}

	-- Support GITHUB_TOKEN or GH_TOKEN for API rate limits
	local token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
	if token and token ~= "" then
		headers["Authorization"] = "token " .. token
	end

	return headers
end

-- Truncate string for error messages
local function truncate(str, max_len)
	if not str then
		return ""
	end
	if #str <= max_len then
		return str
	end
	return str:sub(1, max_len) .. "..."
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

	-- Check platform support
	local pattern = PLATFORM_PATTERNS[platform_key]
	if pattern == nil then
		error(
			"Unsupported platform: "
				.. platform_key
				.. "\nSupported platforms: "
				.. SUPPORTED_PLATFORMS
				.. "\nNote: Windows is not yet supported."
		)
	end

	-- Query GitHub releases API for F* assets
	local release_url = "https://api.github.com/repos/FStarLang/FStar/releases/tags/" .. fstar_tag
	local resp, err = http.get({
		url = release_url,
		headers = get_github_headers(),
	})

	if err ~= nil then
		error("Failed to fetch release info from GitHub: " .. tostring(err))
	end

	-- Handle specific HTTP status codes
	if resp.status_code == 404 then
		error(
			"F* version not found: "
				.. fstar_tag
				.. "\nThe release tag may not exist on GitHub."
				.. "\nCheck https://github.com/FStarLang/FStar/releases for available releases."
		)
	elseif resp.status_code == 403 then
		local body = truncate(resp.body, 200)
		if body:match("rate limit") or body:match("API rate") then
			error(
				"GitHub API rate limit exceeded.\n"
					.. "Set GITHUB_TOKEN or GH_TOKEN environment variable to increase limits.\n"
					.. "Get a token at: https://github.com/settings/tokens"
			)
		else
			error("GitHub API access forbidden (403): " .. body)
		end
	elseif resp.status_code ~= 200 then
		error("GitHub API error (status " .. resp.status_code .. "): " .. truncate(resp.body, 200))
	end

	-- Parse response
	local ok, release = pcall(json.decode, resp.body)
	if not ok then
		error("Failed to parse GitHub API response: " .. truncate(resp.body, 100))
	end

	-- Validate response structure
	if not release or not release.assets then
		error("Invalid GitHub API response: missing assets field")
	end

	-- Find matching asset for this platform
	-- Require: matches platform pattern, is .tar.gz, starts with fstar-, not source archive
	for _, asset in ipairs(release.assets) do
		local name = asset.name
		if name:match(pattern) and name:match("%.tar%.gz$") and name:match("^fstar%-") and not name:match("%-src") then
			-- Prefer pinned SHA256 from versions.lua, fall back to API digest
			local sha256
			if fstar_config.sha256 and fstar_config.sha256[platform_key] then
				sha256 = fstar_config.sha256[platform_key]
			else
				sha256 = extract_sha256(asset.digest)
			end

			return {
				version = version,
				url = asset.browser_download_url,
				sha256 = sha256,
				note = "fstar-stack " .. version .. " (F* " .. fstar_tag .. ")",
			}
		end
	end

	-- No matching asset found - provide helpful error with available assets
	local available_assets = {}
	for _, asset in ipairs(release.assets) do
		if asset.name:match("^fstar%-") and not asset.name:match("%-src") then
			table.insert(available_assets, "  - " .. asset.name)
		end
	end

	error(
		"No F* release available for "
			.. platform_key
			.. "\nAvailable assets for "
			.. fstar_tag
			.. ":\n"
			.. table.concat(available_assets, "\n")
			.. "\n\nNote: F* does not provide builds for all platform/architecture combinations."
	)
end
