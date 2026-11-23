-- Terrain motion for opted-in bosses. Bosses are unparented, like enemies.
local Terrain = require "mvtk.enemies.enemy_ground_physics"
local Surface = require "mvtk.core.surface_classifier"
local Confinement = require "mvtk.bosses.boss_confinement"
local Clock = require "mvtk.bosses.boss_clock"
local Tiles = require "developer.config.tile_settings"
local Defaults = require("mvtk.core.util").require_config("developer.config.boss_defaults", {})
local M = {}

local PLATFORM = Surface.GROUPS.PLATFORM
local ALL_HITS = {all = true}
local MAX_RAYS = 3
local MIN_PROBE = 0.001
local AIR_PROFILES = {hover = true, flying_patrol = true, wall_crawl = true}

function M.active(boss)
    local state = boss._locomotion
    return state and state.active
end

function M.enabled(boss)
    local state = boss._locomotion
    return state and not state.disabled
end

function M.gravity()
    local multiplier = tonumber(Defaults.ground_gravity_multiplier) or 1
    return Terrain.gravity() * (multiplier > 0 and multiplier or 1)
end

function M.can_probe(boss, count)
    return boss._locomotion.rays + count <= MAX_RAYS
end

local function ray(boss, x1, y1, x2, y2, z)
    local state = boss._locomotion
    if state.rays >= MAX_RAYS or x1 == x2 and y1 == y2 then return end
    state.rays = state.rays + 1
    return Terrain.cast(x1, y1, x2, y2, z, nil, ALL_HITS)
end

local function nearest_hit(hits, classify, platform_ceiling)
    -- Include all hits so a one-way surface or an unrelated normal cannot
    -- hide a usable floor or a solid ceiling behind it.
    local nearest
    for _, hit in ipairs(hits or {}) do
        if classify(hit) and (hit.group ~= PLATFORM or platform_ceiling and hit.position.y <= platform_ceiling)
            and (not nearest or hit.fraction < nearest.fraction) then
            nearest = hit
        end
    end
    return nearest
end

local function cast(boss, x1, y1, x2, y2, z, classify, platform_ceiling)
    return nearest_hit(ray(boss, x1, y1, x2, y2, z), classify, platform_ceiling)
end

local function rect_for(boss)
    if not boss._confine_rect then
        boss._confine_rect, boss._confine_kind = Confinement.resolve_rect(boss.config)
    end
    return boss._confine_rect
end

local function put(boss, pos, x, y)
    if pos.x ~= x or pos.y ~= y then
        go.set_position(vmath.vector3(x, y, pos.z), boss.self_url)
    end
end

local function land(boss, x, y)
    local state = boss._locomotion
    state.on_ground, state.vy = true, 0
    state.safe_x, state.safe_y = x, y
    state.air_vx, state.stop_x, state.jump_stop_x = 0, nil, nil
    if state.jumping then
        state.jumping = false
        state.jump_recovery = math.max(0, tonumber(Defaults.jump_recovery) or 0.4)
    end
end

local function fits_on_floor(boss, floor_y)
    local rect = rect_for(boss)
    local floor_min = Confinement.floor_min(boss)
    return not rect or floor_y >= (floor_min or rect.min_y) - MIN_PROBE
        and floor_y + boss._locomotion.feet_offset + boss._body.half_height <= rect.max_y + MIN_PROBE
end

local function depth()
    local _, _, _, _, tile_h, enemy_depth = Terrain.terrain_limits()
    return math.max(0, tonumber(Defaults.spawn_settle_depth_tiles) or enemy_depth) * tile_h
end

local function floor_hit(boss, x, top, bottom, z, decision)
    if top <= bottom then return end
    if decision then
        local hits = Terrain.cast(x, top, x, bottom, z, nil, ALL_HITS)
        return nearest_hit(hits, Surface.is_ground_collision, top)
    end
    return cast(boss, x, top, x, bottom, z, Surface.is_ground_collision, top)
end

