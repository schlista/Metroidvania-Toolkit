-- mvtk/rooms/input_controller.lua
-- Unified keyboard and Defold 1.13.2+ SDL game-controller input.

local Util = require "mvtk.core.util"
local RuntimeSettings = require "developer.config.runtime_settings"
local PS = RuntimeSettings.get_player_settings()
local Bindings = require "mvtk.core.input_bindings"
local Debug = Util.require_config("developer.config.debug_config")
local C = require "mvtk.core.constants"
local TutorialPopups = require "mvtk.ui.tutorial_popups"
local ACTION_ROWS = require "mvtk.rooms.input_actions"

local M = {}
local hud_covers = {}

-- Scenes that draw over HUD controls own an entry for their visible lifetime,
-- including closing fades. This is separate from gameplay blocking: dialogue
-- and the death screen block gameplay while leaving the Menu button visible.
function M.set_hud_covered(owner, covered)
  hud_covers[owner] = covered and true or nil
end

function M.is_hud_covered()
  return next(hud_covers) ~= nil
end

local function debug_enabled()
  return (Debug.global and Debug.global.enable)
    or (Debug.gameplay and Debug.gameplay.input)
end

local input_log = Util.make_debug_log("[INPUT]", debug_enabled)

local KEYBOARD_DIRECTIONS = {
  [hash("key_left")] = "left",
  [hash("key_a")] = "left",
  [hash("key_right")] = "right",
  [hash("key_d")] = "right",
  [hash("key_up")] = "up",
  [hash("key_w")] = "up",
  [hash("key_down")] = "down",
  [hash("key_s")] = "down",
}

M.input_state = { move_x = 0, move_y = 0, left_mag = 0, camera_y = 0 }

local sources = {
  digital = { left = {}, right = {}, up = {}, down = {} },
  left_stick = { left = 0, right = 0, up = 0, down = 0 },
  camera = { up = 0, down = 0 },
}

