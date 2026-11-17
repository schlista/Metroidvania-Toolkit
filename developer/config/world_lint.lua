-- Cross-room flag and world pacing checks for Prepare & Check, validation and layout publication.
return {
    -- Player proportions: Prepare & Check warns without resizing or blocking
    -- the game. Height means the full standing collider at saved Player size,
    -- divided by the project's tile height; art and box offsets do not count.
    player_size = {
        -- Warn below this many tiles (positive; exactly this height is fine).
        min_height_tiles = 1,
        -- Warn above this many tiles (greater than min; equality is fine).
        max_height_tiles = 3,
        -- Suggested height in tiles, between min and max. The suggested Player
        -- size rounds down to the field's step, within its accepted range.
        target_height_tiles = 2,
    },
    flags = {
        -- Warnings are the default: flag mistakes never block Build.
        -- Set true to make them errors, blocking Prepare & Check, Validate All
        -- and every Build until the flag is fixed or allowed below.
        errors = false,
        -- Custom-script writers absent from Tiled/config: exact names or a
        -- trailing prefix_* wildcard, for example "quest_done", "custom_*".
        -- Clear a literal "none" outside dialogue triggers; it is a real flag.
        allow = {},
    },
    -- World pacing: Analyze Progression and every publication check walk the
    -- placed rooms through doors, elevators, zip lines, vehicles and
    -- teleporters (fast travel and gates are ignored). Results are written to
    -- developer/assets/tiled/progression_diagnostics.txt; warnings also show in
    -- Project > Preparation Status. Pacing never blocks publication or Build.
    pacing = {
        -- false turns every pacing warning and info line off.
        enabled = true,
        -- Warn about rooms more than this many room-to-room hops from the
        -- nearest save point, checkpoint, fast travel station or the start
        -- room. A whole number, 1 or more. Hops ignore room size, so worlds
        -- with very large rooms may need a lower number.
        max_rooms_without_save = 8,
        -- true adds an info line (report only) for each room with one exit
        -- and no save point, reward, map station, vendor or other counted content.
        dead_end_info = true,
    },
}
