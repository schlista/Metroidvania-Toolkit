-- Kinematic grappling for the existing player movement/collision pipeline.
-- Tiled surfaces are static, baked room objects; this module creates no objects.
local Timers = require "mvtk.player.timers"
local BonePhysics = require "mvtk.player.bone_physics"
local M = {}

local function setting(actions, config, key, fallback)
    local value = config and config[key]
    if value == nil then value = actions and actions[key] end
    if value == nil then return fallback end
    return value
end

-- Shared with hook travel: preserve physical release edges in the input copy.
function M.effective_stay_hooked(actions, config)
    local HoldToggles = require "mvtk.player.hold_toggles"
    return setting(actions, config, "stay_hooked", false) or HoldToggles.enabled("grapple")
end

function M.direction(input, facing, actions, config)
    input = input or {}
    local deadzone = setting(actions, config, "aim_deadzone", 0.3)
    local x, y = input.move_x or 0, input.move_y or 0
    if math.abs(x) < deadzone then x = 0 end
    if math.abs(y) < deadzone then y = 0 end
    y = math.max(0, y)
    if x == 0 and y == 0 and setting(actions, config, "default_aim", "up") == "forward" then
        x = facing and facing ~= 0 and facing or 1
    end
    if x == 0 then return 0, 1 end
    local angle = math.rad(setting(actions, config, "diagonal_angle_deg", 45))
    return (x > 0 and 1 or -1) * math.cos(angle), math.sin(angle)
end

-- Tagged strips may overlap the terrain they mark, but cannot catch through it.
function M.pick_target(hits, ray_length, opts)
    if ray_length <= 0 then return nil end
    table.sort(hits, function(a, b) return a.fraction < b.fraction end)
    local first = hits[1]
    if not first then return nil end
    local limit = first.fraction + (opts.tolerance_px or 0) / ray_length
    for _, hit in ipairs(hits) do
        if hit.fraction > limit then break end
        if hit.group == opts.grapple_group and hit.normal.y < 0.5 then return hit, "surface" end
    end
    if opts.targets == "ceilings" and opts.latch[first.group] then
        if first.normal.y <= -opts.ceiling_normal_min then return first, "ceiling" end
        if opts.allow_walls and math.abs(first.normal.x) >= opts.wall_normal_min then return first, "wall" end
    end
    return nil
end

function M.clear(self)
    if self._vertical_grid then self._vertical_grid.release_mult = nil end
    self._grapple_hook = nil
    self._grapple_active = false
    self._grapple_hanging = false
    self._grapple_anchor = nil
    self._grapple_target = nil
    self._grapple_rope_length = nil
    self._grapple_room_id = nil
    self._grapple_launch_length = nil
    self._grapple_swing_step, self._grapple_swing_path, self._grapple_contact_elapsed = nil, nil, nil
    self._grapple_step_vx, self._grapple_step_vy = nil, nil
    self._grapple_carry_t = 0
    self._grapple_flight = false
    self._grapple_recast_t = 0
    self._grapple_elapsed = 0
    self._grapple_pull_ready, self._grapple_pull_variable = nil, nil
    self._grapple_timeout_config, self._grapple_timeout_motion = nil, nil
    self._grapple_timeout_after_contact = nil
    Timers.clear_window(self, "_grapple_timeout")
    self._grapple_just_released = false
    self._grapple_release_hold = nil
    self._control_locked = false
end

local function release_velocity(self, input, actions, config, kind)
    if kind == "let_go" then
        local momentum = setting(actions, config, "release_momentum_mult", 1)
        self.vx, self.vy = (self.vx or 0) * momentum, (self.vy or 0) * momentum
    end
    local boost = kind == "let_go" and setting(actions, config, "release_boost_px", 0) or 0
    if boost ~= 0 then
        local x = input and input.move_x or 0
        local vx = self.vx or 0
        local dir
        if vx ~= 0 and math.abs(vx) >= 0.25 * setting(actions, config, "swing_max_speed", 1200) then
            dir = vx > 0 and 1 or -1
        else
            dir = x ~= 0 and (x > 0 and 1 or -1) or (self.facing and self.facing ~= 0 and self.facing or 1)
        end
        self.vx = (self.vx or 0) + dir * boost
    end
    if kind == "let_go" then
        self.vy = (self.vy or 0) + setting(actions, config, "release_up_boost_px", 0)
    end
