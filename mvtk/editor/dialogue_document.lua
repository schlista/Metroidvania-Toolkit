-- Pure dialogue editing model. Callers own disk reads, reference snapshots and writes.
local Fresh = require "mvtk.editor.fresh_config"
local Sources = require "mvtk.dialogue.dialogue_sources"
local Model = require "mvtk.core.creator_settings_model"
local M = {}
local STATIC = "developer/config/narrative/dialogues.lua"
local AUTHORED = "developer/config/narrative/dialogues_authored.lua"
local HEADER = "-- Dialogue sequences written by Project > Dialogue Editor....\n"
    .. "-- A key here replaces the dialogues.lua sequence with the same id; dialogues.lua is never rewritten.\n"
    .. "-- Line and choice fields are documented at the top of narrative/dialogues.lua.\n"

local function valid_id(id)
    -- Same ASCII key rule as CatalogEnums.check_values.
    return type(id) == "string" and id ~= "" and not id:find("[^A-Za-z0-9_.-]")
end

local function refresh(doc)
    doc.merged, doc.origin = Sources.merge(doc.static, doc.authored)
    return doc
end

function M.load(opts)
    local root = tostring(opts.root or "."):gsub("\\", "/"):gsub("/$", "")
    local authored_text, authored_missing = nil, false
    local loader = Fresh.new({root=root, read=function(path)
        local text = opts.read(path)
        if path == root .. "/" .. AUTHORED then
            authored_text, authored_missing = text, text == nil
        end
        return text
    end})
    local static, err = loader.load_path(STATIC)
    if not static then return nil, err end
    -- Older projects may not have this optional file. Malformed existing files
    -- still fail to load; they must never be mistaken for an empty document.
    local authored, authored_err = loader.load_path(AUTHORED)
    if not authored and not authored_missing then return nil, authored_err end
    return refresh({static=static, authored=authored or {}, authored_text=authored_text})
end

function M.set(doc, id, lines)
    if not valid_id(id) then return nil, "Use a nonempty id containing letters, digits, _, . or -." end
    if type(lines) ~= "table" then return nil, "A sequence must be a table of lines." end
    -- Copy the entire replacement, including fields this editor cannot edit.
    doc.authored[id] = Model.copy(lines)
    return refresh(doc)
end

function M.remove(doc, id)
    doc.authored[id] = nil
    return refresh(doc)
end

-- Includes both the room reference index and configured dialogue branches.
-- The future window uses this same count for its Used by display.
function M.used_by(doc, id, ctx)
    local count = 0
    for _,ref in ipairs(ctx and ctx.index and ctx.index.references or {}) do
        if ref.namespace == "dialogue" and ref.key == id then count = count + 1 end
    end
    for _,lines in pairs(doc.merged) do
        if type(lines) == "table" then
            for _,line in ipairs(lines) do
                if type(line) == "table" then
                    if line.next == id then count = count + 1 end
                    if type(line.choices) == "table" then
                        for _,choice in ipairs(line.choices) do
                            if type(choice) == "table" and choice["goto"] == id then count = count + 1 end
                        end
                    end
                end
            end
        end
    end
    return count
end

function M.rename(doc, id, new_id, ctx)
    if not valid_id(new_id) then return nil, "Use a nonempty id containing letters, digits, _, . or -." end
    if doc.merged[id] == nil then return nil, "Sequence does not exist." end
    if id == new_id then return doc end
    if M.used_by(doc, id, ctx) > 0 then return nil, "Sequence is used; its id cannot be renamed." end
    -- Without tombstones the baseline id would remain, so renaming it would
    -- actually duplicate it. Overrides can only be reverted to that baseline.
    if doc.static[id] ~= nil then return nil, "Baseline sequence ids cannot be renamed; add a new sequence instead." end
    if doc.merged[new_id] ~= nil or doc.authored[new_id] ~= nil then return nil, "Sequence id already exists." end
    doc.authored[new_id], doc.authored[id] = doc.authored[id], nil
    return refresh(doc)
end

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys, function(a,b)
        if type(a) == type(b) and (type(a) == "string" or type(a) == "number") then return a < b end
        return type(a) .. tostring(a) < type(b) .. tostring(b)
    end)
    return keys
end

