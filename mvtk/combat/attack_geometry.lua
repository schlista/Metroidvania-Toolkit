-- mvtk/combat/attack_geometry.lua
-- Shared geometry helpers for enemy & boss attacks.
--
-- Pure math, no side effects. Used by:
--   * mvtk/bosses/boss_attacks.lua     (multi-type boss attacks)
--   * mvtk/enemies/patterns/attack_patterns.lua (enemy pattern execution)
--
-- Keeping these in one place avoids the "copy-paste angle math" drift between
-- boss and enemy code that the robustness review flagged.

local M = {}

-- Compute a list of angles (radians) for a spread/fan attack.
-- count: number of projectiles to spawn (>=1)
-- arc_deg: total arc of the spread in degrees (0 = all on base_angle)
-- base_angle: center angle in radians (e.g. atan2(dy, dx) toward the player)
-- Returns a list of `count` radian angles.
--
--   M.compute_spread_angles(1, 0, 0)          --> {0}
--   M.compute_spread_angles(3, 30, 0)         --> {-0.26, 0, 0.26} approx
function M.compute_spread_angles(count, arc_deg, base_angle)
    count = math.max(1, math.floor(tonumber(count) or 1))
    arc_deg = tonumber(arc_deg) or 0
    base_angle = tonumber(base_angle) or 0

    local angles = {}
    if count == 1 or arc_deg == 0 then
        for i = 1, count do angles[i] = base_angle end
        return angles
    end

    local arc_rad = math.rad(arc_deg)
    local step = arc_rad / (count - 1)
    local start = base_angle - arc_rad * 0.5
    for i = 1, count do
        angles[i] = start + step * (i - 1)
    end
    return angles
end

-- Normalized 2D aim vector from `from` to `to`.
-- Accepts anything with .x/.y (vector3, vector2, table). Returns vmath.vector3(1,0,0)
-- when the two points coincide, so callers can safely multiply by a speed.
function M.aim_vector(from, to)
    local dx = (to.x or 0) - (from.x or 0)
    local dy = (to.y or 0) - (from.y or 0)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then
        return vmath.vector3(1, 0, 0)
    end
    return vmath.vector3(dx / len, dy / len, 0)
end

function M.distance_2d(from, to)
    local dx = (to.x or 0) - (from.x or 0)
    local dy = (to.y or 0) - (from.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

-- Circle hit-test — is `point` within `radius` of `center`?
-- Uses squared distance to avoid a sqrt.
function M.point_in_circle(center, radius, point)
    local dx = (point.x or 0) - (center.x or 0)
    local dy = (point.y or 0) - (center.y or 0)
    local r = tonumber(radius) or 0
    return (dx * dx + dy * dy) <= (r * r)
end

-- Axis-aligned box hit-test — is `point` inside the hitbox centered on `center`?
-- half_w/half_h are HALF-extents (i.e. full width = 2*half_w).
function M.point_in_box(center, half_w, half_h, point)
    return math.abs((point.x or 0) - (center.x or 0)) <= (tonumber(half_w) or 0)
       and math.abs((point.y or 0) - (center.y or 0)) <= (tonumber(half_h) or 0)
end

-- Beam hit-test — is `point` inside the beam swept from `origin` along `dir`
-- for `length` units, with `width` total width (centered on the beam line)?
--
-- Extracted from boss_attacks.lua dot-product logic (was inline, fragile).
-- `dir` must be normalized (e.g. from M.aim_vector).
function M.point_in_beam(origin, dir, length, width, point)
    local to = vmath.vector3((point.x or 0) - (origin.x or 0),
                             (point.y or 0) - (origin.y or 0), 0)
    local proj = vmath.dot(to, dir)
    if proj <= 0 or proj >= (tonumber(length) or 0) then
        return false
    end
    -- Perpendicular component magnitude.
    local perp = to - dir * proj
    local half_w = (tonumber(width) or 0) * 0.5
    return vmath.length(perp) <= half_w
end

-- Squared distance to the nearest point on or inside the body.
function M.distance_sq_to_rect(center, rect)
    local dx = math.max(0, math.abs((rect.x or 0) - (center.x or 0)) - rect.half_w)
    local dy = math.max(0, math.abs((rect.y or 0) - (center.y or 0)) - rect.half_h)
    return dx * dx + dy * dy
end

function M.rect_in_circle(center, radius, rect)
    local r = tonumber(radius) or 0
    return M.distance_sq_to_rect(center, rect) <= r * r
end

function M.rect_in_box(center, half_w, half_h, rect)
    half_w, half_h = tonumber(half_w) or 0, tonumber(half_h) or 0
    return half_w >= 0 and half_h >= 0
       and math.abs((rect.x or 0) - (center.x or 0)) <= half_w + rect.half_w
       and math.abs((rect.y or 0) - (center.y or 0)) <= half_h + rect.half_h
end

function M.rect_in_ring(center, inner, outer, rect)
    inner, outer = math.max(0, tonumber(inner) or 0), tonumber(outer) or 0
    if outer < inner or M.distance_sq_to_rect(center, rect) > outer * outer then return false end
    local far_x = math.abs((rect.x or 0) - (center.x or 0)) + rect.half_w
    local far_y = math.abs((rect.y or 0) - (center.y or 0)) + rect.half_h
    return far_x * far_x + far_y * far_y >= inner * inner
end

function M.rect_in_beam(origin, dir, length, width, rect)
    local half_length = (tonumber(length) or 0) * 0.5
    local half_width = (tonumber(width) or 0) * 0.5
    local ux, uy = dir.x or 0, dir.y or 0
    local magnitude = math.sqrt(ux * ux + uy * uy)
    if half_length <= 0 or half_width < 0 or magnitude == 0 then return false end
    if rect.half_w == 0 and rect.half_h == 0 then
        -- Preserve the legacy endpoint comparisons for directions already
        -- normalized to vector precision. Only normalize an actual scale.
        local unit = math.abs(magnitude - 1) <= 2 ^ -22 and dir
            or vmath.vector3(ux / magnitude, uy / magnitude, 0)
        return M.point_in_beam(origin, unit, length, width, rect)
    end
    ux, uy = ux / magnitude, uy / magnitude

    -- Test the two world axes and the beam's longitudinal and transverse axes.
    local dx = (rect.x or 0) - (origin.x or 0) - ux * half_length
    local dy = (rect.y or 0) - (origin.y or 0) - uy * half_length
    local ax, ay = math.abs(ux), math.abs(uy)
    return math.abs(dx) <= rect.half_w + half_length * ax + half_width * ay
       and math.abs(dy) <= rect.half_h + half_length * ay + half_width * ax
       and math.abs(dx * ux + dy * uy) <= half_length + rect.half_w * ax + rect.half_h * ay
       and math.abs(dy * ux - dx * uy) <= half_width + rect.half_w * ay + rect.half_h * ax
end

-- Evenly distribute `count` points on a circle of `radius` around `center`.
-- Used by summon attacks to place minions.
function M.ring_positions(center, radius, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    radius = tonumber(radius) or 0
    local out = {}
    for i = 1, count do
        local angle = (math.pi * 2 / count) * i
        out[i] = vmath.vector3(
            (center.x or 0) + math.cos(angle) * radius,
            (center.y or 0) + math.sin(angle) * radius,
            center.z or 0
        )
    end
    return out
end

return M
