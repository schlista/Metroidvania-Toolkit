-- Transient return targets and delivery state; all movement uses RoomArrival.
-- Keep dependencies lazy: real player harnesses load every feature.
local M = {}
local function state(self)
    self._hazard_return = self._hazard_return or {}
    return self._hazard_return
end
function M.init(self, ctx)
    self._hazard_return = {PSTATE=ctx and ctx.PSTATE}
end
local function enabled()
    return require("mvtk.player.safe_ground").return_sampling_enabled()
end
-- Movement and parry iFrames, stat invulnerability and return grace pass over
-- return hazards. Post-hit iFrames only waive the return damage: an enemy on
-- the player re-hits as they end, which would hold the player in spikes.
local function protected(self)
    local ps = state(self).PSTATE or require "mvtk.player.player_state"
    return (self._respawn_grace_timer or 0) > 0
        or (ps.is_movement_invulnerable and ps.is_movement_invulnerable(self))
end
local function hurt_protected(self)
    local ps = state(self).PSTATE or require "mvtk.player.player_state"
    return ps.is_damage_invulnerable and ps.is_damage_invulnerable(self)
end
local function repost(message)
    local payload = {}
    for _, key in ipairs({"amount","knockback","knockback_direction","stun_t",
        "source_actor","source_attack","damage_type","dtype","source","kx","ky","dir"}) do payload[key] = message[key] end
    -- The legacy receiver forwards dtype/source, while direct return damage
    -- uses damage_type/source_actor. Preserve both names at this boundary.
    payload.dtype = payload.damage_type or payload.dtype
    payload.source = payload.source_actor or payload.source
    if message.lethal then
        payload.lethal, payload.amount = true, math.max(9999, tonumber(payload.amount) or 0)
    end
    msg.post(".", hash("take_damage"), payload)
end
local function checked_target(self, position, room_id, facing, allow_water, position_kind)
    if not position or not room_id then return nil end
    local Safe = require "mvtk.player.safe_ground"
    local hw, hh = self.collider_half_width or 0, self.collider_half_height or 0
    local point_y = position.y
    if position_kind == "feet" then
        position = require("mvtk.player.placement").origin(self, position, position_kind)
    end
    if not Safe.is_safe(room_id, position.x, position.y, hw, hh, allow_water) then return nil end
    local Surface = require "mvtk.core.surface_classifier"
    local from = vmath.vector3(position.x, position.y + hh, position.z or 0)
    local hit = physics.raycast(from, from - vmath.vector3(0, math.max(1, hh*3), 0),
        {Surface.GROUPS.SOLID, Surface.GROUPS.WORLD})
    local target = vmath.vector3(position)
    if hit and hit.position then
        local lift = position_kind == "feet" and (position.y - point_y) or hh - (self.foot_floor_adjust or 0)
        target.y = hit.position.y + lift
    end
    if not Safe.is_safe(room_id, target.x, target.y, hw, hh, allow_water) then return nil end
    return {position=target, room_id=room_id, facing=facing}
end
local function target(self, room_id, lethal, locked)
    local s = state(self)
    local Rooms = require "mvtk.map.streaming.room_manager"
    if s.zone and s.zone.room_id == room_id then
        local room = Rooms.get_room_data(room_id)
        if room then
            local x, y = require("mvtk.map.streaming.room_geometry").compute_spawn_xy(room)
            local result = checked_target(self, vmath.vector3(x+s.zone.x,y+s.zone.y,0),room_id,s.zone.facing,true,"feet")
            if result then return result end
        end
    end
    local sample = require("mvtk.player.safe_ground").peek(self, {neighbor_rooms=not locked, fit_current_collider=true})
    if sample then return {position=sample.world, room_id=sample.room_id} end
    if lethal and not locked then
        local checkpoint = require("mvtk.core.checkpoint").data.checkpoint
        if checkpoint then
            local layout = require("mvtk.rooms.layout_io").load({runtime_preferred=true})
            local result = require("mvtk.world.checkpoint_return").resolve(checkpoint, layout)
            if result then return checked_target(self, result.position, result.room_id, nil, nil, result.position_kind) end
        end
    end
end
local function lock_state(self, room_id)
    local s = state(self)
    local locked = require("mvtk.bosses.fight_lock").is_locked(room_id)
    if enabled() and locked and (not s.locked or s.lock_room ~= room_id) then
        s.zone = nil
        require("mvtk.player.safe_ground").forget(self)
    end
    s.locked, s.lock_room = locked, room_id
    return locked