-- Context maps contain ability definitions and quest definitions keyed by id.
-- Quest definitions have ordered steps with stable step.id values. Quests may
-- ship off; missing quest/step references are always warnings.
function M.validate(doc, ctx)
    ctx = ctx or {}
    local out = {}
    local function issue(code, severity, id, line, choice, message)
        out[#out+1] = {code=code, severity=severity, id=id, line=line, choice=choice, message=message}
    end
    local function quest(value, has_step, id, line, choice)
        local quest_id, step_id = value, nil
        if has_step and type(value) == "string" then
            quest_id, step_id = value:match("^(.+)%.([^.]+)$")
            if not quest_id then quest_id = value end
        end
        local def = (ctx.quests or {})[quest_id]
        if type(def) ~= "table" then
            issue("unknown_quest", "warning", id, line, choice, "Unknown quest: " .. tostring(quest_id))
        elseif has_step then
            local found = false
            for _,step in ipairs(def.steps or {}) do if step.id == step_id then found = true end end
            if not found then issue("unknown_quest_step", "warning", id, line, choice,
                "Unknown quest step: " .. tostring(value)) end
        end
    end
    local function fields(row, id, line, choice)
        local cond = row.condition
        if cond ~= nil then
            if type(cond) ~= "table" or not (cond.flag or cond.ability or cond.quest or cond.quest_step) then
                issue("unknown_condition", "error", id, line, choice, "Choose a flag, ability, quest state or quest step condition.")
            elseif cond.flag then -- Flags are project-defined, not a closed catalog.
            elseif cond.ability then
                if not (ctx.abilities or {})[cond.ability] then
                    issue("unknown_ability", "warning", id, line, choice, "Unknown ability: " .. tostring(cond.ability))
                end
            elseif cond.quest then quest(cond.quest, false, id, line, choice)
            else quest(cond.quest_step, true, id, line, choice) end
        end
        for _,action in ipairs({"quest_start", "quest_advance", "quest_turn_in", "quest_fail"}) do
            local value = row[action]
            if value ~= nil then
                local step = action == "quest_advance" and type(value) == "string" and value:find(".", 1, true) ~= nil
                quest(value, step, id, line, choice)
            end
        end
    end
    -- Inspect invalid authored values too: Sources.merge deliberately ignores
    -- them at runtime rather than hiding a valid baseline sequence.
    local candidates = {}
    for id,lines in pairs(doc.merged) do candidates[id] = lines end
    for id,lines in pairs(doc.authored) do candidates[id] = lines end
    for _,id in ipairs(sorted_keys(candidates)) do
        local lines = candidates[id]
        if not valid_id(id) then issue("invalid_id", "error", id, nil, nil,
            "Use a nonempty id containing letters, digits, _, . or -.") end
        if type(lines) ~= "table" or #lines == 0 then
            issue("empty_sequence", "error", id, nil, nil, "A sequence needs at least one line.")
        else
            for i,line in ipairs(lines) do
                if type(line) ~= "table" or (line.text == nil and line.choices == nil) then
                    issue("empty_line", "error", id, i, nil, "A line needs text or choices.")
                end
                if type(line) == "table" then
                    fields(line, id, i)
                    if line.next ~= nil and not doc.merged[line.next] then
                        issue("missing_next", "warning", id, i, nil, "Unknown next sequence: " .. tostring(line.next))
                    end
                    if line.choices ~= nil and type(line.choices) ~= "table" then
                        issue("empty_choice", "error", id, i, nil, "Choices must be a table of choices with text.")
                    elseif type(line.choices) == "table" then
                        if #line.choices > 4 then issue("too_many_choices", "error", id, i, nil, "A line supports at most four choices.") end
                        for j,choice in ipairs(line.choices) do
                            if type(choice) ~= "table" or type(choice.text) ~= "string" or not choice.text:match("%S") then
                                issue("empty_choice", "error", id, i, j, "A choice needs text.")
                            end
                            if type(choice) == "table" then
                                fields(choice, id, i, j)
                                if choice["goto"] ~= nil and not doc.merged[choice["goto"]] then
                                    issue("missing_goto", "warning", id, i, j, "Unknown goto sequence: " .. tostring(choice["goto"]))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Dotted ids can alias nested paths ("story.1" and story[1]). Keep only the
-- encoder's top-level comments. Track quoted strings so a multiline text value
-- containing an indented comment-like line is preserved byte for byte.
local function sequence_comments(source)
    local rows, quoted = {}, false
    for row in (source .. "\n"):gmatch("(.-)\n") do
        local indent = not quoted and row:match("^( +)%-%- ")
        if not indent or #indent == 4 then
            rows[#rows+1] = row
            local escaped = false
            for i = 1, #row do
                local char = row:sub(i, i)
                if escaped then escaped = false
                elseif quoted and char == "\\" then escaped = true
                elseif char == '"' then quoted = not quoted end
            end
        end
    end
    return table.concat(rows, "\n")
end

-- Pass doc.static to identify overrides of this freshly loaded project.
-- Without it every sequence is described as newly added.
function M.serialize(authored, static)
    local comments = {}
    for id in pairs(authored) do
        assert(valid_id(id), "Cannot serialize an invalid dialogue id")
        comments[id] = static and static[id] ~= nil and ("Replaces dialogues.lua's " .. id .. ".")
            or "Added in the Dialogue Editor."
    end
    return HEADER .. "return " .. sequence_comments(Model.encode(authored, comments)) .. "\n"
end

return M
