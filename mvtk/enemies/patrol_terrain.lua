-- Resolve patrol stops on the reference step, including bodies that normally
-- only learn about walls from contacts at the end of a display frame.
local Surface = require "mvtk.core.surface_classifier"
local Ground = require "mvtk.enemies.enemy_ground_physics"
local Ledge = require "mvtk.enemies.ledge_guard"
local Carrier = require "mvtk.prefabs.passenger_carrier"
local Obstacles = require "mvtk.enemies.patrol_obstacles"

local M = {}
local ALL_HITS = {all = true}
M.ROOM_MARGIN = 16

function M.wall(self, axis, dir, dt)
    if dt <= 0 then return false end
    if axis == "x" then return self._patrol_wall_x == dir end
    return self._patrol_wall_y == dir
end

function M.request(self, axis, speed)
    self.vel[axis] = speed
    if axis == "x" then self._patrol_vx = self.vel.x else self._patrol_vy = self.vel.y end
end

local function static_terrain(hit, face_probe)
    return hit and Surface.is_terrain_group(hit.group) and hit.group ~= Surface.GROUPS.PLATFORM
        and not Obstacles.excludes(hit.id, hit.group, face_probe)
        and not Carrier.is_carrier(hit.id) and not Carrier.is_moving_body(hit.id)
end

local function body_bounds(self)
    local scale = self._patrol_shape_scale or 1
    if self._patrol_body and self._patrol_body.scale == scale then
        return self._patrol_body
    end
    if not b2d or not b2d.body.get_fixtures or self._patrol_no_body then return end
    local ok, body = pcall(b2d.get_body, "#co")
    if not ok then self._patrol_no_body = true end
    if not ok or not body then return end
    local bounds = {left = math.huge, right = -math.huge, bottom = math.huge, top = -math.huge,
        scale = scale}
    local fixtures = b2d.body.get_fixtures(body)
    for _, fixture in ipairs(fixtures) do
        if not fixture.sensor then
            local shape = b2d.fixture.get_shape(body, fixture.index)
            for _, vertex in ipairs(shape.vertices or {}) do
                -- Polygon snapshots keep their creation vertices. The live
                -- body applies the same scale factor as the sprite.
                local x, y = vertex.x * scale, vertex.y * scale
                bounds.left, bounds.right = math.min(bounds.left, x), math.max(bounds.right, x)
                bounds.bottom, bounds.top = math.min(bounds.bottom, y), math.max(bounds.top, y)
            end
            if shape.radius then
                local x, y = shape.center.x, shape.center.y
                if #fixtures == 1 then bounds.radius = shape.radius end
                bounds.left, bounds.right = math.min(bounds.left, x - shape.radius), math.max(bounds.right, x + shape.radius)
                bounds.bottom, bounds.top = math.min(bounds.bottom, y - shape.radius), math.max(bounds.top, y + shape.radius)
            end
        end
    end
    if bounds.left < bounds.right and bounds.bottom < bounds.top then
        self._patrol_body = bounds
        return bounds
    end
end

local function is_face_hit(hit, axis, dir, kind)
    return Surface.classify_collision(hit) == kind and hit.normal and hit.normal[axis] * dir < 0
end

local function face_hit(from, to, axis, dir, kind)
    local nearest
    for _, candidate in ipairs(physics.raycast(from, to, Surface.RAYCAST.TERRAIN, ALL_HITS) or {}) do
        if is_face_hit(candidate, axis, dir, kind)
            and (not nearest or (candidate.position[axis] - nearest.position[axis]) * dir < 0)
            and static_terrain(candidate, true) then
            nearest = candidate
        end
    end
    return nearest
end

