-- Pure UTF-8 spreadsheet interchange. Escape controls before TSV quoting.
-- IDs track UI keys or exact source text; locations track changed wording.
local Collector = require "developer.tools.localization_collect"
local M = {}
local COLUMNS = {"id", "where", "source", "translation", "status"}

function M.utf8(text)
    local i = 1
    while i <= #text do
        local a, n = text:byte(i), 0
        if a < 128 then n = 1
        elseif a >= 194 and a <= 223 then n = 2
        elseif a >= 224 and a <= 239 then n = 3
        elseif a >= 240 and a <= 244 then n = 4 end
        if n == 0 or i+n-1 > #text then return nil, "Not UTF-8 at byte " .. i .. "; save the spreadsheet as UTF-8 TSV." end
        for j = i+1, i+n-1 do
            local b = text:byte(j)
            if b < 128 or b > 191 then return nil, "Not UTF-8 at byte " .. j .. "; save the spreadsheet as UTF-8 TSV." end
        end
        local b = text:byte(i+1)
        if (a == 224 and b < 160) or (a == 237 and b > 159)
            or (a == 240 and b < 144) or (a == 244 and b > 143) then
            return nil, "Not UTF-8 at byte " .. i .. "; save the spreadsheet as UTF-8 TSV."
        end
        i = i+n
    end
    return true
end

local function escape(value)
    local text = value:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\r", "\\r"):gsub("\n", "\\n")
    if text:find('"', 1, true) then text = '"' .. text:gsub('"', '""') .. '"' end
    return text
