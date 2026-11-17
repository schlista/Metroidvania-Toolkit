-- Default behaviour for baked Encounter rectangles and their wave points.
-- Per-Encounter Wave delay -1 and Max alive 0 inherit these project defaults.
-- Framework toast wording is translated through ui_text.lua, not saved here.
return {
    -- Seconds between defeated waves (not added before the first wave).
    wave_delay = 1.5,
    -- Simultaneously living wave enemies; pending telegraphs reserve a slot.
    max_alive = 6,
    -- Seconds from a point's telegraph to its enemy spawn; 0 spawns immediately.
    spawn_telegraph_time = 0.5,
    -- fx_types.lua effect id; blank means no default visual telegraph.
    telegraph_effect = "",
    -- Global wave-toast switch; the Encounter's Show wave messages must also be on.
    show_wave_messages = true,
    -- Seconds for wave and Area cleared toasts to remain visible.
    toast_duration = 2.5,
    -- Save clear flags, shortcut channels and synchronous event listener changes together.
    autosave_on_clear = true,
}
