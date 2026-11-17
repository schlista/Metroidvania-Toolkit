-- Shared per-frame light mask state. Engine-free at load; only scripts publish.
local M = {}
local cached, revision, published
local supported = true
local frame = {}

local function clamp(value, low, high, fallback)
    if type(value) ~= "number" or value ~= value then return fallback end
    return math.max(low, math.min(high, value))
end

local function color(raw, r, g, b)
    raw = type(raw) == "table" and raw or {}
    return { r = clamp(raw.r, 0, 1, r), g = clamp(raw.g, 0, 1, g), b = clamp(raw.b, 0, 1, b) }
end

function M.normalize(raw)
    raw = type(raw) == "table" and raw or {}
    return {
        mode = raw.mode == "glow" and "glow" or "mask",
        max_darkness = clamp(raw.max_darkness, 0, 1, 1),
        shadow_color = color(raw.shadow_color, 0, 0, 0),
        light_color = color(raw.light_color, 1, 0.92, 0.70),
        falloff = clamp(raw.falloff, 0.25, 4, 0.6),
        mask_scale = clamp(raw.mask_scale, 0.25, 1, 0.5),
        glow_with_mask = clamp(raw.glow_with_mask, 0, 1, 0),
        light_shape = type(raw.light_shape) == "string" and raw.light_shape:match("%S")
            and raw.light_shape or "light_glow_soft",
        max_lights = math.floor(clamp(raw.max_lights, 1, 64, 24)),
    }
end

function M.settings()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local current = RuntimeSettings.revision()
    if not cached or revision ~= current then
        cached = M.normalize(RuntimeSettings.section("lighting", require "developer.config.lighting"))
        revision = current
    end
    return cached
end

function M.ambient(darkness, shadow)
    return 1 - darkness + darkness * shadow.r,
        1 - darkness + darkness * shadow.g, 1 - darkness + darkness * shadow.b
end

function M.light_scale(radius, sprite_width)
    return math.max(1e-4, 2 * radius / sprite_width)
end

function M.publish(r, g, b, scale)
    frame.r, frame.g, frame.b, frame.scale = r, g, b, scale
    published = supported and frame or nil
end
function M.clear() published = nil end
function M.frame() return published end
function M.mark_unsupported() supported = false; M.clear() end
function M.supported() return supported end

return M
