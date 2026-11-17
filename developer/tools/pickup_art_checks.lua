-- Pure catalog coverage for authored pickups. Never rolls loot or spawns objects.
local Chest = require "mvtk.world.chest_contents"
local Drops = require "mvtk.collectibles.reward_drops"
local Enemy = require "mvtk.enemies.enemy_overrides"
local M = {}

-- Resolve inherited tile properties exactly as the room baker does, without
-- mutating the relationship index or emitting any resources. The caller owns
-- metadata reads; tests can supply inline-only metadata.
function M.with_tile_defaults(index, get_tileset_meta)
    local maps, objects = {}, {}
    for _, o in ipairs(index.objects or {}) do
        local raw = o.raw or o
        local record = o
        if raw.gid and o.map then
            local by_id = maps[o.map]
            if not by_id then
                local map = require("mvtk.core.creator_settings_model").copy(o.map)
                require("mvtk.editor.object_art").prepare({get_tileset_meta=get_tileset_meta}, map, o.file)
                by_id = {}
                local function walk(layers)
                    for _, layer in ipairs(layers or {}) do
                        for _, object in ipairs(layer.objects or {}) do
                            if object.id ~= nil then by_id[object.id] = {object=object,map=map} end
                        end
                        walk(layer.layers)
                    end
                end
                walk(map.layers)
                maps[o.map] = by_id
            end
            local normalized = by_id[o.object_id or raw.id]
            if normalized then
                record = {}
                for key, value in pairs(o) do record[key] = value end
                record.type = require("hooks.core.tiled_objects").resolve_object_type(normalized.object) or o.type
                record.properties = normalized.object.properties
                record.raw, record.map = normalized.object, normalized.map
            end
        end
        objects[#objects+1] = record
    end
    return {objects=objects}
end

local function text(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end
local function keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out+1] = k end
    table.sort(out)
    return out
end

function M.validate(index, cfg, issue)
    -- Missing means the caller has not loaded post-import art, not an empty catalog.
    if cfg.item_art == nil then return end
    local art, seen, empty_reported = cfg.item_art, {}, false
    local fix = "Add a tile whose item_type is this pickup type to the item catalog in Tiled, then Export and run Project > Prepare & Check."
    local function pickup(kind, where, field, custom_fix)
        if type(kind) ~= "string" or kind == "" or seen[kind] then return end
        seen[kind] = true
        if art[kind] then return end
        local source = where.room and ("room '" .. where.room .. "', object '"
            .. tostring(where.name or where.object_id or where.instance_id) .. "', field '" .. field .. "'")
            or (tostring(where.file) .. " entry '" .. field .. "'")
        if next(art) == nil then
            if empty_reported then return end
            empty_reported = true
            issue("warning", "pickup_art_missing", where, field,
                "The item catalog is empty. Pickup '" .. kind .. "' used in " .. source
                    .. " has no catalog image; other pickup types also need images.", custom_fix or fix)
        else
            issue("warning", "pickup_art_missing", where, field,
                "Pickup type '" .. kind .. "' used in " .. source .. " has no item catalog image.", custom_fix or fix)
        end
    end
    local function planned(items, where, field, legacy_chest)
        for _, item in ipairs(items or {}) do
            if type(item) == "table" and (tonumber(item.chance) or 1) > 0 then
                -- Chests accept the legacy collectible_type spelling; enemy tables
                -- pass entries unchanged to plan. One representative avoids expanding
                -- huge authored amounts just to discover their type.
                local kind = item.type or (legacy_chest and item.collectible_type)
                for _, drop in ipairs(Drops.plan({{type=kind, amount=1}}, cfg.collectible_types, "check_")) do
                    pickup(drop.type, where, field)
                end
            end
        end
    end
    local function mapped(drops, where, field)
        if type(drops) == "string" then drops = Enemy.parse_drops_string(drops) end
        if type(drops) ~= "table" then return end
        for _, kind in ipairs(keys(drops)) do
            if type(drops[kind]) == "table" and (tonumber(drops[kind].chance) or 1) > 0 then
                pickup(kind, where, field .. "." .. kind)
            end
        end
    end
    -- An authored "none" means no pickup, as the bakers read it.
    local function opt(value)
        value = text(value)
        if value == "none" then return "" end
        return value
    end
    local function fallback_coin(where, field)
        if not cfg.object_art then return end
        local kind = text(cfg.object_art.currency_item)
        if kind == "" then
            pickup("(unset currency_item)", where, field,
                "Choose a pickup type for currency_item in developer/config/object_art.lua. " .. fix)
        else pickup(kind, where, field .. " (object_art.currency_item)") end
    end
    local function enemy_rewards(profile, where, field)
        local table_id, drops = profile.loot_table, profile.drops
        if type(drops) == "table" and next(drops) == nil then table_id = nil end
        if table_id then return end -- All effective named tables are checked below.
        if type(drops) == "table" then mapped(drops, where, field .. ".drops")
        else fallback_coin(where, field .. ".loot_factory") end
    end
    local function chest(value, where, field, normalize)
        value = text(value)
        if normalize and Chest.looks_inline_contents(value) then
            value = Chest.normalize_inline_contents(value) or value
        end
        if value == "" then value = "common" end
        local loot = (cfg.loot_tables or {})[value]
        if loot then planned(loot.items, where, field, true)
        else planned(Chest.parse_inline_contents(value) or {{type="gem_small"}}, where, field) end
    end

    -- Room order is the content index's stable order; each type names its first source.
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and o.top_level ~= false then
            local p = require("mvtk.tiled.property_flattener").flatten(o.properties or {})
            if o.type == "chest" then chest(p.contents, o, "contents", true)
            elseif o.type == "collectible" or o.type == "ability" or o.type == "item_art" then
                -- Match the authoritative room baker, not the retired runtime
                -- spawner's object-name fallback. Tile item_art is normalized by
                -- ObjectArt.prepare before baking; owned tiles are visual only.
                local kind = p.collectible_type
                if o.type == "item_art" then kind = kind or p.item_type end
                local ability = text(p.ability_id)
                if ability == "none" then ability = "" end
                local owned = o.type == "item_art" and p.owner_ref and p.owner_ref ~= 0 and p.owner_ref ~= ""
                if kind ~= "none" and not owned and (o.type ~= "ability" or ability ~= "") then
                    kind = text(kind)
                    if kind == "none" then kind = "" end
                    if kind == "" then
                        if ability ~= "" then kind = "ability_" .. ability
                        elseif p.relic_id ~= nil or p.relic_name ~= nil or p.relic_description ~= nil or o.name == "Relic" then
                            kind = "relic"
                        end
                    end
                    if kind:match("^relic_") and not (cfg.collectible_types or {})[kind] then kind = "relic" end
                    if kind == "" then kind = "health_container" end
                    pickup(kind, o, o.type == "ability" and "ability_id" or "collectible_type")
                end
            elseif o.type == "secret" then
                if (tonumber(p.reward_amount) or 0) > 0 then pickup(opt(p.reward_type), o, "reward_type") end
            elseif o.type == "encounter" then
                -- plan clamps every amount, including zero, to at least one pickup.
                -- The encounter baker writes "none" as "" (bake_kit.opt): no reward.
                pickup(opt(p.reward_collectible), o, "reward_collectible")
            elseif o.type == "breakable_prop" or o.type == "breakable_wall" then
                if text(p.drop_collectible) ~= "none" and (o.type == "breakable_wall"
                    or ((tonumber(p.drop_count) or 1) >= 1 and (tonumber(p.drop_chance) or 1) > 0)) then
                    pickup(text(p.drop_collectible), o, "drop_collectible")
                end
            elseif o.type == "enemy" then
                local normalized = Enemy.normalize(p)
                local preset = {}
                if normalized.enemy_type then
                    local defaults = require("mvtk.enemies.enemy_respawn_policy").effective_defaults(cfg.enemy_defaults, cfg.creator_settings)
                    preset = Enemy.normalize(require("mvtk.enemies.enemy_type_overlay").resolve_with_archetype(
                        normalized.enemy_type, normalized.archetype, cfg.enemy_types or {}, cfg.enemy_skins or {},
                        {default_archetype=defaults.default_archetype}) or {})
                end
                if type(preset.drops) == "table" and next(preset.drops) == nil then preset.loot_table = nil end
                preset.loot_table = normalized.loot_table or preset.loot_table
                if normalized.drops ~= nil then preset.drops = normalized.drops end
                enemy_rewards(preset, o, "rewards")
            end
        end
    end
    for i, value in ipairs(cfg.chest_inline or {}) do
        chest(value, {file="developer/config/chest_inline_contents.lua"}, tostring(i))
    end
    for _, id in ipairs(keys(cfg.loot_tables)) do
        local where = {file=(cfg.loot_table_origins or {})[id] == "authored"
            and "developer/config/loot_tables_authored.lua" or "developer/config/loot_tables.lua"}
        local loot = cfg.loot_tables[id]
        -- Both consumers are covered, including chest-only legacy entry spelling.
        planned(loot.items, where, id .. ".items", true)
        planned(require("mvtk.enemies.loot_table_drops").entries(loot), where, id .. ".drops")
    end
    for _, id in ipairs(keys(cfg.enemy_types)) do
        local preset = Enemy.normalize(cfg.enemy_types[id])
        enemy_rewards(preset, {file="developer/config/enemy_types.lua"}, id)
    end
    for _, id in ipairs(keys(cfg.boss_types)) do
        local rewards = cfg.boss_types[id].on_defeat or {}
        local where = {file="developer/config/boss_types.lua"}
        mapped(rewards.drops, where, id .. ".on_defeat.drops")
        for _, bonus in ipairs({"no_hit_bonus", "time_bonus", "difficulty_bonus"}) do
            mapped((rewards[bonus] or {}).drops, where, id .. ".on_defeat." .. bonus .. ".drops")
        end
    end
    -- Match random_drops.pool's catalog construction without runtime ownership
    -- predicates: an unowned/eligible entry can become a pickup in a new save.
    local random = cfg.random_drops or {}
    if random.enabled then
        for _, family in ipairs({"weapons", "charms"}) do
            local catalog = cfg[family] or {}
            if random[family] and catalog.enabled then
                for _, entry in ipairs(catalog[family] or {}) do
                    if entry.random_drop ~= false then
                        pickup((family == "weapons" and "weapon_" or "charm_") .. entry.id,
                            {file="developer/config/" .. family .. ".lua"}, family .. "." .. entry.id .. ".random_drop")
                    end
                end
            end
        end
        if random.upgrades then
            for _, id in ipairs(keys((cfg.upgrades or {}).upgrades)) do
                if cfg.upgrades.upgrades[id].random_drop ~= false then
                    pickup("upgrade_" .. id, {file="developer/config/upgrades.lua"}, "upgrades." .. id .. ".random_drop")
                end
            end
        end
    end
end

return M
