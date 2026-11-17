-- mvtk/player/surface_effects.lua
-- Conveyor helpers and keyed environment push/lift channels. Zones track an
-- overlap set by other_id and post once per frame to PU.get_player_url(), never
-- to individual parts or the external_force accumulator. Contacts are stamped
-- counter + 1 and stay live while current - frame <= 2, like conveyors.

local M = {}

function M.note_contact(self, channel, key, data)
  if not self or not channel or key == nil or not data then return end
  self._env_contacts = self._env_contacts or {}
  local contacts = self._env_contacts[channel] or {}
  self._env_contacts[channel] = contacts
  contacts[tostring(key)] = {data = data, frame = (self._frame_counter or 0) + 1}
end

local function live_contacts(self, channel)
  local contacts = self and self._env_contacts and self._env_contacts[channel] or {}
  local current = self and self._frame_counter or 0
  for key, contact in pairs(contacts) do
    if current - contact.frame > 2 then contacts[key] = nil end
  end
  return contacts
end

function M.push(self)
  local vx, vy = 0, 0
  for _, contact in pairs(live_contacts(self, "push")) do
    vx = vx + (contact.data.vx or 0)
    vy = vy + (contact.data.vy or 0)
  end
  return vx, vy
end

function M.lift(self)
  local multiple, cap = 0, 0
  for _, contact in pairs(live_contacts(self, "lift")) do
    local data = contact.data
    local dir = data.dir or 0
    multiple = multiple + dir * (data.gravity_multiple or 0)
    local speed = data.max_rise_speed or 0
    if dir > 0 and speed > 0 and (cap == 0 or speed < cap) then cap = speed end
  end
  return multiple, cap
end

function M.clear_contacts(self)
  if self then self._env_contacts = nil end
end

function M.conveyor_vector(direction, speed)
  local vx, vy = 0, 0
  local spd = speed or 0
  if direction == "left" then
    vx = -spd
  elseif direction == "right" then
    vx = spd
  elseif direction == "up" then
    vy = spd
  elseif direction == "down" then
    vy = -spd
  end
  return vx, vy
end

function M.sum_conveyor_forces(self)
  local vx, vy = 0, 0
  if not self then return vx, vy end
  local contacts = self._conveyor_contacts
  local current_frame = self._frame_counter or 0
  local stale = {}
  if contacts then
    for sender, force in pairs(contacts) do
      local f_frame = force.frame or current_frame
      if (current_frame - f_frame) > 2 then
        stale[#stale + 1] = sender
      else
        vx = vx + (force.vx or 0)
        vy = vy + (force.vy or 0)
      end
    end
    if #stale > 0 then
      for i = 1, #stale do
        contacts[stale[i]] = nil
      end
    end
  end
  local push_x, push_y = M.push(self)
  vx, vy = vx + push_x, vy + push_y
  self._conveyor_force_x = vx
  self._conveyor_force_y = vy
  return vx, vy
end

return M
