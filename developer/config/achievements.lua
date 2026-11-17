-- Assist use can be a flag trigger: {type="flag", flag="assist_used"} when Record assist use is on.
-- Optional goals shared by every save slot in this game's player profile.
-- Game Settings > Progression > Achievements controls the three switches below.
-- Rewards go only to the save slot active at unlock time, once per achievement.
return {
    enabled = false, -- Track and unlock goals; ships off. Off means no counters or writes.
    notify = true, -- Queue an unlock notice. When off, the configured sound still plays.
    show_hidden_count = true, -- Include the number of hidden goals in the Journal summary.
    sfx = "secret_reveal", -- sound_bank.lua id; blank silences unlock feedback.
    categories = { -- Stable category ids mapped to translatable source names and sort order.
        -- exploration = {name = "Exploration", order = 10},
    },
    achievements = { -- Stable ids: renaming an id creates a different profile achievement.
        -- Names and descriptions are creator source text collected for translation.
        -- category is optional; when supplied it must name a category above.
        -- hidden hides a locked goal's name and description in the Journal.
        -- hunter = {name = "First Victories", description = "Defeat three enemies.",
        --     hidden = false, trigger = {type = "event", event = "enemy_defeated",
        --         where = {spawned = false}, count = 3}, reward = "currency:10"},
        -- first_level = {name = "Growing Stronger", description = "Reach level two.",
        --     trigger = {type = "level", level = 2}},
        -- Other triggers: {type="flag", flag="opened_path"},
        -- {type="item", item="potion", count=2}, {type="currency", amount=100},
        -- {type="quests_completed", count=3} uses completed quests in the active save slot.
        -- {type="completion", percent=100} uses the enabled completion tracker.
        -- Add category="upgrades" to check one configured category instead.
        -- {type="ending", ending_id="main"} checks the active slot's completed ending.
        -- Add max_playtime_s=3600 for an inclusive in-game RunStats time limit in seconds.
        -- Omit max_playtime_s for no time limit; 0 permits only a zero-second run.
        -- The id must name an enabled ending in Game Settings > Ending.
        -- {type="all_of", ids={"hunter", "first_level"}}.
        -- Event filters use exact declared payload fields and scalar values.
        -- gate_opened ignores temporary openings unless where.temporary=true.
        -- Event counters stop at their target and survive deaths and slot deletion.
        -- State triggers check current flags, held items, carried currency and level.
        -- reward is optional grant text or a list of grant strings (never a keyed table).
    },
}
