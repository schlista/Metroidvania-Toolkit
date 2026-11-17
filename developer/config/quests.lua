-- Optional save-slot quests. Game Settings > Progression > Quests switches tracking on.
-- Stable quest and step ids are saved; keep them when changing display text.
return {
    enabled = false, -- Off means no quest transitions, counters, mirrors or rewards.
    notify = true, -- Show started, updated, completed and failed notices while tracking is on.
    categories = { -- Stable category ids with translatable source names and display order.
        side = {name = "Side quests", order = 10},
    },
    quests = {
        desert_hermit_find_relic = {
            title = "The Hermit's Lost Relic", -- Creator source text, collected for translation.
            description = "Retrieve the Hermit Medal from the desert ruins above and return it to the Desert Hermit.",
            category = "side", -- Optional category id from categories above.
            giver = "Desert Hermit", -- Display text, never an NPC id; optional.
            hidden_until_started = true, -- The quest log may hide an unstarted quest.
            start = {mode = "flag", flag = "desert_hermit_quest_given"},
            -- Start modes: auto, flag (needs flag), dialogue or trigger (explicit start).
            steps = {
                {id = "find_relic", text = "Find the Hermit Medal.",
                    complete_when = {flag = "desert_hermit_relic_found"}},
                {id = "return", text = "Return to the Desert Hermit.", complete_when = {turn_in = true}},
            },
            -- Rewards use grant text (or a list). Paid once, only on explicit turn-in.
            rewards = {"xp:50", "currency:100", "item:upgrade_material"},
        },
        -- Each step has exactly one complete_when form:
        -- {flag="opened_path"}, {item="potion", count=2},
        -- {event="enemy_defeated", where={species="bat", spawned=false}, count=3},
        -- {trigger=true}, {turn_in=true} (last step only),
        -- {quest="other_quest"} (completed or turned in), or {level=2}.
        -- Event objectives count only while current; temporary gate openings never count.
        -- Optional step requires_flag delays completion; set_flag is written on completion.
        -- giver, title, description, step text and category names are creator source text.
    },
}
