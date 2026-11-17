-- Native loot authoring. Callbacks edit memory; only the modal run loop does I/O.
local Document = require "mvtk.editor.loot_document"
local Model = require "mvtk.core.creator_settings_model"
local Transaction = require "mvtk.editor.project_transaction"
local Fresh = require "mvtk.editor.fresh_config"
local CatalogEnums = require "mvtk.tiled.catalog_enums"
local M = {}
local AUTHORED = "/developer/config/loot_tables_authored.lua"

-- JavaFX interprets underscores in button text as mnemonics.
function M.button_text(text) return (text:gsub("_", "__")) end

local function keys(map)
    local out = {}
    for id in pairs(map) do out[#out+1] = id end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end
local function invalid(issues)
    for _, issue in ipairs(issues) do if issue.severity == "error" then return true end end
    return false
end
local function field_issue(ui, issues, id, item, field)
    local found
    for _, issue in ipairs(issues) do
        if issue.id == id and issue.item == item and issue.field == field then
            found = issue
            if issue.severity == "error" then break end
        end
    end
    return found and {severity=found.severity == "error" and ui.ISSUE_SEVERITY.ERROR or ui.ISSUE_SEVERITY.WARNING,
        message=found.message} or false
end
local function options(values, current)
    local out = Model.copy(values)
    for _, value in ipairs(out) do if value == current then return out end end
    if current ~= nil then out[#out+1] = current end
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
        local function result(action)
            return {action=action, doc=doc, selected=selected, new_id=new_id}
        end
        local issues = Document.validate(doc, props.types)
        local rows = {
            ui.label({text=string.format("%d tables; %d issues.", #keys(doc.merged), #issues)}),
            ui.paragraph({text=props.status or "Edit a table, then Save. Baseline loot is kept in loot_tables.lua."}),
            ui.label({text="Table"}),
            ui.select_box({value=selected, options=keys(doc.merged), to_string=function(id)
                return tostring(id) .. (doc.authored[id] ~= nil and (doc.static[id] ~= nil and " (override)" or " (new)") or " (loot_tables.lua)")
            end, on_value_changed=set_selected}),
            ui.label({text="New table id"}),
            ui.string_field({value=new_id, on_value_changed=set_new_id}),
            ui.dialog_button({text="New table", result=result("new")}),
        }
        if selected ~= nil then
            if doc.authored[selected] ~= nil then
                rows[#rows+1] = ui.dialog_button({text=M.button_text(doc.static[selected] ~= nil and "Revert to loot_tables.lua" or "Delete"), result=result("remove")})
            end
            local value = type(doc.merged[selected]) == "table" and doc.merged[selected] or {}
            local items = type(value.items) == "table" and value.items or {}
            local function edit_items(fn)
                local next_doc = Model.copy(doc)
                local next_value = Model.copy(value)
                next_value.items = Model.copy(items)
                fn(next_value.items)
                assert(Document.set(next_doc, selected, next_value))
                change(next_doc)
            end
            for i, item in ipairs(items) do
                local index = i
                local row = type(item) == "table" and item or {}
                local function edit(key, v)
                    edit_items(function(next_items)
                        if type(next_items[index]) ~= "table" then next_items[index] = {} end
                        next_items[index][key] = v
                    end)
                end
                local function move(delta)
                    edit_items(function(next_items)
                        next_items[index], next_items[index+delta] = next_items[index+delta], next_items[index]
                    end)
                end
                rows[#rows+1] = ui.horizontal({spacing=ui.SPACING.SMALL, children={
                    ui.label({text="Type"}),
                    ui.select_box({value=row.type, options=options(props.types, row.type), to_string=function(id)
                        local entry = (props.entries or {})[id]
                        return tostring(id) .. " (" .. tostring(type(entry) == "table" and entry.category or "unknown") .. ")"
                    end, on_value_changed=function(v) edit("type", v) end, issue=field_issue(ui, issues, selected, index, "type")}),
                    ui.label({text="Amount"}),
                    ui.integer_field({value=row.amount == nil and 1 or row.amount, on_value_changed=function(v) edit("amount", v) end,
                        issue=field_issue(ui, issues, selected, index, "amount")}),
                    ui.label({text="Chance"}),
                    ui.number_field({value=row.chance == nil and 1 or row.chance, on_value_changed=function(v) edit("chance", v) end,
                        issue=field_issue(ui, issues, selected, index, "chance")}),
                    ui.button({text="Move up", enabled=index>1, on_pressed=function() move(-1) end}),
                    ui.button({text="Move down", enabled=index<#items, on_pressed=function() move(1) end}),
                    ui.button({text="Remove", on_pressed=function() edit_items(function(next_items) table.remove(next_items, index) end) end}),
                }})
            end
            rows[#rows+1] = ui.button({text="Add item", enabled=#props.types>0, on_pressed=function()
                edit_items(function(next_items) next_items[#next_items+1] = {type=props.types[1], amount=1, chance=1} end)
            end})
        end
        for _, issue in ipairs(issues) do
            rows[#rows+1] = ui.paragraph({text=tostring(issue.id) .. (issue.item and (" item " .. issue.item) or "") .. ": " .. issue.message})
        end
        return ui.dialog({title="Loot Tables", width=960, height=680, resizable=true,
            content=ui.scroll({content=ui.vertical({padding=ui.PADDING.MEDIUM, spacing=ui.SPACING.SMALL, children=rows})}),
            -- Enter commits a field; no default dialog button.
            buttons={ui.dialog_button({text="Save", enabled=not invalid(issues), result=result("save")}),
                ui.dialog_button({text="Save and Prepare & Check", enabled=not invalid(issues), result=result("prepare")}),
                ui.dialog_button({text="Close", cancel=true, result=result("close")})}})
    end)
end

local function load_types(deps)
    local fresh = Fresh.new({root=deps.root, read=deps.read or Transaction.read})
    local values, entries = CatalogEnums.derive(CatalogEnums.row("collectibles"), function(m) return fresh.require(m) end)
    assert(values, entries or "Cannot load collectible types.")
    return values, entries
end
local function confirm(ui)
    return ui.show_dialog(ui.dialog({title="Discard unsaved changes?", content=ui.paragraph({text="Your loot changes have not been saved."}), buttons={
        ui.dialog_button({text="Keep editing", cancel=true, result=false}),
        ui.dialog_button({text=M.button_text("Discard"), result=true}),
    }})) == true
end

function M.run(deps)
    assert(not deps.headless and deps.editor and deps.editor.ui, "Loot Tables needs the Defold editor.")
    local ui = deps.editor.ui
    local root = tostring(deps.root or "."):gsub("\\", "/"):gsub("/$", "")
    local read = deps.read or Transaction.read
    Transaction.recover(root .. "/developer", deps.transaction)
    local opts = {root=root, read=read}
    local doc = assert(Document.load(opts))
    local types, entries = (deps.load_types or load_types)(deps)
    local saved = Model.encode(doc.authored)
    local selected, new_id, status = keys(doc.merged)[1], "", nil
    local view = M.component(ui)
    while true do
        local memory = {doc=doc}
        local result = ui.show_dialog(view({doc=doc, selected=selected, new_id=new_id, status=status, types=types, entries=entries, memory=memory}))
        doc = result and result.doc or memory.doc
        if result then selected, new_id = result.selected, result.new_id end
        if not result or result.action == "close" then
            if Model.encode(doc.authored) == saved or confirm(ui) then return true end
        else
            local ok, message = pcall(function()
                if result.action == "new" then
                    assert(doc.merged[new_id] == nil and doc.authored[new_id] == nil, "Table id already exists.")
                    assert(Document.set(doc, new_id, {items={}})); selected, new_id = new_id, ""
                elseif result.action == "remove" then
                    if doc.static[selected] ~= nil then Document.revert(doc, selected) else Document.remove(doc, selected) end
                    if not doc.merged[selected] then selected=keys(doc.merged)[1] end
                elseif result.action == "save" or result.action == "prepare" then
                    assert(not invalid(Document.validate(doc, types)), "Correct loot errors before saving.")
                    assert(read(root .. AUTHORED) == doc.authored_text, "The authored file changed since the window opened; reopen it")
                    Transaction.commit(root .. "/developer", {{path="config/loot_tables_authored.lua",
                        content=Document.serialize(doc.authored, doc.static)}}, deps.transaction)
                    doc=assert(Document.load(opts)); saved=Model.encode(doc.authored)
                    status="Saved. Build to play it; run Prepare & Check before Export Game (the publication is stale)."
                    if result.action == "prepare" then
                        assert(type(deps.prepare) == "function", "Prepare & Check is unavailable.")
                        deps.prepare()
                    end
                else error("Unknown loot action") end
            end)
            if not ok then status="Loot Tables: " .. tostring(message) end
        end
    end
end
return M
