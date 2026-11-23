-- Launch state belongs to PlayerHost. Grapple bridge fields reuse its ordinary
-- flight/carry policy; release kind launch deliberately excludes float gravity.
local Timers = require "mvtk.player.timers"
local M = {}

local function tick_ground_bypass(self, state, dt)
    if not Timers.is_active(state, "ground_t") then return end
    local ended = Timers.tick_deadline(state, "ground_t", dt)
    -- The collision resolver spends one slot before applying floor contacts.
    self.bypass_ground_frames = math.max(self.bypass_ground_frames or 0, ended and 1 or 2)
end

local function reply(cannon, name, data)
    if cannon then pcall(msg.post, cannon, name, data or {}) end
end

local function unload(self, fired_angle)
    local state = self._host.features.launch
    if state.loaded then
        require("mvtk.player.player_stats").clear_source("feature:launch")
        reply(state.loaded.cannon, fired_angle and "cannon_fired" or "cannon_cancelled", {angle = fired_angle})
        state.loaded, state.elapsed, state.fire_at = nil, 0, nil
        Timers.clear_window(state, "fire_t")
    end
end

function M.clear(self)
    self._launch_fire_offset = nil
    local state = self._host and self._host.features.launch
    if state then
        unload(self)
        if state.contact then
            require("mvtk.player.player_combat").clear_movement_contact_hitbox(self, "launch")
            state.contact = false
        end
        state.active = false
        Timers.clear_window(state, "lock_t")
        Timers.clear_window(state, "ground_t")
    end
    -- A later grapple release may already own these fields.
    if self._grapple_release_kind == "launch" then
        self._grapple_flight, self._grapple_carry_t = false, 0
        self._grapple_release_kind = nil
    end
end

function M.start(self, request)
    if self._is_dead or self._in_water or require("mvtk.core.pause").get() then return false end
    M.clear(self)
    local PSTATE = require "mvtk.player.player_state"
    self._in_climb = false
    Timers.extend_window(self, "_climb_reattach_lock_t", 0.25)
    PSTATE.cancel_grapple(self)
    PSTATE.clear_ledge_state(self)
    PSTATE.exit_wall_climb(self)
    PSTATE.cancel_ground_pound(self)
    PSTATE.end_dash_slide(self)
    Timers.clear_window(self, "_backdash_t")
    self._pound_recovery_t = 0
    self._extended_jump_active = false
    self.vx, self.vy = tonumber(request.vx) or 0, tonumber(request.vy) or 0
    self._jump_cut_pending = nil
    PSTATE.set_grounded(self, false)
    self.bypass_ground_frames = 2
    if self.vx ~= 0 then self.facing = self.vx < 0 and -1 or 1 end
    local state = self._host.features.launch
    state.active = true
    Timers.start_window(state, "ground_t", 2 * Timers.REFERENCE_STEP)
    Timers.start_window(state, "lock_t", math.max(0, tonumber(request.lock_t) or 0))
    self._grapple_flight = true
    self._grapple_release_kind = "launch"
    Timers.start_window(self, "_grapple_carry_t", request.keep_momentum ~= false and 30 or state.lock_t)
    return true
end

function M.load(self, request)
    local state = self._host.features.launch
    local zip = self._host.features.zipline
    if state.loaded or (zip and zip.active) or self._room_arrival or (self._stun_t or 0) > 0
        or not request.cannon or not M.start(self, {vx=0, vy=0, keep_momentum=false}) then
        reply(request.cannon, "cannon_cancelled")
        return false
    end
    -- Loading takes over the body and its pose; a pad launch keeps its old
    -- combat policy. Cancel timelines before another player update can spawn.
    require("mvtk.combat.attack_executor").cancel(self)
    require("mvtk.player.player_combat").clear_all_movement_contact_hitboxes(self)
    self._anim_lock_t, self._anim_lock_allow_movement = 0, true
    -- The body stays visible. Only this feature owns the temporary hold/source.
    state.active, state.loaded, state.elapsed = false, request, 0
    require("mvtk.player.player_state").update_motion_takeover(self, 0, false)
    if request.fire_on == "auto" then
        local delay = tonumber(request.auto_delay) or 1
        Timers.start_window(state, "fire_t", delay > 0 and delay or Timers.REFERENCE_STEP)
        state.fire_at = Timers.window_remaining(state, "fire_t")
    end
    self._grapple_flight, self._grapple_carry_t, self._grapple_release_kind = false, 0, nil
    self.pos.x, self.pos.y = request.x, request.y
    if ((self._cfg or {}).launch or {}).cannon_invulnerable ~= false then
        require("mvtk.player.player_stats").set_source("feature:launch", {invulnerable=true}, {layer="temporary"})
    end
    if request.fire_on ~= "auto" then
        local prompt = ((self._cfg or {}).launch or {}).cannon_prompt or ""
        require("mvtk.prefabs.prefab_utils").toast(prompt)
    end
    return true
