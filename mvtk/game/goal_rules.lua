-- Pure goals.lua checks shared by startup schemas, headless Lua and editor LuaJ.
-- Bundled requires only: an exported game validates this at startup and cannot
-- read project files.
local M = {}
M.MAX_TITLE_BYTES = 120 -- Source text travels in msg.post tables (2 KB limit).
M.MAX_HINT_BYTES = 1024
local GOAL_FIELDS = {id=true, title=true, text=true, hint=true, done_when=true, target=true}
local REQUIREMENT_FIELDS = {abilities=true, items=true, flags=true, resources=true, counts=true, any=true}
local function text(v) return type(v) == "string" and v:match("%S") ~= nil end
local function positive_integer(v) return type(v) == "number" and v == v and v > 0 and v < math.huge and v % 1 == 0 end
local function dense(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    return n == #t
end
local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end
-- Requirements.evaluate passes an empty table at once, so every level must ask
-- for something. env.abilities, when given, names the known ability ids.
local function requirement(req, path, bad, env)
    if type(req) ~= "table" or next(req) == nil then bad(path .. " must be a nonempty requirement table"); return end
    for _, key in ipairs(sorted_keys(req)) do
        if not REQUIREMENT_FIELDS[key] then bad(path .. " has unknown field " .. tostring(key)) end
    end
    for _, key in ipairs({"abilities", "items", "flags", "resources"}) do
        if req[key] ~= nil and (type(req[key]) ~= "table" or next(req[key]) == nil) then bad(path .. "." .. key .. " must be a nonempty table") end
    end
    for _, id in ipairs(sorted_keys(type(req.abilities) == "table" and req.abilities or {})) do
        if not text(id) then bad(path .. ".abilities needs text ids")
        elseif req.abilities[id] ~= true then bad(path .. ".abilities." .. id .. " must be true")
        elseif env and env.abilities and next(env.abilities) and not env.abilities[id] then bad(path .. ".abilities." .. id .. " is not an ability in abilities.lua") end
    end
    for _, id in ipairs(sorted_keys(type(req.items) == "table" and req.items or {})) do
        if not text(id) then bad(path .. ".items needs text ids")
        elseif not positive_integer(req.items[id]) then bad(path .. ".items." .. id .. " must be a positive integer") end
    end
    for _, id in ipairs(sorted_keys(type(req.flags) == "table" and req.flags or {})) do
        local kind = type(req.flags[id])
        if not text(id) then bad(path .. ".flags needs text ids")
        elseif kind ~= "boolean" and kind ~= "string" and kind ~= "number" then bad(path .. ".flags." .. id .. " must be true, false, text or a number") end
    end
    for _, id in ipairs(sorted_keys(type(req.resources) == "table" and req.resources or {})) do
        if id ~= "currency" then bad(path .. ".resources supports currency only")
        elseif not positive_integer(req.resources[id]) then bad(path .. ".resources.currency must be a positive integer") end
    end
    if req.counts ~= nil then
        if not dense(req.counts) or #req.counts == 0 then bad(path .. ".counts must be a nonempty list")
        else
            for n, count in ipairs(req.counts) do
                local at = path .. ".counts." .. n
                if type(count) ~= "table" or not dense(count.flags) or #count.flags == 0 then bad(at .. ".flags must be a nonempty list")
                else
                    for _, flag in ipairs(count.flags) do if not text(flag) then bad(at .. ".flags needs text ids") end end
                    if count.need ~= nil and (not positive_integer(count.need) or count.need > #count.flags) then
                        bad(at .. ".need must be a positive integer no larger than the flag list")
                    end
                end
                for key in pairs(type(count) == "table" and count or {}) do
                    if key ~= "flags" and key ~= "need" then bad(at .. " has unknown field " .. tostring(key)) end
                end
            end
        end
    end
    if req.any ~= nil then
        if not dense(req.any) or #req.any == 0 then bad(path .. ".any must be a nonempty list")
        else for n, alternative in ipairs(req.any) do requirement(alternative, path .. ".any." .. n, bad, env) end end
    end
end
function M.validate(cfg, env)
    local errors = {}
    local function bad(message) errors[#errors + 1] = "Goals: " .. message end
    if type(cfg) ~= "table" then return {"Goals config must be a table"} end
    if type(cfg.enabled) ~= "boolean" then bad("enabled must be boolean") end
    if type(cfg.hint_reveals_target) ~= "boolean" then bad("hint_reveals_target must be boolean") end
    if not dense(cfg.goals) then bad("goals must be a list"); return errors end
    local seen = {}
    for n, goal in ipairs(cfg.goals) do
        local label = "goal " .. n
        if type(goal) ~= "table" then bad(label .. " must be a table")
        else
            if type(goal.id) ~= "string" or not goal.id:match("^[%w_]+$") then bad(label .. " needs an id of letters, digits and underscores")
            elseif seen[goal.id] then bad("goal '" .. goal.id .. "' is listed twice")
            else seen[goal.id] = true; label = "goal '" .. goal.id .. "'" end
            for _, key in ipairs(sorted_keys(goal)) do
                if key == "hint_cost" then bad(label .. " hint_cost is not used: set Goal hint cost on the Hint Stone")
                elseif not GOAL_FIELDS[key] then bad(label .. " has unknown field " .. tostring(key)) end
            end
            if not text(goal.title) then bad(label .. " title must be nonblank source text")
            elseif #goal.title > M.MAX_TITLE_BYTES then bad(label .. " title is longer than " .. M.MAX_TITLE_BYTES .. " bytes") end
            if goal.text ~= nil and type(goal.text) ~= "string" then bad(label .. " text must be source text") end
            if goal.hint ~= nil and type(goal.hint) ~= "string" then bad(label .. " hint must be source text")
            elseif type(goal.hint) == "string" and #goal.hint > M.MAX_HINT_BYTES then bad(label .. " hint is longer than " .. M.MAX_HINT_BYTES .. " bytes") end
            requirement(goal.done_when, label .. " done_when", bad, env)
            if goal.target ~= nil then
                local t = goal.target
                local forms = type(t) == "table" and ((t.objective ~= nil and 1 or 0) + (t.marker ~= nil and 1 or 0)) or 0
                if type(t) ~= "table" or forms ~= 1 then bad(label .. " target needs exactly one of objective or marker")
                else
                    for key in pairs(t) do if key ~= "objective" and key ~= "marker" then bad(label .. " target has unknown field " .. tostring(key)) end end
                    if not text(t.objective or t.marker) then bad(label .. " target id must be text") end
                end
            end
        end
    end
    return errors
end
return M
