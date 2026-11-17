local M = {id="vehicle_ride", order=62, messages={vehicle_ride="any"}}

function M.on_message(self, message_id, message)
    if message_id ~= hash("vehicle_ride") then return false end
    local state = self._host.features.vehicle_ride
    state.active, state.walk = message.active == true, message.walk == true
    return true
end

function M.pre_physics(self, dt, input)
    local state = self._host.features.vehicle_ride
    if state.active and not state.walk then input.move_x = 0 end
end

function M.reset(self, reason)
    local state = self._host.features.vehicle_ride
    state.active, state.walk = false, false
end

M.init = M.reset
return M
