-- Currency mutations share Inventory's HUD updates and change events.
-- Reasons describe the caller's intent; saving remains the caller's job.
local Inventory = require "mvtk.core.inventory"
local CurrencyText = require "mvtk.ui.currency_text"
local M = {}

local function valid_amount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

function M.get()
    return Inventory.get_currency()
end

function M.can_afford(n)
    return valid_amount(n) and M.get() >= n
end

function M.spend(n, reason)
    if not valid_amount(n) then return false, "invalid_amount" end
    if not M.can_afford(n) then return false, "insufficient" end
    if n > 0 then Inventory.set_currency(M.get() - n) end
    return true
end

function M.add(n, reason)
    if not valid_amount(n) then return false, "invalid_amount" end
    if n > 0 then Inventory.set_currency(M.get() + n) end
    return true
end

function M.format(n)
    return CurrencyText.text(n)
end

return M