end

function M.release(self, input, actions, config, kind, velocity_prepared)
    if not self._grapple_active then return false end
    self._vertical_grid = nil
    self._jump_cut_pending = nil
    kind = kind or "let_go"
    M.clear(self)
    self._grapple_release_kind = kind
    if kind ~= "impact" and kind ~= "hang_jump" then
        -- The rising arc after letting go is swing momentum, not a jump: the
        -- early-jump-release gravity must not cut it short (cleared at apex).
        self._grapple_flight = true
        Timers.start_window(self, "_grapple_carry_t", setting(actions, config, "release_carry_time", 0.35))
        Timers.extend_window(self, "_climb_reattach_lock_t", setting(actions, config, "ladder_grab_delay_s", 0.25))
    end
    if not velocity_prepared then release_velocity(self, input, actions, config, kind) end
    -- Movement for the release frame consumes these exact velocities before
    -- ordinary air steering resumes. Jump release does not spend an air jump.
    self._grapple_just_released = kind ~= "impact"
    self._grapple_release_hold = self._grapple_just_released and Timers.REFERENCE_STEP or nil
    return true
end

function M.release_on_jump(actions, config)
    return setting(actions, config, "release_on_jump", true)
end

function M.attach(self, position, hit, actions, config, grounded)
    require("mvtk.player.hold_toggles").sync(self, "grapple")
    local normal = hit.normal or { x = 0, y = 0 }
    local half_w = self.collider_half_width or self._cfg.collider_half_width or 0
    local half_h = self.collider_half_height or self._cfg.collider_half_height or 0
    local clearance = math.abs(normal.x) * half_w + math.abs(normal.y) * half_h
        + setting(actions, config, "surface_clearance_px", 4)
    local dx, dy = position.x - hit.position.x, position.y - hit.position.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local min_length = math.max(clearance, setting(actions, config, "min_rope_length_px", clearance))
    local desired_length = setting(actions, config, "rope_length_px", 0)
    local launch_length
    if grounded then
        local gap = hit.position.y - position.y - setting(actions, config, "ground_clearance_px", 16)
        if gap < min_length then return false end
        launch_length = math.min(distance, gap)
    end
    self._grapple_anchor = vmath.vector3(hit.position)
    self._grapple_target = vmath.vector3(hit.position.x + normal.x * clearance,
        hit.position.y + normal.y * clearance, position.z)
    self._grapple_rope_length = grounded and distance or
        (desired_length > 0 and math.max(min_length, desired_length) or math.max(min_length, distance))
    self._grapple_launch_length = launch_length
    self._grapple_swing_step, self._grapple_swing_path, self._grapple_contact_elapsed = nil, nil, nil
    self._grapple_carry_t = 0
    self._grapple_flight = false
    self._grapple_recast_t = 0
    self._grapple_release_kind = nil
    self._grapple_min_length = min_length
    self._grapple_elapsed = 0
    self._grapple_pull_ready, self._grapple_pull_variable = nil, nil
    self._grapple_timeout_config, self._grapple_timeout_motion = nil, nil
    Timers.clear_window(self, "_grapple_timeout")
    self._grapple_just_released = false
    self._grapple_release_hold = nil
    self._grapple_active = true
    self._jump_cut_pending = nil
    self._grapple_hanging = false
    self.grounded = false
    Timers.clear_window(self, "_coyote_t")
    Timers.clear_window(self, "_jump_buffer_t")
    self._control_locked = true
    self._on_wall, self._wall_sliding = false, false
    self._dash_t, self._slide_t, self._backdash_t = 0, 0, 0
    self._ledge_hanging, self._ledge_climbing, self._ledge_kinematic = false, false, false
    Timers.clear_window(self, "_ledge_climb_window")
    return true
end

function M.rope_state(hit, ray_len, anchor_dist, tol)
    if not hit then return "lost" end
    if hit.fraction * ray_len < anchor_dist - tol then return "lost" end
    return "ok"
end

