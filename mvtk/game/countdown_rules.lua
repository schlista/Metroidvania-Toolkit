-- Pure countdowns.lua rules shared by the startup schema, headless Lua and the
-- editor's LuaJ sandbox. Bundled requires only: an exported game validates the
-- file at startup and cannot read project files.
local Condition = require "mvtk.world.presence_condition"
local M = {}
M.MAX_LABEL_BYTES = 120 -- Source text travels in msg.post tables (2 KB limit).
M.TIMEOUTS = {death=true, restart=true, return_safe=true}
M.DEFAULT_WARNINGS = {10, 5}
local TOP = {warning_sfx=true, finish_sfx=true, fail_sfx=true, tenths_below=true, autosave_on_finish=true,
    return_fade_out=true, return_fade_in=true, result_duration=true, countdowns=true}
local ENTRY = {label=true, duration=true, start_when=true, on_timeout=true, finish_flag=true, reward=true,
    repeatable=true, best_time=true, music=true, tint=true, block_saves=true, block_travel=true, warnings=true}
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end
local function blank(v) return v == nil or (type(v) == "string" and not v:match("%S")) end
local function trim(v) return type(v) == "string" and v:match("^%s*(.-)%s*$") or "" end

function M.valid_id(id) return type(id) == "string" and id:match("^[%w_]+$") ~= nil end
function M.active_flag(id) return "countdown_" .. id .. "_active" end
function M.best_flag(id) return "countdown_best_" .. id end
function M.cleared_flag(id) return "countdown_cleared_" .. id end

-- Effective entry with defaults, or nil when the id is unknown.
function M.entry(config, id)
    local row = type(config) == "table" and type(config.countdowns) == "table" and config.countdowns[id]
    if not M.valid_id(id) or type(row) ~= "table" then return nil end
    local warnings = {}
    for _, seconds in ipairs(type(row.warnings) == "table" and row.warnings or M.DEFAULT_WARNINGS) do
        if finite(seconds) and seconds > 0 then warnings[#warnings + 1] = seconds end
    end
    local finish = trim(row.finish_flag)
    return {
        id = id, label = type(row.label) == "string" and row.label or "",
        duration = finite(row.duration) and row.duration > 0 and row.duration or 0,
        start_when = trim(row.start_when),
        on_timeout = M.TIMEOUTS[row.on_timeout] and row.on_timeout or "death",
        finish_flag = finish ~= "" and finish or M.cleared_flag(id),
        reward = type(row.reward) == "string" and row.reward or "",
        repeatable = row.repeatable == true, best_time = row.best_time ~= false,
        music = trim(row.music), tint = type(row.tint) == "table" and row.tint or nil,
        block_saves = row.block_saves ~= false, block_travel = row.block_travel ~= false,
        warnings = warnings,
    }
end

-- Sorted ids of every countdown, valid or not.
function M.ids(config)
    local out = {}
    local rows = type(config) == "table" and type(config.countdowns) == "table" and config.countdowns or {}
    for _, id in ipairs(sorted_keys(rows)) do
        if M.valid_id(id) and type(rows[id]) == "table" then out[#out + 1] = id end
    end
    return out
end

-- env.sfx, when given, is sound_bank.lua's sfx table. Returns a list of messages.
function M.validate(config, env)
    local errors = {}
    local function bad(message) errors[#errors + 1] = "countdowns.lua: " .. message end
    if type(config) ~= "table" then bad("must return a table"); return errors end
    for _, key in ipairs(sorted_keys(config)) do
        if not TOP[key] then bad("unknown field " .. tostring(key)) end
    end
    local sfx = env and env.sfx
    for _, key in ipairs({"warning_sfx", "finish_sfx", "fail_sfx"}) do
        local id = config[key]
        if type(id) ~= "string" then bad(key .. " must be text")
        elseif id ~= "" and type(sfx) == "table" and not sfx[id] then bad(key .. " needs a sound_bank.lua id: " .. id) end
    end
    if not finite(config.tenths_below) or config.tenths_below < 0 or config.tenths_below > 60 then
        bad("tenths_below must be a number from 0 to 60")
    end
    if type(config.autosave_on_finish) ~= "boolean" then bad("autosave_on_finish must be true or false") end
    for _, key in ipairs({"return_fade_out", "return_fade_in", "result_duration"}) do
        if not finite(config[key]) or config[key] < 0 then bad(key .. " must be finite and non-negative") end
    end
    if type(config.countdowns) ~= "table" then bad("countdowns must be a table"); return errors end
    for _, id in ipairs(sorted_keys(config.countdowns)) do
        local row, at = config.countdowns[id], "countdowns." .. tostring(id)
        if not M.valid_id(id) then bad(at .. ": ids use letters, digits and underscores only")
        elseif type(row) ~= "table" then bad(at .. " must be a table")
        else
            for _, key in ipairs(sorted_keys(row)) do
                if not ENTRY[key] then bad(at .. " has unknown field " .. tostring(key)) end
            end
            if type(row.label) ~= "string" then bad(at .. ".label must be source text")
            elseif #row.label > M.MAX_LABEL_BYTES then bad(at .. ".label is longer than " .. M.MAX_LABEL_BYTES .. " bytes") end
            if not finite(row.duration) or row.duration <= 0 then bad(at .. ".duration must be a number above 0") end
            if row.start_when ~= nil and type(row.start_when) ~= "string" then bad(at .. ".start_when must be text")
            elseif not blank(row.start_when) then
                local ok, err = Condition.parse(row.start_when)
                if not ok then bad(at .. ".start_when: " .. tostring(err)) end
            end
            if not M.TIMEOUTS[row.on_timeout] then bad(at .. ".on_timeout must be death, restart or return_safe") end
            if row.finish_flag ~= nil and (type(row.finish_flag) ~= "string"
                or (not blank(row.finish_flag) and not trim(row.finish_flag):match("^[%w_:%.%-]+$"))) then
                bad(at .. ".finish_flag must be a flag name without spaces, or blank")
            end
            for _, key in ipairs({"reward", "music"}) do
                if row[key] ~= nil and type(row[key]) ~= "string" then bad(at .. "." .. key .. " must be text") end
            end
            for _, key in ipairs({"repeatable", "best_time", "block_saves", "block_travel"}) do
                if row[key] ~= nil and type(row[key]) ~= "boolean" then bad(at .. "." .. key .. " must be true or false") end
            end
            if row.tint ~= nil then
                if type(row.tint) ~= "table" then bad(at .. ".tint must be {r=, g=, b=, a=}")
                else
                    for _, key in ipairs({"r", "g", "b", "a"}) do
                        local v = row.tint[key]
                        if (v ~= nil or key ~= "a") and (not finite(v) or v < 0 or v > 1) then
                            bad(at .. ".tint." .. key .. " must be a number from 0 to 1")
                        end
                    end
                end
            end
            if row.warnings ~= nil then
                local list, count = row.warnings, 0
                if type(list) ~= "table" then bad(at .. ".warnings must be a list of seconds")
                else
                    for k in pairs(list) do count = count + 1
                        if type(k) ~= "number" then bad(at .. ".warnings must be a list") break end
                    end
                    if count ~= #list then bad(at .. ".warnings must be a list without gaps") end
                    for _, seconds in ipairs(list) do
                        if not finite(seconds) or seconds <= 0 then bad(at .. ".warnings need seconds above 0") end
                    end
                end
            end
        end
    end
    return errors
end

return M
