-- Physical navigation shared by list menus and command-based legends.
local M = {}
local commands = { "confirm", "back", "close", "up", "down", "left", "right", "tab_prev", "tab_next", "pointer" }
local cached_settings, cached_revision

-- Shared read-only settings; callers that customize them must take a copy.
function M.settings()
  local RuntimeSettings = require "developer.config.runtime_settings"
  local revision = RuntimeSettings.revision and RuntimeSettings.revision()
  if revision == nil or cached_settings == nil or cached_revision ~= revision then
    cached_settings = RuntimeSettings.section("menu_settings", require "developer.config.menu_settings")
    cached_revision = revision
  end
  return cached_settings
end

function M.inputs(command, settings)
  return ((settings or M.settings()).navigation or {})[command] or {}
end

function M.matches(command, id, settings)
  if id == nil then return false end
  for _, name in ipairs(M.inputs(command, settings)) do
    if id == name or id == hash(name) then return true end
  end
  return false
end

function M.lifecycle(id)
  return id == "gamepad_connected" or id == "gamepad_disconnected"
    or id == hash("gamepad_connected") or id == hash("gamepad_disconnected")
end

function M.classify(id, settings)
  if M.lifecycle(id) then return nil end
  for _, command in ipairs(commands) do
    if M.matches(command, id, settings) then return command end
  end
end

function M.primary(command, settings)
  local out = {}
  for _, id in ipairs(M.inputs(command, settings)) do
    local kind = id:match("^gamepad_") and "pad" or "key"
    if not out[kind] then out[kind] = id end
  end
  return out
end

-- Older screens have a single Back/Close operation. Keep their Esc + face
-- button legend, derived from the same config as the list's separate commands.
function M.legacy_inputs(command, settings)
  local out = M.primary(command, settings)
  if command == "back" then out.key = M.primary("close", settings).key or out.key end
  return out
end

function M.legacy_matches(command, id, settings)
  return M.matches(command, id, settings) or (command == "back" and M.matches("close", id, settings))
end

-- A Close input that the older screens' Back legend does not show: every Close
-- input except the legend's keyboard key. Screens whose Back destroys something
-- (the death screen's Quit, the world map's marker delete) refuse these.
function M.unshown_close(id, settings)
  if M.matches("back", id, settings) or not M.matches("close", id, settings) then return false end
  local key = M.legacy_inputs("back", settings).key
  return key == nil or not (id == key or id == hash(key))
end

-- Hashes cannot be decoded in release builds. Recognize physical directions
-- independently of their configured menu command (including tab bindings).
local sticks = {}
for _, stick in ipairs({ "lstick", "rstick" }) do
  for direction, opposite in pairs({ up = "down", down = "up", left = "right", right = "left" }) do
    local name = "gamepad_" .. stick .. "_" .. direction
    local row = { name = name, opposite = "gamepad_" .. stick .. "_" .. opposite }
    sticks[name], sticks[hash(name)] = row, row
  end
end

-- Each menu owns a guard. The injected clock is for tests; runtime time keeps
-- advancing while gameplay is paused. Never use a gameplay dt for rebound.
function M.new_guard(settings, clock)
  local timing = (settings or M.settings()).list
  clock = clock or function() return socket.gettime() end
  local directions, blocked_until = {}, {}
  local guard = {}
  function guard.input(id, action)
    action = action or {}
    local row = sticks[id]
    if not row then return action.pressed == true, false end
    -- The stick's value decides. Defold's own stick press and release points
    -- sit near full tilt: an Xbox-style controller sent `released` at 0.80
    -- and then 0.70 on the way back, and treating that `released` as letting
    -- go fired every push twice. A pushed direction counts as let go only
    -- below the lower release threshold. The flags stand in for a missing value.
    local state = directions[row.name]
    local magnitude = tonumber(action.value) and math.abs(tonumber(action.value)) or nil
    local active
    if magnitude then
      -- Only a push that fired, or one held when the menu opened, keeps the lower
      -- release threshold; a rejected reversal must reach the press point again.
      local held = state and (state.fired or state.unarmed)
      active = magnitude > (held and timing.stick_release_threshold or timing.stick_press_threshold)
    else
      active = action.pressed == true or (state and state.active and not action.released) or false
    end
    if not state then
      state = { unarmed = active and not action.pressed }
      directions[row.name] = state
    end
    -- Defold sends `pressed` only for a fresh push, near full tilt, never for a
    -- stick already held: a fast first push whose first sample is past the
    -- press point is not a stick held at opening.
    if state.unarmed and action.pressed == true then state.unarmed = false end
    state.active = active
    if not active then
      if state.fired then blocked_until[row.opposite] = clock() + timing.stick_rebound_seconds end
      state.fired, state.unarmed = false, false
    elseif not state.unarmed and not state.fired then
      local deadline = blocked_until[row.name]
      if not deadline or clock() >= deadline then
        state.fired = true
        return true, true
      end
      -- Do not latch a rejected reversal: a still-held deliberate push can
      -- fire on the next continuous event after the rebound window expires.
    end
    return false, active
  end
  function guard.reset() directions, blocked_until = {}, {} end
  return guard
end

-- Legacy menus use native digital presses and own no repeat timer. Feed this
-- once at the start of on_input, before visibility/modal/arming early returns.
function M.pressed(menu, id, action)
  if not menu._menu_stick_guard then menu._menu_stick_guard = M.new_guard() end
  if M.lifecycle(id) then menu._menu_stick_guard.reset(); return false end
  return menu._menu_stick_guard.input(id, action)
end

function M.new(settings, clock)
  settings = settings or M.settings()
  local state = { held = {} }
  local timing = settings.list
  local guard = M.new_guard(settings, clock)
  function state.input(id, action, suppressed)
    action = action or {}
    local pressed, active = guard.input(id, action)
    if suppressed then state.held = {}; return nil end
    local command = M.classify(id, settings)
    if not command then return nil end
    local stick = sticks[id]
    local direction = command == "up" or command == "down" or command == "left" or command == "right"
    if stick then
      if not active then state.held[stick.name] = nil end
      if pressed then
        if direction then state.held[stick.name] = { command = command, time = timing.repeat_delay } end
        return command
      end
      return nil -- Native stick repeats must not duplicate the timer.
    end
    if pressed or (direction and action.repeated) then return command end
  end
  function state.update(dt)
    local out = {}
    for _, held in pairs(state.held) do
      held.time = held.time - dt
      while held.time <= 0 do
        out[#out + 1] = held.command
        held.time = held.time + math.max(0.01, timing.repeat_interval)
      end
    end
    return out
  end
  function state.reset() state.held = {}; guard.reset() end
  return state
end

return M
