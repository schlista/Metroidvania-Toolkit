-- Pure economy diagnostics. Supplied configs/index are never modified; no
-- runtime services, editor APIs, filesystem access or cached config requires.
local Spec = require "mvtk.game.grant_spec"
local Selling = require "mvtk.economy.selling"
local Vendor = require "mvtk.economy.vendor"
local M = {}
local function optional(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value ~= "" and value ~= "none" then return value end
end
local function sorted(t)
    local out = {}
    for id in pairs(t or {}) do out[#out + 1] = id end
    table.sort(out)
    return out
end
local function config_fix(field)
    return "Correct " .. field .. " in developer/config/shops.lua, then choose Project > Prepare & Check."
end
local function tiled_fix(field)
    return "In Tiled, select this object in View > Views and Toolbars > Objects, correct " .. field
        .. ", then File > Export Current Room. In Defold choose Project > Prepare & Check."
end
local function grant_env(cfg, where)
    local env = {}
    for k, v in pairs(cfg.grant_env or {}) do env[k] = v end
    env.items = cfg.items or env.items or {}
    env.upgrades = (cfg.upgrades or {}).upgrades or env.upgrades or {}
    env.collectible_types = cfg.collectible_types or env.collectible_types or {}
    env.instance_id = where.instance_id or "config:shop"
    -- Config offers use the eventual station position; object rewards use the
    -- indexed coordinates. Both are numeric even before world layout export.
    env.position = {x=tonumber((where.raw or where).x) or 0, y=tonumber((where.raw or where).y) or 0}
    return env
end
local function currency_type(id, cfg)
    local def = (cfg.collectible_types or {})[id]
    return type(def) == "table" and def.on_collect == "add_currency" and (tonumber(def.value) or 1) > 0
end
local function currency_drops(drops, cfg)
    for id, drop in pairs(drops or {}) do
        if type(drop) == "table" and currency_type(drop.type or drop.collectible_type or id, cfg)
            and (tonumber(drop.chance) or 1) > 0
            and (tonumber(drop.max) or tonumber(drop.amount) or tonumber(drop.min) or 1) > 0 then return true end
    end
    return false
end
local function chest_currency(items, cfg)
    -- RewardDrops.plan clamps chest amounts to at least one pickup. Only the
    -- collectible behavior and a possible chance roll decide whether it pays.
    for _, item in ipairs(items or {}) do
        if currency_type(item.type or item.collectible_type, cfg)
            and (tonumber(item.chance) or 1) > 0 then return true end
    end
    return false
end
local function currency_source(o, cfg)
    local p = o.properties or {}
    if o.type == "collectible" then
        return currency_type(p.collectible_type, cfg) and (tonumber(p.amount) or 1) > 0
    elseif o.type == "chest" then
        local contents = optional(p.contents) or optional(p.loot_table) or "common"
        local loot = (cfg.loot_tables or {})[contents]
        if loot then return chest_currency(loot.items, cfg) end
        local items = {}
        -- chest.script accepts bare names with implicit count one, and splits
        -- only on commas. An unknown nonempty name is still an inline item;
        -- it never reaches the fallback gem. Amounts do not change this census.
        for entry in contents:gmatch("[^,]+") do
            local id = entry:match("([^:]+)")
            if id then items[#items + 1] = {type=id:match("^%s*(.-)%s*$")} end
        end
        if #items > 0 then return chest_currency(items, cfg) end
        return currency_type("gem_small", cfg)
    elseif o.type == "enemy" then
        local Overrides = require "mvtk.enemies.enemy_overrides"
        local defaults = require("mvtk.enemies.enemy_respawn_policy").effective_defaults(cfg.enemy_defaults, cfg.creator_settings)
        local base = require("mvtk.enemies.enemy_type_overlay").resolve_with_archetype(p.enemy_type, p.archetype,
            cfg.enemy_types or {}, cfg.enemy_skins or {}, {default_archetype=defaults.default_archetype}) or {}
        local overrides = Overrides.normalize(p)
        local drops = overrides.drops
        if drops == nil then
            drops = base.drops
            if type(drops) == "string" then
                drops = drops == "none" and {} or Overrides.parse_drops_string(drops)
            end
        end
        local loot = overrides.loot_table or optional(base.loot_table)
        if type(drops) == "table" and next(drops) == nil then return false end
        if loot then
            local entry = (cfg.loot_tables or {})[loot] or {}
            return currency_drops(entry.items or entry.drops, cfg)
        end
        return currency_drops(drops, cfg)
    end
    return false
end
local catalog_fields = {shop="shop_id", upgrade_station="upgrade_catalog", skill_trainer="trainer_catalog", npc="vendor_shop"}
function M.validate(index, cfg, ds, issue, check_grant_text)
    -- Catalog-only callers may intentionally omit optional economy configs.
    if not cfg.shops then return end
    local shops = cfg.shops
    local catalogs = shops.catalogs or {}
    local env = grant_env(cfg, {})
    local offers = {}
    -- Validate every configured offer, including catalogs not placed yet.
    for _, id in ipairs(sorted(catalogs)) do
        local catalog = catalogs[id]
        for i, entry in ipairs(catalog.entries or {}) do
            local field = "catalogs." .. id .. ".entries." .. tostring(entry.id or i)
            local where = {file="developer/config/shops.lua"}
            check_grant_text(ds, where, field .. ".gives", entry.gives, env,
                "economy_bad_grant", config_fix("gives"))
            local _, _, gives = Spec.validate(entry.gives, env)
            for _, give in ipairs(gives) do
                if give.kind == "upgrade" and not env.upgrades[give.id] then
                    issue("error", "economy_upgrade_requires", where, field .. ".gives",
                        "Catalog offer references missing upgrade '" .. give.id .. "'.",
                        "Use an upgrade defined in developer/config/upgrades.lua in this catalog's gives, then choose Project > Prepare & Check.")
                end
            end
            for _, item in ipairs(sorted(entry.cost_items)) do
                check_grant_text(ds, where, field .. ".cost_items." .. item,
                    "item:" .. item .. ":" .. tostring(entry.cost_items[item]), env,
                    "economy_bad_cost_item", config_fix("cost_items"))
            end
            offers[#offers + 1] = {entry=entry, gives=gives, where=where, field=field}
        end
    end
    local settings = shops.settings or {}
    local creator = cfg.creator_settings or {}
    local override = creator.published == true and (((creator.overrides or {}).shops or {}).settings or {}) or {}
    local project_share = override.sell_share
    if project_share == nil then project_share = settings.sell_share end
    local highest, charge, has_source = nil, nil, false
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            local p = o.properties or {}
            if currency_source(o, cfg) then has_source = true end
            local field = catalog_fields[o.type]
            local id = field and optional(p[field])
            if o.type == "npc" then id = Vendor.catalog(p, (cfg.npc_types or {})[p.npc_type]) end
            local catalog = id and catalogs[id]
            if catalog then
                local expected = o.type == "skill_trainer" and "ability" or o.type == "upgrade_station" and "upgrade"
                local found = false
                for _, entry in ipairs(catalog.entries or {}) do
                    if (tonumber(entry.price) or 0) > 0 then charge = charge or o end
                    for _, give in ipairs(Spec.parse(entry.gives)) do
                        if give.kind == expected then found = true end
                        if o.type == "skill_trainer" and give.kind == "ability" and (cfg.abilities or {})[give.id] == true then
                            issue("warning", "economy_trainer_start_unlocked", o, field,
                                "Trainer catalog '" .. id .. "' sells starting ability '" .. give.id .. "'; it is already Learned.",
                                "Untick this start unlock in Project > Game Settings... > Abilities, or change trainer_catalog, then choose Project > Prepare & Check.")
                        end
                    end
                end
                if expected and not found then
                    issue("warning", "economy_catalog_kind", o, field,
                        "Catalog '" .. id .. "' has no " .. expected .. " grants for this station.",
                        "Choose a catalog with " .. expected .. " grants for " .. field .. ", or edit developer/config/shops.lua, then export the room and choose Project > Prepare & Check.")
                end
            end
            if o.type == "shop" or (o.type == "npc" and id) then
                local share, why = Selling.share(p.sell_share, project_share)
                if share == nil then
                    issue("error", "economy_sell_share_range", o, "sell_share", why,
                        tiled_fix("Sell share (-1 to inherit, or 0 to 1); check Game Settings > Game > Shops > Sell price share too"))
                elseif p.buys_items ~= false then highest = math.max(highest or 0, share) end
            elseif o.type == "offering_altar" then
                if (tonumber(p.cost_currency) or 0) > 0 then charge = charge or o end
                if not optional(p.reward) then
                    issue("error", "economy_altar_without_reward", o, "reward", "Offering altar has no reward.", tiled_fix("Payout > Reward"))
                else
                    check_grant_text(ds, o, "reward", p.reward, grant_env(cfg, o), "economy_bad_grant")
                end
                local item = optional(p.cost_item)
                if item then
                    check_grant_text(ds, o, "cost_item", "item:" .. item .. ":" .. tostring(p.cost_item_count or 1), env, "economy_bad_cost_item")
                end
            end
        end
    end
    -- Banks transfer existing balances; a deposit is neither a charge nor a source.
    if charge and not has_source then
        issue("info", "economy_currency_sources", charge, nil,
            "Stations charge currency, but the world has no currency pickup, chest reward or enemy loot source.",
            "Place a currency pickup or configure currency chest/enemy loot in this world, export the room and choose Project > Prepare & Check.")
    end
    env.registry = cfg.selling_registry
    if highest then
        local lowest = {}
        for _, offer in ipairs(offers) do
            local e, gives = offer.entry, offer.gives
            if #gives == 1 and gives[1].kind == "item" and gives[1].count == 1
                and not next(e.cost_items or {}) and type(e.price) == "number" then
                local item = gives[1].id
                if not lowest[item] or e.price < lowest[item].entry.price then lowest[item] = offer end
            end
        end
        for _, item in ipairs(sorted(lowest)) do
            local offer = lowest[item]
            if Selling.sellable(item, env) and Selling.price(item, highest, env.items) > offer.entry.price then
                issue("warning", "economy_sell_above_buy", offer.where, offer.field .. ".price",
                    "Selling item '" .. item .. "' at a buying store pays more than its lowest catalog purchase price.",
                    "Raise this offer's price, lower the buying stores' Sell share or the project Sell price share, or set sellable = false in developer/config/items.lua; then choose Project > Prepare & Check.")
            end
        end
    end
    for _, o in ipairs(index.objects or {}) do
        if o.type == "gate" and o.visible ~= false and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            local p = o.properties or {}
            local defaults = (cfg.gate_types or {})[p.gate_type] or {}
            local item = optional(p.required_item) or optional(defaults.required_item)
            local def = item and (cfg.collectible_types or {})[item]
            item = def and optional(def.item_id) or item
            if item and Selling.sellable(item, env) then
                issue("warning", "economy_sellable_required_item", o, "required_item",
                    "This gate requires sellable item '" .. item .. "'; selling it can prevent progress.",
                    "Set sellable = false for this item in developer/config/items.lua, then choose Project > Prepare & Check.")
            end
        end
    end
end
return M
