-- Optional fight soundtrack above room music and below boss, champion and encounter music.
-- Track ids come from music registered by Prepare & Check. No audio files are copied here.
return {
    enabled = false, -- Game Settings > Game > Combat music: off until a creator opts in.
    default_track = "", -- Synced track id; blank needs a room combat_music override.
    engage = {
        radius = 640, -- Distance in world pixels; only living enemies in the current room count.
        count = 1, -- Whole number of enemies the player can see within radius needed to engage.
        line_of_sight = true, -- Terrain (including one-way platforms) blocks sight; false counts through walls.
        min_time = 0.75, -- Continuous seconds above count before proximity engages.
        on_player_hit = true, -- Accepted player damage to a non-boss engages immediately.
    },
    release_delay = 4.0, -- Quiet seconds before returning to exploration (0.5 to 30).
    fade_in = 0.8, -- Seconds into combat; minimum 0.5 to accommodate music debounce.
    fade_out = 2.0, -- Seconds back to the room or silence; minimum 0.5.
    ignore_spawned = false, -- Ignore runtime summons, splits and encounter/boss adds in proximity counts.
}
