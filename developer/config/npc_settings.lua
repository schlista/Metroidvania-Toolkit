-- NPC behaviour settings (living hub NPCs).
--
-- Only NPCs that opt in are affected: tick Behavior > Show new dialogue marker,
-- tick Face player, enter Barks or set a Wander width on an NPC in Tiled, or set
-- show_new_dialogue_marker = true or barks = {...} on its type in npc_types.lua.
-- Every other NPC behaves exactly as before.
--
-- Game Settings > Game > NPCs edits markers.enabled, barks.enabled and
-- barks.show_seconds. Edit the marker text and wander pauses here.
-- Game Settings > Progression > People edits the people block.
return {
    markers = {
        -- Show the marker above opted-in NPCs. false hides every marker.
        enabled = true,
        -- Shown while an NPC has lines you have not heard since its dialogue
        -- last changed. Creator source text, collected by Project > Translations….
        new_text = "!",
        -- Shown instead when those lines start a quest (quest_start) or turn
        -- one in (quest_turn_in). Creator source text, collected for translation.
        task_text = "?",
        -- Marker size, 0.25..16. 1 is the label font's own size, which is a speck beside
        -- 64 pixel tiles. Applies when the NPC loads.
        scale = 3,
    },
    barks = {
        -- Show ambient lines (Behavior > Barks, or a type's barks) above NPCs
        -- when the player walks within Bark range. false silences every NPC.
        -- An NPC showing the marker does not bark.
        enabled = true,
        -- Seconds each line stays up, 1..10. The NPC's Bark cooldown starts
        -- when the line hides.
        show_seconds = 3,
        -- Line size, 0.25..16. 1 is the label font's own size. Lines are
        -- sentences, so they stay smaller than the one-character marker.
        scale = 1.5,
    },
    wander = {
        -- Seconds a wandering NPC (Behavior > Wander width above 0) waits at
        -- each end of its line before turning back, chosen at random between
        -- these two, 0..60. pause_max must not be below pause_min.
        pause_min = 1.5,
        pause_max = 4,
    },
    -- Journal > People (WM12c): a record of who the player has talked to.
    -- A person is an npc_types.lua type with a journal block
    -- (journal = {title = "...", bio = "...", order = 10}); a type without
    -- one, or an NPC with no npc_type, is never listed. Talking to any NPC
    -- of the type once marks that person as met, and the entry shows the
    -- bio and the last line they said. Resets with a new save or New Game+.
    people = {
        -- Show the People tab in the Journal. Ships off; the tab also stays
        -- hidden while no npc_types.lua type has a journal block.
        enabled = false,
        -- true lists people not met yet as "???" rows; false hides them
        -- until the first talk.
        show_unmet = true,
    },
}
