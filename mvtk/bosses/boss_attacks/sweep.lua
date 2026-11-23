-- Turn one beam effect in place and sample the same beam against the player.
local C = require "mvtk.bosses.boss_attacks.common"
local Telegraph = require "mvtk.bosses.boss_telegraph"

local M = {}
local TURN = 2 * math.pi

local function sweep_contact(origin, first, last, length, width, body)
    local function overlaps(angle)
        return C.Geometry.rect_in_beam(origin,
            vmath.vector3(math.cos(angle), math.sin(angle), 0), length, width, body)
    end
    if first == last then
        if overlaps(first) then return first, last end
        return
    end
    local x, y = body.x - origin.x, body.y - origin.y
    local hw, hh, beam_half = body.half_w, body.half_h, width * 0.5
    local near_x, near_y = math.max(0, math.abs(x) - hw), math.max(0, math.abs(y) - hh)
    if near_x * near_x + near_y * near_y > length * length + beam_half * beam_half then return end

    -- Overlap only changes at a vertex/edge contact. Solve each edge's
    -- projected coordinate, then test the intervals between contacts.
    local low, high = math.min(first, last), math.max(first, last)
    if last > first then high = math.min(high, low + TURN)
    else low = math.max(low, high - TURN) end
    local edges = {low, high}
    local function crossing(radius, phase, offset)
        if radius <= 0 or math.abs(offset) > radius then return end
        local arc = math.acos(offset / radius)
        for sign = -1, 1, 2 do
            local a = phase + sign * arc
            a = a + math.ceil((low - a) / TURN) * TURN
            if a > low and a < high then edges[#edges + 1] = a end
        end
    end
    for side = -1, 1, 2 do
        for height = -1, 1, 2 do
            local bx, by = x + side * hw, y + height * hh
            local radius, phase = math.sqrt(bx * bx + by * by), math.atan2(by, bx)
            crossing(radius, phase, 0)
            crossing(radius, phase, length)
            crossing(radius, phase - math.pi / 2, -beam_half)
            crossing(radius, phase - math.pi / 2, beam_half)

            local rx, ry = side == -1 and 0 or length, height * beam_half
            radius, phase = math.sqrt(rx * rx + ry * ry), math.atan2(ry, rx)
            crossing(radius, -phase, x - hw)
            crossing(radius, -phase, x + hw)
            crossing(radius, math.pi / 2 - phase, y - hh)
            crossing(radius, math.pi / 2 - phase, y + hh)
        end
    end
    table.sort(edges)
    local index, step, stop = 1, 1, #edges
    if last < first then index, step, stop = #edges, -1, 1 end
    local enter, leave
    while index ~= stop do
        local a, b = edges[index], edges[index + step]
        if overlaps((a + b) * 0.5) then
            enter, leave = enter or a, b
        elseif enter then
            break
        elseif overlaps(a) then
            return a, a
        end
        index = index + step
    end
    if enter then return enter, leave end
    if overlaps(edges[stop]) then return edges[stop], edges[stop] end
end

function M.execute(boss, pattern, instance)
    local settings = C.stationary_options(pattern)
    if not settings then return end
    instance = C.stationary_instance(boss, pattern, instance)
    local cue = Telegraph.take_stationary(boss, pattern, settings)
    local damage = (pattern.damage or settings.damage) * C.damage_mult(boss)
    local knockback = pattern.knockback or settings.knockback
    local origin, length, width = cue.origin, settings.length, settings.width
    local angle_delta = settings.to_angle - settings.from_angle

    local function fire()
        Telegraph.cancel(cue)
        local angle = Telegraph.sweep_angle(settings.from_angle, cue.facing)
        local direction = vmath.vector3(math.cos(angle), math.sin(angle), 0)
        local effect_origin = vmath.vector3(origin.x, origin.y, origin.z + 0.1)
        local effect = C.stationary_effect(instance, "#beam_effect_factory", effect_origin, {
            end_pos = effect_origin + direction * length, width = width,
        })

        C.active_frames(instance, settings.duration, function(active, time)
            local previous_angle = angle
            local degrees = settings.from_angle + angle_delta * time / settings.duration
            angle = Telegraph.sweep_angle(degrees, cue.facing)
            direction = vmath.vector3(math.cos(angle), math.sin(angle), 0)
            if effect and go.exists(effect) then
                go.set_position(effect_origin + direction * (length * 0.5), effect)
                go.set_rotation(vmath.quat_rotation_z(angle), effect)
            end
            local body, count = C.hit_body(active, function(body)
                local enters, leaves = sweep_contact(origin, previous_angle, angle, length, width, body)
                if not enters then return false end
                if previous_angle == angle then return true end
                local schedule = active._hit_schedule
                local from = schedule.previous or schedule.first
                local seconds_per_radian = (schedule.through - from) / (angle - previous_angle)
                return true, from + (enters - previous_angle) * seconds_per_radian,
                    from + (leaves - previous_angle) * seconds_per_radian
            end, "beam", origin, direction, length, width)
            if body then
                local payload = C.build_payload(boss, pattern, damage, direction.x * knockback, direction.y * knockback)
                for _ = 1, count do C.post_damage(payload) end
            end
            if time >= settings.duration then C.delete_owned(effect) end
        end, true)
    end

    if settings.windup > 0 then instance:after(settings.windup, fire) else fire() end
end

return M
