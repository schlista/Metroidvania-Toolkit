-- Purchase and sale transactions, usable from a gameobject or a GUI context.
local Catalog = require "mvtk.economy.catalog"
local Grants = require "mvtk.game.grants"
local Checkpoint = require "mvtk.core.checkpoint"
local Events = require "mvtk.core.game_events"
local M = {}
local function refused(code, detail)
    return {ok = false, code = code, message = detail, entries = {}, saved = false}
end
function M.buy_inline(ctx, entry)
    if not entry then return refused("unknown_entry") end
    local stock_key = Catalog.stock_key(ctx, entry)
    -- Catalogless exchanges use the owner's fixed identity and once key.
    if not stock_key and (entry.stock ~= nil or not (ctx.instance_id or ctx.once_key)) then
        return refused("invalid")
    end
    local visible, state = Catalog.status(ctx, entry)
    if not visible then return refused("hidden") end
    if state ~= "available" then return refused(state) end
    if Grants.is_exhausted(entry.gives) then return refused("exhausted") end
    local sold = Catalog.sold(ctx, entry)
    local flags = {}
    for key, value in pairs(ctx.set_flags or {}) do flags[key] = value end
    if stock_key then flags[stock_key] = sold + 1 end
    if entry.set_flag and entry.set_flag ~= "" then flags[entry.set_flag] = true end
    local settings = Catalog.config(ctx).settings or {}
    local plan, why = Grants.prepare(entry.gives, {
        costs = Catalog.costs(entry), source = ctx.source or "purchase", reason = ctx.reason or "purchase",
        refuse_if_exhausted = true, durable = settings.autosave_after_purchase ~= false,
        instance_id = ctx.instance_id or (stock_key and ("shop:" .. ctx.catalog_id .. ":" .. entry.id .. ":" .. (sold + 1))),
        once_key = ctx.once_key, position = ctx.position, set_flags = flags,
    })
    if not plan then return refused(why.code, why.message) end
    local committed = false
    local function apply()
        Grants.commit(plan)
        committed = true
        Events.emit("purchase_completed", {station_kind = ctx.station_kind or "shop",
            catalog = ctx.catalog_id or "", entry = entry.id, price = entry.price})
    end
    local called, saved, save_error
    if plan.opts.durable then
        local result
        called, result, save_error = pcall(Checkpoint.batch, "purchase", apply)
        saved = called and result == true
        if not called then save_error = result end
    else
        called, save_error = pcall(apply)
        saved = false
        if called then save_error = nil end
    end
    if not committed then return refused("failed", save_error) end
    return {ok = true, code = "purchased", entries = plan.entries, saved = saved, save_error = save_error}
end
function M.buy(ctx, entry_id) return M.buy_inline(ctx, Catalog.entry(ctx, entry_id)) end
-- Resolve creator overrides once per revision. Purchases retain Catalog.config's
-- existing baseline/injected behavior; sale callers share this settings view.
local cached_settings, cached_revision
function M.sell_settings(ctx)
    if ctx.config then return ctx.config.settings or {} end
    local RuntimeSettings = require "developer.config.runtime_settings"
    local revision = RuntimeSettings.revision()
    if cached_settings == nil or cached_revision ~= revision then
        cached_settings = (RuntimeSettings.section("shops", require "developer.config.shops")).settings or {}
        cached_revision = revision
    end
    return cached_settings
end
function M.sell(item_id, ctx)
    if ctx.buys ~= true then return refused("not_buying") end
    local Selling = require "mvtk.economy.selling"
    local env = Grants.runtime_env()
    env.registry = ctx.registry or require "mvtk.ui.menu_registry"
    if not Selling.sellable(item_id, env) then return refused("not_sellable") end
    local settings = M.sell_settings(ctx)
    local share, why = Selling.share(ctx.sell_share, settings.sell_share)
    if share == nil then return refused("invalid", why) end
    local price = Selling.price(item_id, share, env.items)
    if price <= 0 then return refused("worthless") end
    local ok, result = Grants.exchange("item:" .. item_id .. ":1", "currency:" .. price, {
        source = "sale", reason = "sale", durable = settings.autosave_after_purchase, notify = false,
    })
    if not ok then return refused(result.code, result.message) end
    Events.emit("item_sold", {item_id = item_id, count = 1, price = price, station_kind = ctx.station_kind or "shop"})
    return {ok = true, code = "sold", entries = result.entries, saved = result.saved, save_error = result.save_error}
end
return M
