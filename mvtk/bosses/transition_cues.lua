-- Phase-change cue settings for bosses.
--
-- Creators edit these values in developer/config/boss_defaults.lua, under
-- transition_feedback. This module lays that table over the built-in values
-- below, key by key, so a project whose boss_defaults.lua predates the table,
-- or leaves part of it out, keeps working after a toolkit update.
-- test/boss_transition_cue_tests.lua keeps BUILTIN equal to the shipped file.
local M = {}

M.BUILTIN = {
    authored_camera = {
        duration = 0.5,
        intensity = 8,
    },
    cutscene = {
        flash_color = {1, 1, 1, 0.45},
        flash_duration = 0.25,
        music_fade = 0.3,
        shake_duration = 0.5,
        shake_intensity = 1.2,
    },
    dramatic = {
        effects_delay = 0.1,
        music_fade = 0.5,
        pause_duration = 1,
        presets = {
            environmental = {
                activate_hazards = true,
                flash_color = {1, 0.5, 0, 0.7},
                flash_duration = 0.3,
                hitstop_duration = 0.183333333,
                pause_duration = 1,
                shake_intensity = "critical",
                spawn_particles = "arena_activation",
            },
            heal = {
                boss_scale_pulse = 1.1,
                flash_color = {0.3, 1, 0.3, 0.6},
                flash_duration = 0.3,
                hitstop_duration = 0.083333333,
                pause_duration = 0.7,
                shake_intensity = "medium",
                spawn_particles = "heal_effect",
            },
            rage = {
                boss_scale_pulse = 1.2,
                flash_color = {1, 0.2, 0.2, 0.8},
                flash_duration = 0.3,
                hitstop_duration = 0.183333333,
                pause_duration = 1,
                shake_intensity = "critical",
                spawn_particles = "rage_aura",
            },
            standard = {
                flash_color = {1, 1, 1, 0.5},
                flash_duration = 0.2,
                hitstop_duration = 0.133333333,
                pause_duration = 0.5,
                shake_intensity = "heavy",
            },
            summon = {
                boss_invulnerable = true,
                flash_color = {0.7, 0.3, 0.9, 0.6},
                flash_duration = 0.25,
                hitstop_duration = 0.133333333,
                pause_duration = 0.8,
                shake_intensity = "medium",
                spawn_adds = true,
                spawn_particles = "summon_circle",
            },
            teleport = {
                boss_disappear = true,
                boss_reappear_delay = 0.5,
                flash_color = {0.5, 0.5, 1, 0.4},
                flash_duration = 0.15,
                hitstop_duration = 0.083333333,
                pause_duration = 0.3,
                shake_intensity = "light",
                spawn_particles = "teleport_out",
                teleport_destination = true,
            },
            transform = {
                boss_disappear = true,
                boss_reappear_delay = 1,
                flash_color = {0.8, 0.4, 1, 0.9},
                flash_duration = 0.5,
                hitstop_duration = 0.233333333,
                music_change = true,
                pause_duration = 1.5,
                shake_intensity = "critical",
                spawn_particles = "transformation",
            },
        },
        reappear_delay = 0.5,
        scale_duration = 0.3,
    },
    flash_enabled = true,
    phase_duration = 2,
    rage = {
        flash_color = {1, 0.2, 0.2, 0.7},
        flash_duration = 0.3,
        music_fade = 0.3,
        shake_duration = 0.8,
        shake_intensity = 1.8,
    },
    shake_enabled = true,
    shield = {
        arena_flash_duration = 0.15,
        flash_color = {0.4, 0.8, 1, 0.55},
        flash_duration = 0.25,
        music_fade = 0.3,
        shake_duration = 0.4,
        shake_intensity = 1,
    },
    telegraph = {
        flash_color = {1, 0.8, 0.2, 0.5},
        flash_duration = 0.2,
        shake_duration = 0.4,
        shake_intensity = 1.4,
    },
    teleport = {
        grow_duration = 0.3,
        shrink_duration = 0.3,
    },
    transform = {
        arena_flash_duration = 0.2,
        flash_color = {0.8, 0.4, 1, 0.7},
        flash_duration = 0.35,
        music_fade = 0.4,
        shake_duration = 0.6,
        shake_intensity = 1.5,
    },
}

local function is_list(value)
    return type(value) == "table" and #value > 0
end

-- Tables merge key by key. A list (a colour) replaces the built-in list whole.
local function merge(base, over)
    if type(base) ~= "table" or is_list(base) then
        if over == nil then return base end
        return over
    end
    local out = {}
    for key, value in pairs(base) do
        local authored
        if type(over) == "table" then authored = over[key] end
        if type(value) == "table" and not is_list(value) then
            out[key] = merge(value, type(authored) == "table" and authored or nil)
        elseif authored == nil then
            out[key] = value
        else
            out[key] = authored
        end
    end
    -- Keep creator additions, such as an extra dramatic preset.
    if type(over) == "table" then
        for key, value in pairs(over) do
            if out[key] == nil and base[key] == nil then out[key] = value end
        end
    end
    return out
end

--- Resolve the cue table for a loaded boss_defaults table (or nil).
function M.resolve(boss_defaults)
    local authored = type(boss_defaults) == "table" and boss_defaults.transition_feedback or nil
    return merge(M.BUILTIN, type(authored) == "table" and authored or nil)
end

return M
