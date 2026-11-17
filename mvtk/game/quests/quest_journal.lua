-- Static Journal provider: runtime services load only when the menu asks for them.
-- Creator text and nested reward descriptions remain unresolved until display.
local M = {}
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end
local function title(def) return nonblank(def.title) and def.title or {key = "list.missing_name"} end
function M.new(deps)
    deps = deps or {}
    local provider = {}
    local function quests() return deps.quests or require "mvtk.game.quests.quests" end
    function provider.title() return {key = "journal.quests"} end
    function provider.enabled() return quests().settings().enabled == true end
    function provider.rows()
        local owner = quests()
        local cfg, saved = owner.settings(), owner.snapshot().quests
        local groups, out = {active = {}, completed = {}}, {}
        for id, def in pairs(cfg.quests or {}) do
            local state = saved[id] or {state = "not_started", step = 1}
            if state.state ~= "not_started" or not def.hidden_until_started then
                local terminal = state.state == "completed" or state.state == "turned_in" or state.state == "failed"
                local step = (def.steps or {})[state.step]
                local parts = {}
                if nonblank(def.description) then parts[#parts + 1] = def.description end
                if state.state == "completed" and step and (step.complete_when or {}).turn_in and nonblank(def.giver) then
                    parts[#parts + 1] = {key = "journal.quest_return_to", params = {giver = {text = def.giver}}}
                end
                local reward = (deps.grants or require "mvtk.game.grants").describe(def.rewards or {})
                if reward ~= "" then parts[#parts + 1] = {key = "journal.quest_reward", params = {reward = reward}} end
                local item = {id = id, label = title(def), state = terminal and "completed" or "available",
                    value = state.state == "failed" and {key = "notice.quest_failed"} or (step and step.text),
                    detail = {title = title(def), body = {parts = parts, separator = "\n"}}}
                -- The shared reader takes raw source text, preserving translation identity.
                if nonblank(def.description) then item.read = {title = def.title, text = def.description} end
                local group = terminal and groups.completed or groups.active
                group[#group + 1] = {row = item, category = def.category, name = def.title or ""}
            end
        end
        local function category_order(id) return ((cfg.categories or {})[id] or {}).order or math.huge end
        local function less(a, b)
            local ac, bc = category_order(a.category), category_order(b.category)
            if ac ~= bc then return ac < bc end
            if a.category ~= b.category then return (a.category or "") < (b.category or "") end
            if a.name ~= b.name then return a.name < b.name end
            return a.row.id < b.row.id
        end
        for _, section in ipairs({"active", "completed"}) do
            local rows = groups[section]
            table.sort(rows, less)
            if #rows > 0 then
                out[#out + 1] = {id = "section:" .. section, kind = "section", selectable = false,
                    label = {key = "journal.quests_" .. section}}
                for _, item in ipairs(rows) do out[#out + 1] = item.row end
            end
        end
        return out
    end
    function provider.detail(_, row) return row.detail end
    return provider
end
local default = M.new()
default.new = M.new
return default