end
local function contact(self, message)
    local s = state(self)
    local Rooms = require "mvtk.map.streaming.room_manager"
    if self._is_dead or not self.pos or not Rooms.is_startup_ready() or self._room_arrival or s.pending then return end
    if (self._frame_counter or 0) <= (s.settle_until or -1)
        and (message.rect_w or 0) > 0 and (message.rect_h or 0) > 0 then
        if math.abs(self.pos.x-message.rect_x) > message.rect_w/2 + 2*(self.collider_half_width or 0)
            or math.abs(self.pos.y-message.rect_y) > message.rect_h/2 + 3*(self.collider_half_height or 0) then return end
    end
    local Contact = require "mvtk.hazards.hazard_contact"
    local cfg = Contact.settings()
    local mode, damage = Contact.player_mode(message.mode, message.lethal == true, message.return_damage or cfg.damage)
    if mode == "kill" then msg.post(".", hash("mvtk_death"), {reason="hazard"}); return end
    if mode == "damage" then repost(message); return end
    if not enabled() then return end
    local immune = protected(self)
    if immune and not message.lethal then return end
    local riders = require("mvtk.elevators.elevator_manager").ridden_ids()
    if #riders > 0 and not message.lethal then repost(message); return end
    if message.lethal then
        for _, id in ipairs(riders) do
            require("mvtk.elevators.elevator_manager").cancel(id,"hazard_return",{reset_home=true})
        end
    end
    local room_id = Rooms.get_current_room()
    local locked = lock_state(self,room_id)
    if s.zone and s.zone.room_id ~= room_id then s.zone = nil end
    local destination = target(self,room_id,message.lethal,locked)
    if not destination then repost(message); return end
    if not immune and not hurt_protected(self) and damage > 0 then
        local dispatch = require("mvtk.player.room_arrival").get_dispatch()
        if not dispatch then repost(message); return end
        dispatch(self,hash("mvtk_apply_damage"),{amount=damage,kx=0,ky=0,stun_t=0,parryable=false,
            source_actor=message.source_actor,source_attack=message.source_attack,damage_type=message.damage_type},nil)
        if self._is_dead then return end
    end
    s.next_request = (s.next_request or 0)+1
    s.pending = {grace=cfg.grace_time,lethal=message.lethal == true,room_id=destination.room_id,
        contact=message,request=s.next_request}
    msg.post(".",hash("mvtk_set_position"),{position=destination.position,room_id=destination.room_id,
        facing=destination.facing ~= 0 and destination.facing or nil,update_camera=true,
        arrival_fade=cfg.fade_time > 0,arrival_fade_out=cfg.fade_time,arrival_fade_in=cfg.fade_time,
        reset_motion=true,reason="hazard_return",hazard_return_request=s.pending.request})
end
function M.on_message(self, id, message)
    if id == hash("mvtk_hazard_contact") then contact(self,message); return true end
    if id ~= hash("mvtk_return_point") then return false end
    local s = state(self)
    if message.clear then s.zone = nil; return true end
    if not enabled() or not message.position then return true end
    local Rooms = require "mvtk.map.streaming.room_manager"
    local room_id = Rooms.get_room_for_position(message.position)
    local room = room_id and Rooms.get_room_data(room_id)
    if room then
        local x,y = require("mvtk.map.streaming.room_geometry").compute_spawn_xy(room)
        s.zone = {room_id=room_id,x=message.position.x-x,y=message.position.y-y,facing=message.facing,zone_id=message.zone_id}
    end
    return true
end
function M.reset(self, reason)
    local s = state(self)
    if reason == "teleport" then
        s.settle_until = (self._frame_counter or 0)+2
        local pending, delivery = s.pending, self._room_arrival_delivery
        s.pending = nil
        if pending and delivery and delivery.hazard_return_request == pending.request then
            self._respawn_grace_timer = math.max(self._respawn_grace_timer or 0,pending.grace)
            require("mvtk.core.game_events").emit("hazard_return",{room_id=pending.room_id,lethal=pending.lethal})
        elseif enabled() then s.zone = nil; require("mvtk.player.safe_ground").forget(self) end
    elseif reason == "death" then s.zone,s.pending = nil,nil
    elseif reason == "respawn" then
        s.pending = nil
        if enabled() then s.zone = nil; require("mvtk.player.safe_ground").forget(self) end
    elseif reason == "final" then self._hazard_return = nil end
end
function M.pre_physics(self)
    if not self.pos or self._is_dead or not self._room_start_ready then return end
    local s = state(self)
    if s.pending and not self._room_arrival then
        local pending = s.pending
        s.pending = nil
        if pending.lethal then repost(pending.contact) end
    end
    local Rooms = require "mvtk.map.streaming.room_manager"
    local room_id = Rooms.get_current_room()
    if s.zone and s.zone.room_id ~= room_id then s.zone = nil end
    if enabled() then lock_state(self,room_id) end
    local Contact = require "mvtk.hazards.hazard_contact"
    local cfg = Contact.settings()
    if not cfg.world_bottom_acts_as_pit or Rooms.get_room_for_position(self.pos) then return end
    local bounds = Rooms.get_room_bounds(room_id)
    if not bounds or self.pos.y >= bounds.min_y - 2*(self.collider_half_height or 0) then return end
    local types = require("mvtk.core.util").require_config("developer.config.hazard_types") or {}
    local mode, lethal = Contact.resolve(nil,false,types.void)
    if mode == "damage" then mode = "safe_return" end
    mode = Contact.effective(mode,true,cfg)
    contact(self,{mode=mode,lethal=true,return_damage=Contact.return_damage(-1,types.void,cfg),amount=9999})
end
return M
