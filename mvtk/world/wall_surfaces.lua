-- Shared, engine-free registry. Baked scripts own entries for their lifetimes.
local Presets = require "developer.config.wall_surface_types"
local entries, order = {}, {}
local M = {}

function M.is_legacy(version)
    local major, minor = tostring(version or ""):match("^(%d+)%.(%d+)")
    return not major or tonumber(major) < 2 or (tonumber(major) == 2 and tonumber(minor) < 8)
end

-- Old exports flattened defaults which were inert. Opt in only on re-export.
function M.export_rule(props)
    local out = {}
    for key, value in pairs(props or {}) do out[key] = value end
    if M.is_legacy(out.mvtk_template_version) then
        out.allow_slide, out.allow_jump, out.allow_climb = true, true, true
        out.slide_speed, out.jump_force_x, out.jump_force_y = -1, -1, -1
        out.facing, out.require_ability, out.requires_ability, out.surface_type = 0, "", nil, "stone"
        out.direction = nil
    end
    return out
end

local function number_override(value, fallback)
    value = tonumber(value)
    if value and value >= 0 then return value end
    fallback = tonumber(fallback)
    return fallback and fallback >= 0 and fallback or -1
end

function M.register(id, rule)
    local preset = Presets[rule.surface_type] or {}
    local resolved = {}
    for key, value in pairs(rule) do resolved[key] = value end
    for _, key in ipairs({"allow_slide", "allow_jump", "allow_climb"}) do
        resolved[key] = rule[key] ~= false and preset[key] ~= false
    end
    resolved.slide_speed = number_override(rule.slide_speed, preset.slide_mult)
    resolved.jump_force_x = number_override(rule.jump_force_x, preset.jump_force_x)
    resolved.jump_force_y = number_override(rule.jump_force_y, preset.jump_force_y)
    -- Both requirements apply; an object must never loosen its material preset.
    resolved.preset_ability = preset.require_ability
    if not entries[id] then order[#order + 1] = id end
    entries[id] = resolved
end

function M.unregister(id)
    entries[id] = nil
    for i, key in ipairs(order) do
        if key == id then table.remove(order, i); return end
    end
end

-- x is the wall-facing collider edge; y +/- half_height is its vertical span.
-- Stable registration order resolves overlapping markers deterministically.
function M.find(x, y, side, half_height)
    for _, id in ipairs(order) do
        local r = entries[id]
        if (not r.facing or r.facing == 0 or r.facing == -side)
            and math.abs(x - r.x) <= r.half_width
            and y + (half_height or 0) >= r.y - r.half_height
            and y - (half_height or 0) <= r.y + r.half_height then
            return r
        end
    end
end

return M
