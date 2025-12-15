-- lib/versions.lua
-- Stack version manifest - maps stack versions to component versions
-- Each stack version pins compatible F*, KaRaMeL, and OCaml versions together

local M = {}

-- Stack versions with pinned component versions and checksums
-- Format: YYYY.MM.DD-stack.N where the date is the F* release date
-- Platforms that require building F* from source (no pre-built binaries available)
-- NOTE: Do not use sha256==nil to detect this, as darwin_amd64 is also nil
M.SOURCE_BUILD_PLATFORMS = {
	["linux_arm64"] = true,
}

-- Check if a platform requires building F* from source
function M.needs_fstar_source_build(platform_key)
	return M.SOURCE_BUILD_PLATFORMS[platform_key] == true
end

M.STACK_VERSIONS = {
	["2025.10.06-stack.1"] = {
		-- F* configuration
		fstar = {
			tag = "v2025.10.06",
			-- Source tarball for platforms that need to build from source
			source_url = "https://github.com/FStarLang/FStar/archive/refs/tags/v2025.10.06.tar.gz",
			source_sha256 = "e31ec0ee04c0bf45cb55dbcdb3fbb3c64c850c09be0890a565f89302c015ac6e",
			-- SHA256 checksums per platform (from GitHub release)
			sha256 = {
				["darwin_arm64"] = "e922281c189240d9e6a16684d5d3b9f3343d345ba2c6cd55ce9b68025c823373",
				["darwin_amd64"] = nil, -- Not available for this release
				["linux_amd64"] = "940c187d7a6dc3e95d17fd5159b5eaec17d62981c7f135a7e6c531ce3b59442d",
				["linux_arm64"] = nil, -- Not available, use source build
			},
		},
		-- Z3 configuration for source build platforms (bundled with F* binary on other platforms)
		z3 = {
			version = "4.13.3",
			-- Only platforms that need separate Z3 download (source build platforms)
			urls = {
				["linux_arm64"] = "https://github.com/Z3Prover/z3/releases/download/z3-4.13.3/z3-4.13.3-arm64-glibc-2.34.zip",
			},
			sha256 = {
				["linux_arm64"] = "5bc5fd2c501445970de3b13d5699ff601ff51d3e496cb15ce67d7ee2a4a93b03",
			},
		},
		-- KaRaMeL configuration (for Phase 2)
		karamel = {
			commit = "5f493441d9324869eaf83d5994bd62f29aa9ee1e", -- From Everest hashes.sh
			repository = "https://github.com/FStarLang/karamel",
		},
		-- OCaml toolchain
		ocaml = {
			version = "4.14.2", -- Stable version; KaRaMeL only needs >= 4.10.0
			-- Let opam solve package versions instead of manual pinning
			-- These are the packages KaRaMeL needs (from KaRaMeL docs)
			packages = {
				"batteries",
				"zarith",
				"stdint",
				"yojson",
				"fileutils",
				"menhir",
				"pprint",
				"process",
				"fix",
				"wasm",
				"visitors",
				"ppx_deriving",
				"ppx_deriving_yojson",
				"ctypes",
				"ctypes-foreign",
				"uucp",
				"sedlex",
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
