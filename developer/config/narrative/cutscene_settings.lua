-- Scene entry and playback defaults. Game Settings saves project overrides.
return {
    -- Scene id to play once at the start of a fresh save; blank disables it.
    opening = "",
    -- Permit hold-to-skip for scenes that allow it and have no dialogue outcomes.
    allow_skip = true,
    -- Continuous hold in seconds before skipping (0.2 to 5).
    skip_hold_seconds = 0.8,
    -- Existing high-level action from default_bindings.lua; avoid menu toggles.
    skip_action = "JUMP",
    -- Persistent hint; {skip} follows the action's remapped input prompt.
    skip_hint = "Hold {skip} to skip",
}