local function probe_floor(boss, x, top, bottom, z, decision)
    local rect = rect_for(boss)
    if rect then
        top = math.min(top, rect.max_y - MIN_PROBE)
        bottom = math.max(bottom, (Confinement.floor_min(boss) or rect.min_y) - MIN_PROBE)
    end
    local hit = floor_hit(boss, x, top, bottom, z, decision)
    if hit and fits_on_floor(boss, hit.position.y) then
        return hit.position.y + boss._locomotion.feet_offset
    end
end

local function solid_count(hits)
    local count = 0
    for _, hit in ipairs(hits or {}) do
        if hit.group ~= PLATFORM then count = count + 1 end
    end
    return count
end

local function spawn_floor(boss, pos)
    local limit = pos.y - depth()
    local bottom = Confinement.ray_bottom(boss.config, pos.x, limit) - MIN_PROBE
    local down = ray(boss, pos.x, pos.y, pos.x, bottom, pos.z)
    -- Box2D skips shapes containing a ray's start. Each crossed solid
    -- supplies an entry in both directions. A reverse-only entry means
    -- the origin is inside a solid when the lower endpoint is outside.
    local up = ray(boss, pos.x, bottom, pos.x, pos.y, pos.z)
    if solid_count(up) > solid_count(down) then return nil, "has its origin inside solid terrain" end
    local floor = nearest_hit(down, Surface.is_ground_collision, pos.y)
    if floor and floor.position.y >= limit - MIN_PROBE then return floor.position.y end
    return nil, "has no floor within ground motion settle depth"
end

local function notice(boss, reason)
    print(string.format("[BOSS] WARNING: %s (%s) %s",
        boss.config.name or "Boss", tostring(boss.boss_id or boss.id), reason))
end

function M.settle(boss)
    if not M.active(boss) then return end
    local pos = go.get_position(boss.self_url)
    local state = boss._locomotion
    local spawn = state.spawn_pos or pos
    local floor, reason = spawn_floor(boss, spawn)
    if not floor then
        state.active, state.disabled = false, true
        notice(boss, reason)
        return false
    end
    local rect = rect_for(boss)
    local room = boss._confine_kind == "room" and rect or Confinement.room_rect(boss.config)
    state.room_min_y = room and room.min_y
    local explicit = state.feet_offset or tonumber(boss.config.feet_offset)
    if state.feet_offset == nil and (not explicit or explicit <= 0) then
        explicit = tonumber(Defaults.feet_offset)
    end
    local y = spawn.y
    if state.feet_offset ~= nil or explicit and explicit > 0 and explicit < math.huge then
        state.feet_offset, y = explicit, floor + explicit
    else
        state.feet_offset = spawn.y - floor
        if state.feet_offset > 2 * boss._body.half_height then
            notice(boss, string.format("measured a feet offset of %g px. Set feet_offset if it should stand on the floor",
                state.feet_offset))
        end
    end
    if pos.x == spawn.x and pos.y == spawn.y then
        put(boss, pos, pos.x, y)
        land(boss, pos.x, y)
    else
        -- An airborne first phase ignores terrain. If a later phase starts
        -- ground motion, recover from the authored spawn only if it falls
        -- out, and begin falling at its current transform.
        state.safe_x, state.safe_y = spawn.x, y
    end
    state.spawn_pos = nil
    return true
end

function M.set_profile(boss, profile)
    if boss.config.ground_motion ~= true or not boss._body then return end
    if not boss._locomotion then
        boss._locomotion = {vx = 0, vy = 0, rays = 0, on_ground = false, spawn_pos = go.get_position(boss.self_url)}
    end
    local state = boss._locomotion
    if state.disabled then return end
    local active = not AIR_PROFILES[profile]
    if active ~= state.active then
        state.active = active
        state.on_ground, state.vy, state.air_vx = false, 0, 0
        state.step_y, state.jump_plan = nil, nil
        if active and state.feet_offset == nil then M.settle(boss) end
    end
end

