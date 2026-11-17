-- Pure reward grammar. No engine calls or dependencies: also loaded by LuaJ.
-- Runtime appliers live in grants.lua; grammar stays pure and LuaJ-safe.
local M = {}
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function diag(ds, code, message, entry, severity)
    ds[#ds + 1] = { severity = severity or "error", code = code, message = message, entry = entry }
end
local function positive(n)
    return type(n) == "number" and n > 0 and n < math.huge and n == math.floor(n)
end
local function canonical(id, env)
    return env.canonicalize and env.canonicalize(id) or id
end
local function type_for_item(id, env)
    local keys = {}
    for k in pairs(env.collectible_types or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local def = env.collectible_types[k]
        if type(def) == "table" and type(def.item_id) == "string" and def.item_id ~= ""
            and canonical(def.item_id, env) == id and id ~= "" then return def end
    end
end
function M.is_unique(id, env)
    env = env or {}; id = canonical(id, env)
    local item = (env.items or {})[id]
    if item and item.unique == true then return true end
    -- Scan every granting type: an authored alias must not hide gear uniqueness.
    for _, def in pairs(env.collectible_types or {}) do
        if type(def) == "table" and def.on_collect == "grant_unique_item"
            and type(def.item_id) == "string" and id ~= ""
            and canonical(def.item_id, env) == id then return true end
    end
    return false
end
function M.item_name(id, env)
    env = env or {}; id = canonical(id, env)
    local item = (env.items or {})[id]
    if item and type(item.name)=="string" and item.name:find("%S") then return item.name end
    local def = type_for_item(id, env)
    if def and type(def.name)=="string" and def.name:find("%S") then return def.name end
    if id == "" then return "" end
    return {key="gameplay.unknown_name"}
end
local function name(e, env)
    if e.kind == "item" then return M.item_name(e.id, env) end
    local lookup = e.kind == "ability" and env.ability_info or nil
    local def = lookup and lookup(e.id) or ((env[e.kind == "collectible" and "collectible_types"
        or e.kind == "fast_travel" and "travel_points" or e.kind == "upgrade" and "upgrades" or "abilities"] or {})[e.id])
    return type(def)=="table" and type(def.name)=="string" and def.name:find("%S") and def.name or {key="gameplay.unknown_name"}
end
local allowed = { increase_max_health = true, increase_max_energy = true, increase_max_stamina = true,
    restore_health = true, restore_energy = true, reveal_map_area = true, reveal_nearby = true,
    reveal_map_fragment = true, add_to_collection = true, unlock_lore_entry = true, add_fragment = true }
local dedicated = { add_currency = "currency:<amount>", add_to_inventory = "item:<item_id>",
    unlock_ability = "ability:<ability_id>", grant_unique_item = "item:<item_id>" }
local function validate_id(e, env)
    local known
    if e.kind == "item" then
        if e.id == "" then return "grant_parse", "Item id resolves to an empty key alias." end
        known = (env.items or {})[e.id] or type_for_item(e.id, env)
            or (env.key_ids or {})[e.id]
    elseif e.kind == "ability" then
        known = env.ability_info and env.ability_info(e.id) or (env.abilities or {})[e.id]
    elseif e.kind == "fast_travel" then
        if env.is_known_point then known = env.is_known_point(e.id)
        elseif env.skip_travel_validation then return
        elseif env.travel_points then known = env.travel_points[e.id]
        else return end -- The world census is supplied by its later owner.
    elseif e.kind == "collectible" then known = (env.collectible_types or {})[e.id]
    else return end
    if not known then return "grant_unknown_id", "Unknown " .. e.kind .. " id '" .. e.id .. "'." end
    if e.kind ~= "collectible" then return end
    local behavior = known.on_collect
    if type(behavior) ~= "string" or not allowed[behavior] then
        local hint = dedicated[behavior]
        return "grant_wrong_kind", hint and "Use " .. hint .. " instead of this collectible."
            or "Collectible requires an allowed on_collect behavior."
    end
    if (behavior == "reveal_nearby" or behavior == "reveal_map_fragment")
        and not (type(env.position) == "table" and type(env.position.x) == "number"
            and type(env.position.y) == "number" and math.abs(env.position.x) < math.huge
            and math.abs(env.position.y) < math.huge) then
        return "grant_needs_position", "This collectible requires a numeric world position."
    end
    if not env.instance_id and not env.once_key then
        return "grant_needs_identity", "This collectible requires instance_id or once_key."
    end
end
local function describe_entry(e, env)
    if e.kind == "currency" then return {currency=e.amount} end
    local label = name(e, env)
    label = type(label)=="table" and label or {text=label}
    if e.kind == "fast_travel" then
        return {text=env.text.fast_travel_format, params={name=label}}
    end
    if (e.count or 1) > 1 then
        return {text=env.text.count_format, params={name=label, count=e.count}}
    end
    return label
end
M.KINDS = {
    currency = { arg = "amount", reversible = true },
    xp = { arg = "amount", reversible = false },
    item = { arg = "id", count = true, reversible = true },
    flag = { arg = "id", rest = true, reversible = true },
    fast_travel = { arg = "id", rest = true, reversible = true },
    ability = { arg = "id", reversible = false },
    collectible = { arg = "id", count = true, reversible = false },
    upgrade = { arg = "id", reversible = true },
    weapon_tier = { arg = "id", rest = true, reversible = true },
}
for _, row in pairs(M.KINDS) do row.validate, row.describe = validate_id, describe_entry end
M.KINDS.upgrade.validate = function(e, env)
    if not (env.upgrades or {})[e.id] then
        return "grant_unknown_id", "Unknown upgrade id '" .. e.id .. "'."
    end
end
M.KINDS.upgrade.describe = describe_entry
M.KINDS.weapon_tier.validate = function(e, env)
    local id, raw = e.id:match("^([%w_%-]+):(%d+)$")
    local n, weapon = tonumber(raw), id and (env.weapons or {})[id]
    if not weapon or not positive(n) or n < 2 or type(weapon.tiers) ~= "table"
        or type(weapon.tiers[n-1]) ~= "table" then
        return "grant_unknown_id", "Weapon tier must name a configured weapon and tier (2 or higher)."
    end
    e.weapon, e.tier = id, n
end
M.KINDS.weapon_tier.describe = function(e, env)
    local id, raw = e.id:match("^([%w_%-]+):(%d+)$")
    local weapon = (env.weapons or {})[id]
    return {key="grants.weapon_tier", params={name=weapon and {text=weapon.name} or {key="list.missing_name"}, tier=tonumber(raw)}}
end
M.KINDS.xp.validate = function(e, env)
    if not env.leveling_enabled then return "grant_leveling_off", "XP is skipped while leveling is off.", "warning" end
end
M.KINDS.xp.describe = function(e, env) return {text = env.text.xp_format, params = {amount = e.amount}} end

function M.parse(value)
    local entries, ds, ordinal = {}, {}, 0
    local function part(raw)
        ordinal = ordinal + 1
        if type(raw) ~= "string" then diag(ds, "grant_parse", "Expected reward text.", ordinal); return end
        raw = trim(raw)
        local at = raw:find(":", 1, true)
        if raw == "" then diag(ds, "grant_parse", "Empty reward entry.", ordinal); return end
        local kind = at and trim(raw:sub(1, at - 1)) or raw
        local row = M.KINDS[kind]
        if not row then
            diag(ds, "grant_unknown_kind", "Unknown reward kind '" .. kind .. "'; collectible:" .. kind .. "?", ordinal)
            return
        end
        if not at then diag(ds, "grant_parse", "Expected kind:argument.", ordinal); return end
        local arg = trim(raw:sub(at + 1))
        local e = { kind = kind, entry = ordinal, raw = raw }
        if row.arg == "amount" then
            e.amount = tonumber(arg)
            if not positive(e.amount) then diag(ds, "grant_bad_amount", "Amount must be a positive integer.", ordinal); return end
        else
            e.count = 1
            if row.count then
                local colon = arg:find(":", 1, true)
                if colon then
                    e.count = tonumber(trim(arg:sub(colon + 1))); arg = trim(arg:sub(1, colon - 1))
                    if not positive(e.count) then diag(ds, "grant_bad_amount", "Count must be a positive integer.", ordinal); return end
                end
            elseif not row.rest and arg:find(":", 1, true) then
                diag(ds, "grant_parse", "This kind has no count argument.", ordinal); return
            end
            if arg == "" then diag(ds, "grant_parse", "Reward id cannot be empty.", ordinal); return end
            e.id = arg
        end
        entries[#entries + 1] = e
    end
    local function list(s)
        if type(s) ~= "string" then part(s); return end
        local start = 1
        while true do
            local at = s:find(",", start, true)
            part(s:sub(start, at and at - 1 or #s))
            if not at then break end
            start = at + 1
        end
    end
    if type(value) == "table" then
        for _, s in ipairs(value) do list(s) end
        for k in pairs(value) do
            if type(k) ~= "number" or k < 1 or k > #value or k ~= math.floor(k) then
                diag(ds, "grant_parse", "Expected a list of reward strings.", 0); break
            end
        end
    else list(value) end
    return entries, ds
end

function M.validate(value, env)
    env = env or {}
    local entries, ds = M.parse(value)
    local seen = {}
    for _, e in ipairs(entries) do
        if e.kind == "item" then e.id = canonical(e.id, env) end
        local code, message, severity = M.KINDS[e.kind].validate(e, env)
        if code then diag(ds, code, message, e.entry, severity) end
        local key = e.kind .. ":" .. tostring(e.id or e.amount)
        if seen[key] then diag(ds, "grant_duplicate", "Duplicate reward '" .. key .. "'.", e.entry, "warning") end
        seen[key] = true
    end
    local ok = true
    for _, d in ipairs(ds) do if d.severity == "error" then ok = false end end
    return ok, ds, entries
end

-- Inject CurrencyFormat rather than requiring it: the grammar stays pure.
function M.authoring_env(tables)
    tables = tables or {}
    local env = { items = tables.items or {}, collectible_types = tables.collectible_types or {},
        abilities = (tables.abilities or {}).abilities or tables.abilities or {},
        upgrades = (tables.upgrades or {}).upgrades or {},
        travel_points = tables.travel_points, skip_travel_validation = tables.skip_travel_validation,
        key_ids = {}, position = tables.position, leveling_enabled = (tables.leveling or {}).enabled == true,
        once_key = tables.once_key, instance_id = tables.instance_id }
    env.weapons = {}
    for _, weapon in ipairs((tables.weapons or {}).weapons or {}) do env.weapons[weapon.id] = weapon end
    env.charm_items = {}
    for _, charm in ipairs((tables.charms or {}).charms or {}) do env.charm_items["charm_" .. charm.id] = true end
    if tables.world_census then
        env.travel_points = {}
        for _, entries in pairs(tables.world_census.rooms or {}) do
            for _, entry in ipairs(entries) do
                if entry.kind == "travel" and (entry.type == "fast_travel" or entry.fast_travel == true) then
                    env.travel_points[entry.id] = entry
                end
            end
        end
    end
    local keys = tables.key_ids
    if keys and keys.canonicalize then
        env.canonicalize = keys.canonicalize
        for _, id in ipairs(keys.canonical_ids()) do env.key_ids[id] = true end
    else env.key_ids = keys or {} end
    local text = tables.reward_text or tables.text or {}
    env.text = { xp_format = text.xp_format or "{amount} XP", separator = text.separator or ", ", count_format = text.count_format or "{name} x{count}",
        fast_travel_format = text.fast_travel_format or "{name} unlocked", notice_duration = text.notice_duration or 2,
        hidden_kinds = text.hidden_kinds or { flag = true } }
    local hud = tables.hud_layout or {}
    local creator = tables.creator_settings or {}
    local currency = hud.currency or {}
    local overrides = creator.published and creator.overrides and creator.overrides.hud_layout
    local effective = {}
    for k, v in pairs(currency) do effective[k] = v end
    for k, v in pairs(overrides and overrides.currency or {}) do effective[k] = v end
    env.format_currency = tables.format_currency or function(n)
        if tables.currency_format then return tables.currency_format.apply(effective.format, n, effective) end
        return tostring(n)
    end
    return env
end
-- Shared by bundled startup schemas and fresh Prepare & Check relationships.
function M.validate_crafting(config, env)
    local errors, seen = {}, {}
    local function bad(message) errors[#errors + 1] = "crafting.lua " .. message end
    if type(config) ~= "table" then return {"crafting.lua must be a table"} end
    if type(config.enabled) ~= "boolean" then bad("enabled must be boolean") end
    if type(config.recipes) ~= "table" then bad("recipes must be an ordered list"); return errors end
    for i=1,#config.recipes do
        if config.recipes[i] == nil then bad("recipes must be dense, with no missing entries") end
    end
    for i, recipe in pairs(config.recipes) do
        if type(i) ~= "number" or i < 1 or i > #config.recipes or i % 1 ~= 0 then bad("recipes must be an ordered list") end
        if type(recipe) ~= "table" then bad("recipe must be a table")
        else
            if type(recipe.id) ~= "string" or not recipe.id:match("^[%w_%-]+$") or seen[recipe.id] then bad("recipe ids must be stable and unique")
            else seen[recipe.id] = true end
            if type(recipe.name) ~= "string" or not recipe.name:find("%S") then bad("recipe name must be nonblank text") end
            if type(recipe.description) ~= "string" then bad("recipe description must be text") end
            if recipe.requires_flag ~= nil and type(recipe.requires_flag) ~= "string" then bad("requires_flag must be text") end
            for _, field in ipairs({"costs", "gives"}) do
                local ok, ds, entries = M.validate(recipe[field], env)
                if not ok then for _, d in ipairs(ds) do if d.severity == "error" then bad(d.message) end end end
                if field == "gives" and #entries == 0 then bad("gives must not be empty") end
                for _, e in ipairs(entries) do
                    if field == "costs" then
                        if e.kind ~= "currency" and e.kind ~= "item" then bad("costs accept only currency and items") end
                    elseif e.kind ~= "weapon_tier" and not (e.kind == "item" and env.charm_items[e.id]) then
                        bad("gives accept only weapon tiers and charm items")
                    end
                end
            end
        end
    end
    return errors
end
function M.describe(value, env)
    env = env or M.authoring_env()
    local entries = type(value) == "table" and value[1] and type(value[1]) == "table" and value or M.parse(value)
    local out = {}
    for _, e in ipairs(entries) do
        if not env.text.hidden_kinds[e.kind] then out[#out + 1] = M.KINDS[e.kind].describe(e, env) end
    end
    return #out == 0 and "" or {parts=out, separator={text=env.text.separator}}
end
return M