local function impact_release(collision, vx, vy, elapsed, launch_length, actions, config)
    if not setting(actions, config, "release_on_impact", true) or
        elapsed + 1e-12 < Timers.reference_duration(setting(actions, config, "attach_grace_s", 0.12)) or
        launch_length then return false end
    local wall = collision.wall_contact or 0
    local speed = setting(actions, config, "impact_release_speed", 150)
    return collision.grounded or (wall ~= 0 and vx * wall > 0 and math.abs(vx) >= speed) or
        (collision.ceiling_contact and vy >= speed)
end

function M.on_contacts(self, collision, actions, config)
    local elapsed = self._grapple_contact_elapsed or self._grapple_elapsed or 0
    local timeout_input = self._grapple_timeout_after_contact
    self._grapple_contact_elapsed = nil
    self._grapple_timeout_after_contact = nil
    if collision and (collision.grounded or (collision.wall_contact or 0) ~= 0) then
        self._grapple_carry_t = 0
    end
    if self._grapple_active and not self._grapple_timeout_motion and collision and
        impact_release(collision, self._grapple_step_vx or 0, self._grapple_step_vy or 0, elapsed,
            self._grapple_launch_length, actions, config) then
        return M.release(self, nil, actions, config, "impact")
    end
    if timeout_input then return M.release(self, timeout_input, actions, config, "let_go") end
    return false
end

-- Returns an optional rate override; nil leaves normal acceleration intact.
function M.carry_steering(self, target_vx, accelerating, decel, actions, config, carrying)
    if carrying == nil then carrying = (self._grapple_carry_t or 0) > 0 end
    if not carrying or self.grounded or self._on_wall then return target_vx end
    local vx = self.vx or 0
    if target_vx == 0 or (target_vx * vx > 0 and math.abs(target_vx) <= math.abs(vx)) then
        return vx, 0
    end
    if target_vx * vx < 0 then
        return target_vx, decel * setting(actions, config, "release_carry_brake", 0.35)
    end
    return target_vx
end

-- Carry float replaces ordinary ascent/descent gravity rules. Fast-fall is
-- applied afterward by player_state, so Down still gives deliberate control.
function M.release_gravity(self, g_base, actions, config, carry_remaining)
    if self._grapple_active or self.grounded or self._on_wall
        or (carry_remaining or self._grapple_carry_t or 0) <= 0 then return nil end
    local kind = self._grapple_release_kind
    if kind ~= "let_go" and kind ~= "room" and kind ~= "lost" then return nil end
    return g_base * setting(actions, config, "release_gravity_mult", 0.6)
end

-- Returns velocity whose next integration step stays within a taut rope. The
-- rope can go slack, so jumping/moving toward the anchor remains natural.
function M.swing_velocity(position, anchor, length, vx, vy, dt, input_x, gravity, acceleration, drag, max_speed, speed_limit, pump)
    if dt <= 0 then return vx, vy end
    local speed = math.sqrt(vx * vx + vy * vy)
    local braking = pump and pump.with_swing_only and input_x * vx < 0
        and math.abs(vx) >= pump.start_speed
    if braking then
        local amount = math.max(0, pump.counter_brake) * acceleration * math.abs(input_x) * dt
        vx = (vx > 0 and 1 or -1) * math.max(0, math.abs(vx) - amount)
    elseif max_speed > 0 and speed < max_speed then
        local pumped = vx + input_x * acceleration * dt
        -- Only the input contribution is limited. Preserve vertical energy.
        local horizontal_cap = math.sqrt(math.max(0, max_speed * max_speed - vy * vy))
        vx = math.max(-horizontal_cap, math.min(horizontal_cap, pumped))
    end
    vy = vy - math.abs(gravity) * dt
    local damping = math.exp(-math.max(0, drag) * dt)
    vx, vy = vx * damping, vy * damping
    speed_limit = speed_limit and speed_limit > 0 and speed_limit or 3 * max_speed
    speed = math.sqrt(vx * vx + vy * vy)
    if speed_limit > 0 and speed > speed_limit then
        vx, vy = vx * speed_limit / speed, vy * speed_limit / speed
    end
    local dx = position.x + vx * dt - anchor.x
    local dy = position.y + vy * dt - anchor.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > length and distance > 0 then
        local next_x = anchor.x + dx * length / distance
        local next_y = anchor.y + dy * length / distance
        vx, vy = (next_x - position.x) / dt, (next_y - position.y) / dt
    end
    speed = math.sqrt(vx * vx + vy * vy)
    if speed_limit > 0 and speed > speed_limit then
        vx, vy = vx * speed_limit / speed, vy * speed_limit / speed
    end
    return vx, vy
