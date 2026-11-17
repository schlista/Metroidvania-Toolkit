-- mvtk/core/input_bindings.lua
-- Current-only high-level input bindings for Defold 1.13.2+.

local Util = require "mvtk.core.util"
local DEFAULTS = Util.require_config("developer.config.default_bindings")
local SavePaths = require "mvtk.core.save_paths"

local Rules = require "mvtk.core.input_binding_rules"

local M = {}

local SAVE_FILE = "mvtk_bindings_v2"
local SAVE_VERSION = 2

M.SAVE_FILE = SAVE_FILE
M.SAVE_VERSION = SAVE_VERSION

-- Pure contract also used by editor validation.
local CONTROLLER_INPUTS = Rules.CONTROLLER_INPUTS
M.CONTROLLER_INPUTS = CONTROLLER_INPUTS

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

-- Resolve baseline and later creator defaults here. Replace an action's whole
-- list in a later layer; merging arrays by index retains obsolete inputs.
local defaults_cache, defaults_revision, defaults_host
local warned = {}
function M.defaults()
  local ok, runtime = pcall(require, "developer.config.runtime_settings")
  if not ok or type(runtime.get_binding_overrides) ~= "function" then return copy(DEFAULTS) end
  local current_revision = runtime.revision()
  if defaults_cache == nil or defaults_revision ~= current_revision or defaults_host ~= runtime then
    local layer = runtime.get_binding_overrides()
    local dispatch = require "mvtk.rooms.input_actions"
    local merged, problems, rejected = Rules.apply_creator(DEFAULTS, layer, dispatch)
    while #problems > 0 do
      for _, message in ipairs(problems) do
        if not warned[message] then print("[INPUT_BINDINGS] " .. message); warned[message] = true end
      end
      local removed = false
      for _, entries in pairs(type(layer) == "table" and layer or {}) do
        if type(entries) == "table" then
          for action in pairs(rejected) do
            if entries[action] ~= nil then entries[action] = nil; removed = true end
          end
        end
      end
      if not removed then break end
      merged, problems, rejected = Rules.apply_creator(DEFAULTS, layer, dispatch)
    end
    defaults_cache, defaults_revision, defaults_host = merged, current_revision, runtime
  end
  return copy(defaults_cache)
end

function M.remappable() return M.defaults().remappable or {} end
function M.hold_seconds(action) return (M.defaults().hold_seconds or {})[action] end

local shown_rows = {}
-- Optional owners may supply an event-free predicate for current settings.
function M.show_row(id, visible)
  if visible == nil then visible = true end
  shown_rows[id] = visible
end
function M.row_visible(id)
  local visible = shown_rows[id]
  if type(visible) == "function" then return visible() == true end
  return visible == true
end

-- Every persisted input must exist in the current input binding asset. Adding
-- a new low-level action is an explicit schema change in the creator-owned
-- default_bindings config and binding asset.
local CURRENT_INPUTS = {}
for _, input_name in ipairs(DEFAULTS.inputs or {}) do
  if type(input_name) == "string" and input_name ~= "" then
    CURRENT_INPUTS[input_name] = true
  end
end

M.CURRENT_INPUTS = CURRENT_INPUTS

function M.capturable_key(input) return Rules.capturable_key(input, CURRENT_INPUTS) end

local map = {}
local map_hash = {}
local revision = 0
function M.revision() return revision end

local function current_action_name(action_name)
  if type(action_name) ~= "string" or (DEFAULTS.actions or {})[action_name] == nil then
    return nil
  end
  return action_name
end

