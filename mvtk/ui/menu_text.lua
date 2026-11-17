-- Menu models retain source text and UI keys. Only their displaying scene
-- resolves these descriptions; nested text params follow the same rules.
local M = {}

-- Supplied text, including empty text, keeps its source identity. Callers
-- normalize an absent caption to nil only where they already have a fallback.
function M.default(value, key)
    if value == nil then
        return {key = key}
    end
    return type(value)=="table" and value or {text=value}
end

local function format(text, params)
    return (tostring(text or ""):gsub("{([%w_]+)}", function(name)
        local value = params and params[name]
        return value ~= nil and tostring(value) or "{" .. name .. "}"
    end))
end
-- Debug tools share the list controller but retain English under T9.
local english = {
    render = function(text, opts) return format(text, opts and opts.params) end,
    ui = function(key, params) return format(require("developer.config.ui_text")[key] or key, params) end,
}

function M.render(value, display)
    display = display or english
    if type(value) ~= "table" then return display.render(value) end
    if value.currency ~= nil then
        if display.currency then return display.currency(value.currency) end
        return (value.formatter or require "mvtk.ui.currency_text").text(value.currency, display.render)
    end
    if value.parts then
        local out = {}
        for _, part in ipairs(value.parts) do out[#out + 1] = M.render(part, display) end
        return table.concat(out, M.render(value.separator or "", display))
    end
    local params = {}
    for name, param in pairs(value.params or {}) do
        params[name] = type(param) == "table" and M.render(param, display) or param
    end
    local key = value.key
    if value.forms then
        key = require("mvtk.core.localization").plural_form(value.forms, value.count)
    end
    if key then return display.ui(key, params) end
    return display.render(value.text, { params = params })
end

return M
