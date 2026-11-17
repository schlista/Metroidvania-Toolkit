-- Translation authoring/checking shared by the editor and headless preparation.
-- Configs are read afresh. All writes use the project transaction journal.
local TSV = require "mvtk.editor.translation_tsv"
local Collector = require "developer.tools.localization_collect"
local Fresh = require "mvtk.editor.fresh_config"
local Transaction = require "mvtk.editor.project_transaction"
local Model = require "mvtk.core.creator_settings_model"
local M = {}
local REGISTRY = "developer/config/localization.lua"
local MANIFEST = "developer/config/translations/manifest_generated.lua"
local RULES = {one_other=true, none=true, one_few_many=true}

function M.code(code)
    assert(type(code) == "string" and #code <= 32 and code:match("^[a-z][a-z0-9_-]*$")
        and code ~= "manifest_generated", "Code must start with a lowercase letter and contain only lowercase letters, digits, _ or - (up to 32 characters).")
    assert(code ~= "con" and code ~= "prn" and code ~= "aux" and code ~= "nul"
        and not code:match("^com[1-9]$") and not code:match("^lpt[1-9]$"),
        "Code is a reserved Windows device name; choose another language code.")
    return code
end
local function context(opts)
    opts = opts or {}
    local root = (opts.root or "."):gsub("\\", "/"):gsub("/$", "")
    local read = opts.read or Transaction.read
    return root, read, Fresh.new({root=root, read=read})
