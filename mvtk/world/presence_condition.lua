-- World-state condition text for appear_when and remove_when (G8-09).
-- Pure and LuaJ-safe: the editor loads it through the flag ledger, content
-- checks and progression analysis, and the game through mvtk/world/presence.lua.
--
-- Grammar: a comma list whose terms must all hold. Each term may join
-- alternatives with '|', and '|' binds inside one comma term:
--   met_hermit, ability:dash|ability:grapple
-- Literals:
--   flag            the flag is set
--   !flag           the flag is not set
--   ability:<id>    the ability is unlocked
--   item:<id>[:n]   the inventory holds at least n (default 1)
-- Only the 'ability:' and 'item:' prefixes are reserved; other colons belong to
-- the flag name (altar_used:<id>, npc_greeted:<id>, shop_sold:<id>).
-- Blank text or 'none' means no condition.
local M = {}

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

function M.is_blank(text)
    if text == nil then return true end
    if type(text) ~= "string" then return false end
    local s = trim(text)
    return s == "" or s:lower() == "none"
end

local function literal(text)
    if text == "" then return nil, "empty term" end
    if text:lower() == "none" then return nil, "'none' must stand alone" end
    local negated = false
    if text:sub(1, 1) == "!" then negated = true; text = trim(text:sub(2)) end
    if text:sub(1, 8) == "ability:" then
        if negated then return nil, "only a flag can be negated with '!'" end
        local id = text:sub(9)
        if not id:match("^[%w_%.%-]+$") then return nil, "bad ability id in '" .. text .. "'" end
        return {kind = "ability", id = id}
    elseif text:sub(1, 5) == "item:" then
        if negated then return nil, "only a flag can be negated with '!'" end
        local rest = text:sub(6)
        local id, amount = rest:match("^([%w_%.%-]+):(%d+)$")
        if not id then id = rest:match("^([%w_%.%-]+)$"); amount = "1" end
        if not id then return nil, "bad item term '" .. text .. "'; use item:<id> or item:<id>:<count>" end
        amount = tonumber(amount)
        if amount < 1 then return nil, "item count must be at least 1 in '" .. text .. "'" end
        return {kind = "item", id = id, amount = amount}
    end
    if text == "" then return nil, "'!' needs a flag name" end
    if text:find("[%s!]") then return nil, "bad flag name '" .. text .. "'" end
    return {kind = "flag", id = text, value = not negated}
end

-- Returns the comma groups, each a list of literals, or nil and a message.
local function groups(text)
    if type(text) ~= "string" then return nil, "condition must be text" end
    if M.is_blank(text) then return {} end
    local out = {}
    for term in (text .. ","):gmatch("(.-),") do
        local group = {}
        for alternative in (term .. "|"):gmatch("(.-)|") do
            local lit, err = literal(trim(alternative))
            if not lit then return nil, err end
            group[#group + 1] = lit
        end
        out[#out + 1] = group
    end
    return out
end

local function add(req, lit)
    if lit.kind == "flag" then
        req.flags = req.flags or {}
        if req.flags[lit.id] ~= nil and req.flags[lit.id] ~= lit.value then
            return "flag '" .. lit.id .. "' is required both set and not set"
        end
        req.flags[lit.id] = lit.value
    elseif lit.kind == "ability" then
        req.abilities = req.abilities or {}
        req.abilities[lit.id] = true
    else
        req.items = req.items or {}
        req.items[lit.id] = math.max(req.items[lit.id] or 0, lit.amount)
    end
end

-- Requirement table for mvtk/world/gates/requirements.lua, or nil and a
-- message. Blank text returns an empty table, which always holds. The first
-- '|' group becomes req.any; each later group nests in every alternative of
-- the group before it, which Requirements.evaluate already recurses into.
function M.parse(text)
    local list, err = groups(text)
    if not list then return nil, err end
    local req, chain = {}, {}
    for _, group in ipairs(list) do
        if #group == 1 then
            err = add(req, group[1])
            if err then return nil, err end
        else
            local alternatives = {}
            for _, lit in ipairs(group) do
                local branch = {}
                add(branch, lit)
                alternatives[#alternatives + 1] = branch
            end
            chain[#chain + 1] = alternatives
        end
    end
    for i = #chain - 1, 1, -1 do
        for _, branch in ipairs(chain[i]) do branch.any = chain[i + 1] end
    end
    req.any = chain[1]
    return req
end

-- Every flag name the condition reads (set or not set), sorted and unique.
function M.flags(text)
    local list, err = groups(text)
    if not list then return nil, err end
    local seen, out = {}, {}
    for _, group in ipairs(list) do
        for _, lit in ipairs(group) do
            if lit.kind == "flag" and not seen[lit.id] then seen[lit.id] = true; out[#out + 1] = lit.id end
        end
    end
    table.sort(out)
    return out
end

-- A requirement that holds exactly when a flag-only condition does not:
-- not (A and B) is (not A) or (not B), and not (a | b) is (not a) and (not b).
-- Blank text returns nil (nothing to negate). A condition naming abilities or
-- items cannot be negated in this grammar and returns nil and a message.
function M.negate_flags(text)
    local list, err = groups(text)
    if not list then return nil, err end
    if #list == 0 then return nil end
    local alternatives = {}
    for _, group in ipairs(list) do
        local branch = {flags = {}}
        for _, lit in ipairs(group) do
            if lit.kind ~= "flag" then return nil, "only a condition made of flags can be negated" end
            branch.flags[lit.id] = not lit.value
        end
        alternatives[#alternatives + 1] = branch
    end
    if #alternatives == 1 then return alternatives[1] end
    return {any = alternatives}
end

return M