function M.begin_frame(boss, dt)
    local state = boss._locomotion
    if not state then return end
    state.rays, state.vx, state.owned_step = 0, 0, false
    state.leash_left, state.leash_right, state.stop_x = nil, nil, nil
    state.landing_target = nil
    state.attack_floor = nil
    if state.jump_recovery then
        state.jump_recovery = state.jump_recovery - dt
        if Clock.reached(Clock.window_lead(dt), state.jump_recovery) then state.jump_recovery = nil end
    end
end

function M.walk(boss, vx)
    local state = boss._locomotion
    if state and state.active then state.vx = vx end
end

function M.jump(boss, vx, vy)
    local state = boss._locomotion
    if not M.is_grounded(boss) then return false end
    state.on_ground, state.air_vx, state.vy, state.jumping = false, vx, vy, true
    state.jump_plan = nil
    return true
end

function M.is_grounded(boss)
    return M.active(boss) and boss._locomotion.on_ground == true
end

function M.feet_y(boss, pos)
    local state = boss._locomotion
    if state and state.feet_offset and not state.disabled then return pos.y - state.feet_offset end
end

function M.attack_floor(boss, pos, decision)
    local state = boss._locomotion
    local x = pos.x
    local bottom = pos.y - depth()
    if bottom >= pos.y then return nil, true end
    if not state or state.disabled then
        local hit = floor_hit(boss, x, pos.y, bottom, pos.z, true)
        return hit and hit.position.y, true
    end
    if state.on_ground and x == state.safe_x and pos.y == state.safe_y then
        return M.feet_y(boss, pos), true
    end
    local sample = state.attack_floor
    if sample and x == sample.x and pos.y == sample.y then return sample.floor, true end
    if not decision and state.rays >= MAX_RAYS then return nil, false end
    local hit = floor_hit(boss, x, pos.y, bottom, pos.z, decision)
    local floor_y = hit and hit.position.y
    state.attack_floor = {x = x, y = pos.y, floor = floor_y}
    return floor_y, true
end

-- Candidate support for a leap or blink. Callers keep their old transform
-- when a destination has no reachable floor.
function M.landing(boss, target, rise, decision)
    local state = boss._locomotion
    if not M.active(boss) then return nil, true end
    if state.landing_target and state.landing_target.x == target.x
        and state.landing_target.y == target.y and state.landing_rise == rise then
        return state.landing_y, true
    end
    if not decision and not M.can_probe(boss, 1) then return nil, false end
    local top = target.y + rise
    local y = probe_floor(boss, target.x, top, target.y - state.feet_offset - depth(), target.z, decision)
    state.landing_target, state.landing_rise, state.landing_y = target, rise, y
    return y, true
end

function M.land_at(boss, target)
    local pos = go.get_position(boss.self_url)
    put(boss, pos, target.x, target.y)
    land(boss, target.x, target.y)
    local state = boss._locomotion
    state.owned_step, state.was_owned = true, false
    state.step_y, state.jump_plan = nil, nil
end

local function clip_wall(boss, pos, next_x, y, skin)
    if next_x == pos.x then return next_x end
    local direction = next_x > pos.x and 1 or -1
    local edge = direction * boss._body.half_width
    local wall = cast(boss, pos.x + edge - direction * skin, y, next_x + edge, y,
        pos.z, Surface.is_wall_collision)
    if not wall then return next_x end
    local stop = wall.position.x - edge - direction * skin
    return direction > 0 and math.max(pos.x, stop) or math.min(pos.x, stop), true
end

local function step_support(boss, pos, x, feet, skin, up, down)
    return cast(boss, x, feet + up + skin, x, feet - down, pos.z,
        Surface.is_ground_collision, feet + MIN_PROBE)
end

local function can_stand(boss, hit, feet, up)
    if not hit then return false end
    local y = hit.position.y
    return y <= feet + up + MIN_PROBE and fits_on_floor(boss, y)
end

function M.clear_jump_plan(boss)
    boss._locomotion.jump_plan = nil
end

