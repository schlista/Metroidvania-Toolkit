-- Pure sale rules shared by runtime menus, transactions and authoring checks.
-- env: items, key_ids (canonical id set), canonicalize, registry.owns_item;
-- rows also receives owned (item id -> count), share and collectible_types.
local Spec = require "mvtk.game.grant_spec"
local M = {}
local function valid_share(value)
    return type(value) == "number" and value >= 0 and value <= 1
end
function M.share(store, project)
    if valid_share(store) then return store end
    if store ~= nil and store ~= -1 then return nil, "Store sell share must be -1 or between 0 and 1." end
    if valid_share(project) then return project end
    return nil, "Project sell share must be between 0 and 1."
end
function M.price(id, share, items)
    local item = (items or {})[id]
    local price = item and item.price
    if not valid_share(share) or type(price) ~= "number" or price <= 0 or price >= math.huge then return 0 end
    return math.floor(price * share)
end
function M.sellable(id, env)
    env = env or {}
    id = env.canonicalize and env.canonicalize(id) or id
    local item = (env.items or {})[id]
    if not item or type(item.price) ~= "number" or not (item.price > 0 and item.price < math.huge)
        or item.sellable == false or (env.key_ids or {})[id] then return false end
    return not (env.registry and env.registry.owns_item(id))
end
function M.rows(env)
    local out = {}
    for id, count in pairs(env.owned or {}) do
        local price = M.price(id, env.share, env.items)
        if count > 0 and price > 0 and M.sellable(id, env) then
            out[#out + 1] = {id = id, count = count, price = price, label = Spec.item_name(id, env)}
        end
    end
    table.sort(out, function(a, b)
        local an, bn = type(a.label) == "string" and a.label or "", type(b.label) == "string" and b.label or ""
        return an == bn and a.id < b.id or an < bn
    end)
    return out
end
return M
