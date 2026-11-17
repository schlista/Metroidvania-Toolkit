-- Banked currency is separate from the carried Wallet and death fees.
local Wallet = require "mvtk.core.wallet"
local Checkpoint = require "mvtk.core.checkpoint"
local Util = require "mvtk.core.util"
local RuntimeSettings = require "developer.config.runtime_settings"
local Config = require "developer.config.shops"
local M = {}
local balance = 0

local function whole(n)
    return type(n) == "number" and n == n and n > 0 and n < math.huge and n % 1 == 0
end

function M.get() return balance end

function M.can_deposit(n)
    if not whole(n) then return false, "invalid_amount" end
    if not Wallet.can_afford(n) then return false, "insufficient" end
    local carried, next_balance = Wallet.get(), balance + n
    if next_balance == math.huge or next_balance - balance ~= n
        or carried - (carried - n) ~= n then return false, "limit" end
    return true
end

function M.can_withdraw(n)
    if not whole(n) then return false, "invalid_amount" end
    if n > balance then return false, "insufficient" end
    local carried = Wallet.get()
    local next_carried = carried + n
    if next_carried == math.huge or next_carried - carried ~= n
        or balance - (balance - n) ~= n then return false, "limit" end
    return true
end

-- ok describes the transfer. A disk error is returned as reason after a
-- completed transfer, which stays in memory even when saving is suspended.
local function transfer(apply)
    local settings = RuntimeSettings.section("shops", Config).settings or {}
    if (settings.bank or {}).autosave == false then return apply() end
    local changed, refusal
    local saved, reason = Checkpoint.batch("bank", function()
        changed, refusal = apply()
    end)
    if not changed then return false, refusal or reason end
    if not saved then
        if type(reason) == "string" and reason:sub(1, 15) == "save_suspended:" then return true end
        require("mvtk.ui.notices").post({ text = { key = "gameplay.save_failed" }, key = "bank_save_failed" })
        return true, reason
    end
    return true
end

function M.deposit(n)
    local ok, reason = M.can_deposit(n)
    if not ok then return false, reason end
    return transfer(function()
        local spent, why = Wallet.spend(n, "bank")
        if not spent then return false, why end
        balance = balance + n
        return true
    end)
end

function M.withdraw(n)
    local ok, reason = M.can_withdraw(n)
    if not ok then return false, reason end
    return transfer(function()
        balance = balance - n
        Wallet.add(n, "bank")
        return true
    end)
end

Util.register_checkpoint_provider("bank", {
    version = 2, order = 41, description = "Banked currency",
    migrations = { [1] = function() return {} end },
    capture = function() return { balance = balance } end,
    apply = function(data)
        local n = type(data) == "table" and data.balance
        balance = type(n) == "number" and n == n and n < math.huge and math.max(0, math.floor(n)) or 0
    end,
    defaults = function() balance = 0 end,
})
-- Register after the static menu registry has loaded, without engine state at
-- module load. Re-registration replaces the same stable Records section.
function M.on_session_start()
    require("mvtk.ui.screens.journal_records").add_section({ id = "bank", order = 55,
        visible = function() return M.get() > 0 end,
        header = function() return { key = "journal.bank" } end,
        lines = function() return {{ label = { key = "journal.banked" }, value = { currency = M.get() } }} end,
    })
end
return M