-- Check the nominal landing before launching. If a stop-mode landing lacks
-- support, find the first gap from the grounded side, then refine its edge.
-- Leave one ray each frame for stationary support, then launch on a fresh frame.
function M.plan_jump(boss, pos, target_x, vx, vy)
    local state = boss._locomotion
    local direction = vx < 0 and -1 or 1
    local min_travel = math.max(MIN_PROBE, tonumber(Defaults.jump_min_travel) or 4)
    local distance = math.min((target_x - pos.x) * direction, math.abs(vx) * 2 * vy / M.gravity())
    if distance < min_travel then return M.clear_jump_plan(boss) end
    local plan = state.jump_plan
    if plan and (plan.x ~= pos.x or plan.y ~= pos.y or plan.vx ~= vx or plan.vy ~= vy
        or distance < plan.distance - MIN_PROBE) then
        plan = nil
        state.jump_plan = nil
    end
    if plan and plan.landing_x then
        M.clear_jump_plan(boss)
        if (plan.landing_x - pos.x) * direction >= min_travel then return plan.landing_x end
        return
    end

    local skin, up, down = Terrain.terrain_limits()
    skin = math.max(MIN_PROBE, skin)
    local feet = pos.y - state.feet_offset
    if not plan then
        if not M.can_probe(boss, 2) then return end
        local hw, hh, offset = Confinement.half_extents(boss.config, boss)
        local nominal = Confinement.clamp(pos.x + direction * distance, pos.y, rect_for(boss), hw, hh, offset)
        local edge, wall = clip_wall(boss, pos, nominal, feet + up + skin, skin)
        if (edge - pos.x) * direction < min_travel then return end
        plan = {x = pos.x, y = pos.y, vx = vx, vy = vy, distance = distance,
            high = (edge - pos.x) * direction, check_nominal = true}
        state.jump_plan = plan
        if Defaults.ledge_behavior == "fall" then
            plan.landing_x = wall and edge or target_x
            return
        end
    end

    local function supported(x)
        if not plan.center_checked then
            if not M.can_probe(boss, 2) then return end
            local center = step_support(boss, pos, x, feet, skin, up, down)
            if not can_stand(boss, center, feet, up) then return false end
            plan.center_checked = true
        end
        if not M.can_probe(boss, 2) then return end
        plan.center_checked = nil
        local front = step_support(boss, pos, x + direction * boss._body.half_width, feet, skin, up, down)
        return can_stand(boss, front, feet, up)
    end

    if plan.check_nominal then
        local x = pos.x + direction * plan.high
        local valid = supported(x)
        if valid == nil then return end
        plan.check_nominal = nil
        if valid then
            plan.landing_x = x
            return
        end
    end
    if plan.low == nil then
        local valid = supported(pos.x)
        if valid == nil then return end
        if not valid then return M.clear_jump_plan(boss) end
        plan.low = 0
    end
    -- A farther platform can support both rays even after the leading edge
    -- has crossed a pit. Sample toward the rejected destination before
    -- bisecting so the search does not assume support extends over that gap.
    local stride = math.max(skin, (tonumber(Tiles.width or Tiles.tile_width or Tiles.size) or 64) * 0.5)
    while not plan.refining do
        local next_probe = plan.low + stride
        if next_probe >= plan.high then break end
        local valid = supported(pos.x + direction * next_probe)
        if valid == nil then return end
        if valid then
            plan.low = next_probe
        else
            plan.high = next_probe
            break
        end
    end
    plan.refining = true
    while plan.high - plan.low > skin do
        local middle = (plan.low + plan.high) * 0.5
        local valid = supported(pos.x + direction * middle)
        if valid == nil then return end
        if valid then plan.low = middle
        else plan.high = middle end
    end
    plan.landing_x = pos.x + direction * plan.low
end

