-- Dialogue conditions and actions shared by lines and selected choices.
-- Runtime only: quest rewards remain owned by Quests, Grants and Delivery,
-- so this module is safe to call from the dialogue GUI without go.*.
local M = {}

function M.eval_condition(cond)
  if not cond then return true end

  -- Flag check
  if cond.flag then
    local ok_f, Flags = pcall(require, "mvtk.core.flags")
    if ok_f and Flags then
      local val = Flags.has and Flags.has(cond.flag) or false
      if cond.invert then return not val end
      return val
    end
    return not cond.invert  -- if Flags unavailable, default to true (unless inverted)
  end

  -- Ability check
  if cond.ability then
    local ok_a, AM = pcall(require, "mvtk.abilities.ability_manager")
    if ok_a and AM then
      local unlocked = (AM.is_ability_unlocked and AM.is_ability_unlocked(cond.ability))
        or (AM.has_ability and AM.has_ability(cond.ability))
        or false
      if cond.invert then return not unlocked end
      return unlocked
    end
    return not cond.invert
  end

  if cond.quest or cond.quest_step then
    local Quests = require "mvtk.game.quests.quests"
    local cfg = Quests.settings()
    local id, step_id = cond.quest, nil
    if not id and type(cond.quest_step) == "string" then
      id, step_id = cond.quest_step:match("^(.+)%.([^%.]+)$")
    end
    local def = id and (cfg.quests or {})[id]
    local matches = false
    if cfg.enabled == true and def then
      if cond.quest then
        matches = Quests.get_state(id) == (cond.state or "active")
      elseif step_id then
        local quest = Quests.get(id)
        local step = (def.steps or {})[quest.step]
        matches = (quest.state == "active" or quest.state == "completed")
          and step ~= nil and step.id == step_id
      end
    end
    if cond.invert then return not matches end
    return matches
  end

  return true
end

-- Actions execute in this order after the authored flag write. Quest services
-- own idempotency, notices, save batching and once-only reward delivery.
local function quest_actions(action)
  if not (action.quest_start or action.quest_advance or action.quest_turn_in or action.quest_fail) then return end
  local Quests = require "mvtk.game.quests.quests"
  if action.quest_start then Quests.start(action.quest_start) end
  if action.quest_advance then
    local id, step_id = action.quest_advance:match("^(.+)%.([^%.]+)$")
    Quests.advance(id or action.quest_advance, step_id)
  end
  if action.quest_turn_in then Quests.turn_in(action.quest_turn_in) end
  if action.quest_fail then Quests.fail(action.quest_fail) end
end

-- The last line the dialogue GUI displayed, as source text (WM12a). NPC
-- memory takes it once when the conversation ends, for Journal ▸ People.
local last_line = nil

function M.take_last_line()
  local value = last_line
  last_line = nil
  return value
end

function M.process_line_actions(line)
  if not line then return end
  if line.text ~= nil then last_line = tostring(line.text) end
  if line.set_flag then
    local ok_f, Flags = pcall(require, "mvtk.core.flags")
    if ok_f and Flags and Flags.set then
      Flags.set(line.set_flag, line.flag_value ~= nil and line.flag_value or true)
    end
  end
  quest_actions(line)
end

function M.process_choice_actions(choice)
  if not choice then return end
  if choice and choice.set_flag then
    local ok_f, Flags = pcall(require, "mvtk.core.flags")
    if ok_f and Flags and Flags.set then
      Flags.set(choice.set_flag, choice.flag_value ~= nil and choice.flag_value or true)
    end
  end
  quest_actions(choice)
end

return M