end

local function pull_arrive(self, actions, config)
    self.vx, self.vy = 0, 0
    if setting(actions, config, "pull_hang", true) then self._grapple_hanging = true
    else M.clear(self) end
end

local function pull_step(self, position, dt, actions, config)
    local target = self._grapple_target or self._grapple_anchor
    local dx, dy = target.x - position.x, target.y - position.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local radius = setting(actions, config, "arrival_distance_px", 8)
    self._grapple_pull_variable = self._grapple_pull_variable or not Timers.reference_frame(dt)
    local speed = setting(actions, config, "pull_speed", 2000)
    if self._grapple_hanging or (not self._grapple_pull_variable and distance <= radius) then
        pull_arrive(self, actions, config)
        if not self._grapple_active then return dt end
    elseif dt > 0 then
        local travel = dt
        if self._grapple_pull_variable then
            local h = Timers.REFERENCE_STEP
            local before = self._grapple_elapsed - dt
            if self._grapple_pull_ready and distance > radius + 1e-5 then
                self._grapple_pull_ready = nil
            end
            if not self._grapple_pull_ready and (speed > 0 or distance <= radius) then
                local crossing = before + (distance > radius and (distance - radius) / speed or 0)
                local sample = math.ceil(crossing / h - 1e-9) * h
                if sample <= self._grapple_elapsed + 1e-12 then
                    self._grapple_pull_ready = sample + h
                    travel = math.max(0, math.min(dt, sample - before))
                end
            elseif self._grapple_pull_ready then
                travel = 0
            end
        end
        if travel > 0 and distance > 0 then
            local step_speed = math.min(speed, distance / travel)
            self.vx, self.vy = dx / distance * step_speed, dy / distance * step_speed
            if travel ~= dt then
                self._move_dx_correction = self.vx * (travel - dt)
                self._move_dy_correction = self.vy * (travel - dt)
            end
        else
            self.vx, self.vy = 0, 0
        end
        if self._grapple_pull_ready and self._grapple_elapsed + 1e-12 >= self._grapple_pull_ready then
            local owned = math.max(0, math.min(dt, self._grapple_pull_ready - (self._grapple_elapsed - dt)))
            if travel > 0 then
                self._move_dx_correction = self.vx * travel
                self._move_dy_correction = self.vy * travel
            end
            pull_arrive(self, actions, config)
            if not self._grapple_active then return owned end
        end
    end
end

local function release_hold(self, dt)
    local remaining = self._grapple_release_hold or Timers.REFERENCE_STEP
    self._grapple_just_released = false
    if dt <= 0 or (Timers.reference_frame(dt) and math.abs(remaining - dt) < 1e-8) then
        self._grapple_release_hold = nil
        return true
    end
    if remaining >= dt - 1e-12 then
        self._grapple_release_hold = remaining - dt > 1e-12 and remaining - dt or nil
        return true
    end
    self._grapple_release_hold = nil
    return false, remaining
end

local function swing_step(self, position, dt, input, actions, config)
    local settling = false
    if self._grapple_launch_length then
        -- Keep launch protection through the final inward integration step.
        -- Settle on the next update, once the player has reached the arc.
        settling = self._grapple_rope_length <= self._grapple_launch_length
        self._grapple_rope_length = math.max(self._grapple_launch_length,
            self._grapple_rope_length - math.max(0, setting(actions, config, "launch_reel_speed", 1400)) * dt)
    elseif setting(actions, config, "reel_enabled", false) then
        local reel_speed = math.max(0, setting(actions, config, "reel_speed", 0))
        local range = setting(actions, config, "range_px", 300)
        self._grapple_rope_length = math.max(self._grapple_min_length,
            math.min(range, self._grapple_rope_length - (input.move_y or 0) * reel_speed * dt))
    end
    self._grapple_pump = self._grapple_pump or {}
    local pump = self._grapple_pump
    pump.with_swing_only = setting(actions, config, "pump_with_swing_only", true)
    pump.start_speed = setting(actions, config, "pump_start_speed", 105)
    pump.counter_brake = setting(actions, config, "swing_counter_brake", 0.5)
    self.vx, self.vy = M.swing_velocity(position, self._grapple_anchor,
        self._grapple_rope_length, self.vx or 0, self.vy or 0, dt,
        input.move_x or 0, self._cfg.gravity or 0,
        setting(actions, config, "swing_acceleration", 0),
        setting(actions, config, "swing_drag", 0),
        setting(actions, config, "swing_max_speed", 0),
        setting(actions, config, "swing_speed_limit", 0), pump)
    if settling then
        local dx, dy = position.x - self._grapple_anchor.x, position.y - self._grapple_anchor.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= self._grapple_rope_length + 0.00001 then
            self._grapple_launch_length = nil
            if distance > 0 then
                local ux, uy = dx / distance, dy / distance
                local vr = self.vx * ux + self.vy * uy
                if vr < 0 then self.vx, self.vy = self.vx - vr * ux, self.vy - vr * uy end
            end
        end
    end
