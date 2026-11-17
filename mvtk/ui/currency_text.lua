-- Runtime currency presentation; merely loading this module is engine-free.
local CurrencyFormat = require "mvtk.core.currency_format"
local M = {}
local revision, currency

function M.text(n, render)
    local RuntimeSettings = require "developer.config.runtime_settings"
    local current = RuntimeSettings.revision()
    if currency == nil or revision ~= current then
        currency = RuntimeSettings.section("hud_layout", require "developer.config.hud_layout").currency or {}
        -- Keep our own snapshot: never rewrite the resolved settings table.
        currency = { format = currency.format, thousands_separator = currency.thousands_separator }
        local valid, message = CurrencyFormat.valid(currency.format)
        if not valid then
            print("[CURRENCY] " .. message .. " Using $ %d.")
            currency.format = "$ %d"
        end
        revision = current
    end
    -- GUI callers translate the authored format before filling its amount.
    return CurrencyFormat.apply(render and render(currency.format) or currency.format, n, currency)
end

return M
