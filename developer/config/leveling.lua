-- Optional level growth. Game Settings > Progression > Leveling publishes overrides.
return {
    enabled = false, -- Award XP and apply level growth only when enabled.
    max_level = 20, -- Highest level; XP is capped at its starting threshold (1-99).
    curve = {
        mode = "formula", -- "formula" or "table"; missing table entries use the formula.
        first = 100, -- XP from level 1 to 2, before growth.
        growth = 1.25, -- Multiply the next level's requirement by this factor.
        table = {}, -- Optional [level] = positive whole XP needed for the next level.
    },
    per_level = { -- Added for each level above 1; capacities round down after summing.
        max_health = 0.5, -- Health capacity; +1 at level 3 with this default.
        max_energy = 0, -- Energy capacity; use 0 for no growth.
        max_stamina = 0, -- Stamina capacity; use 0 for no growth.
        damage_mult = 0.02, -- Added to the neutral factor 1 (+2 percent per level).
    },
    milestones = { -- Optional level-to-flag rewards, applied only when crossing a level.
        -- [5] = {set_flag = "reached_level_5"},
    },
    level_up = {
        full_heal = true, -- Heal fully once after a gain that crosses one or more levels.
        sfx = "collect_ability", -- sound_bank.lua id; blank disables the sound.
    },
    sources = {
        enemy_default = 5, -- Used only when neither instance nor enemy type specifies XP.
        elite_mult = 3, -- Multiplies the default only; explicit instance/type XP already wins.
        boss_default = 100, -- Used when boss reward XP is absent or zero.
        secret_found = 10, -- XP for a newly found secret.
        room_first_visit = 0, -- XP for a room's first saved visit; 0 disables it.
        collectible_type_xp = {}, -- Optional [collectible_type] = XP per collection.
        skip_spawned = false, -- Ignore enemies created by encounters or boss summons when true.
        skip_causes = {}, -- Optional [cause] = true to ignore that enemy defeat cause.
    },
}
