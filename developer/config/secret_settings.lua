-- developer/config/secret_settings.lua
-- Defaults for breakable walls and secret discovery behavior.

local M = {
    wall_defaults = {
        wall_type = "cracked",
        health = 3,
        required_ability = nil, -- e.g. "bomb", "air_dash" (defined in abilities.lua)
        reveals_secret = nil,   -- secret id to reveal on break
        audio = {
            wrong_ability = nil,
            hit = nil,
            break_sound = nil,
        },
        visual = {
            intact = nil,
            damaged = nil,
            heavily_damaged = nil,
        },
    },
    -- Passive proximity discovery for secrets authored with Reveals on = ability.
    -- Only an empty requirement or this ability id participates; attack secrets
    -- and secrets requiring other abilities keep their existing reveal rules.
    reveal_lens = {
        ability_id = "reveal_lens", -- Ability whose ownership enables proximity discovery.
        radius_tiles = 3, -- Distance from the secret rectangle, in tile widths (tile_settings.lua).
        check_interval = 0.2, -- Seconds between the player's registry scans; 0 checks every frame.
    },
}

return M