end

local function swing_position(value, native)
    return native and Timers.binary32(value) or value
end

local function swing_travel(self, position, dt, input, actions, config)
    self._grapple_swing_path = nil
    if dt <= 0 then return end
    local bx, by = self._grapple_bias_x or 0, self._grapple_bias_y or 0
    local step = self._grapple_swing_step
    if step and (position.x ~= step.draw_x or position.y ~= step.draw_y
        or step.bx ~= bx or step.by ~= by
        or math.abs(self.vx - step.vx) > 1e-9 or math.abs(self.vy - step.vy) > 1e-9) then
        -- A contact, room guard or external move replaced the last drawn pose.
        step = nil
    end
    if not step and Timers.reference_frame(dt) then
        self._grapple_swing_step = nil
        swing_step(self, position, dt, input, actions, config)
        return
    end

    local h, engine_dt = Timers.REFERENCE_STEP, Timers.engine_reference_step()
    local native = type(position) == "userdata"
    local x, y, left = position.x, position.y, dt
    local path
    while left > 1e-12 do
        if not step then
            step = {x = x, y = y, left = h, bx = bx, by = by}
            swing_step(self, step, engine_dt, input, actions, config)
            step.vx, step.vy = self.vx, self.vy
            step.end_x = swing_position(x + (self.vx + bx) * engine_dt, native)
            step.end_y = swing_position(y + (self.vy + by) * engine_dt, native)
        end
        local piece = math.min(left, step.left)
        step.left, left = step.left - piece, left - piece
        -- Packed display deltas can straddle a shared boundary by a few
        -- nanoseconds. Do not expose the next interval's velocity there.
        if step.left <= 1e-8 then
            if left <= 1e-8 then left = 0 end
            x, y = step.end_x, step.end_y
            if left > 1e-12 and self._bone_physics then
                path = path or {}
                path[#path + 1] = {x = x, y = y, vx = step.vx + bx, vy = step.vy + by,
                    bx = bx, by = by,
                    elapsed = self._grapple_elapsed - left,
                    length = self._grapple_rope_length, launch_length = self._grapple_launch_length}
            end
            step = nil
        else
            local fraction = (h - step.left) / h
            x = step.x + (step.end_x - step.x) * fraction
            y = step.y + (step.end_y - step.y) * fraction
        end
    end
    local dx, dy = (self.vx + bx) * dt, (self.vy + by) * dt
    self._move_dx_correction, self._move_dy_correction = (x - position.x) - dx, (y - position.y) - dy
    local draw_x = swing_position(position.x + (dx + self._move_dx_correction), native)
    local draw_y = swing_position(position.y + (dy + self._move_dy_correction), native)
    if step then step.draw_x, step.draw_y = draw_x, draw_y end
    if path then
        path.x, path.y = draw_x, draw_y
        self._grapple_swing_path = path
    end
    self._grapple_swing_step = step
end

local function attached_step(self, dt, input, actions, config)
    self._jump_cut_pending = nil
    local position = self.pos or go.get_position()
    local owned
    if setting(actions, config, "mode", "pull") == "swing" then
        swing_travel(self, position, dt, input, actions, config)
    else
        -- Pull mode already lifts toward its arrival point; it has no launch reel.
        self._grapple_launch_length = nil
        self._grapple_swing_step = nil
        self._grapple_swing_path = nil
        owned = pull_step(self, position, dt, actions, config)
    end
    self._grapple_step_vx, self._grapple_step_vy = self.vx, self.vy
    self._control_locked = self._grapple_active
    if math.abs(self.vx or 0) > 0.01 then self.facing = self.vx > 0 and 1 or -1 end
    return owned
