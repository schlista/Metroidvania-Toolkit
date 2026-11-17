-- mvtk/core/pause.lua
-- Central pause/time-scale state for gameplay systems.
local M = {
  _paused = false,
  _hitstop_t = 0,
  _hitstop_scale = 1,
  _timescale = 1.0,
  _slowmo_t = 0,
  _system_timescale = nil,
  _proxy = nil,
  _speed_sources = {},
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

function M.hitstop(t)
  local dt = (tonumber(t) or 0) * M._hitstop_scale
  if dt > 0 then
    M._hitstop_t = math.max(M._hitstop_t or 0, dt)
    sync_effect_scale()
  end
end

-- Slow-motion: scales gameplay and engine time for a short real-time duration.
function M.start_slowmo(factor, duration)
  local f = tonumber(factor) or 1.0
  local t = tonumber(duration) or 0
  if t <= 0 or f >= 1.0 then
    return
  end
  if f < 0 then
    f = 0
  end
  M._timescale = math.min(M._timescale or 1.0, f)
  M._slowmo_t = math.max(M._slowmo_t or 0, t)
  sync_effect_scale()
end

function M.clear_slowmo()
  M._slowmo_t = 0
  M._timescale = 1.0
  sync_effect_scale()
end

function M.clear_hitstop()
  M._hitstop_t = 0
  sync_effect_scale()
end

function M.reset()
  M._paused = false
  M._hitstop_t = 0
  M._slowmo_t = 0
  M._timescale = 1.0
  for id, source in pairs(M._speed_sources) do
    if not source.persistent then M._speed_sources[id] = nil end
  end
  sync_effect_scale()
end

function M.update(dt, from_host)
  if M._proxy and not from_host then return end
  if (M._hitstop_t or 0) > 0 then
    M._hitstop_t = math.max(0, M._hitstop_t - dt)
  end
  if (M._slowmo_t or 0) > 0 then
    M._slowmo_t = math.max(0, M._slowmo_t - dt)
    if M._slowmo_t <= 0 then
      M.clear_slowmo()
    end
  end
  sync_effect_scale()
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

return M
