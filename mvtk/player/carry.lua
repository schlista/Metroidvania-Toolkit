-- PlayerHost owns the carry relationship; only PlayerStats owns its slowdown.
local M = {}

local function state(self) return self._host.features.carry end
local function settings() return require("mvtk.core.util").require_config("developer.config.carry_settings") end
local function blocked(self)
    return self._is_dead or self._in_water or self._in_climb or self._ledge_hanging
        or self._ledge_kinematic or self._grapple_active or (self._stun_t or 0) > 0
end
local function suppress(self, input)
    self._light_buffer_count, self._heavy_buffer_count, self._ranged_buffer_count = 0, 0, 0
    self._light_hold_t = 0
    if input then
        for _, key in ipairs({"light_down", "light_held", "light_up", "heavy_down", "heavy_held", "heavy_up",
            "ranged_down", "ranged_held", "ranged_up", "parry_down", "interact_down"}) do input[key] = false end
    end
end

function M.release(self, mode, input)
    local s = state(self)
    local object = s.object
    if object and go.exists(object) then
        local vx, vy = 0, 0
        if mode == "throw" then
            local cfg = settings()
            vx, vy = require("mvtk.world.carry_motion").vector(s.throw_speed,
                (input and (input.move_y or 0) > 0) and cfg.up_throw_angle or cfg.throw_angle, self.facing or 1)
        end
        -- Send final world placement with release: never depend on cross-object update order.
        local pos = self.pos
        local facing = (self.facing or 1) < 0 and -1 or 1
        local x = pos.x
        local y = pos.y + (self.collider_half_height or self._cfg.collider_half_height) * settings().hold_above_ratio + s.half_h
        if mode == "drop" then
            x = x + facing * ((self.collider_half_width or self._cfg.collider_half_width) + s.half_w)
            y = pos.y
        end
        msg.post(object, "carry_release", {mode=mode, vx=vx, vy=vy, x=x, y=y,
            damage=require("mvtk.player.player_stats").outgoing_damage(s.impact_damage),
            bomb_damage=require("mvtk.player.player_stats").outgoing_damage(s.bomb_damage), owner=msg.url()})
    end
    for key in pairs(s) do s[key] = nil end
    self._carry_active, self._carry_blocks_jump = false, false
    require("mvtk.player.player_stats").clear_source("carry")
end

function M.begin(self, request)
    if request.ended then
        if state(self).object == request.object then M.release(self, "lost") end
        return false
    end
    if require("mvtk.core.pause").get() or self._carry_active or blocked(self) or self._block_grab
        or self._room_arrival or not request.object or not go.exists(request.object) then return false end
    local s, cfg = state(self), settings()
    local kind = cfg.kinds[request.kind]
    if not kind or request.room_id ~= require("mvtk.map.streaming.room_manager").get_current_room() then return false end
    -- An attack already playing must not spawn a late hit while carrying.
    require("mvtk.combat.attack_executor").cancel(self)
    require("mvtk.player.player_combat").clear_all_movement_contact_hitboxes(self)
    require("mvtk.player.player_state").end_dash_slide(self)
    require("mvtk.player.player_state").cancel_ground_pound(self)
    self._backdash_t, self._roll_t = 0, 0
    self._teleport_request = nil
    s.object, s.room_id = request.object, request.room_id
    s.half_w, s.half_h = request.half_w, request.half_h
    s.throw_speed = request.throw_speed
    s.impact_damage, s.bomb_damage = kind.impact_damage or 0, kind.damage or 0
    self._carry_active, self._carry_blocks_jump = true, request.blocks_jump == true
    if self._carry_blocks_jump then self._jump_buffer_t = 0 end
    suppress(self)
    require("mvtk.player.player_stats").set_source("carry",
        {speed_mult=math.max(0.25, math.min(1, request.move_speed_mult))}, {layer="temporary"})
    msg.post(s.object, "carry_accept", {owner=msg.url(),
        bomb_damage=require("mvtk.player.player_stats").outgoing_damage(s.bomb_damage)})
    return true
end

function M.pre_physics(self, dt, input)
    if require("mvtk.core.pause").get() or not self._carry_active then return end
    local s = state(self)
    local mode
    if not go.exists(s.object) then mode = "lost"
    elseif s.room_id ~= require("mvtk.map.streaming.room_manager").get_current_room() then mode = "lost"
    elseif blocked(self) then mode = "drop"
    elseif input.light_down then mode = "throw"
    elseif input.interact_down then mode = "drop" end
    if mode then M.release(self, mode, input) end
    suppress(self, input)
end

function M.post_physics(self)
    if require("mvtk.core.pause").get() or not self._carry_active then return end
    local s = state(self)
    if not go.exists(s.object) then M.release(self, "lost"); return end
    if s.room_id ~= require("mvtk.map.streaming.room_manager").get_current_room() then M.release(self, "lost"); return end
    if blocked(self) then M.release(self, "drop"); return end
    msg.post(s.object, "carry_follow", {x=self.pos.x,
        y=self.pos.y + (self.collider_half_height or self._cfg.collider_half_height) * settings().hold_above_ratio + s.half_h,
        facing=self.facing or 1})
end

function M.anim_state(self)
    if not self._carry_active then return end
    local name = settings().animations[math.abs(self.vx or 0) > 1 and "move" or "idle"]
    if name and name ~= "" then return name end
end

return M
