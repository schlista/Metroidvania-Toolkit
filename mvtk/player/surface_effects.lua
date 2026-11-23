-- mvtk/player/surface_effects.lua
-- Conveyor helpers and keyed environment push/lift channels. Zones track an
-- overlap set by other_id and post once per frame to PU.get_player_url(), never
-- to individual parts or the external_force accumulator.

local Clock = require "mvtk.player.environment_clock"
local Pause = require "mvtk.core.pause"
local Timers = require "mvtk.player.timers"

local M = {}
local h = Timers.REFERENCE_STEP
local epsilon = 1e-9
-- A post is delivered after the update. It applies to the next interval and
-- the following two intervals if there is no renewal.
local contact_length = 3 * h
local channels = {"push", "lift", "conveyor"}
local empty = {}

local function add_span(spans, source, from, to, frame_start, frame_end)
  local start = math.max(from, frame_start)
  if math.min(to, frame_end) - start > epsilon then
    spans[#spans + 1] = {channel = source.channel, data = source.data, from = start, to = to}
  end
end

local function wind_spans(self, elapsed, step_dt)
  local winds = self._surface_winds
  if not winds then return end
  local from, to = self._surface_start, self._surface_elapsed
  local spans = {}
  for key, wind in pairs(winds) do
    local start, finish = from, wind.expiry or from
    Clock.advance(wind, elapsed, function(offset)
      if wind.enabled then wind.clock = wind.clock + step_dt end
      if wind.present and Clock.wind_blowing(wind) then
        local now = from + offset
        if now > finish + epsilon then
          add_span(spans, wind, start, finish, from, to)
          start = now
        end
        finish = now + contact_length
      end
    end)
    add_span(spans, wind, start, finish, from, to)
    wind.expiry = finish
    if not wind.present and finish <= to + epsilon then winds[key] = nil end
  end
  if #spans > 0 then
    self._wind_spans = spans
    for _, span in ipairs(spans) do
      if span.channel == "push" then
        self._surface_push_spans = true
        break
      end
    end
  end
end

function M.note_water(self, key, message)
  if key == nil or not message then return end
  self._water_currents = self._water_currents or {}
  local currents = self._water_currents
  key = tostring(key)
  local source = currents[key]
  if message.entering then
    source = source or {
      step_left = message.step_left, timer = message.timer, started = message.reported_late,
    }
    source.x, source.y = message.x, message.y
    source.draw_left = nil
    currents[key] = source
  elseif source and message.draw_left then
    source.draw_left = message.draw_left
  else
    currents[key] = nil
  end
end

local function active_water_duration(source, elapsed, step_dt)
  if source.started then return elapsed end
  local duration = 0
  Clock.advance(source, elapsed, function(offset)
    if source.started then return end
    if source.pending then
      source.started = true
      duration = elapsed - offset
    else
      source.pending = Clock.water_tick(source, step_dt)
    end
  end)
  return duration
end

function M.advance(self, dt, pause)
  pause = pause or Pause
  if pause.get and pause.get() then return end
  local elapsed, step_dt, reference = Clock.frame(dt)
  self._surface_start = self._surface_elapsed or 0
  self._surface_elapsed = self._surface_start + elapsed
  self._wind_spans = nil
  self._surface_push_spans = nil
  self._surface_ignore_push = nil
  local reference_phase = self._surface_start / h
  self._surface_reference_update = reference
    and math.abs(reference_phase - math.floor(reference_phase + .5)) <= epsilon
  wind_spans(self, elapsed, step_dt)
  M.discard_water(self)
  if not self._water_currents or elapsed <= 0 then return end
  for key, source in pairs(self._water_currents) do
    local active = active_water_duration(source, elapsed, step_dt)
    if source.draw_left then
      -- Finish through the already queued deadline at the same drift speed.
      source.draw_left = source.draw_left - elapsed
      if source.draw_left <= epsilon then
        active = math.max(0, active + math.min(0, source.draw_left))
        self._water_currents[key] = nil
      end
    end
    local fraction = active / elapsed
    if fraction > 0 then
      self._water_x = (self._water_x or 0) + source.x * fraction
      self._water_y = (self._water_y or 0) + source.y * fraction
    end
  end
end

function M.discard_water(self)
  self._water_x, self._water_y = nil, nil
end

function M.clear_water(self)
  self._water_currents = nil
  M.discard_water(self)
end

function M.suppress_push(self)
  self._surface_ignore_push = true
  M.discard_water(self)
end

function M.water_travel(self, dt)
  -- Travel goes through ordinary collision resolution without feeding the
  -- current back into swimming, jump cuts or the player's own velocity.
  if dt > 0 and self._water_x and self._water_x ~= 0 then
    self._move_dx_correction = (self._move_dx_correction or 0) + self._water_x * dt
  end
  if dt > 0 and self._water_y and self._water_y ~= 0 then
    self._move_dy_correction = (self._move_dy_correction or 0) + self._water_y * dt
  end
end

function M.note_contact(self, channel, key, data)
  if not self or not channel or key == nil or not data then return end
  if type(data.wind) == "table" then
    self._surface_winds = self._surface_winds or {}
    local phase = data.wind
    key = tostring(key)
    local previous = self._surface_winds[key]
    if phase.present or previous then
      phase.channel = channel
      phase.data = {vx = data.vx, vy = data.vy, dir = data.dir,
        max_rise_speed = data.max_rise_speed, gravity_multiple = data.gravity_multiple}
      phase.expiry = previous and previous.expiry
      self._surface_winds[key] = phase
    end
    return
  end
  self._env_contacts = self._env_contacts or {}
  local contacts = self._env_contacts[channel] or {}
  self._env_contacts[channel] = contacts
  contacts[tostring(key)] = {
    data = data, expires = (self._surface_elapsed or 0) + contact_length,
  }
end

function M.note_conveyor(self, sender, vx, vy, overlap)
  self._conveyor_contacts = self._conveyor_contacts or {}
  local contact = {vx = vx, vy = vy}
  if not overlap then contact.expires = (self._surface_elapsed or 0) + contact_length end
  self._conveyor_contacts[sender] = contact
end

function M.end_conveyor(self, sender, grace)
  local contacts = self._conveyor_contacts
  if not contacts or not contacts[sender] then return end
  if grace then
    contacts[sender].expires = (self._surface_elapsed or 0) + contact_length
  else
    contacts[sender] = nil
  end
end

local function contact_available(contact, now)
  return not contact.expires or contact.expires > now + epsilon
end

local function sum_lift(multiple, cap, data)
  local dir = data.dir or 0
  local speed = data.max_rise_speed or 0
  multiple = multiple + dir * (data.gravity_multiple or 0)
  if dir > 0 and speed > 0 and (cap == 0 or speed < cap) then cap = speed end
  return multiple, cap
end

local function effects_at(self, now, span_list, exclude_conveyor)
  local vx, vy, multiple, cap = 0, 0, 0, 0
  local next_edge = math.huge
  local contacts = self._env_contacts
  for _, kind in ipairs(channels) do
    local list = kind == "conveyor" and self._conveyor_contacts or contacts and contacts[kind]
    if list and (kind ~= "conveyor" or not exclude_conveyor) then
      for key, contact in pairs(list) do
        if contact_available(contact, now) then
          local data = contact.data or contact
          if kind == "lift" then
            multiple, cap = sum_lift(multiple, cap, data)
          else
            vx, vy = vx + (data.vx or 0), vy + (data.vy or 0)
          end
          next_edge = math.min(next_edge, contact.expires or math.huge)
        elseif contact.expires and contact.expires <= (self._surface_start or 0) + epsilon then
          list[key] = nil
        end
      end
    end
  end
  for _, span in ipairs(span_list or empty) do
    if span.from > now + epsilon then
      next_edge = math.min(next_edge, span.from)
    elseif span.to > now + epsilon then
      if span.channel == "lift" then
        multiple, cap = sum_lift(multiple, cap, span.data)
      elseif not self._surface_ignore_push then
        vx, vy = vx + (span.data.vx or 0), vy + (span.data.vy or 0)
      end
      next_edge = math.min(next_edge, span.to)
    end
  end
  return vx, vy, multiple, cap, next_edge
end

-- Time offsets passed by movement are in the player's scaled space.
function M.at(self, offset)
  if not self then return 0, 0, 0, 0, math.huge end
  if not self._env_contacts and not self._wind_spans and not next(self._conveyor_contacts or empty) then
    return 0, 0, 0, 0, math.huge
  end
  local from = self._surface_start or 0
  if not self._surface_dt then
    local x, y, multiple, cap = effects_at(self, from, self._wind_spans)
    return x, y, multiple, cap, math.huge
  end
  local elapsed = (self._surface_elapsed or from) - from
  local scale = self._surface_dt and self._surface_dt > 0 and elapsed / self._surface_dt
  scale = scale and scale > 0 and scale or 1
  local now = from + offset * scale
  local x, y, multiple, cap, edge = effects_at(self, now, self._wind_spans)
  return x, y, multiple, cap, (edge - now) / scale
end

function M.prepare(self, dt)
  self._surface_dt = dt
  self._surface_horizontal_offset = 0
  self._surface_vertical_travel = nil
  if self._surface_reference_update then
    local _, _, _, _, edge = M.at(self, 0)
    if edge < dt - epsilon then self._surface_reference_update = false end
  end
end

-- The old player callback counter did not advance during a menu pause or
-- a room-arrival update. Preserve that clock for player-owned grace.
function M.advance_player_grace(self)
  local elapsed = (self._surface_elapsed or 0) - (self._surface_start or 0)
  self._surface_active_elapsed = (self._surface_active_elapsed or 0) + elapsed
end

function M.horizontal_step(self, offset)
  local from = self._surface_start or 0
  local raw = (self._surface_elapsed or from) - from
  local dt = self._surface_dt
  if not dt or dt <= 0 or raw <= 0 then return h end
  local now = from + offset * raw / dt
  local finish = (math.floor((now + epsilon) / h) + 1) * h
  return (finish - now) * dt / raw
end

function M.horizontal_active(self, raw)
  if self._surface_reference_update or not self._surface_dt or self._surface_dt <= 0 then return false end
  local active = self._surface_push_spans
    or next(self._conveyor_contacts or empty)
    or next(self._env_contacts and self._env_contacts.push or empty)
  if active then return true end
  if raw and raw ~= 0 then self._surface_horizontal_tail = nil end
  return self._surface_horizontal_tail
end

function M.push_travel(self, dt, start_x, start_y)
  if self._surface_reference_update or dt <= 0 or not M.horizontal_active(self) then return end
  local offset, extra_x, extra_y = 0, 0, 0
  while offset < dt - epsilon do
    local x, y, _, _, edge = M.at(self, offset)
    local piece = math.min(dt - offset, edge)
    if self._surface_horizontal_offset == 0 then extra_x = extra_x + (x - start_x) * piece end
    if not self._surface_vertical_travel then extra_y = extra_y + (y - start_y) * piece end
    offset = offset + piece
  end
  if extra_x ~= 0 then self._move_dx_correction = (self._move_dx_correction or 0) + extra_x end
  if extra_y ~= 0 then self._move_dy_correction = (self._move_dy_correction or 0) + extra_y end
end

function M.push(self)
  if not self then return 0, 0 end
  local x, y = effects_at(self, self._surface_start or 0, self._wind_spans, true)
  return x, y
end

function M.lift(self)
  local _, _, multiple, cap = M.at(self, 0)
  return multiple, cap
end

function M.clear_contacts(self)
  if self then
    self._env_contacts, self._wind_spans = nil, nil
    self._water_rounding_x, self._water_rounding_y = nil, nil
    for _, wind in pairs(self._surface_winds or empty) do wind.expiry = nil end
  end
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
  if not self then return 0, 0 end
  local vx, vy = M.at(self, 0)
  self._conveyor_force_x = vx
  self._conveyor_force_y = vy
  return vx, vy
end

return M
