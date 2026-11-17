-- Pure binding contract, shared by runtime menus and editor/headless validation.
-- No runtime globals or requires: the editor can load this module directly.
local M = {}

-- Digital buttons only; analog camera directions have fixed ownership.
M.CONTROLLER_INPUTS = {
  gamepad_lpad_left = true, gamepad_lpad_right = true,
  gamepad_lpad_up = true, gamepad_lpad_down = true,
  gamepad_rpad_left = true, gamepad_rpad_right = true,
  gamepad_rpad_up = true, gamepad_rpad_down = true,
  gamepad_lshoulder = true, gamepad_rshoulder = true,
  gamepad_ltrigger = true, gamepad_rtrigger = true,
  gamepad_lstick_click = true, gamepad_rstick_click = true,
  gamepad_start = true, gamepad_back = true, gamepad_guide = true,
}

M.HOLD_RANGE = { 0.05, 5 }

-- Escape always remains a keyboard way back to Pause, even after remapping.
M.FIXED = { PAUSE_TOGGLE = { "key_escape" } }
M.RESERVED_KEYS = {
  key_r = true, key_escape = true,
  key_f1 = true, key_f2 = true, key_f3 = true, key_f4 = true,
  key_f5 = true, key_f6 = true, key_f7 = true,
  key_w = true, key_a = true, key_s = true, key_d = true,
  key_up = true, key_down = true, key_left = true, key_right = true,
}

function M.is_fixed(action, input)
  for _, fixed in ipairs(M.FIXED[action] or {}) do
    if input == fixed then return true end
  end
  return false
end

-- inputs is the current physical-action allowlist, represented as a set.
function M.capturable_key(input, inputs)
  return type(input) == "string" and inputs[input] == true
    and input:sub(1, 4) == "key_" and not M.RESERVED_KEYS[input]
end

-- Copies and slot projections stay pure: dispatch rows are optional data, never
-- required here. Hosts pass input_actions to include its hold-time fallbacks.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

function M.creator_view(config, dispatch_rows)
  local view = { keyboard = {}, controller = {},
    hold_seconds = dispatch_rows and {} or copy(config.hold_seconds or {}) }
  for _, row in ipairs(config.remappable or {}) do
    if row.keyboard then view.keyboard[row.action] = "none" end
    if row.controller then view.controller[row.action] = "none" end
    for _, input in ipairs((config.actions or {})[row.action] or {}) do
      if row.keyboard and view.keyboard[row.action] == "none"
          and input:sub(1, 4) == "key_" and not M.is_fixed(row.action, input) then
        view.keyboard[row.action] = input
      end
      if row.controller and view.controller[row.action] == "none" and M.CONTROLLER_INPUTS[input] then
        view.controller[row.action] = input
      end
    end
  end
  for _, row in ipairs(dispatch_rows or {}) do
    if row.hold and (config.actions or {})[row.action] then
      view.hold_seconds[row.action] = (config.hold_seconds or {})[row.action] or row.hold_seconds
    end
  end
  return view
end

