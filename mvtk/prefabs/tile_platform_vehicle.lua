-- Loaded only by vehicle platforms. Engine integration stays outside the pure
-- simulation and the already crowded platform script.
local Vehicle = require "mvtk.world.path_vehicle"
local PU = require "mvtk.prefabs.prefab_utils"
local Util = require "mvtk.core.util"
local Bus = require "mvtk.world.trigger_bus"
local Switch = require "mvtk.world.switch_state"
local Timers = require "mvtk.player.timers"
local M = {}

function M.paused() return require("mvtk.core.pause").get() end

function M.init(self)
    self.vehicle_switch_on = false
    self.vehicle_riding = false
    if self.vehicle_switch_id ~= "" then
        self.vehicle_switch_url = msg.url(nil, go.get_id(), "vehicle_switch")
        Bus.register(self.vehicle_switch_id, self.vehicle_switch_url)
        Switch.replay(require("mvtk.core.flags"), self.vehicle_switch_id, function(on)
            self.vehicle_switch_on = on
        end)
    end
end

function M.resolve(self)
    if not self.waypoints or not self.tiles_ready then return false end
    local alt
    if self.vehicle_alt_path ~= "" then
        local Paths = require "mvtk.tiled.tiled_paths"
        local main = Paths.get_polyline(self.room_id, self.path_name)
        local second = Paths.get_polyline(self.room_id, self.vehicle_alt_path)
        if not main or not second or not second.polyline then return false end
        alt = {}
        local first = (main.polyline or main.polygon)[1]
        for i, p in ipairs(second.polyline) do
            alt[i] = {x=self.waypoints[1].x + second.x-main.x + p.x-first.x,
                y=self.waypoints[1].y + second.y-main.y - p.y+first.y}
        end
    end
    local config = {}
    for _, key in ipairs({"vehicle_control","vehicle_max_speed","vehicle_acceleration",
        "vehicle_brake","vehicle_drag","vehicle_end","vehicle_return_delay",
        "vehicle_float","vehicle_float_offset"}) do config[key] = self[key] end
    config.height = self.height
    config.gravity = require("developer.config.resolved_config").physics.gravity_y
    self.vehicle_state = Vehicle.new(self.waypoints, alt, config)
    return true
end

function M.has_rider(self)
    for url, info in pairs(self.passenger_carrier.passengers) do
        if not go.exists(url) then self.passenger_carrier:remove(url)
        elseif info.group == hash("player") then return true end
    end
    return false
end

function M.passengers_changed(self)
    if self.vehicle_control ~= "throttle" then return end
    local active = M.has_rider(self)
    if self.vehicle_riding == active then return end
    self.vehicle_riding = active
    local player = PU.get_player_url()
    if player then msg.post(player, "vehicle_ride", {active=active, walk=self.vehicle_rider_walks}) end
end

function M.visible(self, visible)
    tilemap.set_visible(self.platform_tilemap_url, "solid", visible)
    for _, component in ipairs({"co", "sensor"}) do
        Util.set_component_enabled(msg.url(self.vehicle_collision_id .. "#" .. component), visible, "mass")
    end
    if not visible then
        self.passenger_carrier:clear()
        M.passengers_changed(self)
    end
end

function M.update(self, dt, move_to)
    if not self.vehicle_state and not M.resolve(self) then return end
    local input = require("mvtk.rooms.input_controller").get_state()
    local pause = require "mvtk.core.pause"
    local scale = Timers.world_scale(dt, pause)
    local find_water
    if self.vehicle_float then
        local Water = require "mvtk.world.water_registry"
        local frame = pause.gameplay_frame and pause.gameplay_frame()
        local elapsed = Timers.world_delta(dt, scale)
        find_water = function(x, y)
            return Water.find_for_float(x, y, frame, elapsed, Timers.REFERENCE_STEP * scale)
        end
    end
    local x, y, events = Vehicle.step(self.vehicle_state, dt, {
        has_rider=M.has_rider(self), stick_x=input.move_x, stick_y=input.move_y,
        switch_on=self.vehicle_switch_on, paused=M.paused(),
        reference_scale=scale, find_water=find_water,
    })
    M.passengers_changed(self)
    local visibility = events.visibility
    local last
    if visibility then
        last = visibility[#visibility]
        for i = 1, #visibility - (last and 1 or 0) do M.visible(self, visibility[i]) end
    end
    move_to(self, vmath.vector3(x, y, self.start.z))
    if last then M.visible(self, true) end
end

function M.final(self)
    if self.vehicle_switch_url then Bus.unregister(self.vehicle_switch_id, self.vehicle_switch_url) end
    self.passenger_carrier:clear()
    M.passengers_changed(self)
end

return M
