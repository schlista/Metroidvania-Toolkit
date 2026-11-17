-- The one framework file that differs between the two toolkits.
-- Maintainers edit this data; creators never do. PowerShell and Python read it
-- without Lua: keep each scalar on its own line, with a trailing comma, using
-- double-quoted text without escapes, a boolean, or a decimal integer.
-- Nested tables start on their own line and are skipped by those readers.
-- The separate Python unretire reader accepts object_types, abilities and
-- providers as empty {} lists or lists with one double-quoted id per line,
-- with a trailing comma and closing }, on its own line. No escapes or code.
-- Ids are ASCII, trimmed and lowercased; whitespace and hyphens become
-- underscores, then repeated underscores collapse, as in retired_types.lua.
return {
    -- Stable product identifier used by authoring metadata.
    id = "metroidvania",
    -- Display name for runtime tools, editor commands and generated text.
    name = "Metroidvania Toolkit",
    -- Empty-project title; Game Settings warns creators to choose a game name.
    placeholder_title = "Metroidvania Toolkit (Defold)",
    -- Release archive basename before the version suffix.
    zip_prefix = "Metroidvania_Toolkit",
    -- Release tag prefix immediately before the version.
    tag_prefix = "metroidvania-v",
    -- Exact first line required in the product's LICENSE.
    license_header = "METROIDVANIA TOOLKIT LICENSE",
    -- Public repository address used by generated guides and release links.
    repository_url = "https://github.com/schlista/Metroidvania-Toolkit",
    -- Run the release scope gate when true; false skips it for this product.
    v1_cut_gate = false,
    -- Minimum ID allocated to newly introduced Tiled property types.
    property_type_id_floor = 100000,
    -- Approved features opt back in here once their implementation is ready.
    unretire = {
        -- Authored object type identifiers restored by feature plans.
        object_types = {
            "wind_current",
            "ice_floor",
            "pendulum_hazard",
            "warp_statue",
            "zip_line",
            "shop",
            "upgrade_station",
            "skill_trainer",
            "offering_altar",
            "bank",
            "quest_trigger",
        },
        -- Ability identifiers restored by feature plans.
        abilities = {
            "high_jump",
        },
        -- Checkpoint provider identifiers restored by feature plans.
        providers = {
            "bank",
            "quests",
        },
    },
    -- Optional replacement guidance appended to retired object warnings.
    -- Map normalized object type identifiers to hint text; omit a key for the
    -- standard warning alone. Keep this nested block on separate lines so the
    -- Python and PowerShell scalar readers skip it. Hints name supported replacements.
    retired_hints = {
        spawn_wave = "Use the Encounter template.",
        enemy_spawner = "Use the Encounter template.",
        enemy_nest = "Use an Enemy with archetype nest.",
        turret_rotating = "Use an Enemy with archetype turret.",
        arena_hazard_spawner = "Use a Hazard with Arena settings.",
    },
}
