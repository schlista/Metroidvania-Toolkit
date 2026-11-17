-- World budget settings for the Prepare & Check stage "Check world budget".
-- The stage (developer/tools/world_budget.lua) counts what each baked
-- room puts into the engine's pools (game objects, sprites, colliders, tilemaps,
-- particle effects, sounds, labels and factories), adds the rooms the streamer
-- keeps loaded around it, and compares the worst neighbourhood with the limits
-- in game.project. Its report is developer/assets/tiled/world_budget.txt.
-- The game also reads spawn_caps from this file (mvtk/core/spawn_budget.lua);
-- Project > Game Settings > Game > Large worlds overrides both caps.
return {
    -- false = findings are warnings and Prepare & Check still succeeds (default).
    -- true  = any pool over its game.project limit, or a save size estimate
    --         over sys.save's limit, fails Prepare & Check.
    block_on_overflow = false,

    -- Safety margin for recommended engine limits: a recommended limit is the
    -- worst counted total times this factor (unitless; 1 = no headroom).
    -- Project > Preparation Status's Apply Recommended Engine Limits writes
    -- that value into game.project after you confirm (never lower than now).
    -- `default` applies to every pool; add a "section.key" entry to override one,
    -- for example ["sprite.max_count"] = 1.5. Safe range: 1 to 3.
    margins = {
        default = 1.25,
    },

    -- Live caps for objects the game spawns while playing. The budget reserves
    -- room for this many at once, and the game never goes past them, so a
    -- room streaming in always finds free slots. Reward pickups are never
    -- capped; the reserve below counts them instead.
    spawn_caps = {
        -- Shots alive at once; each is one game object, one sprite and one
        -- collision object. Past the cap the oldest enemy shot disappears;
        -- player shots go only when no enemy shot is left, and nothing
        -- disappears while a boss arena is locked. Whole number, 1 or more
        -- (Game Settings > Large worlds > Live shots).
        projectile = 96,
        -- Damage numbers shown at once; each is one game object and one label.
        -- Extra numbers are skipped. They share game.project's [label]
        -- max_count (128 here) with every sign, lever, teleporter and other
        -- label in the loaded rooms. Whole number, 0 or more; 0 shows none
        -- (Game Settings > Large worlds > Live damage numbers).
        damage_number = 48,
    },

    -- Extra runtime reserve for spawned enemies and dropped pickups (from Loot
    -- tables, chests and random drops). Each counts as one game object, one
    -- sprite and one collision object. Whole numbers, 0 or more.
    reserve = {
        enemies = 32,
        pickups = 64,
    },

    -- Replace the counted developer/game/main.collection baseline (main
    -- collection, the player and world-owned elevators) for a pool. Leave empty
    -- to use the counted values. Keys are pool names: instances, sprite,
    -- collision, tilemap, particlefx, sound, label, factory, collectionfactory,
    -- resources. Example: baseline = { instances = 400 },
    baseline = {},

    -- Rooms with more game objects than this are reported as slow to stream in:
    -- creating a whole room happens in one frame, and the large-world test
    -- (docs/archive/LARGE_WORLD_PERFORMANCE_TEST.md) recorded a 97 ms pause for
    -- its densest rooms. Whole number; lower it to catch smaller pauses.
    slow_room_instances = 1500,

    -- Inputs to the save size estimate (sys.save allows 512 KB and 65,536
    -- rows in one table). The estimate is approximate.
    save_estimate = {
        -- Bytes one saved flag costs, on average (key text plus value).
        bytes_per_flag = 48,
        -- Screenshot markers kept in the save and the bytes each costs. No save
        -- provider stores screenshot markers today, so both start at 0.
        screenshot_markers = 0,
        screenshot_marker_bytes = 0,
    },
}
