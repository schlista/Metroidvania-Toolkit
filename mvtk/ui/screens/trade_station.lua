-- Purchase and sale presentation only. The gameobject owner commits every exchange.
-- Resolve services at event time so the static registry loads without engine state.
local M = { pause = true }
local KINDS = {
    bank = { title = "bank.title" },
    offering_altar = { title = "altar.title" },
    skill_trainer = { title = "trainer.title" },
    shop = { title = "shop.title" },
    upgrade_station = { title = "upgrade_station.title" },
}

local function source(value)
    return type(value) == "table" and value or { text = value }
end

function M.title(ctx)
    local context = ctx.context or {}
    if context.menu_title and context.menu_title ~= "" then return context.menu_title end
    local catalog = require("mvtk.economy.catalog").get(context)
    if catalog and catalog.name and catalog.name ~= "" then return catalog.name end
    return { key = (KINDS[context.station_kind] or KINDS.shop).title }
end

function M.header_right(ctx)
    if ((ctx or {}).context or {}).station_kind == "bank" then
        return { key = "bank.header", params = {
            carried = { currency = require("mvtk.core.wallet").get() },
            banked = { currency = require("mvtk.economy.bank").get() } } }
    end
    return { currency = require("mvtk.core.wallet").get() }
end

local function definition(give, env)
    if give.kind == "ability" then return env.ability_info(give.id) end
    if give.kind ~= "item" and give.kind ~= "upgrade" and give.kind ~= "collectible"
        and give.kind ~= "fast_travel" then return nil end
    local data = env[give.kind == "item" and "items" or give.kind == "upgrade" and "upgrades"
        or give.kind == "collectible" and "collectible_types" or "travel_points"]
    return data and data[give.id]
end

