-- Shared picture treatment. No engine APIs: game scripts publish, renderer reads.
local M = {}
local cached, revision, published
local supported = true
local combined = {}

local function clamp(value, low, high, fallback)
    if type(value) ~= "number" or value ~= value then return fallback end
    return math.max(low, math.min(high, value))
end

function M.normalize(raw)
    raw = type(raw) == "table" and raw or {}
    local tint = type(raw.tint) == "table" and raw.tint or {}
    return {
        brightness = clamp(raw.brightness, 0.5, 1.5, 1),
        gamma = clamp(raw.gamma, 0.5, 2, 1),
        saturation = clamp(raw.saturation, 0, 2, 1),
        tint = { r = clamp(tint.r, 0, 1, 1), g = clamp(tint.g, 0, 1, 1),
            b = clamp(tint.b, 0, 1, 1), strength = clamp(tint.strength, 0, 1, 0) },
        scanlines = clamp(raw.scanlines, 0, 1, 0),
        scanline_count = clamp(raw.scanline_count, 60, 1080, 270),
        curvature = clamp(raw.curvature, 0, 0.25, 0),
        vignette = clamp(raw.vignette, 0, 1, 0),
        player_brightness = raw.player_brightness ~= false,
    }
end

function M.creator()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local current = RuntimeSettings.revision()
    if not cached or revision ~= current then
        cached = M.normalize(RuntimeSettings.section("display", require "developer.config.display_settings").post)
        revision = current
    end
    return cached
end

-- creator is the normalized cached configuration. Reuse one table each frame.
function M.combine(creator, player_brightness)
    local brightness = creator.brightness * (creator.player_brightness
        and clamp(player_brightness, 0.5, 1.5, 1) or 1)
    brightness = clamp(brightness, 0.25, 2, 1)
    if brightness == 1 and creator.gamma == 1 and creator.saturation == 1
        and creator.tint.strength == 0 and creator.scanlines == 0
        and creator.curvature == 0 and creator.vignette == 0 then return nil end
    combined.brightness, combined.inv_gamma, combined.saturation = brightness, 1 / creator.gamma, creator.saturation
    combined.tint_r, combined.tint_g, combined.tint_b = creator.tint.r, creator.tint.g, creator.tint.b
    combined.tint_strength = creator.tint.strength
    combined.scanlines, combined.scanline_count = creator.scanlines, creator.scanline_count
    combined.curvature, combined.vignette = creator.curvature, creator.vignette
    return combined
end

function M.publish(value) published = supported and value or nil end
function M.clear() published = nil end
function M.frame() return published end
function M.mark_unsupported() supported = false; M.clear() end
function M.supported() return supported end

return M
