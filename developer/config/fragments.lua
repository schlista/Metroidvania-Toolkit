-- Container fragments are ordinary permanent Collectibles placed in Tiled.
-- Game Settings > Player > Health and resources overrides the two piece counts.
-- Add another set and a collectible_types.lua entry with fragment_set = its key
-- for stamina or flask charges. Keep set keys stable after publishing saves.
return {
    sets = {
        health = {
            name = "Health fragments", -- Translatable label in Journal > Records.
            pieces = 4, -- Whole pieces per container, from 1 to 20.
            upgrade = "max_health", -- max_health, max_energy, max_stamina or heal_charges.
            amount = 1, -- Positive whole increase for each completed container.
            progress_text = "Health fragment {count}/{needed}", -- Integer progress parameters.
            complete_text = "Max health +{amount}", -- Integer upgrade parameter.
        },
        energy = {
            name = "Energy fragments", -- Translatable Records label.
            pieces = 3, -- Whole pieces per container, from 1 to 20.
            upgrade = "max_energy", -- Adds capacity, even if energy starts switched off.
            amount = 10, -- Positive whole increase per completed container.
            progress_text = "Energy fragment {count}/{needed}", -- Progress notice template.
            complete_text = "Max energy +{amount}", -- Completion notice template.
        },
        -- Optional flask set: uncomment and add a Collectible type pointing to heal.
        -- Use the flask healing model; other models do not use flask charges.
        -- heal = {
        --     name = "Flask fragments", -- Translatable Records label.
        --     pieces = 3, -- Whole pieces per extra charge, from 1 to 20.
        --     upgrade = "heal_charges", -- Saved idempotently by the healing service.
        --     amount = 1, -- Positive whole charge increase per completed set.
        --     progress_text = "Flask fragment {count}/{needed}", -- Progress template.
        --     complete_text = "Flask charges +{amount}", -- Completion template.
        -- },
    },
}
