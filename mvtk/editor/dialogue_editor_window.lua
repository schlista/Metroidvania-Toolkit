-- Native dialogue authoring. Callbacks edit memory; only the modal run loop does I/O.
local Document = require "mvtk.editor.dialogue_document"
local Model = require "mvtk.core.creator_settings_model"
local Transaction = require "mvtk.editor.project_transaction"
local Context = require "mvtk.editor.game_settings_context"
local Fresh = require "mvtk.editor.fresh_config"
local Catalog = require "mvtk.tiled.catalog_enums"
local M = {}
local AUTHORED = "/developer/config/narrative/dialogues_authored.lua"
local CONDITIONS = {"none", "flag", "not flag", "ability", "not ability", "quest state", "quest step"}
local ACTIONS = {"quest_start", "quest_advance", "quest_turn_in", "quest_fail"}
local ACTION_LABELS = {quest_start="Start quest", quest_advance="Advance quest", quest_turn_in="Turn in quest", quest_fail="Fail quest"}

-- JavaFX interprets underscores in button text as mnemonics.
function M.button_text(text) return (text:gsub("_", "__")) end

local function keys(map, first)
    local out = {}
    for id in pairs(map or {}) do out[#out+1] = id end
    table.sort(out)
    if first ~= nil then table.insert(out, 1, first) end
    return out
end
local function options(values, current)
    local out = Model.copy(values)
    if current ~= nil then
        for _, value in ipairs(out) do if value == current then return out end end
        out[#out+1] = current
    end
    return out
end
local function optional(value) if value ~= "" then return value end end
local function invalid(issues)
    for _, issue in ipairs(issues) do if issue.severity == "error" then return true end end
    return false
end
local function field_issue(ui, issues, choice)
    for _, issue in ipairs(issues) do
        if issue.choice == choice then
            return {severity=issue.severity == "error" and ui.ISSUE_SEVERITY.ERROR or ui.ISSUE_SEVERITY.WARNING,
                message=issue.message}
        end
    end
    return false
end
local function summary(line)
    if type(line) ~= "table" then return "Invalid line" end
    local speaker = type(line.speaker) == "string" and line.speaker or ""
    return speaker .. ": " .. tostring(line.text or ""):sub(1, 60)
        .. (line.condition and " [condition]" or "") .. (line.choices and " [choices]" or "")
        .. (line.next and " [next]" or "")
end
local function condition_kind(cond)
    if not cond then return "none" end
    if type(cond) ~= "table" then return "unknown" end
    if cond.flag then return cond.invert and "not flag" or "flag" end
    if cond.ability then return cond.invert and "not ability" or "ability" end
    if cond.quest then return "quest state" end
    if cond.quest_step then return "quest step" end
    return "unknown"
end
local function line_issues(doc, id, index, line, context)
    local draft = Model.copy(doc)
    local lines = Model.copy(draft.merged[id] or {})
    lines[index] = line
    assert(Document.set(draft, id, lines))
    local out = {}
    for _, issue in ipairs(Document.validate(draft, context)) do
        if issue.id == id and issue.line == index then out[#out+1] = issue end
    end
    return out
end

function M.component(ui)
    return ui.component(function(props)
        local doc, set_doc = ui.use_state(Model.copy, props.doc)
        local selected, set_selected = ui.use_state(props.selected)
        local new_id, set_new_id = ui.use_state(props.new_id or "")
        local function change(next_doc)
            props.memory.doc = next_doc
            set_doc(next_doc)
        end
        local function result(action, index)
            return {action=action, doc=doc, selected=selected, new_id=new_id, index=index}
        end
        local issues = Document.validate(doc, props.context)
        local rows = {
            ui.label({text=string.format("%d sequences; %d issues.", #keys(doc.merged), #issues)}),
            ui.paragraph({text=props.status or "Edit a sequence, then Save. Baseline dialogue is kept in dialogues.lua."}),
            ui.label({text="Sequence"}),
            ui.select_box({value=selected, options=keys(doc.merged), to_string=function(id)
                return id .. (doc.authored[id] and (doc.static[id] and " (override)" or " (new)") or " (dialogues.lua)")
            end, on_value_changed=set_selected}),
            ui.label({text="New sequence id"}),
            ui.string_field({value=new_id, on_value_changed=set_new_id}),
            ui.dialog_button({text="New sequence", result=result("new")}),
        }
        if selected then
            rows[#rows+1] = ui.label({text=string.format("Used by %d objects", Document.used_by(doc, selected, props.context))})
            if doc.authored[selected] ~= nil then
                rows[#rows+1] = ui.dialog_button({text=doc.static[selected] and "Revert to dialogues.lua" or "Delete", result=result("remove")})
            end
            local lines = type(doc.merged[selected]) == "table" and doc.merged[selected] or {}
            for i, line in ipairs(lines) do
                local index = i
                local function edit_lines(fn)
                    local next_doc = Model.copy(doc)
                    local next_lines = Model.copy(lines)
                    fn(next_lines)
                    assert(Document.set(next_doc, selected, next_lines))
                    change(next_doc)
                end
                local function move(delta)
                    edit_lines(function(next_lines) next_lines[index], next_lines[index+delta] = next_lines[index+delta], next_lines[index] end)
                end
                rows[#rows+1] = ui.horizontal({spacing=ui.SPACING.SMALL, children={
                    ui.label({text=summary(line), grow=true}),
                    ui.dialog_button({text="Edit…", result=result("edit", index)}),
                    ui.button({text="Move up", enabled=index>1, on_pressed=function() move(-1) end}),
                    ui.button({text="Move down", enabled=index<#lines, on_pressed=function() move(1) end}),
                    ui.button({text="Remove", on_pressed=function() edit_lines(function(next_lines) table.remove(next_lines, index) end) end}),
                }})
            end
            rows[#rows+1] = ui.dialog_button({text="Add line", result=result("add")})
        end
        for _, issue in ipairs(issues) do
            rows[#rows+1] = ui.paragraph({text=tostring(issue.id) .. (issue.line and (" line " .. issue.line) or "") .. ": " .. issue.message})
        end
        return ui.dialog({title="Dialogue Editor", width=760, height=680, resizable=true,
            content=ui.scroll({content=ui.vertical({padding=ui.PADDING.MEDIUM, spacing=ui.SPACING.SMALL, children=rows})}),
            -- Enter commits a field; no default dialog button.
            buttons={ui.dialog_button({text="Save", enabled=not invalid(issues), result=result("save")}),
                ui.dialog_button({text="Save and Prepare & Check", enabled=not invalid(issues), result=result("prepare")}),
                ui.dialog_button({text="Close", cancel=true, result=result("close")})}})
    end)
end

function M.line_component(ui)
    return ui.component(function(props)
        -- Shared initializer identity keeps edits across renders in LuaJ.
        local line, set_line = ui.use_state(Model.copy, props.line)
        local function update(fn)
            local next_line = Model.copy(line); fn(next_line); set_line(next_line)
        end
        local issues = line_issues(props.doc, props.id, props.index, line, props.context)
        local rows = {}
        local function field(label, value, changed, values, issue)
            rows[#rows+1] = ui.label({text=label})
            local spec = {value=value, on_value_changed=changed, issue=issue or false}
            if values then
                spec.options=options(values, value)
                spec.to_string=function(v) return v == "" and "none" or tostring(v) end
                rows[#rows+1] = ui.select_box(spec)
            else rows[#rows+1] = ui.string_field(spec) end
        end
        local function line_field(label, key, values, issue)
            local value = line[key]
            -- A structured speaker remains untouched unless the creator edits it.
            field(label, type(value) == "string" and value or "", function(v) update(function(row) row[key]=optional(v) end) end, values, issue)
        end
        line_field("Speaker", "speaker")
        line_field("Text", "text", nil, field_issue(ui, issues))
        if type(line.speaker) == "table" then rows[#rows+1] = ui.paragraph({text="Structured speaker is preserved unless Speaker is edited."}) end
        local kind = condition_kind(line.condition)
        field("Condition", kind, function(value)
            update(function(row)
                if value == "none" then row.condition=nil; return end
                local cond = type(row.condition) == "table" and Model.copy(row.condition) or {}
                cond.flag, cond.ability, cond.quest, cond.quest_step, cond.state, cond.invert = nil,nil,nil,nil,nil,nil
                if value == "flag" or value == "not flag" then cond.flag=""; cond.invert=value == "not flag" or nil
                elseif value == "ability" or value == "not ability" then cond.ability=""; cond.invert=value == "not ability" or nil
                elseif value == "quest state" then cond.quest=""; cond.state="active"
                elseif value == "quest step" then cond.quest_step="" end
                row.condition=cond
            end)
        end, CONDITIONS)
        local cond = type(line.condition) == "table" and line.condition or {}
        local function cond_field(label, key, values, fallback)
            field(label, cond[key] or fallback or "", function(v) update(function(row) row.condition[key]=v end) end, values)
        end
        local context = props.context or {}
        local quests = context.quests or {}
        local quest_ids = keys(context.quests, "")
        local ability_ids = keys(context.abilities, "")
        if kind == "flag" or kind == "not flag" then cond_field("Flag", "flag")
        elseif kind == "ability" or kind == "not ability" then cond_field("Ability", "ability", ability_ids)
        elseif kind == "quest state" then
            cond_field("Quest", "quest", quest_ids)
            cond_field("State", "state", Catalog.row("quest_states").values, "active")
        elseif kind == "quest step" then
            local quest, step = tostring(cond.quest_step or ""):match("^(.+)%.([^.]*)$")
            quest = quest or ""
            field("Quest", quest, function(v) update(function(row) row.condition.quest_step=v .. "." end) end, quest_ids)
            local steps = {""}
            for _, definition in ipairs((quests[quest] or {}).steps or {}) do steps[#steps+1]=definition.id end
            field("Step", step or "", function(v) update(function(row) row.condition.quest_step=quest .. "." .. v end) end, steps)
        end
        if kind == "quest state" or kind == "quest step" then
            rows[#rows+1] = ui.check_box({text="Invert condition", value=cond.invert == true,
                on_value_changed=function(v) update(function(row) row.condition.invert=v or nil end) end})
        end
        line_field("Set flag", "set_flag")
        local sequences = keys(props.doc.merged, "")
        line_field("Next", "next", sequences)
        local advance = Model.copy(quest_ids)
        for _, id in ipairs(keys(quests)) do
            for _, step in ipairs(quests[id].steps or {}) do advance[#advance+1]=id .. "." .. step.id end
        end
        local function actions(choice_index)
            for _, key in ipairs(ACTIONS) do
                local action_key = key
                local row = choice_index and line.choices[choice_index] or line
                field(ACTION_LABELS[key], row[key] or "", function(v) update(function(next_line)
                    local target = choice_index and next_line.choices[choice_index] or next_line
                    target[action_key]=optional(v)
                end) end, key == "quest_advance" and advance or quest_ids)
            end
        end
        actions()
        local choices = type(line.choices) == "table" and line.choices or {}
        for i, choice in ipairs(choices) do
            local index = i
            rows[#rows+1] = ui.label({text="Choice " .. i})
            for _, spec in ipairs({{"Text", "text"}, {"Goto", "goto", sequences}, {"Set flag", "set_flag"}}) do
                local key = spec[2]
                field(spec[1], choice[key] or "", function(v) update(function(row) row.choices[index][key]=optional(v) end) end,
                    spec[3], key == "text" and field_issue(ui, issues, index) or false)
            end
            actions(index)
            rows[#rows+1] = ui.button({text="Remove", on_pressed=function() update(function(row)
                table.remove(row.choices, index)
                if #row.choices == 0 then row.choices=nil end
            end) end})
        end
        rows[#rows+1] = ui.button({text="Add choice", enabled=#choices<4, on_pressed=function() update(function(row)
            row.choices=row.choices or {}; row.choices[#row.choices+1]={text=""}
        end) end})
        for _, issue in ipairs(issues) do rows[#rows+1]=ui.paragraph({text=issue.message}) end
        return ui.dialog({title="Edit dialogue line", width=760, height=680, resizable=true,
            content=ui.scroll({content=ui.vertical({padding=ui.PADDING.MEDIUM, spacing=ui.SPACING.SMALL, children=rows})}),
            buttons={ui.dialog_button({text="Use line", enabled=not invalid(issues), result={line=line}}),
                ui.dialog_button({text="Cancel", cancel=true, result=false})}})
    end)
end

local function load_context(deps)
    local snapshot = Context.load(deps)
    local loader = Fresh.new({root=deps.root, read=deps.read or Transaction.read})
    local abilities = assert(loader.load_path("developer/config/abilities.lua"))
    local quests = assert(loader.load_path("developer/config/quests.lua"))
    return {index=snapshot.ending and snapshot.ending.index, abilities=abilities.abilities or {}, quests=quests.quests or {}}
end
local function confirm(ui, title, text, action)
    return ui.show_dialog(ui.dialog({title=title, content=ui.paragraph({text=text}), buttons={
        ui.dialog_button({text="Keep editing", cancel=true, result=false}),
        ui.dialog_button({text=M.button_text(action), result=true}),
    }})) == true
end

function M.run(deps)
    assert(not deps.headless and deps.editor and deps.editor.ui, "Dialogue Editor needs the Defold editor.")
    local ui = deps.editor.ui
    local root = tostring(deps.root or "."):gsub("\\", "/"):gsub("/$", "")
    local read = deps.read or Transaction.read
    Transaction.recover(root .. "/developer", deps.transaction)
    local opts = {root=root, read=read}
    local doc = assert(Document.load(opts))
    local context = (deps.load_context or load_context)(deps)
    local saved = Model.encode(doc.authored)
    local selected, new_id, status = keys(doc.merged)[1], "", nil
    local view, line_view = M.component(ui), M.line_component(ui)
    while true do
        local memory = {doc=doc}
        local result = ui.show_dialog(view({doc=doc, selected=selected, new_id=new_id, status=status, context=context, memory=memory}))
        doc = result and result.doc or memory.doc
        if result then selected, new_id = result.selected, result.new_id end
        if not result or result.action == "close" then
            if Model.encode(doc.authored) == saved or confirm(ui, "Discard unsaved changes?", "Your dialogue changes have not been saved.", "Discard") then return true end
        else
            local ok, message = pcall(function()
                if result.action == "new" then
                    assert(doc.merged[new_id] == nil and doc.authored[new_id] == nil, "Sequence id already exists.")
                    assert(Document.set(doc, new_id, {})); selected, new_id = new_id, ""
                elseif result.action == "remove" then
                    local count = Document.used_by(doc, selected, context)
                    local action = doc.static[selected] and "Revert to dialogues.lua" or "Delete"
                    if count == 0 or confirm(ui, "Referenced dialogue", selected .. " is used by " .. count .. " objects or dialogue branches. Continue?", action) then
                        Document.remove(doc, selected)
                        if not doc.merged[selected] then selected=keys(doc.merged)[1] end
                    end
                elseif result.action == "edit" or result.action == "add" then
                    local lines = Model.copy(doc.merged[selected])
                    local index = result.index or (#lines+1)
                    local edited = ui.show_dialog(line_view({line=lines[index] or {}, doc=doc, id=selected, index=index, context=context}))
                    if edited then
                        assert(not invalid(line_issues(doc, selected, index, edited.line, context)), "Correct dialogue line errors first.")
                        lines[index]=edited.line; assert(Document.set(doc, selected, lines))
                    end
                elseif result.action == "save" or result.action == "prepare" then
                    assert(not invalid(Document.validate(doc, context)), "Correct dialogue errors before saving.")
                    assert(read(root .. AUTHORED) == doc.authored_text, "The authored file changed since the window opened; reopen it")
                    Transaction.commit(root .. "/developer", {{path="config/narrative/dialogues_authored.lua",
                        content=Document.serialize(doc.authored, doc.static)}}, deps.transaction)
                    doc=assert(Document.load(opts)); saved=Model.encode(doc.authored)
                    status="Saved. Build to play it; run Prepare & Check before Export Game (the publication is stale)."
                    if result.action == "prepare" then
                        assert(type(deps.prepare) == "function", "Prepare & Check is unavailable.")
                        deps.prepare()
                    end
                else error("Unknown dialogue action") end
            end)
            if not ok then status="Dialogue Editor: " .. tostring(message) end
        end
    end
end
return M
