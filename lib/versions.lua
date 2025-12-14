-- lib/versions.lua
-- Stack version manifest - maps stack versions to component versions
-- Each stack version pins compatible F*, KaRaMeL, and OCaml versions together

local M = {}

-- Stack versions with pinned component versions and checksums
-- Format: YYYY.MM.DD-stack.N where the date is the F* release date
M.STACK_VERSIONS = {
	["2025.10.06-stack.1"] = {
		-- F* configuration
		fstar = {
			tag = "v2025.10.06",
			-- SHA256 checksums per platform (from GitHub release)
			sha256 = {
				["darwin_arm64"] = "e922281c189240d9e6a16684d5d3b9f3343d345ba2c6cd55ce9b68025c823373",
				["darwin_amd64"] = nil, -- Not available for this release
				["linux_amd64"] = "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5",
				["linux_arm64"] = nil, -- Not available for this release
			},
		},
		-- KaRaMeL configuration (for Phase 2)
		karamel = {
			commit = "5f493441d9324869eaf83d5994bd62f29aa9ee1e", -- From Everest hashes.sh
			repository = "https://github.com/FStarLang/karamel",
		},
		-- OCaml toolchain (for Phase 2)
		ocaml = {
			version = "5.4.0",  -- Updated from 5.2.1 for better macOS Tahoe support
			-- Pin opam repo for reproducibility
			opam_repo_commit = nil, -- TODO: determine working commit
			-- Package versions compatible with OCaml 5.4.0
			-- Updated to latest versions for macOS Tahoe compatibility
			packages = {
				"batteries=3.10.0",      -- requires ocaml >= 4.05 & < 5.5
				"zarith=1.14",           -- requires ocaml >= 4.04
				"stdint=0.7.2",
				"yojson=2.2.2",
				"fileutils=0.6.6",
				"menhir=20250912",       -- latest
				"pprint=20230830",
				"process=0.2.1",
				"fix=20250919",          -- latest
				"wasm=2.0.2",            -- latest
				"visitors=20251114",     -- latest (requires ocaml >= 4.14.2)
				"ppx_deriving=6.1.1",    -- latest
				"ppx_deriving_yojson=3.10.0", -- latest
				"ctypes=0.24.0",         -- latest
				"ctypes-foreign=0.24.0",
				"uucp=17.0.0",           -- latest
				"sedlex=3.7",            -- latest
			},
		},
		-- Metadata
		released = "2025-10-06",
		notes = "First stack release for F* 2025.10.06",
	},
}

-- Latest stable stack version
M.LATEST_STACK = "2025.10.06-stack.1"

-- Parse stack version into comparable components
-- Format: YYYY.MM.DD-stack.N
local function parse_stack_version(version)
	local year, month, day, stack_num = version:match("^(%d+)%.(%d+)%.(%d+)%-stack%.(%d+)$")
	if year then
		return {
			year = tonumber(year),
			month = tonumber(month),
			day = tonumber(day),
			stack_num = tonumber(stack_num),
		}
	end
	return nil
end

-- Compare two stack versions numerically (handles double-digit stack numbers)
local function compare_versions(a, b)
	local pa = parse_stack_version(a)
	local pb = parse_stack_version(b)

	-- If either fails to parse, fall back to string comparison
	if not pa or not pb then
		return a > b
	end

	-- Compare year, month, day, then stack number (descending order)
	if pa.year ~= pb.year then
		return pa.year > pb.year
	end
	if pa.month ~= pb.month then
		return pa.month > pb.month
	end
	if pa.day ~= pb.day then
		return pa.day > pb.day
	end
	return pa.stack_num > pb.stack_num
end

-- Get all available stack versions (sorted descending)
function M.get_available_versions()
	local versions = {}
	for version, _ in pairs(M.STACK_VERSIONS) do
		table.insert(versions, version)
	end
	-- Sort descending using numeric comparison
	table.sort(versions, compare_versions)
	return versions
end

-- Get stack configuration for a version
function M.get_stack_config(version)
	return M.STACK_VERSIONS[version]
end

-- Check if a version exists
function M.version_exists(version)
	return M.STACK_VERSIONS[version] ~= nil
end

return M
