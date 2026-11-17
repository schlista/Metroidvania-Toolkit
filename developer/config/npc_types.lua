--- NPC Type Definitions
-- Define reusable NPC types for your game
-- Referenced by Tiled object spawning
--
-- @module npc_types
-- Entries here become the Tiled npcs dropdown after Project > Prepare & Check.
--
-- Optional per type:
--   show_new_dialogue_marker = true  -- every NPC of this type shows the
--     new-dialogue marker ("!" or "?", from npc_settings.lua) while it has
--     unheard lines. A placed NPC can also tick Behavior > Show new dialogue
--     marker; unticked there does not turn a type's marker off.
--   barks = { "Mind the gate.", "Lovely day." }  -- short ambient lines shown
--     above every NPC of this type when the player walks within its Bark
--     range, for those whose Behavior > Barks is blank. Source text, collected
--     by Project > Translations…. Prepare & Check needs a run after editing.
--   journal = {                      -- lists this type in Journal > People
--       title = "The Hermit",        --   shown name; blank uses name above
--       bio = "Lives in the dunes.", --   short text shown once met
--       order = 10,                  --   lower comes first; ties sort by title
--   }
--     A person is met after the first talk with any NPC of this type, in
--     any room. Turn the tab on in Game Settings > Progression > People.
--     Project > Translations… collects title and bio. Prepare & Check warns
--     (people_unplaced) when no exported room places an NPC of the type.

local M = {}

-- Story NPCs
M.guide = {
    name = "Mentor",
    sprite = "npc_mentor",
    dialogue_id = "mentor_tutorial",
}

M.lore_keeper = {
    name = "Sage",
    sprite = "npc_sage",
    dialogue_id = "sage_lore",
}

-- Functional NPCs
M.save_point_keeper = {
    name = "Guardian",
    sprite = "npc_guardian",
    dialogue_id = "save_point_dialogue",
}

M.fast_travel_operator = {
    name = "Mystic",
    sprite = "npc_mystic",
    dialogue_id = "fast_travel_dialogue",
}

-- Desert NPCs
M.desert_hermit = {
    name = "Desert Hermit",
    sprite = "npc_elder",
}

M.desert_coyote = {
    name = "Desert Coyote",
    sprite = "npc_idle",
}

-- Vendor presets: Vendor shop chooses a shops.lua catalog. A placed NPC's
-- Vendor group can override it; none keeps this preset's catalog.
-- Names and greeting text are collected by Project > Translations….
M.merchant = {
    name = "Merchant",                 -- Display name and purchase-menu title.
    vendor_shop = "town_vendor",       -- Catalog sold by this preset.
    dialogue_id = "merchant_greeting", -- Short greeting before trading.
}
M.alchemist = {
    name = "Alchemist",                  -- Display name and purchase-menu title.
    vendor_shop = "apothecary",           -- Catalog sold by this preset.
    dialogue_id = "alchemist_greeting",   -- Short greeting before trading.
}

-- Generic NPCs
M.villager_male = {
    name = "Villager",
    sprite = "npc_villager_male",
    dialogue_id = "generic_villager",
}

M.villager_female = {
    name = "Villager",
    sprite = "npc_villager_female",
    dialogue_id = "generic_villager",
}

return M
