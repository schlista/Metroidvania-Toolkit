-- Positional ambience mixing. Sound Source and positional Ambience Zone use
-- existing looping components registered in ambient_sounds.lua (ambient group).
-- Keep their ids separate from area zones and room/world ambient_sound loops.
return {
    -- "camera" follows the picture centre, falling back to the player until
    -- the camera publishes; "player" always follows the player's world position.
    listener = "camera",
    -- Maximum gain change per second, in both directions (2 = full fade in 0.5s).
    fade_per_second = 2.0,
    -- Start above this gain; stop after two consecutive quiet frames below it.
    stop_below_gain = 0.01,
    -- Stereo strength: 0 centres every source; 1 allows full left/right pan.
    pan_strength = 0.5,
    -- Pixels from listener to full-strength pan. 0 uses half the visible world
    -- width (including wide-screen expansion); before a view exists, uses 960.
    pan_distance_px = 0,
}