end
local function same(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end
local function strings(values)
    local out = {}
    for key, value in pairs(values or {}) do
        if type(key) == "string" and type(value) == "string" and value ~= "" then out[key] = value end
    end
    return out
end
local function table_at(loader, read, root, path)
    if not read(root .. "/" .. path) then return {} end
    return assert(loader.load_path(path))
end
function M.registry(opts)
    local _, _, loader = context(opts)
    local registry = assert(loader.load_path(REGISTRY))
    assert(type(registry.languages) == "table" and #registry.languages > 0, "The language registry is empty.")
    local seen = {}
    for _, language in ipairs(registry.languages) do
        M.code(language.code)
        assert(not seen[language.code], "Duplicate language code: " .. language.code)
        assert(type(language.name) == "string" and language.name:match("%S"), "Each language needs its own name.")
        assert(TSV.utf8(language.name))
        assert(RULES[language.plural], "Unknown plural rule for " .. language.code)
        seen[language.code] = true
    end
    return registry
end
local function language(opts, code)
    M.code(code)
    local registry = M.registry(opts)
    for _, item in ipairs(registry.languages) do if item.code == code then return item, registry end end
    error("Add language " .. code .. " before exporting or importing.")
end
function M.recover(opts)
    local root = context(opts)
    return Transaction.recover(root .. "/developer", opts and opts.transaction)
end
-- Locate the literal language list without treating braces in strings/comments
-- as syntax. Registry settings and comments outside the list stay authored.
local function replace_languages(source, languages)
    local i, depth, opening = 1, 0, nil
    while i <= #source do
        local ch = source:sub(i,i)
        local comment = source:sub(i,i+1) == "--"
        local bracket = comment and i+2 or i
        local equals = source:match("^%[(=*)%[", bracket)
        if equals then
            local _, last = source:find("]" .. equals .. "]", bracket+2+#equals, true)
            assert(last, "Unclosed registry string or comment")
            i = last+1
        elseif comment then i = source:find("\n", i+2, true) or #source+1
        elseif ch == '"' or ch == "'" then
            local quote = ch; i = i+1
            while i <= #source and source:sub(i,i) ~= quote do
                i = i + (source:sub(i,i) == "\\" and 2 or 1)
            end
            i = i+1
        elseif ch == "{" then depth = depth+1; i = i+1
        elseif ch == "}" then
            if opening and depth == 2 then
                return source:sub(1,opening-1) .. Model.encode(languages) .. source:sub(i+1)
            end
            depth = depth-1; i = i+1
        elseif ch:match("[%a_]") then
            local _, last, word = source:find("^([%a_][%w_]*)", i)
            if depth == 1 and word == "languages" then opening = source:match("^%s*=%s*(){", last+1) end
            i = last+1
        else i = i+1 end
    end
    error("Cannot find the literal languages list in " .. REGISTRY)
end
function M.add(opts, code, name, plural)
    M.code(code)
    assert(type(name) == "string" and name:match("%S"), "Own name must not be empty.")
    assert(TSV.utf8(name)); assert(RULES[plural], "Choose a plural rule.")
    M.recover(opts)
    local registry = M.registry(opts)
    for _, item in ipairs(registry.languages) do assert(item.code ~= code, "Language already exists: " .. code) end
    registry.languages[#registry.languages+1] = {code=code, name=name, plural=plural}
    local root, read = context(opts)
    local source = assert(read(root .. "/" .. REGISTRY))
    local changed = replace_languages(source, registry.languages)
    local compiled, syntax = (loadstring or load)(changed, "@" .. REGISTRY)
    assert(compiled, "Language registry was not written: " .. tostring(syntax))
    Transaction.commit(root .. "/developer", {{path="config/localization.lua", content=changed}}, opts.transaction)
    return registry
end
function M.entries(opts) return assert(Collector.collect(opts)) end
local function tsv_path(code) return "developer/localization/" .. M.code(code) .. ".tsv" end
local function table_path(code) return "developer/config/translations/" .. M.code(code) .. ".lua" end
local function previous(read, root, path)
    local text = read(root .. "/" .. path)
    if text == nil then return nil end
    local rows, err = TSV.decode(text)
    assert(rows, path .. ": " .. tostring(err))
    return rows
end
function M.export(opts, code)
    M.code(code); M.recover(opts)
    language(opts, code)
    local root, read, loader = context(opts)
    local path = tsv_path(code)
    local rows = TSV.export(M.entries(opts), previous(read, root, path),
        strings(table_at(loader, read, root, table_path(code))))
    Transaction.commit(root .. "/developer", {{path="localization/" .. code .. ".tsv", content=TSV.encode(rows)}}, opts.transaction)
    return rows, path
end
function M.manifest(map)
    local codes = {}
    for code, included in pairs(map) do if included == true then codes[#codes+1] = M.code(code) end end
    table.sort(codes)
    local lines = {"-- Generated translation dependencies. Import adds literal requires inside this",
        "-- block and returns a code -> true map below. English alone needs no table.", "if false then"}
    for _, code in ipairs(codes) do lines[#lines+1] = '    require("developer.config.translations.' .. code .. '")' end
    lines[#lines+1] = "end"
    if #codes == 0 then lines[#lines+1] = "return {}"
    else
        lines[#lines+1] = "return {"
        for _, code in ipairs(codes) do lines[#lines+1] = "    [" .. Model.encode(code) .. "] = true," end
        lines[#lines+1] = "}"
    end
    return table.concat(lines, "\n") .. "\n"
end
function M.import(opts, code)
    M.code(code); M.recover(opts)
    language(opts, code)
    local root, read, loader = context(opts)
    local path = tsv_path(code)
    local rows = assert(previous(read, root, path), "Export Text for Translation first: " .. path)
    local values, err = TSV.validate(rows); assert(values, path .. ": " .. tostring(err))
    local current = {}
    for _, entry in ipairs(M.entries(opts)) do current[TSV.id(entry)] = entry.source end
    for _, row in ipairs(rows) do
        assert(current[row.id] == row.source, path .. ": Row " .. row.row .. " (" .. row.id
            .. "): source or id changed. Export Text for Translation again; keep id and source unchanged.")
    end
    local target = table_path(code)
    local old = table_at(loader, read, root, target)
    local text = read(root .. "/" .. target)
    -- An unchanged spreadsheet preserves even a hand-formatted table byte for byte.
    if not text or not same(old, values) then
        text = "-- Generated by Project > Translations. Edit the UTF-8 TSV and Import Translations.\n"
            .. "-- Keys are exact creator source text or framework UI keys; empty values use English.\nreturn " .. Model.encode(values) .. "\n"
    end
    local manifest = table_at(loader, read, root, MANIFEST)
    manifest[code] = true
    local writes, warning = Transaction.commit(root .. "/developer", {
        {path="config/translations/" .. code .. ".lua", content=text},
        {path="config/translations/manifest_generated.lua", content=M.manifest(manifest)},
    }, opts.transaction)
    return {count=#rows, writes=writes, warning=warning}
end
function M.check(opts)
    local root, read, loader = context(opts)
    local registry, entries = M.registry(opts), M.entries(opts)
    local manifest = table_at(loader, read, root, MANIFEST)
    local report = {languages={}, lines={}, errors=0, warnings=0}
    for _, item in ipairs(registry.languages) do
        local values = strings(table_at(loader, read, root, table_path(item.code)))
        local result = {code=item.code, name=item.name, missing=0, stale=0, errors=0, differs=false, diagnostics={}}
        local function problem(message)
            result.errors = result.errors+1; result.diagnostics[#result.diagnostics+1] = message
        end
        local text = read(root .. "/" .. tsv_path(item.code))
        local rows, err
        if text then
            rows, err = TSV.decode(text)
            if not rows then problem(tsv_path(item.code) .. ": " .. err)
            else
                local pending, validation = TSV.validate(rows)
                if not pending then problem(tsv_path(item.code) .. ": " .. validation)
                else result.differs = not same(pending, values) end
                local refreshed = TSV.export(entries, rows, values, true)
                for _, row in ipairs(refreshed) do
                    if row.status == "stale" then result.stale = result.stale+1 end
                    if row.ambiguity then result.diagnostics[#result.diagnostics+1] = row.ambiguity end
                end
            end
        end
        for _, entry in ipairs(entries) do
            local key = entry.key or entry.source
            local value = manifest[item.code] == true and values[key] or nil
            -- English is the built-in source language; it needs no translation table.
            if not value and item.code ~= "en" then result.missing = result.missing+1 end
            if value and not TSV.same_tokens(entry.source, value) then
                problem(table_path(item.code) .. ": " .. key .. ": token mismatch (" .. entry.where[1] .. ")")
            end
        end
        if next(values) and manifest[item.code] ~= true then result.differs = true end
        local line = string.format("%s: %d missing, %d errors; %d stale", item.name, result.missing, result.errors, result.stale)
        if result.differs then line = line .. "; TSV differs from imported table" end
        report.lines[#report.lines+1] = line
        for _, diagnostic in ipairs(result.diagnostics) do report.lines[#report.lines+1] = diagnostic end
        if result.missing > 0 or result.stale > 0 or result.differs then report.warnings = report.warnings+1 end
        report.errors = report.errors+result.errors; report.languages[#report.languages+1] = result
    end
    return report
end
return M
