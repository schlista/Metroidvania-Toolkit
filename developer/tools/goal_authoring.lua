-- Goal target checks for Analyze Progression and Prepare & Check (G8-13b).
-- Reads developer/config/goals.lua with published Game Settings overrides,
-- the completion_authoring.lua pattern. Only enabled goals are checked.
--   load(root, read)                        -> effective goals config
--   validate(cfg, index, layout)            -> goal_target_missing errors
--   blocked(cfg, objectives)                -> goal_target_blocked warnings
-- Diagnostics are editor English (Stage 4b T9).
local Source = require "developer.tools.project_source"
local Model = require "mvtk.core.creator_settings_model"
local M = {}
M.FILE = "developer/config/goals.lua"

function M.load(root, read)
    read = read or Source.read
    local text = read((root or ".") .. "/" .. M.FILE)
    local cfg = text and Source.load_table(text, "goals.lua")
    cfg = type(cfg) == "table" and cfg or { enabled = false, goals = {} }
    local creator = Source.load_table(read((root or ".") .. "/developer/config/creator_settings.lua"), "creator_settings.lua")
    if type(creator) == "table" and creator.published then
        cfg = Model.merge(cfg, (creator.overrides or {}).goals or {})
    end
    return cfg
end

local function nonblank(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

-- Each enabled goal with a target: {goal, objective = id} or {goal, marker = id}.
local function targets(cfg)
    local out = {}
    if type(cfg) ~= "table" or cfg.enabled ~= true or type(cfg.goals) ~= "table" then return out end
    for i, goal in ipairs(cfg.goals) do
        local target = type(goal) == "table" and goal.target
        if type(target) == "table" then
            local objective, marker = nonblank(target.objective), nonblank(target.marker)
            if objective or marker then
                out[#out + 1] = { goal = goal, index = i, objective = objective, marker = marker }
            end
        end
    end
    return out
end

local function issue(severity, code, t, message, fix)
    return { severity = severity, code = code, file = M.FILE, property = "goals." .. tostring(t.index) .. ".target",
        message = message, fix = fix }
end

local function label(t)
    return "Goal '" .. tostring(t.goal.id) .. "' target "
        .. (t.objective and ("objective '" .. t.objective .. "'") or ("marker '" .. tostring(t.marker) .. "'"))
end

-- An error when no visible object in a placed room carries the target's
-- progression_objective or Map Marker id. Uses index.objects, not the graph:
-- a config-only objective has no census entry, so it never counts.
function M.validate(cfg, index, layout)
    local ds, list = {}, targets(cfg)
    if #list == 0 then return ds end
    local placed = {}
    for _, room in ipairs(layout and layout.rooms or {}) do placed[room.id] = true end
    local objectives, markers = {}, {}
    for _, o in ipairs(index and index.objects or {}) do
        if o.visible and placed[o.room] then
            local p = o.properties or {}
            local objective = nonblank(p.progression_objective)
            if objective then objectives[objective] = true end
            local marker = o.type == "map_marker" and nonblank(p.marker_id)
            if marker then markers[marker] = true end
        end
    end
    for _, t in ipairs(list) do
        local found = (t.objective and objectives[t.objective]) or (t.marker and markers[t.marker])
        if not found then
            ds[#ds + 1] = issue("error", "goal_target_missing", t,
                label(t) .. " names no visible object in a room placed in the Layout Editor.",
                t.objective and "Give the target object that progression_objective in Tiled and export its room, or correct the goal's target."
                    or "Place a Map Marker with that marker_id in a placed room, or correct the goal's target.")
        end
    end
    return ds
end

-- After the search: a warning for each objective target the model cannot
-- reach. objectives: result.objectives from progression_search (absent when
-- the search did not run). Marker targets have no objective and are skipped.
function M.blocked(cfg, objectives)
    local ds = {}
    if type(objectives) ~= "table" then return ds end
    for _, t in ipairs(targets(cfg)) do
        local r = t.objective and objectives[t.objective]
        if type(r) == "table" and r.status ~= "reachable" then
            ds[#ds + 1] = issue("warning", "goal_target_blocked", t,
                label(t) .. " is " .. tostring(r.status) .. " in the progression model.",
                "Check the route to the target, or point the goal at a reachable object.")
        end
    end
    return ds
end

return M