local function travel(self, axis, dir, distance, cross_offset)
    local body = body_bounds(self)
    if not body then return distance end
    local pos = self.pos
    local x_axis = axis == "x"
    local lo, hi = body.left, body.right
    local cross_lo, cross_hi = body.bottom, body.top
    if not x_axis then lo, hi, cross_lo, cross_hi = cross_lo, cross_hi, lo, hi end
    local center, edge = (lo + hi) / 2, dir > 0 and hi or lo
    local from, to = vmath.vector3(pos), vmath.vector3(pos)
    local cross_axis = x_axis and "y" or "x"
    local cross_origin = pos[cross_axis]
    if cross_offset then cross_origin = cross_origin + cross_offset end
    local kind = x_axis and Surface.KINDS.WALL or (dir > 0 and Surface.KINDS.CEILING or Surface.KINDS.GROUND)
    from[axis] = pos[axis] + center
    local hit_at
    -- Include an exact endpoint after rounding ray coordinates to binary32.
    local epsilon = math.max(1e-5, math.abs(pos[axis] + edge) * 2^-23)
    local cross_inset = math.min((cross_hi - cross_lo) / 2,
        math.max(1e-5, math.abs(cross_origin + cross_lo) * 2^-23,
            math.abs(cross_origin + cross_hi) * 2^-23))
    -- Sample near a box's ends since a low riser can touch only the feet.
    local cross_span = (cross_hi - cross_lo) / 2 - cross_inset
    if body.radius then cross_span = body.radius / 2 end
    for sample = -1, 1 do
        from[cross_axis] = cross_origin + (cross_lo + cross_hi) / 2
            + sample * cross_span
        to[cross_axis] = from[cross_axis]
        local face = edge
        if body.radius and sample ~= 0 then face = center + dir * math.sqrt(body.radius^2 - cross_span^2) end
        to[axis] = pos[axis] + face + dir * (distance + epsilon)
        local hit = face_hit(from, to, axis, dir, kind)
        if hit then
            local at = hit.position[axis]
            local allowed = math.max(0, (at - pos[axis] - face) * dir)
            if not hit_at or allowed <= distance then hit_at = at end
            distance = math.min(distance, allowed)
        end
    end
    return distance, hit_at
end

-- A movement owner may need to resolve its own axes before ground physics
-- (for example a launched hop or a swimmer with no ground pass).
function M.limit(self, axis, velocity, dt, cross_offset)
    if self._ignores_terrain or velocity == 0 or dt <= 0 then return velocity end
    local dir = velocity > 0 and 1 or -1
    local allowed, hit = travel(self, axis, dir, math.abs(velocity) * dt, cross_offset)
    if hit then return allowed * dir / dt, true end
    return velocity
end

function M.room_edge(self, axis, direction)
    local bounds = self._room_bounds
    if not bounds or direction == 0 or (axis == "y" and self._airborne) then return end
    if direction > 0 then return (axis == "x" and bounds.max_x or bounds.max_y) - M.ROOM_MARGIN end
    return (axis == "x" and bounds.min_x or bounds.min_y) + M.ROOM_MARGIN
end

function M.at_room_edge(self, axis, direction)
    local edge = M.room_edge(self, axis, direction)
    return edge ~= nil and (self.pos[axis] - edge) * direction >= 0
end

local function opposite_ledge(self, dt, speed)
    local vx, blocked = self.vel.x, self._ledge_blocked_dir
    self.vel.x = -speed
    Ledge.apply(self, dt)
    local stopped = self._ledge_blocked_dir ~= nil
    self.vel.x, self._ledge_blocked_dir = vx, blocked
    return stopped
end

local function ground_step(self, dt, observe_stop)
    if not observe_stop then return Ground.apply(self, dt) end
    local sweep_hit, floor_hit, floor_sampled
    local function observe(from, to, groups)
        local hit = physics.raycast(from, to, groups)
        if from.y == to.y and from.x ~= to.x then
            if Surface.is_wall_collision(hit) then sweep_hit = hit end
        elseif not floor_sampled then
            floor_hit, floor_sampled = hit, true
        end
        return hit
    end

    local ground = Ground.apply(self, dt, observe)
    if self.vel.x ~= 0 then return ground end
    return ground, static_terrain(sweep_hit or floor_hit, false)
