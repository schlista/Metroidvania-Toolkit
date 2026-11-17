-- Charged launch state is owned by the host; ready/rising/started are PSTATE bridge fields.
local M = { id = "super_jump", order = 34 }

local function clear_charge(self, state)
    state.charge, state.grace = 0, 0
    self._super_jump_ready = false
end

local function taken_over(self)
    return (self._dash_t or 0) > 0 or (self._slide_t or 0) > 0
        or self._grapple_active or self._ledge_kinematic or self._ledge_hanging or self._ledge_climbing
        or self._in_water or self._in_climb or self._pound_active or self._compact_active
        or self._is_dead or (self._stun_t or 0) > 0
end

function M.apply_abilities(overrides)
    local settings = require("developer.config.runtime_settings").get_player_settings()
    local cfg = {}
    for key, value in pairs(settings.super_jump or {}) do cfg[key] = value end
    overrides.super_jump = cfg -- Active use is gated by the ability callback, not SIMPLE_TOGGLES.
end

function M.pre_physics(self, dt, input)
    if require("mvtk.core.pause").get() then return end
    local state, cfg = self._host.features.super_jump, self._cfg.super_jump or {}
    input = input or {}
    if self._super_jump_rising then
        clear_charge(self, state)
        return
    end
    if not self.grounded or taken_over(self) or self._attack or (self._combat and self._combat.current)
        or self._block_grab or self._room_arrival or (self._backdash_t or 0) > 0 or (self._roll_t or 0) > 0
        or math.abs(input.move_x or 0) >= (cfg.still_threshold or 0.25)
        or not self._ability_can_use or not self._ability_can_use("super_jump") then
        clear_charge(self, state)
        return
    end
    if (input.move_y or 0) < -(cfg.down_threshold or 0.6) then
        state.charge = (state.charge or 0) + dt
        state.grace = cfg.release_grace or 0.12
        self._super_jump_ready = state.charge >= (cfg.charge_time or 0.6)
    else
        state.grace = math.max(0, (state.grace or 0) - dt)
        if state.grace <= 0 then clear_charge(self, state) end
    end
end

function M.post_physics(self)
    if require("mvtk.core.pause").get() then return end
    local state = self._host.features.super_jump
    local interrupted = taken_over(self)
    local started = self._super_jump_started == true and not interrupted
    self._super_jump_started = nil
    if self._super_jump_rising and (self.vy <= 0 or interrupted) then
        self._super_jump_rising = false
    end
    local rising = self._super_jump_rising == true
    if started or (rising and not state.contact) then
        require("mvtk.player.player_combat").spawn_movement_contact_hitbox(self, "super_jump")
    elseif state.contact and not rising then
        require("mvtk.player.player_combat").clear_movement_contact_hitbox(self, "super_jump")
    end
    -- A launch that immediately bonks still needs one physics step to deliver its hit.
    -- Ordinary rises clear at their ending edge; an immediately stopped start clears next hook.
    state.contact = rising or started
    if rising or state.hud then
        pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_mode"), {
            mode = rising and "Super Jump" or (self._last_mode or ""),
        })
    end
    state.hud = rising
end

function M.anim_state(self, animation)
    local state, cfg = self._host.features.super_jump, self._cfg.super_jump or {}
    if self._super_jump_rising and (animation == "jump" or animation == "fall") then
        return cfg.launch_animation or "jump"
    elseif (state.charge or 0) > 0 and (animation == "idle" or animation == "crouch" or animation == "crouch_idle") then
        return cfg.charge_animation or "crouch_idle"
    end
end

function M.reset(self)
    require("mvtk.player.player_combat").clear_movement_contact_hitbox(self, "super_jump")
    self._super_jump_ready, self._super_jump_rising = false, false
    self._super_jump_started = nil
    self._host.features.super_jump = {}
    self._last_mode = nil
end

return M
