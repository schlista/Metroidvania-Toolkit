-- Derived completion for the published world; enable in Game Settings > Progression > Completion.
return {
    enabled = false, -- Ships off; no progress events or Records section while disabled.
    rounding = "floor", -- "floor" truncates the weighted percentage; "round" rounds to nearest integer.
    show_in_journal = true, -- Show the breakdown in Journal > Records when enabled.
    show_on_ending = true, -- Capture the percentage on the ending's first page when enabled.
    -- Only positive weights with nonempty totals contribute to the percentage.
    -- Zero-weight categories still appear in Records. Order controls their display order.
    -- Built-in ids use framework translations. Added ids need a source-text label and
    -- collectible_categories; optional lore_items also includes placed Lore objects.
    -- Collectible filters obey world_census.lua exclusions and per-type opt-outs.
    categories = {
        upgrades = {weight=1, order=10, collectible_categories={"upgrade","ability","weapon","charm"}}, -- Fragments and permanent gear pickups count too.
        bosses = {weight=1, order=20}, -- Placed persistent bosses in published rooms.
        map = {weight=1, order=30}, -- Visited rooms, excluding rooms only revealed on the map.
        secrets = {weight=0, order=40}, -- Found Secret objects.
        chests = {weight=0, order=50}, -- Opened single-use chests.
        collection = {weight=0, order=60, collectible_categories={"relic","lore"}, lore_items=true}, -- Includes Lore objects as well as pickups.
        quests = {weight=0, order=70}, -- Completed or turned-in quests from quests.lua.
        bestiary = {weight=0, order=80}, -- Distinct recorded species/bosses in the published census.
        guardians = {weight=0, order=90}, -- Persistent, never-respawning placed enemies.
        trials = {weight=0, order=100}, -- Cleared Combat Trials in published rooms; optional, outside ordinary collectible counts.
    },
}
