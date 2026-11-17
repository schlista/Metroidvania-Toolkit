-- Creature identities and source text. Game Settings > Progression > Bestiary controls visibility.
-- Defeats are recorded even while visibility is off; saves hold ids and counts, never this text.
return {
    enabled = false, -- Show bestiary feedback; ships off. Recording continues while off.
    include_bosses = true, -- Record boss presets and include them in census progress.
    include_spawned = true, -- Record spawned enemies and count the census's known spawn species.
    details_after = 3, -- Whole defeats before a Journal entry reveals combat details.
    notify_new_entry = true, -- Show a notice on the first recorded defeat while enabled.
    unknown_text = "", -- Creator source text for an unrecorded entry; blank shows no body.
    categories = { -- Display order: each row has a stable id and a translatable source label.
        -- {id = "wildlife", label = "Wildlife"},
    },
    entries = { -- Key by On defeat > Species, otherwise enemy_type before archetype and skin.
        -- Different art can share one species; use an explicit species to separate shared art.
        -- Names and descriptions are creator source text collected for translation.
        -- Unrecorded names use the journal.unknown UI key; missing names use list.missing_name.
        -- tt_species = {name = "Platform Watcher", description = "Keeps a quiet lookout.",
        --     category = "wildlife", order = 10, hidden_until_defeated = false},
    },
    bosses = { -- Key by boss preset; optional name and description are creator source text.
        -- guardian = {name = "Guardian", description = "An ancient sentinel."},
    },
}