end
local function unescape(text)
    local out, i = {}, 1
    local codes = {t="\t", n="\n", r="\r", ["\\"]="\\"}
    while i <= #text do
        local ch = text:sub(i,i)
        if ch == "\\" then
            local replacement = codes[text:sub(i+1,i+1)]
            assert(replacement, "Unknown escape; use \\t, \\n, \\r or \\\\.")
            out[#out+1] = replacement; i = i+2
        else out[#out+1] = ch; i = i+1 end
    end
    return table.concat(out)
end
function M.encode(rows)
    local lines = {table.concat(COLUMNS, "\t")}
    for _, row in ipairs(rows) do
        local cells = {}
        for _, column in ipairs(COLUMNS) do cells[#cells+1] = escape(row[column] or "") end
        lines[#lines+1] = table.concat(cells, "\t")
    end
    return table.concat(lines, "\n") .. "\n"
end
local function cells(line)
    local out, i = {}, 1
    while true do
        local value = {}
        if line:sub(i,i) == '"' then
            i = i+1
            while true do
                local ch = line:sub(i,i)
                assert(ch ~= "", "Unclosed spreadsheet quote")
                if ch == '"' then
                    if line:sub(i+1,i+1) == '"' then value[#value+1] = '"'; i = i+2
                    else i = i+1; break end
                else value[#value+1] = ch; i = i+1 end
            end
            assert(i > #line or line:sub(i,i) == "\t", "Unexpected text after spreadsheet quote")
        else
            while i <= #line and line:sub(i,i) ~= "\t" do value[#value+1] = line:sub(i,i); i = i+1 end
        end
        out[#out+1] = unescape(table.concat(value))
        if i > #line then break end
        i = i+1
    end
    return out
end
function M.decode(text)
    local valid, err = M.utf8(text); if not valid then return nil, err end
    text = text:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
    local rows, seen, number = {}, {}, 0
    for line in (text .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("(.-)\n") do
        number = number+1
        local ok, values = pcall(cells, line)
        if not ok then return nil, "Row " .. number .. ": " .. tostring(values) end
        if #values ~= #COLUMNS then return nil, "Row " .. number .. ": expected id, where, source, translation, status (5 columns)." end
        if number == 1 then
            for i, name in ipairs(COLUMNS) do if values[i] ~= name then return nil, "Use the exported TSV header: id, where, source, translation, status." end end
        else
            local row = {row=number}
            for i, name in ipairs(COLUMNS) do row[name] = values[i] end
            if row.id == "" or row.source == "" then return nil, "Row " .. number .. ": id and source must not be empty." end
            if seen[row.id] then return nil, "Row " .. number .. ": duplicate id " .. row.id end
            if row.status ~= "done" and row.status ~= "missing" and row.status ~= "stale" then return nil, "Row " .. number .. ": status must be missing, done or stale." end
            seen[row.id] = true; rows[#rows+1] = row
        end
    end
    if number == 0 then return nil, "The TSV is empty; Export Text for Translation first." end
    return rows
end
function M.key(row)
    return row.id:sub(1,3) == "ui:" and row.id:sub(4) or row.source
end
function M.id(entry) return entry.key and "ui:" .. entry.key or "source:" .. entry.source end
function M.same_tokens(source, translation)
    local a, b = Collector.tokens(source), Collector.tokens(translation)
    return table.concat(a, "\0") == table.concat(b, "\0")
end
function M.validate(rows)
    local values = {}
    for i, row in ipairs(rows) do
        local label = "Row " .. (row.row or i+1) .. " (" .. row.id .. ")"
        if row.status == "done" and row.translation == "" then return nil, label .. ": a done translation must not be empty." end
        if row.translation ~= "" then
            if not M.same_tokens(row.source, row.translation) then
                return nil, label .. ": token mismatch; keep every placeholder and input/printf token, including repeats."
            end
            local key = M.key(row)
            if values[key] and values[key] ~= row.translation then return nil, label .. ": conflicting translations for " .. key end
            values[key] = row.translation
        end
    end
    return values
end
function M.export(entries, previous, translations, check_only)
    local by_source, by_id, by_where = {}, {}, {}
    for _, row in ipairs(previous or {}) do
        by_id[row.id] = row
        -- UI wording must stay separated by meaning even when English is equal.
        if row.id:sub(1,3) ~= "ui:" then
            by_source[row.source] = row
            for reference in (row.where or ""):gmatch("[^\n]+") do
                by_where[reference] = by_where[reference] or {}
                by_where[reference][#by_where[reference]+1] = row
            end
        end
    end
    local rows = {}
    for _, entry in ipairs(entries) do
        local id = M.id(entry)
        local old
        if entry.key then old = by_id[id] else old = by_source[entry.source] end
        local ambiguity
        if not old and not entry.key then
            local candidates, seen, values, sources = {}, {}, {}, {}
            for _, reference in ipairs(entry.where) do
                for _, candidate in ipairs(by_where[reference] or {}) do
                    if not seen[candidate] then
                        seen[candidate] = true; candidates[#candidates+1] = candidate
                        sources[#sources+1] = candidate.source
                        if type(candidate.translation) == "string" and candidate.translation ~= "" then values[candidate.translation] = candidate end
                    end
                end
            end
            local count = 0
            for _, candidate in pairs(values) do count = count+1; old = candidate end
            if count == 0 then old = candidates[1] end
            if count > 1 then
                table.sort(sources)
                ambiguity = "Ambiguous previous translations at " .. table.concat(entry.where, "; ")
                    -- Plain quotes: the editor's LuaJ string.format differs from desktop Lua.
                    .. " for changed source \"" .. entry.source .. "\": "
                    .. table.concat(sources, " | ") .. ". Save a copy of the TSV, then resolve the competing translation cells before Export."
                if not check_only then error(ambiguity) end
                old = {source="", translation="", status="stale"}
            end
        end
        local value = old and old.translation or (translations or {})[entry.key or entry.source]
        if type(value) ~= "string" then value = "" end
        local stale = old and (old.source ~= entry.source or old.status == "stale")
        rows[#rows+1] = {id=id, where=table.concat(entry.where, "\n"), source=entry.source,
            translation=value, status=stale and "stale" or (value == "" and "missing" or "done"), ambiguity=ambiguity}
    end
    return rows
end
return M
