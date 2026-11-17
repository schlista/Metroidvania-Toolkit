-- Pure preference resolution. No engine state or dependencies; callers own clocks and effects.
local M = {}

local function choice(prefs, defaults, key)
    if prefs[key] ~= nil then return prefs[key] end
    return defaults[key]
end

local function effect_scale(level, reduced)
    if level == "off" then return 0 end
    if level == "reduced" then return reduced end
    return 1
end

function M.resolve(prefs, cfg, creator_camera_shake)
    prefs, cfg = prefs or {}, cfg or {}
    local defaults, reduced = cfg.player or {}, cfg.reduced or {}
    local shake = choice(prefs, defaults, "shake")
    if shake == nil or shake == "auto" then
        shake = creator_camera_shake == false and "off" or "full"
    end
    local captions, caption_defaults = prefs.captions or {}, cfg.captions or {}
    return {
        text_scale = choice(prefs, defaults, "text_size") or 1,
        shake_scale = effect_scale(shake, reduced.shake or 0.5),
        freeze_scale = effect_scale(choice(prefs, defaults, "freeze_frames"), reduced.freeze or 0.5),
        flash_level = choice(prefs, defaults, "flashes") or "full",
        flash_alpha = reduced.flash_alpha or 0.35,
        flash_min_seconds = reduced.flash_min_seconds or 0.3,
        flash_min_gap = reduced.flash_min_gap or 0.34,
        captions = {
            enabled = choice(captions, caption_defaults, "enabled") == true,
            background = choice(captions, caption_defaults, "background") or "dim",
        },
    }
end

function M.text_scale(view, role)
    if role == "menu" or role == "hud" then return 1 end
    return view.text_scale
end

-- Returns a colour with named x/y/z/w components. Engine callers construct a vector.
-- Only accepted flash starts update the caller's last timestamp.
function M.flash(view, color, duration, now, last)
    if view.flash_level == "off" then return nil end
    if view.flash_level ~= "reduced" then return color, duration end
    if last ~= nil and now - last < view.flash_min_gap then return nil end
    return { x = color.x, y = color.y, z = color.z, w = color.w * view.flash_alpha },
        math.max(duration, view.flash_min_seconds)
end

return M