end

local function paid_travel(self, dt)
    local dx = self.vx * dt + (self._move_dx_correction or 0)
    local dy = self.vy * dt + (self._move_dy_correction or 0)
    self._move_dx_correction, self._move_dy_correction = nil, nil
    return dx, dy
end

local function finish_motion(self, dt, owned, dx, dy)
    if dt - owned > 1e-12 then return false, owned, dx, dy end
    if dx ~= self.vx * dt then self._move_dx_correction = dx - self.vx * dt end
    if dy ~= self.vy * dt then self._move_dy_correction = dy - self.vy * dt end
    return true
end

local function ordinary_attachment(self, dt, input, actions, config)
    local owned = attached_step(self, dt, input, actions, config)
    if owned and dt - owned > 1e-12 then
        local dx, dy = paid_travel(self, owned)
        return false, owned, dx, dy
    end
    return true
end

-- A draw may span both a terrain stop and the later scheduled release.
-- First query the attached path so the live resolver can commit its stop.
-- The impact gets first choice of release; the timeout can still expire.
local function stop_before_timeout(self, dt, attached, dx, dy, timeout_input)
    if not self._bone_physics then return false end
    local start = self.pos
    local bx, by = self._grapple_bias_x or 0, self._grapple_bias_y or 0
    local path = self._grapple_swing_path or {}
    local native = type(start) == "userdata"
    local terminal = {x = swing_position(start.x + (dx + bx * attached), native),
        y = swing_position(start.y + (dy + by * attached), native),
        vx = self.vx + bx, vy = self.vy + by, bx = bx, by = by,
        elapsed = self._grapple_elapsed, length = self._grapple_rope_length,
        launch_length = self._grapple_launch_length}
    local from = start
    for i = 1, #path + 1 do
        local point = path[i] or terminal
        local collision, pose, vx, vy = BonePhysics.probe_swing_segment(self, from, point)
        if collision.grounded or (collision.wall_contact or 0) ~= 0 or collision.ceiling_contact
            or pose.x ~= point.x or pose.y ~= point.y or vx ~= point.vx or vy ~= point.vy then
            for k = #path, i, -1 do path[k] = nil end
            path.x, path.y = point.x, point.y
            self._grapple_swing_path = #path > 0 and path or nil
            self._grapple_swing_step = nil
            self._grapple_rope_length, self._grapple_launch_length = point.length, point.launch_length
            self._grapple_contact_elapsed = point.elapsed
            self._grapple_timeout_after_contact = timeout_input
            self.vx, self.vy = point.vx - bx, point.vy - by
            self._grapple_step_vx, self._grapple_step_vy = self.vx, self.vy
            return finish_motion(self, dt, dt, point.x - start.x - bx * dt, point.y - start.y - by * dt)
        end
        from = point
    end
    return false
end

local function timed_attachment(self, dt, input, actions, config)
    local h = Timers.REFERENCE_STEP
    local before = Timers.window_remaining(self, "_grapple_timeout")
    local expired, paid = Timers.tick_deadline(self, "_grapple_timeout", dt)
    local attached = math.max(0, math.min(dt, before - h))
    if not expired and (attached >= dt - 1e-12
        or (Timers.reference_frame(dt) and dt - attached <= 1e-7)) then
        return ordinary_attachment(self, dt, input, actions, config)
    end
    if expired and Timers.reference_frame(dt) and math.abs(paid - dt) <= 1e-7
        and not self._grapple_timeout_motion and attached <= 1e-7 then
        M.release(self, input, actions, config, "let_go")
        return release_hold(self, dt)
    end

    local dx, dy = 0, 0
    if attached > 1e-12 then
        local elapsed = self._grapple_elapsed
        self._grapple_elapsed = elapsed - dt + attached
        local owned = attached_step(self, attached, input, actions, config)
        dx, dy = paid_travel(self, owned or attached)
        if not self._grapple_active then return finish_motion(self, dt, owned or attached, dx, dy) end
        local stopped = setting(actions, config, "mode", "pull") == "swing"
            and stop_before_timeout(self, dt, attached, dx, dy, expired and input or nil)
        self._grapple_elapsed = elapsed
        if stopped then return true end
    end
    -- The saved expiry update moves at release velocity through its whole
    -- reference step. Prepare that velocity where the step opens and keep
    -- the public detach on the update that contains its deadline.
    if not self._grapple_timeout_motion then
        release_velocity(self, input, actions, config, "let_go")
        self._grapple_timeout_motion = true
    end
    local held = math.max(0, paid - attached)
    dx, dy = dx + self.vx * held, dy + self.vy * held
    if expired then
        M.release(self, input, actions, config, "let_go", true)
        self._grapple_just_released, self._grapple_release_hold = false, nil
    end
    return finish_motion(self, dt, paid, dx, dy)