local held_sources, EDGE_FIELDS = {}, {}
local edge_fields_seen = {}
for _, row in ipairs(ACTION_ROWS) do
  for _, field in ipairs({ row.down or false, row.up or false, row.tap or false, row.hold or false }) do
    if field and not edge_fields_seen[field] then
      edge_fields_seen[field] = true
      EDGE_FIELDS[#EDGE_FIELDS + 1] = field
      M.input_state[field] = false
    end
  end
  if row.held then
    M.input_state[row.held] = false
    held_sources[row.held] = { keyboard = {}, gamepads = {} }
  end
end

-- Pending holds are per physical source, just like held bookkeeping. They
-- exist only for rows with hold variants; no timing lookup occurs at load.
local pending_holds = {}

local edge_sources = {}
for _, field in ipairs(EDGE_FIELDS) do
  edge_sources[field] = { keyboard = false, gamepads = {} }
end

local controllers = {}
local active_gamepad = nil
local last_device = nil
local DEVICE_LIFECYCLE = { [hash("gamepad_connected")] = true, [hash("gamepad_disconnected")] = true }
local DEVICE_STICKS = {}
for _, direction in ipairs({ "left", "right", "up", "down" }) do
  DEVICE_STICKS[hash("gamepad_lstick_" .. direction)] = "left"
  DEVICE_STICKS[hash("gamepad_rstick_" .. direction)] = "right"
end
local UI_BLOCK = false
local block_generation = 0
local CFG = nil

local function reset_frame_flags(state)
  for field, source in pairs(edge_sources) do
    source.keyboard = false
    source.gamepads = {}
    state[field] = false
  end
end

local function clear_axis_sources()
  local digital = sources.digital
  digital.left, digital.right, digital.up, digital.down = {}, {}, {}, {}
  local stick = sources.left_stick
  stick.left, stick.right, stick.up, stick.down = 0, 0, 0, 0
  sources.camera.up, sources.camera.down = 0, 0
end

local function direction_active(direction_sources)
  return next(direction_sources) ~= nil
end

local function signed_axis(negative_digital, positive_digital, negative_analog, positive_analog)
  local digital = (positive_digital and 1 or 0) - (negative_digital and 1 or 0)
  local analog = (positive_analog or 0) - (negative_analog or 0)
  if math.abs(digital) >= math.abs(analog) then return digital end
  return analog
end

local function refresh_axes()
  local state = M.input_state
  local digital = sources.digital
  local stick = sources.left_stick
  state.move_x = signed_axis(
    direction_active(digital.left),
    direction_active(digital.right),
    stick.left,
    stick.right
  )
  state.move_y = signed_axis(
    direction_active(digital.down),
    direction_active(digital.up),
    stick.down,
    stick.up
  )
  state.camera_y = (sources.camera.up or 0) - (sources.camera.down or 0)
  state.left_mag = math.min(1, math.sqrt(state.move_x * state.move_x + state.move_y * state.move_y))
end

local function action_magnitude(action)
  if action.released then return 0 end
  local value = math.abs(tonumber(action.value) or 0)
  if value == 0 and action.pressed then value = 1 end
  return math.min(1, value)
end

local function copy_table(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end

local function controller_is_selectable(record)
  return record ~= nil and record.unknown ~= true
end

local function remember_controller(action)
  local index = tonumber(action and action.gamepad)
  if index == nil then return nil end
  local existing = controllers[index] or { index = index }
  if action.gamepad_name ~= nil then existing.name = action.gamepad_name end
  if action.gamepad_guid ~= nil then existing.guid = action.gamepad_guid end
  if action.gamepad_guid_info ~= nil then
    existing.guid_info = copy_table(action.gamepad_guid_info)
  end
  if action.userid ~= nil then existing.userid = action.userid end
  if action.gamepad_unknown ~= nil then
    existing.unknown = action.gamepad_unknown and true or false
  end
  controllers[index] = existing
  if active_gamepad == nil and controller_is_selectable(existing) then
    active_gamepad = index
  end
  return index
end

local function first_connected_gamepad()
  local first = nil
  for index, record in pairs(controllers) do
    if controller_is_selectable(record) and (first == nil or index < first) then
      first = index
    end
  end
  return first
end

local function refresh_held_state(field)
  local source = held_sources[field]
  local held = next(source.keyboard) ~= nil
  if not held then
    for _, inputs in pairs(source.gamepads) do
      if next(inputs) ~= nil then
        held = true
        break
      end
    end
  end
  M.input_state[field] = held and true or false
end

local function set_held_state(field, action_id, action, held)
  local source = held_sources[field]
  local index = tonumber(action and action.gamepad)
  if index == nil then
    source.keyboard[action_id] = held and true or nil
  else
    local inputs = source.gamepads[index]
    if held then
      inputs = inputs or {}
      inputs[action_id] = true
      source.gamepads[index] = inputs
    elseif inputs then
      inputs[action_id] = nil
      if next(inputs) == nil then source.gamepads[index] = nil end
    end
  end
  refresh_held_state(field)
end

local function clear_held_state(include_keyboard)
  for field, source in pairs(held_sources) do
    if include_keyboard then source.keyboard = {} end
    source.gamepads = {}
    refresh_held_state(field)
  end
end

local function refresh_edge_state(field)
  local source = edge_sources[field]
  local active = source.keyboard
  if not active then
    for _, gamepad_edge in pairs(source.gamepads) do
      if gamepad_edge then
        active = true
        break
      end
    end
  end
  M.input_state[field] = active and true or false
end

local function set_edge_state(field, action)
  local source = edge_sources[field]
  local index = tonumber(action and action.gamepad)
  if index == nil then
    source.keyboard = true
  else
    source.gamepads[index] = true
  end
  M.input_state[field] = true
end

local function clear_edge_state(include_keyboard)
  for field, source in pairs(edge_sources) do
    if include_keyboard then source.keyboard = false end
    source.gamepads = {}
    refresh_edge_state(field)
  end
end

local function clear_gamepad_state()
  for row, pending in pairs(pending_holds) do
    for key, hold in pairs(pending) do
      if hold.action.gamepad ~= nil then pending[key] = nil end
    end
    if next(pending) == nil then pending_holds[row] = nil end
  end
  local stick = sources.left_stick
  stick.left, stick.right, stick.up, stick.down = 0, 0, 0, 0
  sources.camera.up, sources.camera.down = 0, 0
  clear_held_state(false)
  clear_edge_state(false)
  refresh_axes()
end

local function handle_gamepad_lifecycle(action_id, action)
  if action_id == C.INPUT.GAMEPAD_CONNECTED then
    local index = remember_controller(action)
    if index ~= nil then
      local record = controllers[index]
      input_log(string.format(
        "[INPUT] gamepad %d connected: %s%s",
        index,
        tostring(record.name or record.guid or "unknown controller"),
        record.unknown and " (unmapped)" or ""
      ))
    end
    return true
  end

  if action_id == C.INPUT.GAMEPAD_DISCONNECTED then
    local index = tonumber(action and action.gamepad)
    if index ~= nil then
      controllers[index] = nil
      if active_gamepad == index then
        if last_device == "gamepad" and M.on_active_gamepad_lost then
          M.on_active_gamepad_lost(index)
        end
        clear_gamepad_state()
        active_gamepad = first_connected_gamepad()
      end
      input_log(string.format("[INPUT] gamepad %d disconnected", index))
    end
    return true
  end

  return false
end

function M.accepts_gamepad(action)
  local index = tonumber(action and action.gamepad)
  if index == nil then return true end
  remember_controller(action)
  return index == active_gamepad
end

function M.get_active_gamepad()
  return active_gamepad
end

-- Menus that consume input report it here too. Device identity comes from
-- action.gamepad, not a binding name; controller index zero is valid.
function M.note_device(action_id, action)
  if not action_id or not action or DEVICE_LIFECYCLE[action_id] then return end
  if not M.accepts_gamepad(action) then return end
  if action.gamepad ~= nil then
    local stick = DEVICE_STICKS[action_id]
    if stick then
      if stick == "left" and not action.released and math.abs(tonumber(action.value) or 0) > 0.5 then
        last_device = "gamepad"
      end
    elseif action.pressed then
      last_device = "gamepad"
    end
  elseif action.pressed then
    last_device = "keyboard"
  end
end

function M.get_last_device()
  return last_device or (active_gamepad ~= nil and "gamepad" or "keyboard")
end

function M.set_active_gamepad(index)
  if index == nil then
    clear_gamepad_state()
    active_gamepad = nil
    return true
  end
  index = tonumber(index)
  if index == nil or not controller_is_selectable(controllers[index]) then return false end
  if active_gamepad ~= index then clear_gamepad_state() end
  active_gamepad = index
  return true
end

function M.get_connected_gamepads()
  local out = {}
  for index, record in pairs(controllers) do
    out[#out + 1] = {
      index = index,
      name = record.name,
      guid = record.guid,
      guid_info = copy_table(record.guid_info),
      userid = record.userid,
      unknown = record.unknown and true or false,
      active = index == active_gamepad,
    }
  end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

function M.reset_controllers()
  controllers = {}
  active_gamepad = nil
  clear_gamepad_state()
end

function M.clear_all()
  pending_holds = {}
  local state = M.input_state
  clear_axis_sources()
  reset_frame_flags(state)
  clear_held_state(true)
  state.move_x, state.move_y, state.left_mag = 0, 0, 0
  state.camera_y = 0
end

-- Only named nonpausing readers may hand off to Pause on focus loss.
function M.get_auto_pause_screen() return M._auto_pause_screen end

function M.set_blocked(blocked, auto_pause_screen)
  local next_state = blocked and true or false
  if next_state and not UI_BLOCK then block_generation = block_generation + 1 end
  if UI_BLOCK ~= next_state and debug_enabled() then
    input_log(string.format("[INPUT] set_blocked -> %s", tostring(next_state)))
  end
  UI_BLOCK = next_state
  M._auto_pause_screen = next_state and auto_pause_screen or nil
  if UI_BLOCK then M.clear_all() end
end

function M.get_blocked()
  return UI_BLOCK
end

-- Monotonic across sessions: gameplay may miss an entire blocked interval.
function M.block_generation() return block_generation end

-- The module outlives the game proxy. A screen that blocked input and was torn
-- down by Quit to title never clears its block, so each session starts clean.
-- Connected controllers stay known; only blocks and held input are dropped.
function M.reset_session()
  M.set_blocked(false)
  M.clear_all()
end

function M.set_config(config)
  CFG = config
end

function M.begin_frame()
  reset_frame_flags(M.input_state)
end

local function set_digital_direction(action_id, action)
  local digital = sources.digital
  local name = KEYBOARD_DIRECTIONS[action_id]
  if not name then return false end
  if action.pressed then digital[name][action_id] = true end
  if action.released then digital[name][action_id] = nil end
  refresh_axes()
  return true
end

local function set_left_stick_direction(action_id, action)
  local stick = sources.left_stick
  local name = nil
  if action_id == C.INPUT.GAMEPAD_LSTICK_LEFT then name = "left"
  elseif action_id == C.INPUT.GAMEPAD_LSTICK_RIGHT then name = "right"
  elseif action_id == C.INPUT.GAMEPAD_LSTICK_UP then name = "up"
  elseif action_id == C.INPUT.GAMEPAD_LSTICK_DOWN then name = "down"
  end
  if not name then return false end
  stick[name] = action_magnitude(action)
  refresh_axes()
  return true
end

local function post_action(row)
  if row.event then TutorialPopups.on_event(row.event) end
  if row.post then
    pcall(msg.post, msg.url(row.post.url), hash(row.post.message), row.post.payload or {})
  end
end

local function hold_key(action_id, action)
  return tostring(action.gamepad == nil and "keyboard" or action.gamepad) .. ":" .. tostring(action_id)
end

local function dispatch_row(row, action_id, action)
  if action.pressed then
    if row.down then set_edge_state(row.down, action) end
    if row.held then set_held_state(row.held, action_id, action, true) end
    post_action(row)
    if row.hold then
      local pending = pending_holds[row] or {}
      pending_holds[row] = pending
      local key = hold_key(action_id, action)
      -- Repeat presses do not restart a hold that is already in progress.
      if not pending[key] then
        local seconds = (Bindings.hold_seconds and Bindings.hold_seconds(row.action)) or row.hold_seconds
        assert(type(seconds) == "number" and seconds > 0, "Hold row needs a threshold: " .. row.action)
        pending[key] = { elapsed = 0, fired = false, action = { gamepad = action.gamepad }, seconds = seconds }
      end
    end
  end
  if action.released then
    if row.up then set_edge_state(row.up, action) end
    if row.held then set_held_state(row.held, action_id, action, false) end
    local pending = pending_holds[row]
    local key = hold_key(action_id, action)
    local hold = pending and pending[key]
    if hold then
      if not hold.fired and row.tap then set_edge_state(row.tap, action) end
      pending[key] = nil
      if next(pending) == nil then pending_holds[row] = nil end
    end
  end
end

function M.on_input(action_id, action)
  action = action or {}

  -- Lifecycle events must be processed even while a UI blocks gameplay.
  if handle_gamepad_lifecycle(action_id, action) then return false end
  if not M.accepts_gamepad(action) then return false end

  M.note_device(action_id, action)

  -- Pause and settings remain available while another UI owns gameplay input.
  for _, row in ipairs(ACTION_ROWS) do
    if row.unblocked and action.pressed and Bindings.is(row.action, action_id) then
      dispatch_row(row, action_id, action)
      return false
    end
  end
  if M.get_blocked() then return false end

  if action.pressed and debug_enabled() then
    local labels = {}
    if KEYBOARD_DIRECTIONS[action_id] == "up" or action_id == C.INPUT.GAMEPAD_LSTICK_UP then labels[#labels + 1] = "UP" end
    for _, row in ipairs(ACTION_ROWS) do
      if not row.unblocked and not row.axis and Bindings.is(row.action, action_id) then
        labels[#labels + 1] = row.action
      end
    end
    if #labels > 0 then
      input_log(string.format("[INPUT] pressed id=%s -> %s", tostring(action_id), table.concat(labels, ",")))
    end
  end

  set_digital_direction(action_id, action)
  set_left_stick_direction(action_id, action)

  local camera_set = false
  for _, row in ipairs(ACTION_ROWS) do
    if not row.unblocked and Bindings.is(row.action, action_id) then
      if row.axis then
        if not camera_set then
          sources.camera[row.axis == "camera_up" and "up" or "down"] = action_magnitude(action)
          refresh_axes()
          camera_set = true
        end
      else
        dispatch_row(row, action_id, action)
      end
    end
  end
  return true
end

function M.end_frame(dt)
  for row, pending in pairs(pending_holds) do
    for _, hold in pairs(pending) do
      if not hold.fired then
        hold.elapsed = hold.elapsed + math.max(0, tonumber(dt) or 0)
        if hold.elapsed >= hold.seconds then
          set_edge_state(row.hold, hold.action)
          hold.fired = true
        end
      end
    end
  end
  local state = M.input_state
  refresh_axes()
  local debug_movement = (CFG and CFG.debug_movement) or PS.debug_movement
  if debug_movement and state.slide_held then
    input_log(string.format("[INPUT] slide_held=%s, move_x=%.3f",
      tostring(state.slide_held), state.move_x))
  end
  return state
end

function M.get_state()
  return M.input_state
end

return M