function M.conflicts(config)
  local owners, inputs, out = {}, {}, {}
  for _, input in ipairs(config.inputs or {}) do inputs[input] = true end
  for action, list in pairs(config.actions or {}) do
    if type(list) == "table" then
      for _, input in ipairs(list) do
        if M.CONTROLLER_INPUTS[input] or M.capturable_key(input, inputs) then
          owners[input] = owners[input] or {}
          owners[input][action] = true
        end
      end
    end
  end
  for input, actions in pairs(owners) do
    local names = {}
    for action in pairs(actions) do names[#names + 1] = action end
    table.sort(names)
    if #names > 1 then out[#out + 1] = { input = input, actions = names } end
  end
  table.sort(out, function(a, b) return a.input < b.input end)
  return out
end

-- Invalid entries keep their baseline. Conflicts remain in the returned copy
-- for editor diagnostics; rejected actions let runtime ignore bad authoring.
function M.apply_creator(config, layer, dispatch_rows)
  local merged, problems, rejected = copy(config), {}, {}
  local shown = M.creator_view(config, dispatch_rows)
  merged.hold_seconds = copy(config.hold_seconds or {})
  for action, seconds in pairs(shown.hold_seconds) do merged.hold_seconds[action] = seconds end
  if layer == nil then return merged, problems, rejected end
  if type(layer) ~= "table" then return merged, { "default_bindings must be a table" }, rejected end
  local rows, inputs, accepted = {}, {}, {}
  for _, row in ipairs(config.remappable or {}) do rows[row.action] = row end
  for _, input in ipairs(config.inputs or {}) do inputs[input] = true end
  for slot, entries in pairs(layer) do
    if not shown[slot] or type(entries) ~= "table" then
      problems[#problems + 1] = "Unknown or invalid binding slot: " .. tostring(slot)
    else
      accepted[slot] = {}
      for action, value in pairs(entries) do
        local row, issue = rows[action], nil
        if not row then issue = "Unknown action: " .. tostring(action)
        elseif shown[slot][action] == nil then issue = "Action does not offer " .. slot .. ": " .. action
        elseif slot == "hold_seconds" then
          if type(value) ~= "number" or value ~= value or value < M.HOLD_RANGE[1] or value > M.HOLD_RANGE[2] then
            issue = "hold_seconds." .. action .. " must be between 0.05 and 5 seconds"
          end
        elseif value ~= "none" and (not inputs[value]
            or (slot == "keyboard" and not M.capturable_key(value, inputs))
            or (slot == "controller" and (not M.CONTROLLER_INPUTS[value] or value == "gamepad_guide"))) then
          issue = "Invalid " .. slot .. " input for " .. action .. ": " .. tostring(value)
        end
        if issue then problems[#problems + 1] = issue; rejected[action] = true
        else accepted[slot][action] = value end
      end
    end
  end
  for slot, entries in pairs(accepted) do
    for action, value in pairs(entries) do
      if not rejected[action] then
        if slot == "hold_seconds" then merged.hold_seconds[action] = value
        else
          local list = {}
          for _, input in ipairs(merged.actions[action]) do
            local replace = slot == "keyboard" and input:sub(1, 4) == "key_" and not M.is_fixed(action, input)
                or slot == "controller" and M.CONTROLLER_INPUTS[input]
            if not replace then list[#list + 1] = input end
          end
          if value ~= "none" then list[#list + 1] = value end
          merged.actions[action] = list
          -- Only an unshown alternate yields, and only if its owner did not
          -- explicitly author that slot. Shown defaults remain conflicts.
          for other, other_list in pairs(merged.actions) do
            if other ~= action and shown[slot][other] ~= value and (layer[slot] or {})[other] == nil then
              local kept = {}
              for _, input in ipairs(other_list) do
                if input ~= value then kept[#kept + 1] = input end
              end
              merged.actions[other] = kept
            end
          end
        end
      end
    end
  end
  for _, conflict in ipairs(M.conflicts(merged)) do
    problems[#problems + 1] = conflict.input .. " is owned by " .. table.concat(conflict.actions, " and ")
    for _, action in ipairs(conflict.actions) do rejected[action] = true end
  end
  table.sort(problems)
  return merged, problems, rejected
end

-- With no candidate, validate authored defaults and their presentation rows.
-- A candidate is a complete runtime action map; reserved-default rules then
-- do not apply. Later layers must replace whole action lists before validation.
function M.validate(config, candidate)
  local errors, owners = {}, {}
  local function fail(message) errors[#errors + 1] = message end
  if type(config) ~= "table" or type(config.actions) ~= "table"
      or type(config.inputs) ~= "table" then
    return { "Bindings require inputs and actions tables" }
  end
  local function check_list(list, context)
    for key in pairs(list) do
      if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #list then
        fail(context .. " must be a dense ordered list")
        return
      end
    end
  end
  local inputs = {}
  check_list(config.inputs, "inputs")
  for _, input in ipairs(config.inputs) do
    if type(input) ~= "string" or input == "" then fail("Input names must be nonempty strings")
    else inputs[input] = true end
  end
  local actions = candidate or config.actions
  if type(actions) ~= "table" then return { "Bindings must be a table" } end
  for action, list in pairs(actions) do
    if config.actions[action] == nil then fail("Unknown action: " .. tostring(action)) end
    if type(list) ~= "table" then
      fail("Inputs for " .. tostring(action) .. " must be a list")
    else
      check_list(list, "Inputs for " .. tostring(action))
      for _, input in ipairs(list) do
        if not inputs[input] then fail("Unknown input: " .. tostring(input)) end
        if not candidate and (input == "gamepad_guide" or input == "key_r") then
          fail(tostring(input) .. " cannot be a default")
        end
        if M.CONTROLLER_INPUTS[input] or M.capturable_key(input, inputs) then
          if owners[input] and owners[input] ~= action then
            fail(input .. " is owned by " .. owners[input] .. " and " .. action)
          end
          owners[input] = action
        end
      end
      for _, fixed in ipairs(M.FIXED[action] or {}) do
        local found = false
        for _, input in ipairs(list) do if input == fixed then found = true end end
        if not found then fail(tostring(action) .. " requires fixed input " .. fixed) end
      end
    end
  end
  if not candidate then
    local ids, seen = {}, {}
    if config.remappable ~= nil and type(config.remappable) ~= "table" then
      fail("remappable must be a list")
    else
      check_list(config.remappable or {}, "remappable")
      for _, row in ipairs(config.remappable or {}) do
        if type(row) ~= "table" then
          fail("Each remappable row must be a table")
        else
          if type(row.id) ~= "string" or row.id == "" or ids[row.id] then fail("Invalid or duplicate row id") end
          if row.id then ids[row.id] = true end
          if not config.actions[row.action] then fail("Unknown action: " .. tostring(row.action)) end
          if seen[row.action] then fail("Duplicate action row: " .. tostring(row.action)) end
          if row.action then seen[row.action] = true end
          if type(row.label) ~= "string" or type(row.player) ~= "boolean"
              or type(row.optional) ~= "boolean" or type(row.owner) ~= "string"
              or type(row.keyboard) ~= "boolean" or type(row.controller) ~= "boolean" then
            fail("Row needs label, player, optional, owner, keyboard and controller slots")
          end
        end
      end
      if config.remappable then
        for action in pairs(config.actions) do
          if not seen[action] then fail("Missing action row: " .. action) end
        end
      end
    end
    if config.hold_seconds ~= nil and type(config.hold_seconds) ~= "table" then
      fail("hold_seconds must be a table")
    else
      for action, seconds in pairs(config.hold_seconds or {}) do
        if not config.actions[action] then fail("Unknown action: " .. tostring(action)) end
        if type(seconds) ~= "number" or seconds ~= seconds
            or seconds < M.HOLD_RANGE[1] or seconds > M.HOLD_RANGE[2] then
          fail("hold_seconds." .. action .. " must be between 0.05 and 5 seconds")
        end
      end
    end
  end
  table.sort(errors)
  return errors
end

return M
