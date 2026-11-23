-- Loaded only by level-enabled water or hazards. Shape dimensions are scaled
-- from get_shape rather than assuming that the engine reports full/half extents.
local Level = require "mvtk.world.fluid_level"
local Art = require "mvtk.world.fluid_art_rows"
local Registry = require "mvtk.world.water_registry"
local SafeGround = require "mvtk.player.safe_ground"
local SwitchState = require "mvtk.world.switch_state"
local TriggerBus = require "mvtk.world.trigger_bus"
local Flags = require "mvtk.core.flags"
local PU = require "mvtk.prefabs.prefab_utils"
local Toggle = require "mvtk.prefabs.toggle_messages"
local Pause = require "mvtk.core.pause"
local M = {}
function M.publish(self, pos, height)
    Registry.update(go.get_id(), {room_id=self.room_id, left=pos.x-self.width/2,
        right=pos.x+self.width/2, bottom=pos.y-height/2, surface_y=self.surface_y,
        current_direction=self.current_direction, current_strength=self.current_strength})
end
local function resize(self, height)
    local r = self._fluid
    if height == r.height then return false end
    local ratio = height/r.baked_height
    physics.set_shape(r.component, r.shape, {type=physics.SHAPE_TYPE_BOX,
        dimensions=vmath.vector3(r.dimensions.x, r.dimensions.y*ratio, r.dimensions.z)})
    local pos = vmath.vector3(r.local_origin)
    pos.y = pos.y + (height-r.baked_height)/2
    go.set_position(pos)
    go.update_world_transform()
    local world = go.get_world_position()
    self.surface_y = world.y+height/2+(self.surface_y_offset or 0)
    SafeGround.register_blocker(go.get_id(), self, world, self.width, height, not r.hazard)
    if r.hazard then self.zone_height = height else M.publish(self, world, height) end
    for component, scale in pairs(r.scales) do
        go.set(component, "scale", vmath.vector3(scale.x, scale.y*ratio, scale.z))
    end
    r.height = height
    return true
end
local function apply_signal(self, on, snap)
    local r = self._fluid
    r.on, self._fluid_on = on, on
    if self.level_mode == "rise" then
        if on then Level.start_rise(r.rise) else r.reset = true end
        return
    end
    r.target = Level.target(r.baked_height, self.level_offset, self.tile_height, on)
    if snap then resize(self, r.target) end
end
function M.new(self, options)
    options = options or {}
    local world = go.get_world_position()
    local r = {baked_height=self.height, height=self.height, target=self.height, on=false,
        hazard=options.hazard, component=options.component or "#collisionobject", shape=options.shape or "volume",
        local_origin=go.get_position(), scales={}}
    r.dimensions=vmath.vector3(physics.get_shape(r.component, r.shape).dimensions)
    self._fluid = r
    if self._has_distortion then r.scales["#distortion"]=go.get("#distortion", "scale") end
    if self.show_sprite then r.scales["#sprite"]=go.get("#sprite", "scale") end
    local offset = self.level_mode == "rise" and self.rise_limit or self.level_offset
    r.art = Art.new(self, world, math.max(self.height,
        Level.target(self.height, offset, self.tile_height, true)))
    r.key = options.key or PU.resolve_id(self.water_id) or tostring(go.get_id())
    if not r.hazard then TriggerBus.register(r.key, msg.url()) end
    if self.level_mode == "rise" then
        r.rise = Level.new_rise()
        -- This hub can emit from a GUI context. Only the owning update may
        -- resize physics, move objects or touch tilemaps.
        local Events = require "mvtk.core.game_events"
        local function reset() r.reset = true end
        r.return_token = Events.on("hazard_return", reset)
        r.death_token = Events.on("player_died", reset)
    else
        SwitchState.replay(Flags, r.key, function(on, text)
            if text == "activate" or text == "enable" then on=true
            elseif text == "deactivate" or text == "disable" then on=false end
            apply_signal(self, on, true)
        end)
    end
    if not r.hazard then
        r.predict_surface = function(dt)
            local height = r.height
            if r.rise then
                local elapsed = r.rise.elapsed
                if r.reset then elapsed = 0
                elseif r.rise.running and not Pause.get() then elapsed = elapsed + dt end
                height = Level.rise(r.baked_height, self.rise_speed, self.rise_limit,
                    self.tile_height, self.rise_delay, elapsed)
            elseif not Pause.get() then
                height = Level.step(height, r.target, self.level_speed, dt)
            end
            return self.surface_y + height - r.height
        end
    end
    Art.apply(r.art, self.surface_y)
end
function M.on_message(self, id, message)
    if self.level_mode ~= "switch" and self.level_mode ~= "rise" then return false end
    -- RoomManager shows and hides a streamed room with a bare game-object "enable" or "disable", which
    -- reaches this script too. That is the room's visibility, not a switch: every switch signal carries
    -- its sender's payload (switch_core, plates, props, sockets, encounters).
    if (id == hash("enable") or id == hash("disable")) and (type(message) ~= "table" or next(message) == nil) then
        return false
    end
    if id == hash("activate") then apply_signal(self,true)
    elseif id == hash("deactivate") then apply_signal(self,false)
    elseif id == hash("toggle") then apply_signal(self,not self._fluid.on)
    else
        return Toggle.handle(self,id,message,function(owner,on) apply_signal(owner,on) end,
            {field="_fluid_on"})
    end
    self._fluid_on = self._fluid.on
    return true
end
function M.step(self, dt)
    local moved = false
    local r = self._fluid
    local before_surface = self.surface_y
    if self.level_mode == "rise" then
        if r.reset or not Pause.get() then
            local in_room = self.rise_start == "room_enter"
                and require("mvtk.map.streaming.room_manager").get_current_room() == self.room_id
            Level.step_rise(r.rise, r.reset and 0 or dt, in_room, r.reset)
            if r.reset then r.on, self._fluid_on = false, false end
            r.reset = nil
            moved = resize(self, Level.rise(r.baked_height, self.rise_speed, self.rise_limit,
                self.tile_height, self.rise_delay, r.rise.elapsed))
        end
    elseif not Pause.get() then
        moved = resize(self, Level.step(self._fluid.height, self._fluid.target, self.level_speed, dt))
    end
    Art.apply(self._fluid.art, self.surface_y)
    local frame = Pause.gameplay_frame and Pause.gameplay_frame()
    if frame and not r.hazard then
        local Timers = require "mvtk.player.timers"
        local scale = Timers.world_scale(dt, Pause)
        Registry.record_level(go.get_id(), frame, Timers.world_delta(dt, scale),
            Timers.REFERENCE_STEP * scale, before_surface, r.predict_surface)
    end
    return moved
end
function M.final(self)
    local r = self._fluid
    if r.rise then
        local Events = require "mvtk.core.game_events"
        Events.off(r.return_token)
        Events.off(r.death_token)
    end
    if not r.hazard then TriggerBus.unregister(r.key, msg.url()) end
end
return M
