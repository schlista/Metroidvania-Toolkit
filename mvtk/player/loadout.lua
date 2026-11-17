-- Ordered providers share the one Loadout cycle action. Re-registering replaces
-- a provider in place, preserving deterministic priority across session starts.
local M = {}
local providers = {}
function M.register(id, provider)
    assert(type(id) == "string" and type(provider.active) == "function"
        and type(provider.cycle) == "function", "Invalid loadout provider")
    for _, row in ipairs(providers) do
        if row.id == id then row.provider = provider; return end
    end
    providers[#providers + 1] = {id=id, provider=provider}
end
function M.cycle()
    for _, row in ipairs(providers) do
        if row.provider.active() then return row.provider.cycle() end
    end
    return false
end
return M
