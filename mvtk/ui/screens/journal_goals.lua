-- Static Journal provider for developer/config/goals.lua. It lists the current
-- goal and the finished ones only, so later goals stay hidden. Goal titles and
-- text are creator source text, resolved only by the displaying list menu.
local M = {}
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end
local function title(goal) return nonblank(goal.title) and goal.title or {key = "list.missing_name"} end
function M.new(deps)
    deps = deps or {}
    local provider = {}
    local function goals() return deps.goals or require "mvtk.game.goals" end
    local function row(goal, state)
        return {id = goal.id, label = title(goal), state = state,
            detail = {title = title(goal), body = nonblank(goal.text) and goal.text or ""}}
    end
    function provider.title() return {key = "journal.goals"} end
    function provider.enabled()
        local owner = goals()
        return owner.enabled() and #owner.list() > 0
    end
    function provider.rows()
        local owner, out = goals(), {}
        local current, finished = owner.current(), {}
        for _, goal in ipairs(owner.list()) do
            if owner.is_finished(goal.id) then finished[#finished + 1] = row(goal, "completed") end
        end
        if current then
            out[#out + 1] = {id = "section:current", kind = "section", selectable = false,
                label = {key = "journal.goals_current"}}
            out[#out + 1] = row(current, "available")
        end
        if #finished > 0 then
            out[#out + 1] = {id = "section:finished", kind = "section", selectable = false,
                label = {key = "journal.goals_finished"}}
            for _, item in ipairs(finished) do out[#out + 1] = item end
        end
        return out
    end
    function provider.detail(_, item) return item.detail end
    return provider
end
local default = M.new()
default.new = M.new
return default
