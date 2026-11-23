-- Fallbacks for projects that keep older creator config files when upgrading.
-- Keep these values in step with developer/config/boss_behaviors.lua and the
-- scheduler fields in developer/config/boss_defaults.lua.
local M = {
    attack_range = 150,
    approach_margin = 8,
    engage_range = 800,
    coverage_distance = 800, -- Range to check when there is no Boss Arena rectangle.
    near_wall_distance = 64,
    player_height_dead_band = 24,
    sequence_wait = 1,
}

-- Reach of a legacy attack whose pattern leaves the field out. Same values as
-- the attack executors' own fallbacks (mvtk/bosses/boss_attacks/common.lua).
M.reach = {
    default_aoe_radius = 150,
    default_beam_length = 400,
    default_projectile_speed = 300,
    default_projectile_life = 3.0,
    default_wave_rings = 3,
    default_wave_radius_step = 80,
}

M.behaviors = {
    aggressive = {
        charge = 7, melee = 6, grab = 2, aoe = 5,
        projectile = 4, beam = 3, summon = 1, special = 2, max_repeat = 2,
    },
    berserk = {
        charge = 7, melee = 6, grab = 4, aoe = 5,
        projectile = 3, beam = 2, summon = 1, special = 4, max_repeat = 2,
    },
    cautious = {
        charge = 3, melee = 2, grab = 1, aoe = 5,
        projectile = 7, beam = 6, summon = 4, special = 1, max_repeat = 1,
    },
    defensive = {
        charge = 3, melee = 2, grab = 1, aoe = 4,
        projectile = 7, beam = 6, summon = 5, special = 1, max_repeat = 1,
    },
    desperate = {
        charge = 5, melee = 2, grab = 7, aoe = 6,
        projectile = 3, beam = 4, summon = 1, special = 7, max_repeat = 2,
    },
    erratic = {
        charge = 3, melee = 2, grab = 7, aoe = 5,
        projectile = 4, beam = 1, summon = 6, special = 7, max_repeat = 2,
    },
    patrol = {
        charge = 3, melee = 2, grab = 1, aoe = 4,
        projectile = 7, beam = 6, summon = 5, special = 1, max_repeat = 1,
    },
    random = {
        charge = 1, melee = 1, grab = 1, aoe = 1,
        projectile = 1, beam = 1, summon = 1, special = 1, max_repeat = 2,
    },
    relentless = {
        charge = 7, melee = 6, grab = 2, aoe = 4,
        projectile = 5, beam = 3, summon = 1, special = 2, max_repeat = 1,
    },
    skilled = {
        charge = 7, melee = 4, grab = 1, aoe = 3,
        projectile = 6, beam = 5, summon = 2, special = 1, max_repeat = 1,
    },
    testing = {
        charge = 2, melee = 3, grab = 1, aoe = 4,
        projectile = 7, beam = 6, summon = 5, special = 1, max_repeat = 1,
    },
}

return M