local function normalize_list(value)
  if type(value) ~= "table" then return nil end
  local out = {}
  local seen = {}
  for index = 1, #value do
    local input_name = value[index]
    if type(input_name) ~= "string"
      or input_name == ""
      or not CURRENT_INPUTS[input_name]
    then
      return nil
    end
    if not seen[input_name] then
      seen[input_name] = true
      out[#out + 1] = input_name
    end
  end
  return out
end

local function current_config(saved_bindings)
  local defaults = M.defaults().actions or {}
  local config = {}
  local saved_actions = {}
  for action_name, default_list in pairs(defaults) do
    local saved_list = saved_bindings and normalize_list(saved_bindings[action_name])
    config[action_name] = saved_list or normalize_list(default_list) or {}
    for _, fixed in ipairs(Rules.FIXED[action_name] or {}) do
      local found = false
      for _, input in ipairs(config[action_name]) do if input == fixed then found = true end end
      if not found then config[action_name][#config[action_name] + 1] = fixed end
    end
    if saved_list then saved_actions[action_name] = true end
  end
  return config, saved_actions
end

local function build_maps(source, preferred_actions)
  revision = revision + 1
  map, map_hash = {}, {}
  for action_name, value in pairs(source or {}) do
    local action = tostring(action_name)
    local list = normalize_list(value) or {}
    map[action] = {}
    map_hash[action] = {}
    for _, input_name in ipairs(list) do
      map[action][input_name] = true
      map_hash[action][hash(input_name)] = true
    end
  end

  -- A capturable key or digital pad button has one semantic owner. Repair a
  -- malformed current-version payload deterministically on load.
  local action_names = {}
  for action_name in pairs(map) do action_names[#action_names + 1] = action_name end
  table.sort(action_names, function(a, b)
    local a_preferred = preferred_actions and preferred_actions[a] or false
    local b_preferred = preferred_actions and preferred_actions[b] or false
    if a_preferred ~= b_preferred then return a_preferred end
    return a < b
  end)
  local owners = {}
  for _, action_name in ipairs(action_names) do
    for input_name in pairs(map[action_name]) do
      if CONTROLLER_INPUTS[input_name] or M.capturable_key(input_name) then
        if owners[input_name] then
          map[action_name][input_name] = nil
          map_hash[action_name][hash(input_name)] = nil
        else
          owners[input_name] = action_name
        end
      end
    end
  end
end

function M.owner_of(input)
  local names = {}
  for action in pairs(map) do names[#names + 1] = action end
  table.sort(names)
  for _, action in ipairs(names) do
    if map[action][input] then return action end
  end
end

local function validate_change(action, list)
  local candidate = {}
  for name, inputs in pairs(map) do
    candidate[name] = {}
    for input in pairs(inputs) do candidate[name][#candidate[name] + 1] = input end
  end
  candidate[action] = list
  local errors = Rules.validate(M.defaults(), candidate)
  if #errors > 0 then return false, table.concat(errors, "; ") end
  return true
end

local function save_path()
  return SavePaths.path(SAVE_FILE)
end

function M.load()
  local ok_path, path = pcall(save_path)
  local ok_load, payload = false, nil
  if ok_path then
    ok_load, payload = pcall(sys.load, path)
  end

  local saved_bindings = nil
  if ok_load
    and type(payload) == "table"
    and payload.version == SAVE_VERSION
    and type(payload.bindings) == "table"
  then
    saved_bindings = payload.bindings
  end

  local config, saved_actions = current_config(saved_bindings)
  build_maps(config, saved_actions)
end

function M.save()
  local checkpoint = package.loaded["mvtk.core.checkpoint"]
  if checkpoint and checkpoint.is_save_suspended_by("dev_tools") then return false, "save_suspended:dev_tools" end
  local bindings = {}
  local defaults = M.defaults().actions or {}
  for action_name, set in pairs(map) do
    local list = {}
    for input_name, enabled in pairs(set) do
      if enabled then list[#list + 1] = input_name end
    end
    table.sort(list)
    local baseline = copy(defaults[action_name] or {})
    table.sort(baseline)
    if table.concat(list, "\0") ~= table.concat(baseline, "\0") then bindings[action_name] = list end
  end

  local ok_path, path = pcall(save_path)
  if not ok_path then return false end
  local readable, previous = pcall(sys.load, path)
  if not readable or type(previous) ~= "table" then return false end
  if next(previous) and previous.version ~= SAVE_VERSION then return false end
  local ok_save, result = pcall(sys.save, path, {
    version = SAVE_VERSION,
    bindings = bindings,
  })
  return ok_save and result ~= false
end

function M.bind(action_name, input_names)
  local action = current_action_name(action_name)
  if not action then return false end
  local raw_list = type(input_names) == "table" and input_names or { input_names }
  local list = normalize_list(raw_list)
  if not list then return false end
  local valid, reason = validate_change(action, list)
  if not valid then return false, reason end
  map[action], map_hash[action] = {}, {}
  for _, input_name in ipairs(list) do
    map[action][input_name] = true
    map_hash[action][hash(input_name)] = true
  end
  revision = revision + 1
  return true
end

function M.add(action_name, input_name)
  if type(input_name) ~= "string"
    or input_name == ""
    or not CURRENT_INPUTS[input_name]
  then
    return false
  end
  local action = current_action_name(action_name)
  if not action then return false end
  local list = M.get(action)
  list[#list + 1] = input_name
  local valid, reason = validate_change(action, list)
  if not valid then return false, reason end
  map[action] = map[action] or {}
  map_hash[action] = map_hash[action] or {}
  map[action][input_name] = true
  map_hash[action][hash(input_name)] = true
  revision = revision + 1
  return true
end

function M.remove(action_name, input_name)
  local action = current_action_name(action_name)
  if not action then return false end
  local list = {}
  for _, input in ipairs(M.get(action)) do
    if input ~= tostring(input_name) then list[#list + 1] = input end
  end
  return M.bind(action, list)
end

function M.is(action_name, action_id)
  local action = current_action_name(action_name)
  local set = action and map_hash[action]
  return set and set[action_id] and true or false
end

function M.get(action_name)
  local out = {}
  local action = current_action_name(action_name)
  local set = action and map[action]
  if set then
    for input_name, enabled in pairs(set) do
      if enabled then out[#out + 1] = input_name end
    end
  end
  table.sort(out)
  return out
end

function M.get_controller_binding(action_name)
  for _, input_name in ipairs(M.get(action_name)) do
    if CONTROLLER_INPUTS[input_name] then return input_name end
  end
  return nil
end

function M.set_controller_binding(action_name, input_name)
  if input_name ~= nil and not CONTROLLER_INPUTS[input_name] then return false end
  local action = current_action_name(action_name)
  if not action then return false end
  local list = {}
  for _, existing in ipairs(M.get(action)) do
    if not CONTROLLER_INPUTS[existing] then list[#list + 1] = existing end
  end
  if input_name then list[#list + 1] = input_name end
  return M.bind(action, list)
end

function M.get_keyboard_binding(action_name)
  for _, input in ipairs(M.get(action_name)) do
    if input:sub(1, 4) == "key_" and not Rules.is_fixed(action_name, input) then return input end
  end
end

function M.set_keyboard_binding(action_name, key)
  if key ~= nil and not M.capturable_key(key) then return false end
  local action = current_action_name(action_name)
  if not action then return false end
  local list = {}
  for _, input in ipairs(M.get(action)) do
    if input:sub(1, 4) ~= "key_" or Rules.is_fixed(action, input) then list[#list + 1] = input end
  end
  if key then list[#list + 1] = key end
  return M.bind(action, list)
end

function M.reset()
  build_maps(current_config(nil))
  return M.save()
end

function M.refresh_from_defaults(action_name)
  local action = current_action_name(action_name)
  if not action then return false end
  local default_bindings = (M.defaults().actions or {})[action]
  if default_bindings then return M.bind(action, default_bindings) end
  return false
end

M.load()

return M
