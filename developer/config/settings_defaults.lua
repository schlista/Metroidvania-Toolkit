-- developer/config/settings_defaults.lua
-- Default player-facing settings for audio, graphics, and gameplay.
-- Adjust these instead of editing mvtk/core/settings.lua.

local M = {
    audio = {
        master_volume = 0.8,
        music_volume = 0.7,
        sfx_volume = 0.8,
        muted = false,
        mute_when_unfocused = false, -- Silence gameplay audio in the background; keep saved volumes.
    },
    graphics = {
        window_mode = "windowed",          -- "windowed", "fullscreen_windowed", "fullscreen"
        vsync = true,
        show_fps = false,
        brightness = 1.0,                 -- Picture multiplier, 0.5-1.5 (100% unchanged).
        view_fill = "auto",                -- "auto" follows the creator; "expand" / "letterbox" require permission.
    },
    gameplay = {
        camera_shake = true,
        pause_on_focus_loss = true, -- Open Pause on focus loss or desktop minimise; never auto-resume.
        pause_on_controller_disconnect = true, -- Pause only when the last-used, active controller disconnects.
        rumble = true,
        damage_numbers = false,
        number_options = {
            enemies = true,
            player  = true,
            heal    = true,
            crit    = true,
        },
        auto_save = true,
        icon_theme = "xbox",   -- "xbox", "playstation", or "switch"
    },
    language = "auto", -- Follow a supported system language, else the creator default/fallback.
}

return M
