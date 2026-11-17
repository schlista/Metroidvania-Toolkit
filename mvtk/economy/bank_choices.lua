-- Canonical bank choices shared by presentation and the owner. Rebuilt at event
-- time so all transfers use current balances and current configured steps.
local M = {}
function M.rows(mode)
    local Bank = require "mvtk.economy.bank"
    local config = require("developer.config.runtime_settings").section("shops", require "developer.config.shops")
    local steps = ((config.settings or {}).bank or {}).steps or {}
    local rows = {}
    for _, action in ipairs({"deposit", "withdraw"}) do
        if mode == "both" or mode == action then
            local amount = action == "deposit" and require("mvtk.core.wallet").get() or Bank.get()
            local seen = {}
            for _, step in ipairs(steps) do
                if type(step) == "number" and step > 0 and step < math.huge and step % 1 == 0 and not seen[step] then
                    seen[step] = true
                    rows[#rows + 1] = {id = action .. ":" .. tostring(step), action = action, amount = step}
                end
            end
            rows[#rows + 1] = {id = action .. ":all", action = action, amount = amount, all = true}
        end
    end
    return rows
end
return M
