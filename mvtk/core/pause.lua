-- mvtk/core/pause.lua
-- Central pause/time-scale state for gameplay systems.
local Timers
local M = {
  _paused = false,
  _hitstop_t = 0,
  _hitstop_scale = 1,
  _timescale = 1.0,
  _slowmo_t = 0,
  _system_timescale = nil,
  _proxy = nil,
  _speed_sources = {},
  _effect_starts = {},
}

local function apply_system_timescale(factor)
  local f = tonumber(factor) or 1.0
  if not M._proxy or M._system_timescale == f then
    return
  end
  M._system_timescale = f
  if msg and msg.post then
    msg.post(M._proxy, "set_time_step", { factor = f, mode = 0 })
  end
end

local function sync_effect_scale()
  -- Menus share the collection, so their animations need normal engine time.
  apply_system_timescale(M._paused and 1 or M.scale())
end

-- Named factors compose independently; each owner replaces its own entry.
function M.speed_factor()
  local factor = 1
  for _, source in pairs(M._speed_sources) do
    factor = factor * source.factor
  end
  return factor
end

-- nil or 1 removes a source. Persistent entries survive a session reset.
function M.set_speed_factor(source, factor, persistent)
  local f = tonumber(factor) or 1
  if f ~= f then f = 1 end
  if f == 1 then
    M._speed_sources[source] = nil
  else
    M._speed_sources[source] = {
      factor = math.max(0.1, math.min(4, f)),
      persistent = persistent and true or false,
    }
  end
  sync_effect_scale()
end

-- The boot collection drives recovery with unscaled time. Collection effect
-- scaling covers physics, timers and animations; scripts must not multiply twice.
function M.bind_proxy(url)
  if M._proxy then apply_system_timescale(1) end
  M._proxy = url
  M._system_timescale = nil
  M._proxy_frame_scale = nil
  if url then sync_effect_scale() end
end

function M.set(v)
  M._paused = v and true or false
  sync_effect_scale()
end
function M.get() return M._paused end
-- Retry cadence for due callbacks while menus keep the collection running.
-- This is scheduler precision, not a gameplay duration.
M.PAUSE_POLL = 0.1

-- One-shot in the calling script's context. Defold destroys its timers with
-- the script. A due callback waits out menu pause; elapsed pause still counts.
function M.delay(seconds, fn)
  local function fire(...)
    if M.get() then
      timer.delay(M.PAUSE_POLL, false, fire)
      return
    end
    return fn(...)
  end
  return timer.delay(seconds, false, fire)
end
function M.is_hitstopped() return (M._hitstop_t or 0) > 0 end
function M.hitstop_remaining() return M._hitstop_t or 0 end

-- Hitstop: freeze the gameplay collection for t seconds of real time.
function M.set_hitstop_scale(f)
  M._hitstop_scale = math.max(0, math.min(1, tonumber(f) or 1))
end

local function begin_effect(field, seconds, timing)
  M._effect_starts[field] = timing and true or nil
  if timing then
    Timers = timing
    Timers.start_combat_window(M, field, seconds)
  else
    if Timers then Timers.discard_window(M, field) end
    M[field] = seconds
  end
end

function M.hitstop(t, timing, preserve_short_impact, after_impact)
  local dt = (tonumber(t) or 0) * M._hitstop_scale
  if after_impact then
    local steps = math.floor(dt / timing.engine_reference_step() + 0.5)
    dt = steps * timing.REFERENCE_STEP
  end
  local current = M._hitstop_t or 0
  local duration = math.max(dt, current)
  local preserve = preserve_short_impact and timing and M._hitstop_scale == 1
    and dt > 0 and duration <= timing.engine_reference_step()
  if dt > current or preserve then
    begin_effect("_hitstop_t", duration, timing)
    if preserve or after_impact then
      M._effect_starts._hitstop_t = "after_impact"
    end
    sync_effect_scale()
  end
end

