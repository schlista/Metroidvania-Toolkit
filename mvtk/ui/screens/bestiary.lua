-- Journal descriptions remain source text and keys until the list GUI displays them.
-- Dependencies are lazy: loading the static menu registry must not register save state.
local M = {}
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end
local function name(def) return nonblank(def.name) and def.name or { key = "list.missing_name" } end
local function joined(parts, separator) return { parts = parts, separator = { key = separator } } end
local function plural(prefix, count, params)
  return { forms = { one = prefix .. "_one", other = prefix .. "_other" }, count = count, params = params }
end

function M.new(deps)
  deps = deps or {}
  local provider = {}
  local function bestiary() return deps.bestiary or require "mvtk.game.bestiary" end
  local function census() return (deps.census or require "mvtk.world.census").entries() end
  local function config(key) return deps[key] or require("developer.config." .. key) end
  function provider.title() return { key = "journal.bestiary" } end
  function provider.enabled() return bestiary().settings().enabled == true end
  function provider.header_right()
    local entries = census()
    for _, entry in ipairs(entries) do
      if entry.kind == "enemy" then
        local recorded, total = bestiary().progress(entries)
        return plural("bestiary.recorded", total, { recorded = recorded, total = total })
      end
    end
  end
  local function combat_lines(record, parts)
    local skins = config("enemy_skins_generated")
    local defaults = (deps.runtime_settings or require "developer.config.runtime_settings").section("enemy_defaults", config("enemy_defaults"))
    local resolved = (deps.overlay or require "mvtk.enemies.enemy_type_overlay").resolve_with_archetype(
      record.enemy_type, record.archetype, config("enemy_types"), skins,
      { default_archetype = defaults.default_archetype }) or {}
    local damage = config("damage_types")
    for _, field in ipairs({ { "weak_to", "bestiary.weak_to" }, { "resist_to", "bestiary.resists" }, { "immune_to", "bestiary.immune" } }) do
      local labels = {}
      for _, id in ipairs(require("mvtk.combat.elements").parse_list(resolved[field[1]], damage)) do
        labels[#labels + 1] = nonblank(damage.types[id].label) and damage.types[id].label or { key = "list.missing_name" }
      end
      if #labels > 0 then parts[#parts + 1] = { key = field[2], params = { names = joined(labels, "bestiary.list_separator") } } end
    end
    local ids = {}
    if nonblank(resolved.loot_table) then
      -- Match the enemy runtime's drops list; table identities are never display text.
      local loot = (deps.loot_tables or require("mvtk.game.loot_tables_source").load(require))[resolved.loot_table] or {}
      for _, drop in ipairs(require("mvtk.enemies.loot_table_drops").entries(loot)) do
        if (drop.chance or 1) > 0 then ids[drop.type or "currency"] = true end
      end
    else
      for id, drop in pairs(resolved.drops or {}) do
        if (drop.chance or 1) > 0 then ids[id] = true end
      end
    end
    local sorted, labels = {}, {}
    for id in pairs(ids) do sorted[#sorted + 1] = id end
    table.sort(sorted)
    local types, items = config("collectible_types"), config("items")
    for _, id in ipairs(sorted) do
      -- Drops spawn collectible types; an items.lua name is the fallback.
      local def = types[id]
      if type(def) ~= "table" or not nonblank(def.name) then def = items[id] end
      labels[#labels + 1] = id == "currency" and { key = "bestiary.currency" } or name(def or {})
    end
    if #labels > 0 then parts[#parts + 1] = { key = "bestiary.drops", params = { names = joined(labels, "bestiary.list_separator") } } end
  end
  local function detail(kind, def, record, cfg)
    local defeats = record.defeats or 0
    if defeats <= 0 then return { title = { key = "journal.unknown" }, body = cfg.unknown_text } end
    local parts = {}
    if nonblank(def.description) then parts[#parts + 1] = def.description end
    parts[#parts + 1] = plural("bestiary.defeated", defeats, { count = defeats })
    local result = { title = name(def), body = joined(parts, "bestiary.line_separator") }
    if kind == "species" then
      if defeats >= cfg.details_after then combat_lines(record, parts) end
      local skins = config("enemy_skins_generated")
      local skin = (skins.skins or skins)[record.skin]
      if skin and skin.states and skin.states.idle then
        result.portrait = { texture = "enemy", animation = record.skin .. "__idle" }
      end
    end
    return result
  end
  function provider.rows()
    local cfg, saved, entries = bestiary().settings(), bestiary().snapshot(), census()
    local ids = { species = {}, bosses = {} }
    local has_enemies = false
    for _, entry in ipairs(entries) do if entry.kind == "enemy" then has_enemies = true end end
    if has_enemies then
      for _, entry in ipairs(entries) do
        if entry.kind == "enemy" and entry.in_bestiary ~= false then
          for _, id in ipairs(entry.species or {}) do if nonblank(id) then ids.species[id] = true end end
          if cfg.include_spawned ~= false then
            for _, id in ipairs(entry.spawn_species or {}) do if nonblank(id) then ids.species[id] = true end end
          end
        elseif entry.kind == "boss" and cfg.include_bosses ~= false and nonblank(entry.preset) then ids.bosses[entry.preset] = true end
      end
    end
    for _, kind in ipairs({ "species", "bosses" }) do
      if kind == "species" or cfg.include_bosses ~= false then
        for id, record in pairs(saved[kind]) do if record.defeats > 0 then ids[kind][id] = true end end
      end
    end
    local categories, items, out = {}, {}, {}
    for i, category in ipairs(cfg.categories or {}) do categories[category.id] = { order = i, label = category.label } end
    for _, kind in ipairs({ "species", "bosses" }) do
      for id in pairs(ids[kind]) do
        local def = ((kind == "species" and cfg.entries or cfg.bosses) or {})[id] or {}
        local record = saved[kind][id] or { defeats = 0 }
        local found = record.defeats > 0
        if found or not def.hidden_until_defeated then
          local category = categories[def.category]
          items[#items + 1] = { category = category, order = def.order or 0, sort_name = nonblank(def.name) and def.name or "",
            row = { id = kind .. ":" .. id, label = found and name(def) or { key = "journal.unknown" },
              state = found and "available" or "unknown", selectable = found,
              detail = detail(kind, def, record, cfg) } }
        end
      end
    end
    table.sort(items, function(a, b)
      local ac, bc = a.category and a.category.order or math.huge, b.category and b.category.order or math.huge
      if ac ~= bc then return ac < bc end
      if a.order ~= b.order then return a.order < b.order end
      if a.sort_name ~= b.sort_name then return a.sort_name < b.sort_name end
      return a.row.id < b.row.id
    end)
    local previous
    for _, item in ipairs(items) do
      if item.category and item.category ~= previous then
        out[#out + 1] = { id = "category:" .. item.category.order, kind = "section", selectable = false,
          label = nonblank(item.category.label) and item.category.label or { key = "list.missing_name" } }
      end
      previous = item.category
      out[#out + 1] = item.row
    end
    return out
  end
  function provider.detail(_, row) return row.detail end
  return provider
end
local default = M.new()
default.new = M.new
return default