end

local function climbable(self, dt, hit_x, dir)
    -- Ask the ground solver about the top of the riser. The leading edge of
    -- a body can reach a low step before the ordinary center probe sees it.
    local vx, vy = self.vel.x, self.vel.y
    local airborne, forced, fall_speed = self._airborne, self._forced_airborne, self._vy
    local ledge = self._ledge_blocked_dir
    local beyond = math.max(1e-5, math.abs(hit_x) * 2^-23)
    self.vel.x, self.vel.y = (hit_x - self.pos.x + dir * beyond) / dt, 0
    Ground.apply(self, dt)
    local accepted = self.vel.x ~= 0 and self.vel.y > 0 and not self._airborne
    self.vel.x, self.vel.y = vx, vy
    self._airborne, self._forced_airborne, self._vy = airborne, forced, fall_speed
    self._ledge_blocked_dir = ledge
    return accepted
end

function M.apply(self, dt, patrol_x, patrol_y, patrol_sway)
    local intended_x, intended_y = self.vel.x, self.vel.y
    local grounded_step = patrol_x and dt > 0 and not self._airborne
        and not self._forced_airborne and intended_y <= 0 and Ground.can_fall(self)
    local ground, ground_wall = ground_step(self, dt, grounded_step)
    if ground == nil then Ledge.apply(self, dt) end
    if dt <= 0 then
        -- A stopped proxy frame still runs patterns. Keep the wall decision
        -- pending and hold facing until the patrol can move again.
        if patrol_x and (self._patrol_wall_x or self._patrol_boxed_x) then self.vel.x = 0 end
        if patrol_y and self._patrol_wall_y then self.vel.y = 0 end
        if patrol_sway and self._patrol_boxed_x then self.vel.y = 0 end
        return ground
    end

    local boxed_x, boxed_y = self._patrol_boxed_x, self._patrol_boxed_y
    self._patrol_wall_x, self._patrol_wall_y = nil, nil
    self._patrol_boxed_x, self._patrol_boxed_y = nil, nil
    if self._ignores_terrain or self._airborne or self._surface_crawling then return ground end
    if patrol_x then
        local dir = intended_x > 0 and 1 or -1
        if self.vel.x == 0 then
            -- The ground pass only zeroes x for a sweep hit or a too-tall riser.
            if ground_wall then self._patrol_wall_x = dir end
            if self._ledge_blocked_dir and boxed_x then self._patrol_boxed_x = true end
        elseif not (grounded_step and self.vel.y > 0) then
            -- Preserve a step-up already accepted by the ground pass.
            local distance = math.abs(intended_x) * dt
            local allowed, hit_x = travel(self, "x", dir, distance)
            if hit_x and not (grounded_step and climbable(self, dt, hit_x, dir)) then
                self._patrol_wall_x = dir
                local _, opposite_x = travel(self, "x", -dir, distance)
                self._patrol_boxed_x = opposite_x ~= nil and not (grounded_step and climbable(self, dt, opposite_x, -dir))
                    or (ground == nil and opposite_ledge(self, dt, intended_x))
                if self._patrol_boxed_x or boxed_x then
                    allowed = 0
                end
                self.vel.x = allowed * dir / dt
            end
        end
    end
    if patrol_sway and self.vel.x == 0 and (self._patrol_boxed_x or boxed_x) then self.vel.y = 0 end
    if patrol_y and self.vel.y == intended_y then
        local dir = intended_y > 0 and 1 or -1
        local distance = math.abs(intended_y) * dt
        local allowed, hit_y = travel(self, "y", dir, distance)
        if hit_y then
            self._patrol_wall_y = dir
            local _, opposite_y = travel(self, "y", -dir, distance)
            self._patrol_boxed_y = opposite_y ~= nil
            if self._patrol_boxed_y or boxed_y then allowed = 0 end
            self.vel.y = allowed * dir / dt
        end
    end
    return ground
end

return M
