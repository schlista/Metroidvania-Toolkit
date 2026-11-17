-- Catalog queries do not mutate state. Optional dependencies permit pure fixtures.
-- ctx: catalog_id, config (shops data), flags, upgrades; omitted dependencies
-- are resolved at event time from the runtime services.
local M = {}
function M.config(ctx) return ctx.config or require "developer.config.shops" end
function M.get(ctx) return (M.config(ctx).catalogs or {})[ctx.catalog_id] end
function M.stock_key(ctx, entry)
    if not ctx.catalog_id or ctx.catalog_id == "" then return nil end
    return "shop_sold:" .. ctx.catalog_id .. ":" .. entry.id
end
function M.sold(ctx, entry)
    local key = M.stock_key(ctx, entry)
    if not key then return 0 end
    local flags = ctx.flags or require "mvtk.core.flags"
    local n = flags.get(key)
    return type(n) == "number" and n >= 0 and n == math.floor(n) and n < math.huge and n or 0
end
function M.remaining(ctx, entry)
    if entry.stock == nil then return nil end
    return math.max(0, entry.stock - M.sold(ctx, entry))
end
function M.status(ctx, entry)
    local flags = ctx.flags or require "mvtk.core.flags"
    local locked = entry.requires_flag and entry.requires_flag ~= "" and not flags.has(entry.requires_flag)
    if locked then return entry.show_locked == true, "locked" end
    if M.remaining(ctx, entry) == 0 then return true, "sold_out" end
    local entries = require("mvtk.game.grant_spec").parse(entry.gives)
    for _, give in ipairs(entries) do
        if give.kind == "upgrade" then
            local upgrades = ctx.upgrades or require "mvtk.economy.upgrades"
            local met, required = upgrades.requires_met(give.id)
            if not met then return true, "prerequisite", required end
        end
    end
    return true, "available"
end
function M.entries(ctx)
    local out = {}
    for _, entry in ipairs((M.get(ctx) or {}).entries or {}) do
        if M.status(ctx, entry) then out[#out + 1] = entry end
    end
    return out
end
function M.entry(ctx, id)
    for _, entry in ipairs((M.get(ctx) or {}).entries or {}) do
        if entry.id == id then return entry end
    end
end
function M.costs(entry)
    local out, keys = {}, {}
    if entry.price > 0 then out[#out + 1] = "currency:" .. entry.price end
    for id in pairs(entry.cost_items or {}) do keys[#keys + 1] = id end
    table.sort(keys)
    for _, id in ipairs(keys) do out[#out + 1] = "item:" .. id .. ":" .. entry.cost_items[id] end
    return out
end
-- Hidden and locked entries also count: completing the visible list is not
-- completing the catalog. Ignore non-ability grants; an empty ability list
-- never consumes a trainer. The injected predicate keeps this query pure.
function M.all_abilities_learned(ctx)
    local found = false
    local exhausted = ctx.is_exhausted or require("mvtk.game.grants").is_exhausted
    for _, entry in ipairs((M.get(ctx) or {}).entries or {}) do
        for _, give in ipairs(require("mvtk.game.grant_spec").parse(entry.gives)) do
            if give.kind == "ability" then
                found = true
                if not exhausted("ability:" .. give.id) then return false end
            end
        end
    end
    return found
end
-- Altar data is authored on the object, never in a purchase catalog.
M.OFFER_FIELDS = {"offer_cost_currency", "offer_cost_item", "offer_cost_item_count",
    "offer_reward", "offer_reward_text", "offer_remove_after_use", "offer_set_flag"}
function M.offering_used(ctx)
    return (ctx.flags or require("mvtk.core.flags")).has("altar_used:" .. ctx.station_id)
end
function M.offering_entry(ctx)
    local items = {}
    if ctx.offer_cost_item and ctx.offer_cost_item ~= "" then
        items[ctx.offer_cost_item] = ctx.offer_cost_item_count or 1
    end
    return M.inline_entry({id = "offering", price = ctx.offer_cost_currency or 0,
        cost_items = items, gives = ctx.offer_reward or "", name = ctx.offer_reward_text or "",
        set_flag = ctx.offer_set_flag, confirm = true})
end
-- Inline callers supply the same entry shape, with their own stable identity.
function M.inline_entry(entry) return entry end
return M