local function detail(entry, gives, env)
    local parts, effects = {}, {}
    if entry.description and entry.description ~= "" then parts[#parts + 1] = entry.description end
    for _, give in ipairs(gives) do
        local def = definition(give, env)
        if def then
            if not entry.description or entry.description == "" then
                local description = def.description or def.desc
                if description and description ~= "" then parts[#parts + 1] = description end
            end
            if give.kind == "upgrade" then
                for _, stat in ipairs({"max_health", "max_energy", "max_stamina"}) do
                    local amount = def[stat]
                    if amount and amount ~= 0 then
                        effects[#effects + 1] = { key = "shop.effect_" .. stat,
                            params = { amount = math.floor(amount + 0.5) } }
                    end
                end
                if def.damage_mult and def.damage_mult ~= 1 then
                    effects[#effects + 1] = { key = "shop.effect_damage",
                        params = { percent = math.floor((def.damage_mult - 1) * 100 + 0.5) } }
                end
            end
        end
    end
    if #effects > 0 then
        parts[#parts + 1] = { parts = effects, separator = { key = "shop.effect_separator" } }
    end
    return { parts = parts, separator = "\n" }
end

local function availability(context, entry, gives, env)
    local Catalog = require "mvtk.economy.catalog"
    local Grants = require "mvtk.game.grants"
    if context.station_kind == "skill_trainer" then
        local abilities, learned = false, true
        for _, give in ipairs(gives) do
            if give.kind == "ability" then
                abilities = true
                learned = learned and Grants.is_exhausted("ability:" .. give.id)
            end
        end
        if abilities and learned then return "learned", { key = "shop.learned" } end
    end
    local _, state, required = Catalog.status(context, entry)
    if state == "prerequisite" then
        local def = env.upgrades[required]
        return "locked", { key = "shop.requires", params = {
            name = def and def.name and source(def.name) or { key = "list.missing_name" } } }
    end
    if state == "locked" then
        return state, entry.locked_text and entry.locked_text ~= "" and entry.locked_text or { key = "shop.locked" }
    end
    if state == "sold_out" then return state, { key = "shop.sold_out" } end
    if Grants.is_exhausted(entry.gives) then
        state = "owned"
        for _, give in ipairs(gives) do
            if give.kind == "upgrade" then state = "applied"; break
            elseif give.kind == "ability" then state = "learned" end
        end
        return state, { key = "shop." .. state }
    end
    local can_pay, reason = Grants.can_afford(Catalog.costs(entry))
    if not can_pay then return "unaffordable", reason end
    return "available"
end

local function offering_rows(context)
    local Catalog = require "mvtk.economy.catalog"
    local Grants = require "mvtk.game.grants"
    local entry = Catalog.offering_entry(context)
    local name = entry.name ~= "" and { text = entry.name } or Grants.describe(entry.gives)
    local cost = Grants.describe(Catalog.costs(entry))
    local state, reason = "available", nil
    if Catalog.offering_used(context) then
        state, reason = "used", { key = "altar.already_offered" }
    else
        state, reason = availability(context, entry, require("mvtk.game.grant_spec").parse(entry.gives), Grants.runtime_env())
    end
    return {{id = entry.id, label = name, cost = cost, state = state, value = reason,
        enabled = state == "available", disabled_reason = reason,
        confirm = { key = "altar.offer_confirm", params = { cost = cost, reward = name } }}}
end

local function bank_rows(context)
    local Bank, rows = require "mvtk.economy.bank", {}
    for _, choice in ipairs(require("mvtk.economy.bank_choices").rows(context.bank_mode)) do
        local enabled = Bank["can_" .. choice.action](choice.amount)
        local reason = not enabled and { key = "bank.not_enough" } or nil
        rows[#rows + 1] = { id = choice.id,
            label = { key = "bank." .. choice.action .. (choice.all and "_all" or ""),
                params = not choice.all and { amount = { currency = choice.amount } } or nil },
            enabled = enabled, state = enabled and "available" or "unaffordable",
            value = reason, disabled_reason = reason }
    end
    return rows
end

function M.rows(ctx)
    local context = ctx.context or {}
    if context.station_kind == "bank" then return bank_rows(context) end
    if context.station_kind == "offering_altar" then return offering_rows(context) end
    local Catalog = require "mvtk.economy.catalog"
    local Grants = require "mvtk.game.grants"
    local Spec = require "mvtk.game.grant_spec"
    local env, rows = Grants.runtime_env(), {}
    for _, entry in ipairs(Catalog.entries(context)) do
        local gives = Spec.parse(entry.gives)
        local state, reason = availability(context, entry, gives, env)
        local name = entry.name and entry.name ~= "" and entry.name or Grants.describe(entry.gives)
        local cost = Grants.describe(Catalog.costs(entry))
        local remaining = Catalog.remaining(context, entry)
        local value = state ~= "available" and reason or nil
        if state == "available" and remaining ~= nil then
            value = { forms = { one = "shop.stock_one", other = "shop.stock_other" },
                count = remaining, params = { count = remaining } }
        end
        rows[#rows + 1] = { id = entry.id, label = name, cost = cost, value = value,
            state = state, enabled = state == "available", disabled_reason = reason,
            detail = detail(entry, gives, env), confirm = entry.confirm == true and {
                key = "shop.buy_confirm", params = { name = source(name), cost = cost } } or nil }
    end
    if context.buys_items == true then
        env.owned = require("mvtk.core.inventory").all()
        env.registry = ctx.registry
        env.share = context.sell_share
        rows[#rows + 1] = { id = "sell_section", kind = "section", label = { key = "shop.sell_section" } }
        for _, sale in ipairs(require("mvtk.economy.selling").rows(env)) do
            local item = env.items[sale.id]
            local price = { currency = sale.price }
            rows[#rows + 1] = { id = "sell:" .. sale.id, label = sale.label,
                value = { forms = { one = "inventory.count_one", other = "inventory.count_other" },
                    count = sale.count, params = { count = sale.count } },
                cost = price, detail = item.desc, state = "available", enabled = true,
                confirm = item.unique == true and { key = "shop.sell_confirm", params = {
                    name = source(sale.label), price = price } } or nil }
        end
    end
    return rows
end

function M.subtitle(ctx)
    if (ctx.context or {}).station_kind == "offering_altar" or (ctx.context or {}).station_kind == "bank" then return end
    if #require("mvtk.economy.catalog").entries(ctx.context or {}) == 0 then return { key = "shop.empty" } end
end

function M.on_confirm()
    return { delegate = true }
end

return M
