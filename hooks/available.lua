-- hooks/available.lua
-- Returns available stack versions
-- For the minimal spike, this returns hardcoded versions

function PLUGIN:Available(ctx) -- luacheck: ignore
    -- Hardcoded stack versions for minimal spike
    -- Format: YYYY.MM.DD-stack.N where the date is the F* release date
    local result = {
        {
            version = "2025.10.06-stack.1",
            note = "latest",
        },
    }

    -- Return array directly, not wrapped in { versions = ... }
    return result
end
