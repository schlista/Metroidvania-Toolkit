-- Pure capability audit shared by trial presentation, runtime and preparation.
-- Unlock-only abilities cannot be switched off through an ability-use policy.
local M = {}
M.abilities = {dash=true, bomb=true, compact_form=true, super_jump=true, blink=true,
    grapple=true, healing=true, charge_attack=true, down_strike=true, ranged_attack=true}
M.attacks = {light_attack=true, heavy_attack=true, charge_attack=true, down_strike=true,
    ranged_attack=true, parry_counter=true}
function M.parse(value)
    local result = {}
    if type(value) == "string" then
        for id in value:gmatch("[^,%s]+") do result[id] = true end
    end
    return result
end
function M.ids(value)
    local result = {}
    for id in pairs(M.parse(value)) do result[#result+1] = id end
    table.sort(result)
    return result
end
return M
