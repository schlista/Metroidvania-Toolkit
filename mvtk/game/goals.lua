-- Ordered goals from developer/config/goals.lua: the player's current main objective.
-- Progress only moves forward. The scan starts at the highest goal whose
-- goal_announced_<id> flag is set, so spending an item an earlier goal needed
-- never sends the player back. Finishing them all sets goal_finished_<last id>,
-- which the last goal has no next announcement to keep. Saves hold only these flags.
local Events = require "mvtk.core.game_events"
local Requirements = require "mvtk.world.gates.requirements"
local M = {}
local config, config_revision = nil, nil
local current_index, finished_all = nil, false
local started, busy, again = false, false, false
local serial = 0
local posted = nil -- The serial last sent to the feature HUD's goal line.
-- Bumps whenever the current goal changes, for GUI caches.
function M.revision() return serial end
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if config == nil or config_revision ~= revision then
        config, config_revision = Runtime.section("goals", require "developer.config.goals"), revision
    end
    return config
end
function M.enabled() return M.settings().enabled == true end
function M.list()
    local goals = M.settings().goals
    return type(goals) == "table" and goals or {}
end
function M.get(id)
    for _, goal in ipairs(M.list()) do if goal.id == id then return goal end end
end
-- Live requirement state: world-state presence's, which reads flags without
-- copying them, plus the player's currency for resource requirements.
local function live_state()
    local Inventory = require "mvtk.core.inventory"
    return require("mvtk.world.presence").requirement_state({currency = Inventory.get_currency() or 0})
end
local function announced_floor(goals)
    local Flags = require "mvtk.core.flags"
    for i = #goals, 1, -1 do
        if Flags.has("goal_announced_" .. tostring(goals[i].id)) then return i end
    end
    return 1
end
-- Returns the index of the current goal, or nil when every goal is finished.
local function resolve(goals)
    local first = announced_floor(goals)
    if current_index and current_index > first then first = current_index end
    if finished_all then return nil end
    local Flags = require "mvtk.core.flags"
    if Flags.has("goal_finished_" .. tostring(goals[#goals].id)) then return nil end
    local state = live_state()
    for i = first, #goals do
        if not Requirements.evaluate(goals[i].done_when, state) then return i end
    end
    return nil
end
local function evaluate()
    local goals = M.list()
    if #goals == 0 then return end
    local previous = current_index and goals[current_index]
    local index = resolve(goals)
    if index == current_index and (index ~= nil or finished_all) then return end
    current_index, finished_all = index, index == nil
    serial = serial + 1
    local goal = index and goals[index]
    local Flags = require "mvtk.core.flags"
    if finished_all then Flags.set("goal_finished_" .. tostring(goals[#goals].id), true) end
    if goal and Flags.has("goal_announced_" .. goal.id) then return end -- Restored, not new.
    if goal then
        Flags.set("goal_announced_" .. goal.id, true)
        -- Source title travels untranslated; the notices scene resolves both.
        require("mvtk.ui.notices").post({kind = "goal", key = "goal",
            title = {key = "notice.new_goal"}, text = goal.title or ""})
    end
    if goal or previous then
        Events.emit("goal_changed", {goal_id = goal and goal.id or "", previous_id = previous and previous.id or ""})
    end
end
-- The feature HUD's goal line: the current goal's source title, or an empty
-- payload that hides the line once every goal is finished.
local function publish()
    if not started or not M.enabled() or posted == serial then return end
    posted = serial
    local goal = current_index and M.list()[current_index]
    require("mvtk.ui.hud_bus").post("goal", goal and {title = goal.title or ""} or {})
end
-- Flags.set inside a flag_set listener re-enters: run once more instead.
local function receive()
    if not started or not M.enabled() then return end
    if busy then again = true; return end
    busy = true
    local ok, why = pcall(function()
        repeat again = false; evaluate() until not again
    end)
    busy, again = false, false
    if not ok then error(why, 0) end
    publish()
end
-- The current goal row, or nil when goals are off, none is listed or all are finished.
function M.current()
    if not started or not M.enabled() then return nil end
    return current_index and M.list()[current_index] or nil
end
function M.current_id()
    local goal = M.current()
    return goal and goal.id or nil
end
-- True once the goal lies behind the current one, or every goal is finished.
function M.is_finished(id)
    if not started or not M.enabled() then return false end
    for i, goal in ipairs(M.list()) do
        if goal.id == id then return finished_all or (current_index ~= nil and i < current_index) end
    end
    return false
end
function M.before_session_start()
    started, current_index, finished_all, posted = false, nil, false, nil
    config, config_revision = nil, nil
    serial = serial + 1
end
function M.on_session_start()
    started = true
    receive()
    publish() -- Once per session, even when nothing changed.
end
for _, name in ipairs({"flag_set", "ability_unlocked", "item_added", "currency_changed", "boss_defeated", "room_visited"}) do
    Events.on(name, receive)
end
return M