end

function M.update(self, dt, input, actions, config)
    input = input or {}
    local HoldToggles = require "mvtk.player.hold_toggles"
    local interrupted = HoldToggles.sync(self, "grapple")
    if interrupted and HoldToggles.enabled("grapple") then M.clear(self); return false end
    if self._grapple_just_released or self._grapple_release_hold then
        return release_hold(self, dt)
    end
    if not self._grapple_active or not self._grapple_anchor then return false end
    if (self._stun_t or 0) > 0 then M.clear(self); return false end
    local elapsed = self._grapple_elapsed or 0
    self._grapple_elapsed = elapsed + dt
    local max_duration = setting(actions, config, "max_duration", 0)
    if self._grapple_timeout_config ~= max_duration then
        self._grapple_timeout_config = max_duration
        Timers.start_window(self, "_grapple_timeout", max_duration, false, elapsed)
    end
    -- Keyboard and gamepad holds are aggregated by input_controller. A single
    -- source's release edge must not drop a hook another source still holds.
    local button_released = input.grapple_held == false
        or (input.grapple_held == nil and input.grapple_up)
    local stay_hooked = M.effective_stay_hooked(actions, config)
    local release_press = stay_hooked and input.grapple_down
    if release_press then
        -- player.script runs PSTATE.update (and this update) before its cast.
        -- Attachment happens after this block, so its first press cannot let
        -- go. Consume a later press on the shared frame input to prevent a
        -- same-frame re-hook or a missed-cast hold-retry window.
        input.grapple_down = false
    end
    if release_press or (not stay_hooked and button_released) or
        (input.jump_down and M.release_on_jump(actions, config)) then
        M.release(self, input, actions, config, "let_go", self._grapple_timeout_motion)
        return release_hold(self, dt)
    end
    if max_duration > 0 then return timed_attachment(self, dt, input, actions, config) end
    return ordinary_attachment(self, dt, input, actions, config)
end

-- Interpolate the captured flight segment without reading or changing player state.
function M.hook_tip(hook)
    local fraction = hook.distance > 0 and math.min(1, math.max(0, hook.travelled / hook.distance)) or 1
    return vmath.vector3(hook.from.x + (hook.hit.position.x - hook.from.x) * fraction,
        hook.from.y + (hook.hit.position.y - hook.from.y) * fraction,
        hook.from.z + (hook.hit.position.z - hook.from.z) * fraction)
end

function M.draw_rope(self, actions, config)
    -- These modes bypass normal movement, so discard both the old anchor
    -- and any release carry before they can resume ordinary movement.
    if (self._grapple_active or self._grapple_hook or (self._grapple_carry_t or 0) > 0)
        and (self._is_dead or self._in_water or self._in_climb) then
        M.clear(self)
    end
    if not setting(actions, config, "rope_enabled", false) then return end
    local position = self.pos or go.get_position()
    local anchor = self._grapple_hook and M.hook_tip(self._grapple_hook)
        or (self._grapple_active and self._grapple_anchor) or position
    local color = setting(actions, config, "rope_color", { 1, 1, 1, 1 })
    go.set("#grapple_rope", "rope_start", vmath.vector4(position.x, position.y,
        position.z + setting(actions, config, "rope_z", 0.15),
        setting(actions, config, "rope_width_px", 3)))
    go.set("#grapple_rope", "rope_end", vmath.vector4(anchor.x, anchor.y, 0,
        (self._grapple_active or self._grapple_hook) and 1 or 0))
    go.set("#grapple_rope", "tint", vmath.vector4(color[1], color[2], color[3], color[4] or 1))
end

return M
