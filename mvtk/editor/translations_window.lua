-- Native creator window. Rendering/callbacks only edit state; the run loop owns I/O.
local Project = require "mvtk.editor.translation_project"
local M = {}

function M.component(ui)
    return ui.component(function(props)
        local selected, set_selected = ui.use_state(props.selected)
        local code, set_code = ui.use_state(props.code or "")
        local name, set_name = ui.use_state(props.name or "")
        local plural, set_plural = ui.use_state(props.plural or "one_other")
        local codes, names = {}, {}
        for _, language in ipairs(props.languages) do codes[#codes+1] = language.code; names[language.code] = language.name end
        local function action(kind) return {action=kind, selected=selected, code=code, name=name, plural=plural} end
        return ui.dialog({title="Translations", width=720, resizable=true,
            content=ui.vertical({children={
                ui.paragraph({text=string.format("%d text entries. Export, translate in a spreadsheet saved as UTF-8 TSV, then Import.", props.count)}),
                ui.label({text="Language"}),
                ui.select_box({value=selected, options=codes, to_string=function(value) return names[value] .. " (" .. value .. ")" end, on_value_changed=set_selected}),
                ui.paragraph({text="Files: developer/localization/<code>.tsv. Keep id, where and source unchanged. Edit translation and status (missing, done or stale)."}),
                ui.heading({text="Add language"}),
                ui.label({text="Code"}), ui.string_field({value=code, on_value_changed=set_code}),
                ui.label({text="Own name"}), ui.string_field({value=name, on_value_changed=set_name}),
                ui.label({text="Plural rule"}),
                ui.select_box({value=plural, options={"one_other", "none", "one_few_many"}, on_value_changed=set_plural,
                    to_string=function(value) return (value:gsub("_", " ")) end}),
                ui.paragraph({text=props.status or ""}),
            }}), buttons={
                ui.dialog_button({text="Add language", result=action("add")}),
                ui.dialog_button({text="Export Text for Translation", result=action("export")}),
                ui.dialog_button({text="Import Translations", result=action("import")}),
                ui.dialog_button({text="Close", cancel=true, result=action("close")}),
            }})
    end)
end
function M.run(deps)
    assert(not deps.headless and deps.editor and deps.editor.ui, "Translations needs the Defold editor.")
    local project, ui = deps.project or Project, deps.editor.ui
    if project.recover then project.recover(deps) end
    local registry, entries = project.registry(deps), project.entries(deps)
    local view = M.component(ui)
    local draft = {selected=registry.languages[1].code, count=#entries, languages=registry.languages}
    while true do
        local result = ui.show_dialog(view(draft))
        if not result or result.action == "close" then return true end
        draft.selected, draft.code, draft.name, draft.plural = result.selected, result.code, result.name, result.plural
        local ok, message = pcall(function()
            if result.action == "add" then
                registry = project.add(deps, result.code, result.name, result.plural)
                draft.languages, draft.selected, draft.code, draft.name = registry.languages, result.code, "", ""
                return "Language added. Export Text for Translation to create its spreadsheet."
            elseif result.action == "export" then
                local rows, path = project.export(deps, result.selected)
                return string.format("Exported %d rows to %s.", #rows, path)
            elseif result.action == "import" then
                local imported = project.import(deps, result.selected)
                return string.format("Imported %d rows. Publication is stale: Prepare & Check for a Tiled world, or Build then Layout Editor > Export for a manual layout.", imported.count)
                    .. (imported.warning and (" " .. imported.warning) or "")
            end
            error("Unknown translation action")
        end)
        -- assert/error prefix "path:line: " (LuaJ "@path:line "); the creator sees only the reason.
        draft.status = ok and message
            or ("Translations: " .. require("hooks.core.error_text").strip(tostring(message)))
    end
end
return M