-- Rising uses one head sweep. Filtering the platform group allows a jump
-- through a one-way platform even if a solid ceiling is directly above it.
function M.clip_ceiling(boss, pos, next_x, next_y)
    if next_y <= pos.y then return next_y end
    local half_height = boss._body.half_height
    local skin = math.max(MIN_PROBE, (Terrain.terrain_limits()))
    local hit = cast(boss, next_x, pos.y + half_height - skin, next_x,
        next_y + half_height, pos.z, Surface.is_ceiling_collision)
    local top = hit and hit.position.y
    local rect = rect_for(boss)
    if rect then top = math.min(top or rect.max_y, rect.max_y) end
    if top and next_y + half_height >= top then
        return math.max(pos.y, top - half_height), true
    end
    return next_y
end

function M.sweep_floor(boss, pos, next_x, next_y)
    if next_y > pos.y then return end
    local offset = boss._locomotion.feet_offset
    local feet = pos.y - offset
    local skin = math.max(MIN_PROBE, (Terrain.terrain_limits()))
    local hit = cast(boss, next_x, feet + skin, next_x, next_y - offset, pos.z,
        Surface.is_ground_collision, feet + skin)
    if hit and fits_on_floor(boss, hit.position.y) then
        return hit.position.y + offset
    end
end

local function grounded_step(boss, pos, next_x, skin, up, down)
    local state = boss._locomotion
    local feet = pos.y - state.feet_offset
    local probe_top = feet + up + skin
    next_x = clip_wall(boss, pos, next_x, probe_top, skin)
    local function support(x)
        return step_support(boss, pos, x, feet, skin, up, down)
    end
    local function supported(hit)
        return can_stand(boss, hit, feet, up)
    end
    local hit = support(next_x)
    local stop_at_ledge = Defaults.ledge_behavior ~= "fall" and next_x ~= pos.x
    local direction
    if hit and not supported(hit) or not hit and stop_at_ledge then
        next_x, hit = pos.x, support(pos.x)
    elseif hit and next_x ~= pos.x then
        direction = next_x > pos.x and 1 or -1
        local front_x = next_x + direction * boss._body.half_width
        local front = support(front_x)
        if supported(front) then
            local front_y = front.position.y
            if front_y > hit.position.y and (not state.step_y or front_y > state.step_y) then
                state.step_x, state.step_y, state.step_direction = front_x, front_y, direction
            end
        elseif stop_at_ledge then
            return pos.x, pos.y
        end
    end
    if supported(hit) then
        local floor = hit.position.y
        if state.step_y then
            -- Keep the clearance gained at the leading edge until the
            -- origin crosses the step. A narrow step can leave the
            -- leading edge before it reaches the centre support ray.
            if floor >= state.step_y or direction and direction ~= state.step_direction
                or (next_x - state.step_x) * state.step_direction > MIN_PROBE then
                state.step_y = nil
            else
                floor = state.step_y
            end
        end
        local y = floor + state.feet_offset
        land(boss, next_x, y)
        return next_x, y
    end
    state.step_y, state.jump_plan = nil, nil
    state.on_ground, state.vy, state.air_vx = false, 0, state.vx
    return next_x
end

