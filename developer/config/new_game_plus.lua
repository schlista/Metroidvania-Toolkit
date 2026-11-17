-- Optional replay of a completed save with configured carry and cycle scaling.
-- Ships off. Game Settings > Progression > New Game+ enables the slot-screen choice.
return {
    enabled = false, -- Allow completed slots to begin another cycle when true.
    endings = {}, -- Empty accepts any configured ending; otherwise list ending ids.
    cycles = { -- Cycle 1 uses the first entry; the final entry repeats thereafter.
        { enemy_health_mult = 1.5, damage_taken_mult = 1.5 },
        { enemy_health_mult = 2, damage_taken_mult = 2 },
        -- Optional shared keys: boss_health_mult (defaults to enemy_health_mult),
        -- damage_dealt_mult and loot_mult. Each factor must be from 0.1 to 10.
    },
    carry = { -- Difficulty always carries; profile achievements/records are untouched.
        level = true, -- Keep level and total experience, without world milestones.
        equipment = true, -- Keep weapon/charm items, equipment, charm slots and tiers.
        currency = true, -- Keep both the wallet and the saved bank balance.
        items = false, -- Keep other inventory items, including keys, when true.
        abilities = false, -- Keep acquired ability unlocks when true.
        upgrades = false, -- Keep the permanent ledger and flask bonus charges when true.
        -- Carried ledger entries are idempotent: collecting their sources again adds nothing.
        bestiary = true, -- Keep species and boss-preset defeat knowledge.
        cutscenes_seen = true, -- Keep seen-scene flags so those scenes need not replay.
        -- All other slot data resets, including quests, trials, fragments and run statistics.
    },
}
