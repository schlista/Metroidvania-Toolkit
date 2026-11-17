-- Pure exported-image coverage check. Callers supply image dimensions and config;
-- no editor, filesystem or engine API is used here.
local Props = require "mvtk.tiled.visual_ownership"
local M = {}

-- Named aliases are case-insensitive; built-in preset names use the runtime's
-- exact lookup. Custom tables merge exploration defaults, not their type field.
function M.resolve_zone(value, config, get_preset)
    local named = {}
    for name, zone in pairs((config or {}).zones or {}) do
        if type(name) == "string" and type(zone) == "table" then named[name:lower()] = zone end
    end
    local base = get_preset and get_preset("exploration") or {}
    if type(value) == "string" then
        value = named[value:lower()] or (get_preset and get_preset(value)) or base
    end
    local resolved = {}
    for key, field in pairs(base or {}) do resolved[key] = field end
    for key, field in pairs(type(value) == "table" and value or {}) do resolved[key] = field end
    return resolved
end

local function camera_range(span, view, clamp, padding, locked)
    if locked then return span / 2, span / 2 end
    if not clamp then return 0, span end
    local low, high = view / 2 + padding, span - view / 2 - padding
    if low > high then return span / 2, span / 2 end
    return low, high
end

-- Runtime: image centre = base + (camera - anchor) * (1 - factor).
-- In image-local coordinates the visible endpoints are factor * camera +
-- (1 - factor) * anchor +/- half_view. Extrema occur at camera-range endpoints.
function M.shortfall(size, offset, factor, anchor, low, high, view, stretch)
    local a, b = factor * low, factor * high
    local needed_min = math.min(a, b) + (1 - factor) * anchor - view / 2
    local needed_max = math.max(a, b) + (1 - factor) * anchor + view / 2
    local width = size * (stretch or 1)
    local left = offset + (size - width) / 2
    return math.ceil(math.max(0, left - needed_min) + math.max(0, needed_max - left - width) - 0.000001)
end

function M.check(room_id, map, opts)
    opts = opts or {}
    local warnings = {}
    local display, camera = opts.display or {}, opts.camera or {}
    local view = display.view or {}
    local dw, dh = opts.design_w or 1920, opts.design_h or 1080
    local room_w, room_h = (map.width or 0) * (map.tilewidth or 0), (map.height or 0) * (map.tileheight or 0)
    if room_w <= 0 or room_h <= 0 then return warnings end
    local zone = opts.zone or {}
    local zoom = math.max(0.000001, (camera.default_zoom or 1) * (zone.zoom_level or 1))
    local can_expand = view.mode == "expand" or view.player_choice == true
    local widest = can_expand and math.max(dw, dh * (view.max_aspect or 2.4)) or dw
    local tallest = can_expand and math.max(dh, dw / (view.min_aspect or 4 / 3)) or dh
    local vw, vh = widest / zoom, tallest / zoom
    local lx, hx = camera_range(room_w, vw, zone.clamp_to_room, zone.bounds_padding or 0, zone.lock_camera)
    local ly, hy = camera_range(room_h, vh, zone.clamp_to_room, zone.bounds_padding or 0, zone.lock_camera)
    local origin = map.parallaxorigin or {}
    local ax, ay = origin.x or map.parallaxoriginx or 0, origin.y or map.parallaxoriginy or 0
    local function visit(layers, parent)
        for _, layer in ipairs(layers or {}) do
            local state = { x = parent.x + (layer.offsetx or 0), y = parent.y + (layer.offsety or 0),
                fx = parent.fx * (layer.parallaxx or 1), fy = parent.fy * (layer.parallaxy or 1),
                visible = parent.visible and layer.visible ~= false }
            if layer.type == "group" then visit(layer.layers, state)
            elseif layer.type == "imagelayer" and state.visible and layer.image and (state.fx ~= 1 or state.fy ~= 1) then
                local w, h = layer.imagewidth, layer.imageheight
                if (not w or not h) and opts.dimensions then w, h = opts.dimensions(layer.image) end
                if w and h and w > 0 and h > 0 then
                    local stretch = Props.property_value(layer, "stretch_to_fill") == true
                    local sx = layer.repeatx and 0 or M.shortfall(w, state.x, state.fx, ax, lx, hx, vw, stretch and widest / dw or 1)
                    local sy = layer.repeaty and 0 or M.shortfall(h, state.y, state.fy, ay, ly, hy, vh, stretch and tallest / dh or 1)
                    if sx > 0 or sy > 0 then
                        warnings[#warnings + 1] = string.format("Background %s in %s runs out on wide screens: extend it by %d px horizontally and %d px vertically",
                            tostring(layer.name or layer.id or "image"), tostring(room_id), math.max(0, sx), math.max(0, sy))
                    end
                end
            end
        end
    end
    visit(map.layers, { x = 0, y = 0, fx = 1, fy = 1, visible = true })
    return warnings
end

-- PNG header decoding is data-only; callers own reading the exported image.
function M.png_dimensions(text)
    if not text or text:sub(1, 8) ~= "\137PNG\r\n\26\n" or #text < 24 then return nil end
    local function u32(at)
        local a, b, c, d = text:byte(at, at + 3)
        return a * 16777216 + b * 65536 + c * 256 + d
    end
    return u32(17), u32(21)
end

return M
