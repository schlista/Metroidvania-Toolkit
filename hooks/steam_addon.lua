-- Project > Steam Add-on: lazily loaded editor adapter for the dependency toggle.
local Addon = require "mvtk.editor.steam_addon"
local Transaction = require "mvtk.editor.project_transaction"
local M = {}

M.NOTICE = "You need your own Steamworks account and app ID. Set app_id and achievement_names in developer/config/steam_settings.lua. Valve's terms apply. Turn on the Steam add-on?"

function M.mixed_message(detail)
    return "The Steam add-on state is mixed. Run Project ▸ Steam Add-on… and choose Turn On or Turn Off. " .. tostring(detail or "")
end

local function controls(deps, root)
    local text, err = deps.read(root .. "/game.project")
    assert(text ~= nil or err == nil, "Cannot read game.project: " .. tostring(err))
    return {["game.project"]=text}
end

local function reload_resources(editor)
    -- editor.execute reloads resources by default (official editor API).
    if editor.platform:find("win32", 1, true) then editor.execute("cmd", "/c", "exit", "0")
    else editor.execute("true") end
end

function M.run(deps)
    local editor = deps.editor
    local ui = editor and editor.ui
    assert(not deps.headless and ui and ui.dialog_button,
        "Steam Add-on runs from the Defold editor's Project menu.")
    local root = tostring(deps.root or "."):gsub("\\", "/"):gsub("/$", "")
    if Transaction.recover(root, deps.transaction) then reload_resources(editor) end
    local state, detail = Addon.state(controls(deps, root))
    local lines = {"Current Steam add-on state: " .. state .. "."}
    if state == "mixed" then lines[#lines + 1] = M.mixed_message(detail) end
    local choice = deps.dialog("Steam Add-on", lines, {
        cancel_text="Cancel", cancel_result="cancel",
        extra_buttons={ui.dialog_button({text="Turn On", result="on"}),
            ui.dialog_button({text="Turn Off", result="off"})},
    })
    if choice ~= "on" and choice ~= "off" then return true end
    if choice == "on" then
        local accepted = deps.dialog("Turn On Steam Add-on", {M.NOTICE}, {
            cancel_text="Cancel", cancel_result="cancel",
            extra_buttons={ui.dialog_button({text="Turn On", result="on"})},
        })
        if accepted ~= "on" then return true end
    end
    -- Re-read after dialogs; no settings, app-id file or other control is changed.
    local changes = Addon.plan(controls(deps, root), choice)
    local written, cleanup_warning = Transaction.commit(root, changes, deps.transaction)
    local info = deps.info or function() end
    info("Steam Add-on: " .. choice .. "; updated " .. tostring(#written) .. " file(s).")
    if cleanup_warning then info("Steam Add-on transaction cleanup: " .. cleanup_warning) end
    reload_resources(editor)
    local fetch = type(editor.fetch_libraries) == "function"
    deps.dialog("Steam Add-on " .. (choice == "on" and "On" or "Off"), {
        fetch and "Libraries will refresh when you close this message." or "Next, run Project ▸ Fetch Libraries.",
        "Then run Prepare & Check before building or Export Game.",
    })
    -- Fetch reloads library editor scripts; no editor operation may follow it.
    if fetch then editor.fetch_libraries() end
    return true
end

return M
