-- Launch state belongs to PlayerHost. Grapple bridge fields reuse its ordinary
-- flight/carry policy; release kind launch deliberately excludes float gravity.
local M = {}

local function reply(cannon, name, data)
    if cannon then pcall(msg.post, cannon, name, data or {}) end
end

local function unload(self, fired_angle)
    local state = self._host.features.launch
    if state.loaded then
        require("mvtk.player.player_stats").clear_source("feature:launch")
        reply(state.loaded.cannon, fired_angle and "cannon_fired" or "cannon_cancelled", {angle = fired_angle})
        state.loaded, state.elapsed = nil, 0
    end
end

function M.clear(self)
    local state = self._host and self._host.features.launch
    if state then
        unload(self)
        if state.contact then
            require("mvtk.player.player_combat").clear_movement_contact_hitbox(self, "launch")
            state.contact = false
        end
        state.active, state.lock_t = false, 0
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
    self._climb_reattach_lock_t = math.max(self._climb_reattach_lock_t or 0, 0.25)
    PSTATE.cancel_grapple(self)
    PSTATE.clear_ledge_state(self)
    PSTATE.exit_wall_climb(self)
    PSTATE.cancel_ground_pound(self)
    PSTATE.end_dash_slide(self)
    self._backdash_t, self._roll_t, self._pound_recovery_t = 0, 0, 0
    self._extended_jump_active = false
    self.vx, self.vy = tonumber(request.vx) or 0, tonumber(request.vy) or 0
    PSTATE.set_grounded(self, false)
    self.bypass_ground_frames = 2
    if self.vx ~= 0 then self.facing = self.vx < 0 and -1 or 1 end
    local state = self._host.features.launch
    state.active, state.lock_t = true, math.max(0, tonumber(request.lock_t) or 0)
    self._grapple_flight = true
    self._grapple_release_kind = "launch"
    self._grapple_carry_t = request.keep_momentum ~= false and 30 or state.lock_t
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
    self.pos.x, self.pos.y, self.vx, self.vy = request.x, request.y, 0, 0
    return true
end

local function hold_input(self, input)
    for _, key in ipairs({"light_down","light_held","light_up","heavy_down","heavy_held","heavy_up",
        "ranged_down","ranged_held","ranged_up","parry_down","grapple_down","grapple_held",
        "slide_down","slide_held","slide_up","dash_down","dash_pressed","backdash_down",
        "ground_pound_down","interact_down","potion_down","marker_down","morph_toggle_down"}) do
        input[key] = false
    end
    input.move_x, input.move_y, input.jump_down = 0, 0, false
    self._light_buffer_count, self._heavy_buffer_count, self._ranged_buffer_count = 0, 0, 0
    self._conveyor_contacts, self._ext_fx, self._ext_fy = nil, 0, 0
    if self._env_contacts then self._env_contacts.push = nil end
    self._climb_reattach_lock_t = math.max(self._climb_reattach_lock_t or 0, 0.25)
end

function M.pre_physics(self, dt, input)
    if require("mvtk.core.pause").get() then return end
    local state = self._host.features.launch
    if state.loaded then
        if self._is_dead or self._in_water or self._in_climb or self._grapple_active
            or self._room_arrival or (self._stun_t or 0) > 0 then M.clear(self); return end
        local request = state.loaded
        state.elapsed = state.elapsed + dt
        local fire = request.fire_on == "auto" and state.elapsed >= (tonumber(request.auto_delay) or 1)
            or request.fire_on ~= "auto" and input.jump_down
        hold_input(self, input)
        if not fire then return end
        local angle = tonumber(request.angle) or 45
        if request.aim_mode == "sweep" then
            angle = require("mvtk.world.launch_math").sweep_angle(angle,
                tonumber(request.sweep_range) or 90, tonumber(request.sweep_speed) or 60, state.elapsed)
        end
        local vx, vy = require("mvtk.world.launch_math").vector(angle, tonumber(request.speed) or 2400)
        unload(self, angle)
        M.start(self, {vx=vx, vy=vy, lock_t=request.lock_t, keep_momentum=request.keep_momentum})
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
    if state.lock_t > 0 then
        input.move_x = 0
        state.lock_t = math.max(0, state.lock_t - dt)
    end
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
