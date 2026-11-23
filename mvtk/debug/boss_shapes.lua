-- Installed by the debug overlay. Gameplay sees a nil probe when it is off.
local Common = require "mvtk.bosses.boss_attacks.common"
local Indicator = require "mvtk.bosses.indicator_geometry"
local M = {}
local SEGMENTS = 24

local function line(x1, y1, x2, y2, z, color)
    msg.post("@render:", "draw_line", {
        start_point = vmath.vector3(x1, y1, z),
        end_point = vmath.vector3(x2, y2, z),
        color = color,
    })
end

local function rectangle(left, bottom, right, top, z, color)
    line(left, bottom, right, bottom, z, color)
    line(right, bottom, right, top, z, color)
    line(right, top, left, top, z, color)
    line(left, top, left, bottom, z, color)
end

local function circle(center, radius, color)
    local x, y, z = center.x, center.y, center.z or 0
    local px, py = x + radius, y
    for segment = 1, SEGMENTS do
        local angle = segment * 2 * math.pi / SEGMENTS
        local next_x, next_y = x + radius * math.cos(angle), y + radius * math.sin(angle)
        line(px, py, next_x, next_y, z, color)
        px, py = next_x, next_y
    end
end

local shapes = {}
function shapes.circle(_, color, center, radius)
    circle(center, radius, color)
end

function shapes.ring(_, color, center, inner, outer)
    circle(center, outer, color)
    if inner > 0 then circle(center, inner, color) end
end

function shapes.box(_, color, center, half_w, half_h)
    rectangle(center.x - half_w, center.y - half_h,
        center.x + half_w, center.y + half_h, center.z or 0, color)
end

function shapes.beam(_, color, origin, direction, length, width)
    local dx, dy = direction.x, direction.y
    local magnitude = math.sqrt(dx * dx + dy * dy)
    if magnitude == 0 then return end
    dx, dy = dx / magnitude, dy / magnitude
    local x, y, z = origin.x, origin.y, origin.z or 0
    local sx, sy = -dy * width * 0.5, dx * width * 0.5
    local ex, ey = x + dx * length, y + dy * length
    line(x + sx, y + sy, ex + sx, ey + sy, z, color)
    line(ex + sx, ey + sy, ex - sx, ey - sy, z, color)
    line(ex - sx, ey - sy, x - sx, y - sy, z, color)
    line(x - sx, y - sy, x + sx, y + sy, z, color)
end

local function band(left, right, y, height, z, color)
    rectangle(left, y - height * 0.5, right, y + height * 0.5, z, color)
end

function shapes.ground_area(_, color, center, radius, options)
    local y, height = Indicator.floor_band(center.y, Indicator.clearance(options))
    band(center.x - radius, center.x + radius, y, height, center.z or 0, color)
end

function shapes.charge(body, color, ctx, from, to)
    local y, height = Indicator.charge_band(ctx.ground_y, ctx.hitbox_half_height, body)
    band(math.min(from.x, to.x) - ctx.hitbox_half_width, math.max(from.x, to.x) + ctx.hitbox_half_width,
        y, height, to.z or 0, color)
end

function shapes.swept_band(_, color, from, to, half_width, y, height, z)
    band(math.min(from, to) - half_width, math.max(from, to) + half_width, y, height, z or 0, color)
end

function M.install(config)
    local attack_color = vmath.vector4(unpack(config.shape_color))
    local body_color = vmath.vector4(unpack(config.player_body_color))
    local samples = {}
    -- Flush the whole batch in the overlay update so the attack outlines and
    -- the single player outline reach the renderer together.
    Common.shape_probe = function(body, shape, ...)
        local draw = shapes[shape]
        if draw then samples[#samples + 1] = {body, draw, ...} end
    end
    return function()
        local body
        for index, sample in ipairs(samples) do
            sample[2](sample[1], attack_color, unpack(sample, 3))
            body = sample[1]
            samples[index] = nil
        end
        if body then shapes.box(nil, body_color, body, body.half_w, body.half_h) end
    end
end

function M.uninstall()
    Common.shape_probe = nil
end

return M
