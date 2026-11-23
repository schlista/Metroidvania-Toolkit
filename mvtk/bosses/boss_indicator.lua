-- Shared art, sizing and visual states for the two boss indicator scripts.
local Util = require "mvtk.core.util"

local M = {}
local SPRITE = "#sprite"
local CANVAS = 64
local Defaults = require("developer.config.boss_defaults").indicator
local BAKED_FILL = 51 / 255

M.BUILTIN = {
    warning_color = {0.81, 0.28, 0.03, 0.96},
    active_color = {0.90, 0.16, 0.46, 1},
    neutral_color = Defaults.neutral_color,
    fill = 0.20,
    rim = 1,
    pulse_speed = 2,
    pulse_min = 0.86,
    pulse_max = 1,
    spent_fraction = 0.33,
    minimum_active_time = 0.12,
}

function M.resolve(defaults)
    local authored = defaults and defaults.indicator
    authored = type(authored) == "table" and authored or {}
    local config = {}
    for key, fallback in pairs(M.BUILTIN) do
        local value = authored[key]
        config[key] = value == nil and fallback or value
    end
    return config
end

function M.config()
    return M.resolve(Util.require_config("developer.config.boss_defaults", {}))
end

function M.resize_box(component, width, height)
    -- Defold does not clamp overlapping slices. Keep narrow boxes intact.
    local rim = Defaults.box_rim_pixels
    local x = width >= 2 * rim and rim or 0
    local y = height >= 2 * rim and rim or 0
    if width < 1 or height < 1 then x, y = 0, 0 end
    go.set(component, "slice", vmath.vector4(x, y, x, y))
    go.set(component, "size", vmath.vector3(width, height, 0))
end

function M.setup(shape, width, height)
    local round = shape == "circle" or shape == "ring"
    local image = round and (shape == "ring" and "ring" or "disc") or "box"
    sprite.play_flipbook(SPRITE, "boss_indicator_" .. image)
    if round then
        go.set(SPRITE, "size", vmath.vector3(CANVAS, CANVAS, 0))
        local scale = math.max(1e-6, width / CANVAS)
        go.set_scale(vmath.vector3(scale, scale, 1))
    else
        M.resize_box(SPRITE, width, height)
        go.set_scale(vmath.vector3(1, 1, 1))
    end
end

local function channel(value, default)
    return value >= 0 and value or default
end

function M.tint(self, look, elapsed, fade)
    local config = self.indicator
    local warning = look == "warning"
    local color = look == "neutral" and config.neutral_color
        or (warning and config.warning_color or config.active_color)
    local opacity = 1
    if warning then
        local Settings = require "mvtk.core.settings"
        opacity = config.pulse_max
        if Settings.get_accessibility().flash_level == "full" then
            local phase = (1 + math.cos(elapsed * config.pulse_speed * 2 * math.pi)) * 0.5
            opacity = config.pulse_min + (config.pulse_max - config.pulse_min) * phase
        end
    elseif look == "spent" then
        opacity = config.spent_fraction * fade
    end
    local r, g, b, a = self.color_r, self.color_g, self.color_b, self.color_a
    if self.effect_warning and warning then
        local override = self.warning_color
        r, g, b, a = override.x, override.y, override.z, override.w
    end
    go.set(SPRITE, "tint", vmath.vector4(
        channel(r, color[1]), channel(g, color[2]), channel(b, color[3]),
        channel(a, color[4]) * opacity))
end

function M.set_look(self, look, fade)
    local spent = look == "spent"
    local config = self.indicator
    go.set(SPRITE, "indicator_opacity", vmath.vector4(look == "neutral" and 0 or config.fill,
        config.rim, self.ring and 0 or BAKED_FILL, spent and 1 or 0))
    M.tint(self, look, 0, fade or 1)
end

return M