end

function M.cancel_cannon(self, cannon)
    local state = self._host.features.launch
    if state.loaded and state.loaded.cannon == cannon then M.clear(self) end
end

function M.owns_motion(self)
    local request = self._host.features.launch.loaded
    if not request then return false end
    self._jump_cut_pending = nil
    self.pos.x, self.pos.y, self.vx, self.vy = request.x, request.y, 0, 0
    return true
end

local function hold_input(self, input)
    for _, key in ipairs({"light_down","light_held","light_up","heavy_down","heavy_held","heavy_up",
        "ranged_down","ranged_held","ranged_up","parry_down","grapple_down","grapple_held",
        "slide_down","slide_held","slide_up","backdash_down",
        "ground_pound_down","interact_down","potion_down","marker_down","morph_toggle_down"}) do
        input[key] = false
    end
    input.move_x, input.move_y, input.jump_down = 0, 0, false
    self._light_buffer_count, self._heavy_buffer_count, self._ranged_buffer_count = 0, 0, 0
    self._conveyor_contacts, self._ext_fx, self._ext_fy = nil, 0, 0
    require("mvtk.player.surface_effects").suppress_push(self)
    if self._env_contacts then self._env_contacts.push = nil end
    Timers.extend_window(self, "_climb_reattach_lock_t", 0.25)
end

local function tick_control_lock(self, state, dt, input, raw_x)
    if state.lock_t <= 0 then return end
    local active, travel = Timers.slice_window(state, "lock_t", dt)
    if travel > 1e-12 and travel < dt - 1e-12
        and not (Timers.reference_frame(dt) and dt - travel < 1e-7) then
        self._launch_steer_dt, self._launch_steer_x = travel, raw_x
    end
    if active then input.move_x = 0 end
end

function M.pre_physics(self, dt, input)
    self._launch_steer_dt, self._launch_steer_x = nil, nil
    self._launch_fire_offset = nil
    if require("mvtk.core.pause").get() then return end
    local state = self._host.features.launch
    tick_ground_bypass(self, state, dt)
    if state.loaded then
        if self._is_dead or self._in_water or self._in_climb or self._grapple_active
            or self._room_arrival or (self._stun_t or 0) > 0 then M.clear(self); return end
        local request = state.loaded
        state.elapsed = state.elapsed + dt
        local fire, fire_offset
        if request.fire_on == "auto" then
            fire, fire_offset = Timers.tick_deadline(state, "fire_t", dt)
            if Timers.reference_frame(dt) and dt - fire_offset <= 1e-7 then fire_offset = dt end
        else
            fire = input.jump_down
        end
        local raw_x = input.move_x or 0
        hold_input(self, input)
        if not fire then return end
        local angle = tonumber(request.angle) or 45
        if request.aim_mode == "sweep" then
            local aim_time = state.elapsed
            if state.fire_at and not (Timers.reference_frame(dt)
                and math.abs(aim_time - state.fire_at) <= 1e-7) then
                aim_time = state.fire_at
            end
            angle = require("mvtk.world.launch_math").sweep_angle(angle,
                tonumber(request.sweep_range) or 90, tonumber(request.sweep_speed) or 60, aim_time)
        end
        local vx, vy = require("mvtk.world.launch_math").vector(angle, tonumber(request.speed) or 2400)
        unload(self, angle)
        M.start(self, {vx=vx, vy=vy, lock_t=request.lock_t, keep_momentum=request.keep_momentum})
        self._launch_fire_offset = fire_offset
        local flight_dt = dt - (fire_offset or 0)
        tick_ground_bypass(self, state, flight_dt)
        if fire_offset then
            if state.lock_t > 0 then
                tick_control_lock(self, state, flight_dt, input, raw_x)
            else
                input.move_x = raw_x
            end
        end
        if request.breaks_action and request.breaks_action ~= "" and request.breaks_action ~= "none" then
            require("mvtk.player.player_combat").spawn_movement_contact_hitbox(self, "launch", request.lock_t,
                {attack_type=request.breaks_action, damage=0, hit_enemy=false, lifetime=request.lock_t})
            state.contact = true
        end
        return
    end
    if not state.active then return end
    if self.grounded or self._on_wall or self._in_water or self._in_climb
        or self._grapple_active or self._is_dead then
        M.clear(self)
        return
    end
    tick_control_lock(self, state, dt, input, input.move_x or 0)
    if state.contact and state.lock_t <= 0 then
        require("mvtk.player.player_combat").clear_movement_contact_hitbox(self, "launch")
        state.contact = false
    end
end

function M.post_physics(self, collision)
    local state = self._host.features.launch
    if state.active and (self.grounded or self._on_wall or self._in_water or self._in_climb
        or self._grapple_active or self._is_dead or (collision and
            (collision.grounded or (collision.wall_contact or 0) ~= 0))) then M.clear(self) end
end

return M
