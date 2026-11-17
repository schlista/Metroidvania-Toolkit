-- Extras: a jukebox, a gallery and credits replay, unlocked across save slots.
-- Unlocks are stored in the per-game profile, so they survive slot deletion and
-- belong to this game only. Game Settings > Ending > Extras edits the switches;
-- the track and gallery lists stay in this file.
--
-- Each entry's `unlock` is one of:
--   { type = "always" }                         -- always unlocked.
--   { type = "heard" }                          -- jukebox only: once the track has played in any slot.
--   { type = "ending", ending_id = "" }         -- an ending was reached; blank means any ending.
--   { type = "achievement", id = "" }           -- that achievement is unlocked.
--   { type = "flag", flag = "" }                -- that flag was set in any slot while Extras was enabled.
--   { type = "cycle", cycle = 1 }               -- a save reached at least this New Game+ cycle.
-- An entry with no `unlock` uses "heard" for tracks and "always" for gallery images.
return {
    enabled = false,      -- Off: no listeners act, no title entry, no profile writes.
    notify = true,        -- Show a notice when an entry with a flag unlock unlocks during play.
    show_locked = true,   -- Locked entries show as ??? instead of being hidden.
    jukebox = {
        enabled = true,   -- Show the Jukebox tab once it has at least one track.
        tracks = {        -- Each track id is a registered music track (developer/assets/music/).
            -- { track = "forest_theme", title = "Forest", unlock = { type = "heard" } },
        },
    },
    gallery = {
        enabled = true,   -- Show the Gallery tab once it has at least one image.
        entries = {       -- id is unique; image is a PNG name in developer/assets/extras/ (without .png).
            -- { id = "concept_1", image = "concept_1", title = "Early sketch", caption = "",
            --   unlock = { type = "ending", ending_id = "" } }, -- blank = any ending
        },
    },
    credits = {
        enabled = true,   -- One row per ending seen on this profile.
    },
}
