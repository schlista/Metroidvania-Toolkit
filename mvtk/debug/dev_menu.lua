-- A private provider registry: the shipping list-menu scene never loads it.
local List = require "mvtk.ui.list_menu"
local Nav = require "mvtk.ui.menu_nav"
local Warp = require "mvtk.debug.dev_warp"
local M = {}
local pages = {}

-- Later debug tools register pages at runtime; selection/paging stay shared.
function M.register(id, title, provider)
    for i, page in ipairs(pages) do if page.id == id then table.remove(pages, i); break end end
    pages[#pages + 1] = { id = id, title = title, provider = provider }
end

M.register("warp", "Warp", {
    rows = function(ctx)
        local rows = {}
        for _, id in ipairs(Warp.rooms()) do
            if id:lower():find(ctx.context.query:lower(), 1, true) then
                rows[#rows + 1] = { id = id, label = id, hold = 0 }
            end
        end
        return rows
    end,
    on_confirm = function(_, row)
        local ok, err = Warp.warp(row.id)
        return { close = ok, status = err }
    end,
})

-- Diagnostic pseudo rendering wraps resolved text without installing a language table.
local function register_languages()
    M.register("languages", "Languages", {
        rows = function()
            local localization = require "mvtk.core.localization"
            return { { id = "pseudo", label = "Pseudo-language", value = localization.pseudo() and "On" or "Off", hold = 0 } }
        end,
        on_confirm = function()
            local localization = require "mvtk.core.localization"
            localization.set_pseudo(not localization.pseudo())
            return { refresh = true }
        end,
    })
end

function M.new()
    register_languages()
    local menu = { query = "" }
    local base = Nav.settings()
    -- Typing is always active. Letters/Space and pad buttons must never turn
    -- into menu commands, irrespective of the shared gameplay menu bindings.
    menu.settings = { list = base.list, books = { dev = {title = "Dev Menu", pause = true} }, navigation = {
        up = {"key_up"}, down = {"key_down"}, left = {"key_left"}, right = {"key_right"},
        confirm = {"key_enter"}, close = {"key_escape"}, tab_next = {"key_tab", "key_f4"},
    } }
    local registry = { tabs = function() return pages end }
    menu.model = assert(List.new({book = "dev", registry = registry, settings = menu.settings, context = menu}))
    menu.nav = Nav.new(menu.settings)
    function menu.input(id, action)
        if id == hash("text") then
            menu.query = menu.query .. (action.text or "")
            menu.model.refresh()
        elseif id == hash("key_backspace") then
            if action.pressed or action.repeated then
                menu.query = menu.query:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
                menu.model.refresh()
            end
        else
            local command = menu.nav.input(id, action)
            if command then return menu.model.command(command, {pressed = true}) end
        end
    end
    return menu
end

return M
