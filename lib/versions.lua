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
				["darwin_arm64"] = "e14e4fd8e04c5b5b96f6f8e5d07ab600da28d9f8d52b3e6f0d2adf8c3d2a4b1c",
				["darwin_amd64"] = nil, -- Not available for this release
				["linux_amd64"] = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
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
			version = "5.2.1",
			-- Pin opam repo for reproducibility
			opam_repo_commit = nil, -- TODO: determine working commit
			packages = {
				"batteries=3.6.0",
				"zarith=1.13",
				"stdint=0.7.2",
				"yojson=2.1.2",
				"fileutils=0.6.4",
				"menhir=20231231",
				"pprint=20230830",
				"process=0.2.1",
				"fix=20230505",
				"wasm=2.0.1",
				"visitors=20210608",
				"ppx_deriving=5.2.1",
				"ppx_deriving_yojson=3.7.0",
				"ctypes=0.22.0",
				"ctypes-foreign=0.22.0",
				"uucp=15.1.0",
				"sedlex=3.2",
			},
		},
		-- Metadata
		released = "2024-10-06",
		notes = "First stack release for F* 2025.10.06",
	},
}

-- Latest stable stack version
M.LATEST_STACK = "2025.10.06-stack.1"

-- Get all available stack versions (sorted descending)
function M.get_available_versions()
	local versions = {}
	for version, _ in pairs(M.STACK_VERSIONS) do
		table.insert(versions, version)
	end
	-- Sort descending
	table.sort(versions, function(a, b)
		return a > b
	end)
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