-- Slow-motion: scales gameplay and engine time for a short real-time duration.
function M.start_slowmo(factor, duration, timing)
  local f = tonumber(factor) or 1.0
  local t = tonumber(duration) or 0
  if t <= 0 or f >= 1.0 then
    return
  end
  if f < 0 then
    f = 0
  end
  M._timescale = math.min(M._timescale or 1.0, f)
  if t > (M._slowmo_t or 0) then begin_effect("_slowmo_t", t, timing) end
  sync_effect_scale()
end

function M.clear_slowmo()
  if Timers then Timers.clear_window(M, "_slowmo_t") else M._slowmo_t = 0 end
  M._effect_starts._slowmo_t = nil
  M._timescale = 1.0
  sync_effect_scale()
end

function M.clear_hitstop()
  if Timers then Timers.clear_window(M, "_hitstop_t") else M._hitstop_t = 0 end
  M._effect_starts._hitstop_t = nil
  sync_effect_scale()
end

function M.reset()
  M._paused = false
  M._hitstop_t = 0
  M._slowmo_t = 0
  if Timers then
    Timers.discard_window(M, "_hitstop_t")
    Timers.discard_window(M, "_slowmo_t")
  end
  M._effect_starts = {}
  M._timescale = 1.0
  for id, source in pairs(M._speed_sources) do
    if not source.persistent then M._speed_sources[id] = nil end
  end
  sync_effect_scale()
end

local function tick_effect(field, dt)
  if not Timers or not Timers.has_window(M, field) then
    M[field] = math.max(0, M[field] - dt)
    return
  end
  if M._effect_starts[field] and dt > 0 then
    local start = M._effect_starts[field]
    M._effect_starts[field] = nil
    -- The impact draw has already simulated. Full-duration freezes and short
    -- player-shot freezes start spending time on the next draw.
    if start == "after_impact" then return end
    -- The host counts the draw on which the player requested the effect.
    -- That draw's proxy has already simulated, so debit one reference step.
    if not Timers.combat_reference_frame(dt, 1) then
      if M[field] <= Timers.engine_reference_step() then
        Timers.clear_window(M, field)
      else
        Timers.start_combat_window(M, field, M[field], Timers.REFERENCE_STEP)
      end
      return
    end
  end
  Timers.tick_combat_deadline(M, field, dt, 1)
end

function M.update(dt, from_host)
  if M._proxy and not from_host then return end
  if (M._hitstop_t or 0) > 0 then
    tick_effect("_hitstop_t", dt)
  end
  if (M._slowmo_t or 0) > 0 then
    tick_effect("_slowmo_t", dt)
    if M._slowmo_t <= 0 then
      M.clear_slowmo()
    end
  end
  sync_effect_scale()
  if from_host and M._proxy then
    -- The proxy runs before this script. Its scale for the next update is
    -- the last one requested here, including requests from the child world.
    M._proxy_frame_scale = M._system_timescale
    M._gameplay_frame = (M._gameplay_frame or 0) + 1
  end
end

-- The parent updates the gameplay proxy as a unit. All of its scripts see
-- the same serial, including when gameplay dt is zero.
function M.gameplay_frame()
  if M._proxy then return M._gameplay_frame or 0 end
end

function M.scale()
  if M._paused then return 0 end
  if (M._hitstop_t or 0) > 0 then return 0 end
  return (M._timescale or 1.0) * M.speed_factor()
end

-- Menu pause remains a gameplay-script gate: menus share the game collection.
-- Hitstop/slowmo dt already arrives scaled when the boot proxy is bound.
function M.dt_scale()
  if M._paused then return 0 end
  return M._proxy and 1 or M.scale()
end

-- With a boot proxy, gameplay receives a delta the engine already scaled.
-- Without one, gameplay scripts apply dt_scale() themselves.
function M.proxy_frame_scale(dt)
  if not M._proxy then return end
  local scale = M._proxy_frame_scale or M._system_timescale or 1
  if scale == 0 and dt > 0 then return M._system_timescale or 1 end
  return scale
end

return M