local function advance(boss, dt)
    local state, pos = boss._locomotion, go.get_position(boss.self_url)
    local rect = rect_for(boss)
    local hw, hh, feet = Confinement.half_extents(boss.config, boss)
    local vx = state.on_ground and state.vx or state.air_vx or 0
    if state.void_direction then
        if vx * state.void_direction > 0 then vx = 0
        elseif vx * state.void_direction < 0 then state.void_direction = nil end
    end
    local next_x = Confinement.clamp(pos.x + vx * dt, pos.y, rect, hw, hh, feet)
    if state.leash_left and not state.owned_step then
        next_x = math.max(math.min(state.leash_left, pos.x), math.min(math.max(state.leash_right, pos.x), next_x))
    end
    if state.stop_x and vx ~= 0 then
        next_x = vx < 0 and math.max(state.stop_x, next_x) or math.min(state.stop_x, next_x)
    end
    local skin, up, down, max_fall = Terrain.terrain_limits()
    skin = math.max(MIN_PROBE, skin)
    if state.on_ground then
        -- Spawn or another attack may already have cast this frame. Wait
        -- for enough rays to check the entire grounded step.
        local required = next_x == pos.x and 1 or 3
        if not M.can_probe(boss, required) then return false end
        local grounded_x, y = grounded_step(boss, pos, next_x, skin, up, down)
        if y then return put(boss, pos, grounded_x, y) end
        -- The ledge step already spent its probes. Start falling next frame.
        return put(boss, pos, grounded_x, pos.y)
    end
    local gravity = M.gravity()
    local vy = state.vy
    local next_vy = math.max(vy - gravity * dt, -max_fall)
    local required = (next_x ~= pos.x and 1 or 0) + (vy > 0 and 1 or 0) + (next_vy <= 0 and 1 or 0)
    if not M.can_probe(boss, required) then return false end
    local blocked
    next_x, blocked = clip_wall(boss, pos, next_x, pos.y, skin)
    if blocked or state.stop_x and next_x == state.stop_x then state.air_vx = 0 end

    state.vy = next_vy
    local travel = (vy + state.vy) * dt * 0.5
    -- Sample the exact apex even when a frame straddles it.
    local rise = vy > 0 and math.min(dt, vy / gravity)
    if rise then
        local apex = pos.y + (vy - gravity * rise * 0.5) * rise
        local ceiling_y, ceiling = M.clip_ceiling(boss, pos, next_x, apex)
        if ceiling then
            state.vy = 0
            return put(boss, pos, next_x, ceiling_y)
        end
    end
    local next_y = pos.y + travel
    if state.vy <= 0 then
        local sweep_start = pos
        if rise then
            sweep_start = vmath.vector3(pos.x, pos.y + vy * vy / (2 * gravity), pos.z)
        end
        local floor_y = M.sweep_floor(boss, sweep_start, next_x, next_y)
        if floor_y then
            land(boss, next_x, floor_y)
            return put(boss, pos, next_x, floor_y)
        end
    end
    local safe_y = state.safe_y or pos.y
    local room_min = Confinement.floor_min(boss)
    local min_y = room_min and room_min + feet or rect and rect.min_y + feet or safe_y - depth()
    if next_y < min_y then
        if room_min and state.safe_y then
            -- Emergency recovery only when the next step would leave the room.
            -- Wait for a direction change before walking into that drop again.
            local dx = next_x - state.safe_x
            state.void_direction = dx ~= 0 and (dx < 0 and -1 or 1) or nil
            land(boss, state.safe_x, state.safe_y)
            return put(boss, pos, state.safe_x, state.safe_y)
        end
        state.vy, state.air_vx = 0, 0
        next_y = min_y
    end
    put(boss, pos, next_x, next_y)
end

-- Walking reposition explicitly advances terrain motion under attack
-- ownership. Automatic motion stays suppressed on its completion frame.
function M.walk_owned(boss, vx, dt, target_x, time_left)
    local state = boss._locomotion
    state.vx, state.owned_step = vx, true
    state.stop_x = target_x
    if not state.on_ground then state.air_vx = vx end
    -- The attack owns this time until a complete terrain sweep can pay it,
    -- or until the move releases ownership.
    local owed = math.min((state.owned_time or 0) + dt, time_left or math.huge)
    if owed <= 0 then return 0 end
    if advance(boss, owed) == false then
        state.owned_time = owed
        return 0
    end
    state.owned_time = nil
    return owed
end

function M.stop_owned_walk(boss)
    local state = boss._locomotion
    state.vx, state.air_vx = 0, 0
    state.owned_time = nil
end

function M.update(boss, dt)
    if not M.active(boss) or dt <= 0 then return end
    local state = boss._locomotion
    if state.owned_step then return end
    local move = boss._active_charge
    if move and not (move.grounded_charge and move.complete) then
        state.was_owned = true
        return
    end
    if state.was_owned then
        state.on_ground, state.vy, state.air_vx = false, 0, 0
        state.was_owned, state.step_y, state.jump_plan = false, nil, nil
    end
    advance(boss, dt)
end

return M
