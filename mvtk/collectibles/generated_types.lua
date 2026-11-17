-- Pure catalog-to-collectible generation, shared by the editor and runtime.
-- Catalogs are supplied by the caller; this module loads no configs or APIs.
local M = {}

-- Default glow colors per ability category
local category_colors = {
    movement = {r = 0.5, g = 1.0, b = 0.5, a = 1.0},   -- Green
    combat = {r = 1.0, g = 0.3, b = 0.3, a = 1.0},     -- Red
    defensive = {r = 0.3, g = 0.7, b = 1.0, a = 1.0},  -- Blue
    utility = {r = 0.8, g = 0.3, b = 1.0, a = 1.0},    -- Purple
}

local default_color = {r = 0.9, g = 0.8, b = 0.3, a = 1.0}  -- Gold fallback
local ability_icon_pool = {
    "xbox_a",
    "xbox_b",
    "xbox_x",
    "xbox_y",
    "xbox_lb",
    "xbox_rb",
    "xbox_lt",
    "xbox_rt",
    "xbox_menu",
    "xbox_view",
    "ps_cross",
    "ps_circle",
    "ps_square",
    "ps_triangle",
    "ps_l1",
    "ps_r1",
    "ps_l2",
    "ps_r2",
    "ps_options",
    "ps_share",
}

local function ability_entry(ability_id, ability_data, idx)
    local glow_color = category_colors[ability_data.category] or default_color
    local minimap_color = {r = glow_color.r, g = glow_color.g, b = glow_color.b}
    local icon = ability_icon_pool[((idx - 1) % #ability_icon_pool) + 1]
    return {
        category = "ability",
        name = ability_data.name,
        description = ability_data.description,

        -- Visual: use the gameplay visuals atlas which has ability-specific animations
        -- (ability_double_jump, ability_air_dash, etc.) built in.
        sprite = "/developer/assets/atlas/gameplay_visuals.atlas",
        animation = "ability_" .. ability_id,
        glow = true,
        glow_color = glow_color,

        -- Audio
        audio = {
            collect = "/sound#ability_found",
            ambient = "/sound#item_hum",
        },

        -- Behavior
        on_collect = "unlock_ability",
        ability_id = ability_id,

        -- UI
        notification = "Ability Unlocked: " .. ability_data.name .. "!",
        show_popup = true,
        popup_title = ability_data.name,
        popup_description = ability_data.description,
        popup_duration = 4.0,
        show_in_collection = false,

        -- Minimap
        minimap_icon = "ability",
        minimap_color = minimap_color,
    }
end

-- Collect sounds must be one-shot: "/sound#item_hum" loops (it is the ambient hum
-- of an item lying in the world), so as a collect sound it never stopped.
local function powerup_entry(id, entry)
    return {
        category = "powerup", name = entry.name,
        sprite = "/developer/assets/atlas/gameplay_visuals.atlas",
        animation = entry.icon_animation or "prop_base",
        on_collect = "apply_powerup", powerup_id = id, respawns = true,
        audio = {collect = entry.collect_sound or "/sound#gem_collect"},
        show_in_collection = false, notification = entry.name,
    }
end

local function weapon_entry(id, entry)
    return {
        category = "weapon", name = entry.name, description = entry.description,
        sprite = "/developer/assets/atlas/gameplay_visuals.atlas",
        animation = entry.icon_animation or "prop_base",
        on_collect = "grant_unique_item", item_id = "weapon_" .. id,
        unique_owner = "weapons", count_in_census = entry.count_in_census,
        audio = {collect = entry.collect_sound or "/sound#relic_found"},
        show_popup = false, show_in_collection = false,
    }
end

local function charm_entry(id, entry)
    return {
        category = "charm", name = entry.name, description = entry.description,
        sprite = "/developer/assets/atlas/gameplay_visuals.atlas",
        animation = entry.icon_animation or "prop_base",
        on_collect = "grant_unique_item", item_id = "charm_" .. id,
        unique_owner = "charms", count_in_census = entry.count_in_census,
        audio = {collect = entry.collect_sound or "/sound#relic_found"},
        show_popup = false, show_in_collection = false,
    }
end

local function upgrade_entry(id, entry)
    return {
        category = "upgrade", name = entry.name, description = entry.description,
        sprite = "/developer/assets/atlas/gameplay_visuals.atlas",
        animation = entry.icon_animation or "prop_base",
        on_collect = "apply_upgrade", upgrade_id = id,
        count_in_census = entry.count_in_census,
        audio = {collect = entry.collect_sound or "/sound#gem_collect"},
        show_popup = false, show_in_collection = false,
    }
end

-- Later catalog families add their own row when their runtime support ships.
M.SPECS = {
    {catalog = "abilities", module = "developer.config.abilities",
        source = "developer/config/abilities.lua", field = "abilities",
        prefix = "ability_", build = ability_entry},
    {catalog = "powerups", module = "developer.config.powerups",
        source = "developer/config/powerups.lua", field = "powerups",
        prefix = "powerup_", build = powerup_entry},
    {catalog = "weapons", module = "developer.config.weapons",
        source = "developer/config/weapons.lua", field = "weapons",
        prefix = "weapon_", ordered = true, build = weapon_entry},
    {catalog = "upgrades", module = "developer.config.upgrades",
        source = "developer/config/upgrades.lua", field = "upgrades",
        prefix = "upgrade_", build = upgrade_entry},
    {catalog = "charms", module = "developer.config.charms",
        source = "developer/config/charms.lua", field = "charms",
        prefix = "charm_", ordered = true, build = charm_entry},
}

-- Non-enumerable, per-input provenance distinguishes our exact entries from
-- authored ones on validation's second pass. No global registry or config cache.
local PROVENANCE = {}

function M.append(types, catalogs)
    local diagnostics, generated, metadata = {}, {}, {}
    for key, value in pairs(getmetatable(types) or {}) do metadata[key] = value end
    for key, value in pairs(metadata[PROVENANCE] or {}) do generated[key] = value end
    for _, spec in ipairs(M.SPECS) do
        local catalog = (catalogs or {})[spec.catalog]
        local entries = type(catalog) == "table" and catalog[spec.field] or nil
        local ids, by_id = {}, entries or {}
        if spec.ordered then
            by_id = {}
            for _, entry in ipairs(type(entries) == "table" and entries or {}) do
                if type(entry) == "table" and type(entry.id) == "string" then
                    ids[#ids + 1], by_id[entry.id] = entry.id, entry
                end
            end
        else
            for id in pairs(by_id) do ids[#ids + 1] = id end
            table.sort(ids)
        end
        for idx, id in ipairs(ids) do
            local key = spec.prefix .. id
            if types[key] ~= nil then
                if types[key] ~= generated[key] then
                    diagnostics[#diagnostics + 1] = {source = spec.source, id = id, key = key}
                end
            else
                types[key] = spec.build(id, by_id[id], idx)
                generated[key] = types[key]
            end
        end
    end
    metadata[PROVENANCE] = generated
    setmetatable(types, metadata)
    return types, diagnostics
end

return M
