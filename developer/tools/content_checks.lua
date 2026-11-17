-- developer/tools/content_checks.lua
-- Prepare & Check content checks for authoring mistakes that used to fail
-- silently in play (see docs/archive/PT4_TOUR_PLAYTEST_FIX_PLAN.md section 6):
--
--   creator_bindings_invalid       error    invalid fresh defaults or creator controls
--   player_size_out_of_proportion  warning  standing collider unusually tall or short in tiles
--   charm_pickup_while_off         warning  disabled charm stays in place
--   weapon_pickup_while_off        warning  disabled weapon stays in place
--   powerup_pickup_while_off       warning  disabled power-up stays in place
--   ability_pickup_starts_unlocked   warning  pickup deletes itself on a new game
--   boss_without_arena               info     boss starts when the player enters its room
--                                             (the whole room is the fight area)
--   gate_energy_unaffordable         warning  energy cost above the player's max energy
--   gate_energy_off                  error/warning  energy gate while energy starts off
--   energy_container_while_off       warning  container enables energy that starts off
--   stamina_container_while_off      warning  container enables stamina that starts off
--   station_resource_off             warning  station restores a resource that starts off
--   wall_surface_legacy              info     old wall fields await re-export
--   sequence_switch_unknown          error    order names no switch in this room
--   sequence_switch_duplicate        error    two switches have the same identity
--   switch_target_non_sequence       warning  gate ignores switch messages
--   switch_gate_without_switch       warning  switch gate has no channel sender
--   persist_state_ignored            warning  call and momentary levers ignore saved state
--   shared_persistent_channel        warning  receivers in several rooms share saved state
--   sequence_switch_persistent       warning  switch state outlives partial progress
--   undefined_immunity_ability       warning  hazard protection names no ability
--   undefined_immunity_item          warning  hazard protection names no inventory item
--   return_zone_inside_hazard        warning  return marker overlaps a hazard
--   hazard_instant_kill_overrides_return info authored kill overrides return default
--   hazard_lethal_damage_mode        info     lethal damage resolves to kill
--   lore_id_blank                    warning  blank lore identity cannot persist
--   chest_inline_contents_unregistered error  chest contents not in the generated lookup
--   pickup_art_missing               warning  authored pickup type has no catalog image
--   catalog_value_unknown           error/warning  value removed from its dropdown
--   random_drops_empty_pool       warning  enabled random drops have no eligible catalog family
--   enemy_loot_table_unknown      warning  enemy Loot table names no configured entry
--   enemy_default_archetype_unknown warning  published default preset was removed
--   guard_never_breaks             info     guard has no breaking tags
--   armor_tag_never_emitted        warning  armor requires a tag no hit emits
--   flask_upgrade_without_flask      warning  flask upgrade while healing is not flask
--   healing_pickup_items_only        warning  Healing ability pickup in items-only healing
--   attack_energy_cost              warning  attack cost exceeds starting Max energy (ignored at 0)
--   channel_heal_energy_off          error    channel healing while energy is off
--   channel_heal_unaffordable        warning  channel cost exceeds starting Max energy
--   channel_heal_no_combat_energy    info     channel healing relies on pickups/stations/rests
--   any_gate_single_ability        info     any logic has fewer than two distinct abilities
--   any_gate_without_abilities     warning  any logic has no ability requirements
--   gate_group_single_member       info     only one gate uses the shared group id
--   staged_gate_without_flags      warning  staged gate has no listed flags
--   staged_gate_count_unreachable   error    required count exceeds listed flags
--   ability_marker_without_ability  warning  hidden crossing has no ability requirement
--   action_barrier_tag_never_emitted warning  action barrier has no matching hit emitter
--   breakable_wall_requirement_never_emitted warning wall has no matching hit emitter
--   intangible_barrier_too_thick    warning barrier exceeds scaled dash distance
--   economy_bad_grant               error    invalid catalog grant or altar reward
--   economy_bad_cost_item           error    invalid catalog or altar item cost
--   economy_upgrade_requires        error    catalog references a missing upgrade
--   economy_trainer_start_unlocked  warning  trainer ability starts learned
--   economy_catalog_kind            warning  catalog has no grants for this station kind
--   economy_currency_sources        info     currency costs without a world currency source
--   economy_altar_without_reward    error    altar has no reward
--   economy_sell_share_range        error    invalid store sale share
--   economy_sell_above_buy          warning  selling one item exceeds its catalog cost
--   economy_sellable_required_item  warning  gate requires an item players can sell
--   presence_condition_invalid     error    appear_when / remove_when does not parse
--   presence_timing_invalid        error    presence_timing is not enter or live
--   state_layer_forbidden          error    world-state tile layer is a control, tag, parallax or
--                                           duplicate layer, or state_collision is not auto/none
--   state_layer_referenced         error    an object field reads the world-state layer by name
--   countdown_zone_blank           warning  Countdown Zone names no countdown
--   countdown_zone_unknown         error    zone names a missing countdown (when no dropdown is loaded)
--   countdown_unused               info     countdown has no start_when and no start zone
--   countdown_without_finish       warning  countdown can start but has no finish zone
--   countdown_reward_invalid       error/warning  reward grant text is invalid
--   countdown_unknown_music        warning  music names no registered track
--   countdown_return_safe_kills    warning  return_safe timeout while hazard returns are off
--
-- Pure Lua: takes the content index built by developer/tools/content_relationships
-- plus already-loaded config tables, so it also runs headless, in Analyze
-- Progression and in the in-game Layout Editor and layout publication checks.
local M = {}

local function check_projectile_counterplay(index, cfg, issue)
    local Model = require "mvtk.core.creator_settings_model"
    local creator = cfg.creator_settings or {}
    local overrides = creator.published == true and creator.overrides or {}
    local features = Model.merge(Model.copy(cfg.combat_features or {}), ((overrides or {}).combat or {}).features or {})
    local off = features.cut_projectiles ~= true and features.parry_reflects ~= true
    local function check(value, where, property, warn_unused)
        if value == nil or value == "" or value == "inherit" or value == "type_default" then return end
        if value ~= "none" and value ~= "destroy" and value ~= "reflect" then
            issue("warning", "projectile_deflect_unknown", where, property,
                "Unknown Projectile deflect mode '" .. tostring(value) .. "'.",
                "Choose none, destroy or reflect, then run Prepare & Check.")
        elseif off and value ~= "none" and warn_unused ~= false then
            issue("warning", "projectile_deflect_unused", where, property,
                "Projectile deflect is set while both projectile counterplay features are off.",
                "Enable Cut projectiles or Parry reflects shots under Game Settings > Combat features, or keep the setting for later.")
        end
    end
    local ids = {}
    for id in pairs(cfg.enemy_types or {}) do ids[#ids+1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local preset = cfg.enemy_types[id]
        if type(preset) == "table" then
            check(preset.projectile_deflect, {file="developer/config/enemy_types.lua"}, id .. ".projectile_deflect")
        end
    end
    ids = {}
    for id in pairs(cfg.boss_attack_patterns or {}) do ids[#ids+1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local pattern = cfg.boss_attack_patterns[id]
        if type(pattern) == "table" then
            check(pattern.projectile_deflect, {file="developer/config/attack_patterns.lua"}, id .. ".projectile_deflect")
        end
    end
    check(((overrides or {}).enemy_defaults or {}).projectile_deflect or (cfg.enemy_defaults or {}).projectile_deflect,
        {file="developer/config/enemy_defaults.lua"}, "projectile_deflect", ((overrides or {}).enemy_defaults or {}).projectile_deflect ~= nil)
    for _, o in ipairs(index.objects or {}) do
        if o.type == "enemy" and o.visible ~= false and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            check(require("mvtk.enemies.enemy_overrides").flatten_tiled_properties(o.properties or {}).projectile_deflect,
                o, "tuning.projectile_deflect")
        end
    end
end

local function check_bestiary(cfg, issue)
    local settings = cfg.bestiary or {}
    if settings.enabled~=true then return end
    local ids = {}
    for room,entries in pairs((cfg.world_census or {}).rooms or {}) do
        if not cfg.published_rooms or cfg.published_rooms[room] then
            for _,entry in ipairs(entries) do
                if entry.kind=="enemy" and entry.in_bestiary~=false then
                    for _,id in ipairs(entry.species or {}) do ids[id]=true end
                    if settings.include_spawned~=false then
                        for _,id in ipairs(entry.spawn_species or {}) do ids[id]=true end
                    end
                end
            end
        end
    end
    local sorted = {}; for id in pairs(ids) do sorted[#sorted+1]=id end; table.sort(sorted)
    for _,id in ipairs(sorted) do
        local name = ((settings.entries or {})[id] or {}).name
        if type(name)~="string" or not name:match("%S") then
            issue("warning", "bestiary_unnamed_species", {file="developer/config/bestiary.lua"}, "entries."..id..".name",
                "Census species '"..id.."' has no bestiary name.",
                "Set this entry's source name in developer/config/bestiary.lua, then run Prepare & Check.")
        end
    end
end

local function check_enemy_respawn(index, cfg, issue)
    local Policy=require "mvtk.enemies.enemy_respawn_policy"
    local defaults=Policy.effective_defaults(cfg.enemy_defaults,cfg.creator_settings)
    local configs={enemy_types=cfg.enemy_types,enemy_skins=cfg.enemy_skins,enemy_defaults=defaults}
    local fix="Choose always, room_reload, save or never, then run Prepare & Check."
    local keys={};for key in pairs(cfg.enemy_types or {}) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do
        local entry=cfg.enemy_types[key]
        if type(entry)=="table" and entry.respawn~=nil and not Policy.valid(entry.respawn) then
            issue("warning","enemy_respawn_unknown",{file="developer/config/enemy_types.lua"},key..".respawn",
                "Unknown enemy respawn policy '"..tostring(entry.respawn).."' on archetype '"..key.."'.",fix)
        end
    end
    if defaults.respawn_policy~=nil and not Policy.valid(defaults.respawn_policy) then
        issue("warning","enemy_respawn_unknown",{file="developer/config/enemy_defaults.lua"},"respawn_policy",
            "Unknown project enemy respawn policy '"..tostring(defaults.respawn_policy).."'.",fix)
    end
    local seen={}
    for _,o in ipairs(index.objects or {}) do
        if o.type=="enemy" and o.visible~=false and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            local p=o.properties or {}
            local flag=type(p.defeat_flag)=="string" and p.defeat_flag:match("^%s*(.-)%s*$") or ""
            if flag~="" and Policy.for_object(p,configs)=="never" then
                if seen[flag] then
                    issue("warning","enemy_defeat_flag_shared",o,"defeat_flag",
                        "Permanent enemies share Defeat flag '"..flag.."'; defeating either marks both defeated.",
                        "Use a different Defeat flag for each enemy unless they share one defeat.")
                else seen[flag]=o.instance_id end
            end
        end
    end
end

local function check_enemy_defense(index, cfg, issue)
    local Defense = require "mvtk.enemies.enemy_defense"
    local Overrides = require "mvtk.enemies.enemy_overrides"
    local Overlay = require "mvtk.enemies.enemy_type_overlay"
    local defaults = require("mvtk.enemies.enemy_respawn_policy").effective_defaults(
        cfg.enemy_defaults, cfg.creator_settings)
    local emitted = require("mvtk.abilities.ability_tags").hit_tags(
        cfg.player_actions, cfg.combat_attacks, cfg.carry_settings)
    local function tags(value)
        if type(value) == "table" then return value end
        local list = {}
        for tag in tostring(value or ""):gmatch("[^,%s]+") do list[#list + 1] = tag end
        return list
    end
    local function check(profile, where, prefix)
        if profile.guard and profile.guard ~= "none" and #tags(profile.guard_break) == 0 then
            issue("info", "guard_never_breaks", where, prefix .. "guard_break",
                "This guard has no breaking tags; covered hits cannot open it.",
                "Keep this intentional guard or select Guard break tags under Defense, then run Prepare & Check.")
        end
        -- A caller without complete emitter data cannot prove a tag absent.
        if (tonumber(profile.armor_hits) or 0) > 0 and cfg.player_actions
            and cfg.combat_attacks and cfg.carry_settings then
            local seen = {}
            for _, tag in ipairs(tags(profile.armor_requires)) do
                if not emitted[tag] and not seen[tag] then
                    seen[tag] = true
                    issue("warning", "armor_tag_never_emitted", where, prefix .. "armor_requires",
                        "Armor requires tag '" .. tostring(tag) .. "', which no configured player hit emits.",
                        "Choose Armor requires tags emitted by attacks, action contacts or carryable kinds, then run Prepare & Check.")
                end
            end
        end
    end
    local ids = {}
    for id in pairs(cfg.enemy_types or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local archetype = cfg.enemy_types[id]
        if type(archetype) == "table" and type(archetype.defense) == "table" then
            check(Defense.profile(archetype, {}, defaults.defense),
                {file="developer/config/enemy_types.lua"}, id .. ".defense.")
        end
    end
    for _, o in ipairs(index.objects or {}) do
        if o.type == "enemy" and o.visible ~= false
            and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            local p = Overrides.flatten_tiled_properties(o.properties or {})
            local archetype = Overlay.resolve_with_archetype(p.enemy_type, p.archetype,
                cfg.enemy_types or {}, cfg.enemy_skins or {},
                {default_archetype=defaults.default_archetype}) or {}
            check(Defense.profile(archetype, Overrides.normalize(p), defaults.defense), o, "defense.")
        end
    end
end

-- Follow the runtime's preset, placement override and explicit no-drops order.
local function check_enemy_loot_tables(index, cfg, issue)
    if not cfg.loot_tables then return end
    local Overrides = require "mvtk.enemies.enemy_overrides"
    local Overlay = require "mvtk.enemies.enemy_type_overlay"
    local defaults = require("mvtk.enemies.enemy_respawn_policy").effective_defaults(
        cfg.enemy_defaults, cfg.creator_settings)
    for _, object in ipairs(index.objects or {}) do
        if object.type == "enemy" and object.visible ~= false and object.top_level ~= false
            and (not cfg.published_rooms or cfg.published_rooms[object.room]) then
            local props = Overrides.normalize(object.properties or {})
            -- Untyped enemies skip apply_overrides at runtime.
            if props.enemy_type then
                local preset = Overlay.resolve_with_archetype(props.enemy_type, props.archetype,
                    cfg.enemy_types or {}, cfg.enemy_skins or {},
                    {default_archetype=defaults.default_archetype}) or {}
                local normalized = Overrides.normalize(preset)
                local table_id = normalized.loot_table
                if type(normalized.drops) == "table" and next(normalized.drops) == nil then table_id = nil end
                table_id = props.loot_table or table_id
                if type(props.drops) == "table" and next(props.drops) == nil then table_id = nil end
                if table_id and not cfg.loot_tables[table_id] then
                    issue("warning", "enemy_loot_table_unknown", object, "loot_table",
                        "This enemy's Loot table '" .. table_id .. "' is missing; it drops no table loot and skips fallback drops.",
                        "Choose an existing Loot table under On defeat, or add it to developer/config/loot_tables.lua, then run Prepare & Check.")
                end
            end
        end
    end
end

-- One contextual diagnostic per bad entry; callers provide already-loaded data.
function M.check_grant_text(diags, where, field, value, env, code, fix)
    local ok, found = require("mvtk.game.grant_spec").validate(value, env)
    for _, d in ipairs(found) do
        diags[#diags + 1] = { severity = d.severity, code = code or d.code, grant_code = d.code,
            message = d.message, entry = d.entry, file = where.file, room = where.room,
            layer = where.layer, object_id = where.object_id, property = field,
            fix = fix or "In Tiled, select this object in View > Views and Toolbars > Objects, correct " .. field
                .. ", then File > Export Current Room. In Defold run Project > Prepare & Check." }
    end
    return ok
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function merged(base, override)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    for k, v in pairs(override or {}) do out[k] = v end
    return out
end

-- Only aliases whose template and index types differ need translation.
-- test/catalog_value_checks_tests.lua keeps this in step with bake_audit's aliases.
local catalog_type_aliases = { ability_pickup="ability", key="collectible", map_fragment="collectible",
    secret_area="secret", sound_source="ambience_zone", moving_platform="platform", horizontal_platform="platform",
    vertical_platform="platform", path_platform="platform" }
M.CATALOG_TYPE_ALIASES = catalog_type_aliases
local ability_references = { ability_id=true, require_ability=true, requires_ability=true, reward_ability=true }

local function check_catalogs(index, cfg, issue)
    local usage, seen = {}, {}
    for _, row in ipairs(cfg.usage or {}) do
        local kind = catalog_type_aliases[row.type] or row.type
        local key = kind .. ":" .. row.property .. ":" .. row.enum
        if cfg.catalogs[row.enum] and not ability_references[row.property] and not seen[key] then
            seen[key] = true
            usage[kind] = usage[kind] or {}
            usage[kind][#usage[kind]+1] = row
        end
    end
    local function check(o, property, value, enum)
        local catalog = cfg.catalogs[enum]
        local function token(raw)
            local v = trim(raw)
            if v == "" or (catalog.sentinels or {})[v] or catalog.values[v] then return end
            local source = catalog.source or ("the template field " .. property)
            local place = o.object_id and ("object " .. tostring(o.object_id)) or "Map Properties"
            issue(catalog.severity or "error", "catalog_value_unknown", o, property,
                "'" .. v .. "' is not listed in " .. source .. " (the " .. enum .. " dropdown).",
                "In Tiled reopen MVTK.tiled-project, choose a listed value for " .. property .. " on " .. place
                    .. " in " .. tostring(o.room) .. ", export the room and choose Project > Prepare & Check; or add '"
                    .. v .. "' back to " .. source .. ".")
        end
        if catalog.flags then
            local checked = {}
            for raw in tostring(value or ""):gmatch("[^,]+") do
                local v = trim(raw)
                if not checked[v] then token(v); checked[v] = true end
            end
        else token(value) end
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false then
            for _, row in ipairs(usage[catalog_type_aliases[o.type] or o.type] or {}) do
                check(o, row.property, (o.properties or {})[row.property], row.enum)
            end
        end
    end
    -- Sort both sets so map-only diagnostics have stable order across hosts.
    local rooms, enums = {}, {}
    for room in pairs(cfg.map_properties or {}) do rooms[#rooms+1] = room end
    for enum in pairs(cfg.catalogs) do enums[#enums+1] = enum end
    table.sort(rooms); table.sort(enums)
    for _, room in ipairs(rooms) do
        local o = {room=room,file="developer/assets/tiled/maps/" .. room .. ".lua"}
        for _, enum in ipairs(enums) do
            for _, property in ipairs(cfg.catalogs[enum].map_properties or {}) do
                check(o, property, cfg.map_properties[room][property], enum)
            end
        end
    end
end

-- A biomes.lua region that no room, world default or map station names.
-- `default` is the fallback entry and is never reported.
local function check_region_unused(index, cfg, issue)
    local catalog = (cfg.catalogs or {}).biomes
    if not catalog then return end
    local used = {}
    local function use(value)
        value = trim(value)
        if value ~= "" then used[value] = true end
    end
    local world_default = trim((cfg.world_properties or {}).default_biome)
    use(world_default)
    for room, properties in pairs(cfg.map_properties or {}) do
        local biome = trim((properties or {}).biome)
        if (biome == "" or biome == "inherit") and (cfg.world_rooms or {})[room] then biome = world_default end
        use(biome)
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and o.type == "map_station" then use((o.properties or {}).reveal_area) end
    end
    local ids = {}
    for id in pairs(catalog.values or {}) do
        if id ~= "default" and not used[id] and not (catalog.sentinels or {})[id] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        issue("info", "region_unused", {file="developer/config/biomes.lua"}, id,
            "Region '" .. id .. "' in developer/config/biomes.lua is not used by any room, world default or map station.",
            "Set a room's biome to '" .. id .. "' in Tiled Map Properties and export it, or remove the entry from biomes.lua.")
    end
end

-- Only attacks reachable from a placed boss are checked. Authored attack lists
-- replace preset lists, just as the runtime boss setup does.
local function check_boss_summons(index, cfg, issue)
    if not cfg.boss_attack_patterns or not cfg.enemy_types then return end
    local objects, seen = index.objects or {}, {}
    local skins = (cfg.enemy_skins or {}).skins or {}
    local function attacks(value)
        if type(value) == "table" then return value end
        local ids = {}
        for token in tostring(value or ""):gmatch("[^,]+") do
            local id = trim(token)
            if id ~= "" then ids[#ids + 1] = id end
        end
        return ids
    end
    local function inspect(o, preset, names)
        for _, name in ipairs(names) do
            local pattern = cfg.boss_attack_patterns[name]
            local summon = type(pattern) == "table" and pattern.type == "summon" and pattern.summon
            if type(summon) == "table" then
                local kind = summon.skin or summon.enemy_type or "slime"
                local key = preset .. ":" .. name
                if not cfg.enemy_types[kind] and not skins[kind] and not seen[key] then
                    seen[key] = true
                    issue("warning", "boss_summon_type_unknown", o, "attacks",
                        "Boss preset '" .. preset .. "', attack '" .. name .. "' summons missing enemy type '"
                            .. tostring(kind) .. "'; it spawns nothing.",
                        "Point the summon at an existing enemy type or synced skin in developer/config/attack_patterns.lua, "
                            .. "then run Project > Prepare & Check.")
                end
                if summon.skin and summon.enemy_type and not cfg.enemy_types[summon.enemy_type]
                    and not seen[key .. ":archetype"] then
                    seen[key .. ":archetype"] = true
                    issue("warning", "boss_summon_type_unknown", o, "attacks",
                        "Boss preset '" .. preset .. "', attack '" .. name .. "' summons missing archetype '"
                            .. tostring(summon.enemy_type) .. "'; its art uses fallback stats.",
                        "Choose an existing enemy_types.lua key for summon.enemy_type, then run Project > Prepare & Check.")
                end
            end
        end
    end
    for _, o in ipairs(objects) do
        if o.type == "boss" and o.visible ~= false and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            local p = o.properties or {}
            local preset = trim(p.boss_type)
            local fallback, matched = attacks(p.attack_pattern_ids), false
            for _, marker in ipairs(objects) do
                if marker.type == "boss_phase" and marker.visible ~= false then
                    local m = marker.properties or {}
                    local id, arena, kind = trim(m.boss_id), trim(m.arena_id), trim(m.boss_type)
                    if marker.room == o.room and (id == "" or id == trim(p.boss_id))
                        and (arena == "" or arena == trim(p.arena_id)) and (kind == "" or kind == preset) then
                        matched = true
                        local names = attacks(m.attacks)
                        inspect(o, preset, #names > 0 and names or fallback)
                    end
                end
            end
            if not matched then
                if #fallback > 0 then inspect(o, preset, fallback)
                else
                    local config = (cfg.boss_types or {})[preset] or {}
                    for _, entry in ipairs(config.phases or {}) do inspect(o, preset, attacks(entry.attacks)) end
                end
            end
        end
    end
end

-- Group membership mirrors the authored save/music arena key. Unlocked bosses
-- remain independent even when cleanup shares the room with a locked boss.
local function check_boss_groups(index, cfg, issue)
    local groups, arenas, arena_props = {}, {}, {}
    local function music_id(value)
        local id = trim(value)
        return id ~= "none" and id or ""
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            if o.type == "boss_arena" then
                local p = o.properties or {}
                arenas[p.arena_id or o.arena_id or ""] = music_id(p.battle_music or p.combat_music)
                arena_props[p.arena_id or o.arena_id or ""] = p
                if trim(p.group_name) ~= "" and p.shared_health ~= true then
                    issue("info", "boss_group_name_unused", o, "group_name",
                        "Group name is used only with shared health.",
                        "Tick Shared health on the Boss Arena to display Group name.")
                end
            elseif o.type == "boss" then
                local p = o.properties or {}
                if p.arena_lock ~= false and p.arena_lock ~= "false" then
                    local key = trim(p.arena_id)
                    if key == "" then key = "arena_" .. tostring(o.room) end
                    groups[key] = groups[key] or {}
                    groups[key][#groups[key] + 1] = o
                end
            end
        end
    end
    local ui = cfg.boss_ui or {}
    local limit = math.max(1, math.min(3, math.floor(tonumber(ui.max_bars) or 3)))
    for key, members in pairs(groups) do
        if #members > limit then
            issue("warning", "boss_group_too_large", members[1], "arena_id",
                "This boss group has more members than the boss HUD can display.",
                "Reduce the group or raise max_bars in developer/config/boss_ui.lua, up to three.")
        end
        local first, mixed
        for _, o in ipairs(members) do
            local p = o.properties or {}
            local preset = (cfg.boss_types or {})[p.boss_type or p.boss_preset] or {}
            local audio = preset.audio or {}
            local music = music_id(p.music_track)
            if music == "" then music = music_id(p.battle_music) end
            if music == "" then music = music_id(p.combat_music) end
            if music == "" then music = music_id(arenas[key]) end
            -- Match the music controller's inherited theme precedence.
            music = music_id(audio.music_theme or audio.theme or (music ~= "" and music or audio.music))
            if first == nil then first = music elseif first ~= music then mixed = true end
        end
        if mixed then
            issue("info", "boss_group_music_mixed", members[1], "music_track",
                "Bosses in this group select different music; the lead boss's music plays for the fight.",
                "Use the same music for every member, or leave member music blank and set the Boss Arena's battle_music.")
        end
    end
    for _, boss in ipairs(index.objects or {}) do
        if boss.type == "boss" and boss.visible ~= false
            and (not cfg.published_rooms or cfg.published_rooms[boss.room]) then
            local p = boss.properties or {}
            local key = trim(p.arena_id)
            if key == "" then key = "arena_" .. tostring(boss.room) end
            for _, marker in ipairs(index.objects or {}) do
                local m = marker.properties or {}
                if marker.type == "boss_phase" and marker.visible ~= false and marker.room == boss.room
                    and m.partner_defeated == true
                    and (trim(m.boss_id) == "" or trim(m.boss_id) == trim(p.boss_id))
                    and (trim(m.arena_id) == "" or trim(m.arena_id) == trim(p.arena_id))
                    and (trim(m.boss_type) == "" or trim(m.boss_type) == trim(p.boss_type)) then
                    if p.arena_lock == false or p.arena_lock == "false" or #(groups[key] or {}) < 2 then
                        issue("warning", "boss_partner_phase_without_group", marker, "partner_defeated",
                            "This partner-defeated boss phase has no other boss in its group.",
                            "Link another Boss to the same Boss Arena and leave Arena lock ticked on both.")
                    elseif (arena_props[key] or {}).shared_health == true then
                        issue("info", "boss_partner_phase_shared", marker, "partner_defeated",
                            "A partner-defeated boss phase never starts with shared health: both bosses fall together.",
                            "Clear Shared health on the Boss Arena to use this boss phase.")
                    end
                end
            end
        end
    end
end

--- Effective start-of-game settings: baseline files plus published Setup
-- Wizard overrides (developer/config/creator_settings.lua).
-- inputs: { ability_defaults = <ability_defaults.lua table>,
--           player_settings = <player_settings.lua table>,
--           creator = <creator_settings.lua table or nil> }
function M.effective_settings(inputs)
    inputs = inputs or {}
    local overrides = (type(inputs.creator) == "table" and inputs.creator.published == true
        and type(inputs.creator.overrides) == "table") and inputs.creator.overrides or {}
    local abilities = merged((inputs.ability_defaults or {}).abilities, overrides.abilities)
    local Model = require "mvtk.core.creator_settings_model"
    local player = Model.merge(Model.copy(inputs.player_settings or {}), overrides.player)
    local progression = merged((inputs.game_config or {}).progression, overrides.progression)
    return { hazard_return_enabled = (progression.hazard_return or {}).enabled == true, abilities = abilities, max_energy = tonumber(player.max_energy), max_stamina = tonumber(player.max_stamina),
        player = player, fragments = Model.merge(Model.copy(inputs.fragments or {}), overrides.fragments), healing = merged(inputs.healing, overrides.healing) }
end

local function check_sequence_gates(index, cfg, issue)
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        if o.visible ~= false and o.type == "strike_switch" and p.persist_state == true
            and (trim(p.mode) == "timed" or trim(p.mode) == "momentary") then
            issue("warning", "persist_state_ignored", o, "persist_state",
                "Timed and momentary strike switches ignore Persist state.",
                "Clear Persist state or use toggle or once for a saved shortcut.")
        end
        if o.visible ~= false and o.type == "lever" and p.persist_state == true
            and (p.toggle == false or trim(p.message_on) == "elevator_call_bottom"
                or trim(p.message_on) == "elevator_call_top") then
            issue("warning", "persist_state_ignored", o, "persist_state",
                "Call and momentary levers ignore Persist state.",
                "Clear Persist state or use a toggle lever for a saved shortcut.")
        end
    end
    if not cfg.gate_types then return end
    local SwitchState = require "mvtk.world.switch_state"
    local Util = require "mvtk.core.util"
    local switches, gates, targets = {}, {}, {}
    local function id(value) return Util.normalize_hash_string(value) end
    local function is_sequence(o)
        return (cfg.gate_types[trim(o.properties.gate_type)] or {}).type == "sequence"
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false then
            local p = o.properties or {}
            if o.type == "gate" then
                local preset = cfg.gate_types[trim(p.gate_type)] or {}
                if preset.type == "staged" then
                    local flags = p.stage_flags or preset.stage_flags or {}
                    if type(flags) ~= "table" then flags = SwitchState.parse_order(flags) end
                    local need = tonumber(p.stages_required)
                    if not need or need < 0 then need = tonumber(preset.stages_required) or 0 end
                    if #flags == 0 then
                        issue("warning", "staged_gate_without_flags", o, "stage_flags",
                            "This staged gate has no stage flags.",
                            "List the flags written by your switches, plates or events in Stages > Stage flags.")
                    end
                    if need > #flags then
                        issue("error", "staged_gate_count_unreachable", o, "stages_required",
                            "Stages required exceeds the number of listed stage flags.",
                            "Lower Stages required or add the missing flags; 0 requires all listed flags.")
                    end
                end
                local key = id(p.gate_id) or o.instance_id
                if key then
                    gates[key] = gates[key] or {}
                    gates[key][#gates[key] + 1] = o
                end
            elseif o.type == "lever" or o.type == "pressure_plate" or o.type == "strike_switch" or o.type == "socket" then
                local target = id(p.target_id) or (o.type == "pressure_plate" and id(p.plate_id))
                if target then targets[target] = true end
                local prefix = o.type == "lever" and "lever" or o.type == "strike_switch" and "switch"
                    or o.type == "socket" and "socket" or "plate"
                -- Match the baker's property/name/fallback precedence. A blank
                -- baked id falls back to unreadable engine hash text at runtime,
                -- so never invent a usable authored identity for it here.
                local key
                if o.type == "socket" then
                    key = id(p.socket_id) or o.instance_id
                else
                    key = id(p[prefix .. "_id"] or o.name
                        or (prefix .. "_" .. o.room .. "_" .. tostring(o.object_id)))
                end
                switches[o.room] = switches[o.room] or {}
                if key then
                    local bucket = switches[o.room][key] or {}
                    switches[o.room][key] = bucket
                    bucket[#bucket + 1] = o
                    if #bucket == 2 then
                        issue("error", "sequence_switch_duplicate", o, prefix .. "_id",
                            "Switch id '" .. key .. "' matches two switches in this room.",
                            "Give each lever, strike switch, socket and pressure plate in the room a unique id.")
                    end
                end
            end
        end
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false then
            local p = o.properties or {}
            if o.type == "gate" and (cfg.gate_types[trim(p.gate_type)] or {}).type == "switch" then
                local key = id(p.gate_id) or o.instance_id
                if not targets[key] then
                    issue("warning", "switch_gate_without_switch", o, "gate_id",
                        "No switch targets this switch gate's channel '" .. tostring(key) .. "'.",
                        "Set a lever, strike switch, socket or pressure plate's Target to this gate, or Target id to its Gate id.")
                end
            elseif o.type == "gate" and is_sequence(o) then
                local order = SwitchState.parse_order(p.sequence_order)
                if #order == 0 then order = (cfg.gate_types[trim(p.gate_type)] or {}).required_sequence or {} end
                for _, step in ipairs(order) do
                    if not (switches[o.room] or {})[step] then
                        issue("error", "sequence_switch_unknown", o, "sequence_order",
                            "Sequence order id '" .. tostring(step) .. "' has no lever, strike switch, socket or pressure plate in this room.",
                            "Set Sequence order to the exact ids of switches in this room, including when replacing the preset order.")
                    end
                end
            elseif o.type == "lever" or o.type == "pressure_plate" or o.type == "strike_switch" or o.type == "socket" then
                for _, gate in ipairs(gates[id(p.target_id)] or {}) do
                    if not is_sequence(gate) and (cfg.gate_types[trim(gate.properties.gate_type)] or {}).type ~= "switch" then
                        issue("warning", "switch_target_non_sequence", o, "target_id",
                            "This switch targets a gate that ignores switch messages.",
                            (cfg.gate_types[trim(gate.properties.gate_type)] or {}).type == "staged"
                                and "Staged gates count Set flag on or a plate's Set flag; leave Target blank."
                                or "Choose a switch gate or sequence gate, or a supported trigger target.")
                    elseif is_sequence(gate) and (p.persist_state == true or ((o.type == "lever" or o.type == "strike_switch") and (p.starts_on == true or id(p.set_flag_on)))
                        or (o.type == "pressure_plate" and p.stays_pressed == true)) then
                        issue("warning", "sequence_switch_persistent", o,
                            p.persist_state == true and "persist_state" or o.type ~= "pressure_plate" and "starts_on" or "stays_pressed",
                            "This switch can stay on while sequence progress resets after a reload.",
                            "For sequence puzzles leave Persist state, Starts on and Stays pressed off, and Set flag on blank.")
                    end
                end
            end
        end
    end
end

-- Config immunity uses declared abilities, not their start-unlocked settings.
-- The grant item descriptor shares inventory ids, collectible item_ids and keys.
local function check_hazard_immunities(cfg, issue)
    local catalog = (cfg.catalogs or {}).optional_abilities
    local env = cfg.grant_env
    local grants = env and require "mvtk.game.grant_spec"
    local ids = {}
    for id, hazard in pairs(cfg.hazard_types or {}) do
        if id ~= "settings" and type(hazard) == "table" then ids[#ids+1] = id end
    end
    table.sort(ids)
    local where = {file="developer/config/hazard_types.lua"}
    for _, id in ipairs(ids) do
        local hazard = cfg.hazard_types[id]
        local ability = hazard.immunity_ability
        if catalog and ability ~= nil and ability ~= "" and not catalog.values[ability] then
            issue("warning", "undefined_immunity_ability", where, id .. ".immunity_ability",
                "Hazard '" .. id .. "' names undefined immunity ability '" .. tostring(ability) .. "'.",
                "Set immunity_ability to an id declared in developer/config/abilities.lua, or nil in "
                    .. where.file .. ", then run Project > Prepare & Check.")
        end
        local item = hazard.immunity_item
        if env and item ~= nil and item ~= "" then
            local canonical = env.canonicalize and env.canonicalize(item) or item
            local code = grants.KINDS.item.validate({kind="item", id=canonical}, env)
            if code then
                issue("warning", "undefined_immunity_item", where, id .. ".immunity_item",
                    "Hazard '" .. id .. "' names undefined immunity item '" .. tostring(item) .. "'.",
                    "Set immunity_item to an inventory id from developer/config/items.lua, a collectible item_id "
                        .. "or a key id, or nil in " .. where.file .. ", then run Project > Prepare & Check.")
            end
        end
    end
    -- Hazard-barrier presets use the same declared ability ids as hazard types.
    local gate_ids = {}
    for id, preset in pairs(cfg.gate_types or {}) do
        if type(preset) == "table" and preset.type == "hazard_barrier" then
            gate_ids[#gate_ids+1] = id
        end
    end
    table.sort(gate_ids)
    local gate_where = {file="developer/config/gate_types.lua"}
    for _, id in ipairs(gate_ids) do
        local ability = cfg.gate_types[id].required_ability
        if catalog and ability ~= nil and ability ~= "" and not catalog.values[ability] then
            issue("warning", "undefined_immunity_ability", gate_where, id .. ".required_ability",
                "Hazard-barrier preset '" .. id .. "' names undefined immunity ability '" .. tostring(ability) .. "'.",
                "Set required_ability to an id declared in developer/config/abilities.lua, or nil in "
                    .. gate_where.file .. ", then run Project > Prepare & Check.")
        end
    end
end

-- Config arena hazards and platforms spawn nothing at runtime; the supported
-- route is Tiled hazards with arena.active_phases baked into the room.
local function check_arena_phase_hazards(cfg, issue)
    local arenas = type(cfg.boss_arenas) == "table" and (cfg.boss_arenas.arenas or cfg.boss_arenas) or {}
    local ids = {}
    for id, arena in pairs(arenas) do
        if type(arena) == "table" then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    local where = {file="developer/config/boss_arenas.lua"}
    local fix = "Remove it from developer/config/boss_arenas.lua. Place environment/hazard.tx in the Boss Arena in Tiled, "
        .. "link arena_ref and set arena.active_phases, then export the room and run Project > Prepare & Check."
    local function listed(list) return type(list) == "table" and next(list) ~= nil end
    for _, id in ipairs(ids) do
        local arena = arenas[id]
        local set = false
        for _, list in pairs(type(arena.phase_hazards) == "table" and arena.phase_hazards or {}) do
            if listed(list) then set = true end
        end
        if set then
            issue("warning", "config_arena_hazards_unsupported", where, "arenas." .. id .. ".phase_hazards",
                "Arena '" .. id .. "' sets phase_hazards, which spawn nothing in play.", fix)
        end
        local phase_ids = {}
        for phase, phase_def in pairs(type(arena.phases) == "table" and arena.phases or {}) do
            if type(phase_def) == "table" and (listed(phase_def.hazards) or listed(phase_def.platforms)) then
                phase_ids[#phase_ids + 1] = tostring(phase)
            end
        end
        table.sort(phase_ids)
        for _, phase in ipairs(phase_ids) do
            issue("warning", "config_arena_hazards_unsupported", where, "arenas." .. id .. ".phases." .. phase,
                "Arena '" .. id .. "' phase " .. phase .. " lists hazards or platforms, which spawn nothing in play.", fix)
        end
    end
end

local function check_gate_groups(index, issue)
    local groups = {}
    for _, o in ipairs(index.objects or {}) do
        if o.type == "gate" and o.visible ~= false then
            local group = trim((o.properties or {}).group_id)
            if group ~= "" then
                groups[group] = groups[group] or {}
                groups[group][#groups[group] + 1] = o
            end
        end
    end
    -- Iterate the source order so diagnostics stay deterministic.
    for _, o in ipairs(index.objects or {}) do
        if o.type == "gate" and o.visible ~= false then
            local group = trim((o.properties or {}).group_id)
            if group ~= "" and #groups[group] == 1 then
                issue("info", "gate_group_single_member", o, "group_id",
                    "Only one gate uses group '" .. group .. "'.",
                    "Set the same Group id on another Gate to open them together, or leave it blank.")
            end
        end
    end
end

-- A Tiled map_icon must name an icon in map_icons.lua, or the object shows its kind's icon.
local function check_map_icons(index, cfg, issue)
    local icons = type(cfg.map_icons) == "table" and type(cfg.map_icons.icons) == "table" and cfg.map_icons.icons
    if not icons then return end
    for _, o in ipairs(index.objects or {}) do
        local icon = trim((o.properties or {}).map_icon)
        if o.visible ~= false and icon ~= "" and icon ~= "auto" and icon ~= "hide" and icons[icon] == nil then
            issue("warning", "map_icon_unknown", o, "map_icon",
                "Map icon '" .. icon .. "' is not in developer/config/map_icons.lua icons.",
                "Use auto, hide or an icon id from map_icons.lua icons, or add that icon there.")
        end
    end
end

local function check_intangible_barriers(index, cfg, issue)
    if not cfg.player then return end
    local player = require("mvtk.player.player_scale").apply(cfg.player)
    local dash = player.air_dash or {}
    local distance = (tonumber(dash.speed) or 0) * (tonumber(dash.duration) or 0)
    for _, o in ipairs(index.objects or {}) do
        local preset = (cfg.gate_types or {})[trim((o.properties or {}).gate_type)] or {}
        if o.type == "gate" and o.visible ~= false
            and (preset.type or trim((o.properties or {}).gate_type)) == "intangible_barrier" then
            local rect = o.raw or {}
            if (tonumber(rect.width) or 0) > distance
                or (dash.directions == "eight" and (tonumber(rect.height) or 0) > distance) then
                issue("warning", "intangible_barrier_too_thick", o, "gate_type",
                    "This Intangible Barrier exceeds the scaled air dash distance.",
                    "Resize the Gate in Tiled or adjust Air Dash speed and duration; export the room and run Project > Prepare & Check.")
            end
        end
    end
end

local function check_ability_barriers(index, cfg, issue)
    local Tags = require "mvtk.abilities.ability_tags"
    local Rules = require "developer.tools.progression_rules"
    local registry = ((cfg.catalogs or {}).optional_abilities or {}).values
    local function optional(value)
        local id = trim(value)
        return id ~= "" and id ~= "none" and id or nil
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false then
            local p = o.properties or {}
            local preset = (cfg.gate_types or {})[optional(p.gate_type)] or {}
            local ability_set={}
            local ability=optional(p.required_ability) or optional(preset.required_ability)
            if ability then ability_set[ability]=true end
            for token in tostring(p.required_abilities or preset.required_abilities or ""):gmatch("[^,]+") do
                local id=optional(token); if id then ability_set[id]=true end
            end
            local ability_count=0; for _ in pairs(ability_set) do ability_count=ability_count+1 end
            if o.type=="gate" and (p.requirement_logic or preset.requirement_logic)=="any" then
                if ability_count<2 then
                    issue("info","any_gate_single_ability",o,"required_abilities",
                        "Any logic has fewer than two distinct abilities.",
                        "Tick two abilities in Requirements > Required abilities to offer alternatives.")
                end
                if ability_count==0 then
                    issue("warning","any_gate_without_abilities",o,"required_abilities",
                        "Any logic has no ability requirements, so the gate needs no ability.",
                        "Tick abilities in Requirements > Required abilities, export the room and run Project > Prepare & Check.")
                end
            end
            if o.type == "gate" and p.gate_type == "ability_marker"
                and ability_count==0 then
                issue("warning", "ability_marker_without_ability", o, "required_ability",
                    "This ability marker has no required ability, so its crossing is open in the model.",
                    "Set Required ability on the Gate in Tiled, export the room and run Project > Prepare & Check.")
            end
            -- A standalone caller without emitter data cannot prove absence.
            if registry and cfg.player_actions and cfg.combat_attacks then
                local code, property, value, ids, core
                if o.type == "gate" and (preset.type or optional(p.gate_type)) == "action_barrier" then
                    property = "required_action"
                    value = optional(p.required_action) or optional(preset.required_action)
                    ids = Tags.abilities_for_tag(value, cfg.player_actions, cfg.combat_attacks, registry)
                    core = Tags.CORE_TAGS[value]
                    code = "action_barrier_tag_never_emitted"
                elseif o.type == "breakable_wall" and optional(p.required_ability) then
                    property, value = "required_ability", optional(p.required_ability)
                    ids, core = Rules.wall_emitters(value, {abilities=registry,
                        player_actions=cfg.player_actions, combat_attacks=cfg.combat_attacks})
                    code = "breakable_wall_requirement_never_emitted"
                end
                if ids and #ids == 0 and not core then
                    issue("warning", code, o, property,
                        "No ability emits a hit for '" .. (value or "") .. "'; this barrier cannot open from that requirement.",
                        "Choose a requirement emitted by developer/config/player_actions.lua or combat_config.lua, "
                            .. "export the room and run Project > Prepare & Check.")
                end
            end
        end
    end
end

--- Run every check.
-- index: content index ({ objects = { {type, room, file, layer, object_id, name, visible, properties} } })
-- cfg: { abilities = {id = bool}, max_energy = number, max_stamina = number,
--        gate_types = table, collectible_types = table, hazard_types = table, grant_env = table,
--        player_actions = table, combat_attacks = table (raw hit emitter data),
--        chest_inline = list of strings or nil (file missing),
--        catalogs = {enum={values=set,sentinels=set,source=path,severity,flags,map_properties}},
--        usage = enum usage rows, map_properties = {room=properties} }
local function moving_hazard_bounds(o, w, h)
    local p, raw, map = o.properties or {}, o.raw or {}, o.map or {}
    local spec = {motion_type=p.motion_type, motion_distance_x=tonumber(p.motion_distance_x) or 0,
        motion_distance_y=tonumber(p.motion_distance_y) or 0, motion_radius=tonumber(p.motion_radius) or 128}
    local Bake = require "hooks.core.bakes.hazard_bake"
    local _, state = Bake.reference(map, raw.id)
    state = type(state) == "table" and state or {x=0,y=0}
    local height = (tonumber(map.height) or 0)*(tonumber(map.tileheight) or 0)
    local cx, cy = (tonumber(raw.x) or 0)+state.x+w/2, height-(tonumber(raw.y) or 0)-state.y-h/2
    if p.motion_type == "path" then
        local encoded, pts = require("hooks.core.path_points").resolve(map,p.motion_path_ref,height,0,0,nil,o.object_id)
        if encoded then
            spec.points = {}
            for _, pt in ipairs(pts) do spec.points[#spec.points+1] = {x=pt.x-cx,y=pt.y-cy} end
        end
    elseif p.motion_type == "orbit" then
        local ref = p.motion_pivot_ref
        if (tonumber(type(ref)=="table" and ref.id or ref) or 0) ~= 0 then
            local pivot, offsets = Bake.reference(map,ref,"point")
            if pivot then
                spec.motion_pivot_x = (tonumber(pivot.x) or 0)+offsets.x-cx
                spec.motion_pivot_y = height-(tonumber(pivot.y) or 0)-offsets.y-cy
            end
        end
    end
    local dx, dy, sw, sh = require("mvtk.world.kinematic_path").sweep_bounds(spec,w,h)
    return cx+dx-sw/2, height-(cy+dy)-sh/2, sw, sh
end

local function moving_hazard_has_solid_art(o)
    local p, raw, map = o.properties or {}, o.raw or {}, o.map
    if not map then return false end
    local name = trim(p.retract_visual_layer):match("([^/]+)$") or "player"
    if name == "none" then name = "player" end
    local tw, th = tonumber(map.tilewidth) or 64, tonumber(map.tileheight) or 64
    local _, state = require("hooks.core.bakes.hazard_bake").reference(map, raw.id)
    state = type(state) == "table" and state or {x=0,y=0}
    local x, y = (tonumber(raw.x) or 0) + state.x, (tonumber(raw.y) or 0) + state.y
    local w, h = tonumber(raw.width) or tw, tonumber(raw.height) or th
    local function shaped(gid)
        gid = gid % 536870912 -- Strip Tiled flip bits; gid 1 is tilesource tile 0.
        local selected
        for _, ts in ipairs(map.tilesets or {}) do
            if gid >= (ts.firstgid or 1) and (not selected or (ts.firstgid or 1) > (selected.firstgid or 1)) then selected = ts end
        end
        for _, tile in ipairs(selected and selected.tiles or {}) do
            local group = tile.objectGroup or tile.objectgroup
            if tile.id == gid - (selected.firstgid or 1) and group and #(group.objects or {}) > 0 then return true end
        end
        return false
    end
    local function walk(layers, ox, oy)
        for _, layer in ipairs(layers or {}) do
            local lx, ly = ox + (tonumber(layer.offsetx) or 0), oy + (tonumber(layer.offsety) or 0)
            if layer.type == "tilelayer" and layer.name == name then
                for _, chunk in ipairs(layer.chunks or {{x=layer.x or 0,y=layer.y or 0,width=layer.width or map.width,data=layer.data}}) do
                    local data = require("mvtk.editor.tilemap_regen").decode_tiled_layer_data({
                        data=chunk.data, encoding=chunk.encoding or layer.encoding,
                        compression=chunk.compression or layer.compression,
                    }, o.room, name)
                    for i, gid in ipairs(type(data) == "table" and data or {}) do
                        local cx = lx + ((chunk.x or 0) + (i-1) % chunk.width) * tw
                        local cy = ly + ((chunk.y or 0) + math.floor((i-1) / chunk.width)) * th
                        if tonumber(gid) and gid > 0 and cx + tw > x and cx < x+w and cy+th > y and cy < y+h and shaped(gid) then return true end
                    end
                end
            end
            if walk(layer.layers, lx, ly) then return true end
        end
        return false
    end
    return walk(map.layers, 0, 0)
end

local function check_hazard_returns(index, cfg, issue)
    local Contact = require "mvtk.hazards.hazard_contact"
    local hazards, zones = {}, {}
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false then
            if o.type == "hazard" or o.type == "pendulum_hazard" then hazards[#hazards+1] = o
            elseif o.type == "hazard_return_zone" then zones[#zones+1] = o end
        end
    end
    for _, o in ipairs(hazards) do
        local p = o.properties or {}
        local defaults = o.type == "hazard" and ((cfg.hazard_types or {})[p.hazard_type or "spikes"] or {}) or {}
        local mode = Contact.normalize_mode(p.on_contact, o.name)
        if o.type == "hazard" and cfg.hazard_return_enabled and defaults.on_contact == "safe_return" and p.instant_kill == true and not mode then
            issue("info","hazard_instant_kill_overrides_return",o,"instant_kill",
                "Instant kill overrides this type's safe return.","Set On contact to safe_return, or untick Instant kill.")
        end
        if o.type == "hazard" and mode == "damage" and (p.instant_kill == true or defaults.instant_kill == true) then
            issue("info","hazard_lethal_damage_mode",o,"on_contact",
                "A lethal hazard cannot use plain damage; it resolves to kill.","Choose safe_return or kill.")
        end
        local motion = trim(p.motion_type)
        if o.type == "hazard" and motion ~= "" and motion ~= "none" then
            local dx, dy = tonumber(p.motion_distance_x) or 0, tonumber(p.motion_distance_y) or 0
            local ref = p.motion_pivot_ref
            local pivot = (tonumber(type(ref)=="table" and ref.id or ref) or 0) ~= 0
            if ((motion == "line" or motion == "slam") and dx == 0 and dy == 0)
                or (motion == "orbit" and not pivot and (tonumber(p.motion_radius) or 128) == 0)
                or (motion ~= "slam" and (tonumber(p.motion_speed) or 200) == 0) then
                issue("warning","moving_hazard_no_travel",o,"motion_type",
                    "This moving hazard has no travel or speed.","Set Path motion travel, radius or speed to a nonzero value.")
            end
            if Contact.resolve(p.on_contact,p.instant_kill,defaults) == "safe_return" then
                issue("info","moving_hazard_safe_return",o,"on_contact",
                    "Safe returns avoid this hazard's whole sweep.","Add a Hazard Return Zone on safe ground in tight rooms.")
            end
            if p.retract_hides_tiles ~= false then
                issue("info","moving_hazard_painted_art",o,"retract_hides_tiles",
                    "Painted tiles under this hazard now move with it.","Paint on Retract visual layer; surrounding floor tiles stay in the room.")
                if moving_hazard_has_solid_art(o) then
                    issue("warning","moving_hazard_solid_art",o,"retract_visual_layer",
                        "Captured art has collision shapes; its solid ground will not move with the hazard.","Use art without collision shapes and paint the floor on a separate layer.")
                end
            end
        end
    end
    for _, zone in ipairs(zones) do
        local z = zone.raw or {}
        local x, y = (tonumber(z.x) or 0)+(tonumber(z.width) or 0)/2,
            (tonumber(z.y) or 0)+(tonumber(z.height) or 0)
        for _, hazard in ipairs(hazards) do
            local h = hazard.raw or {}
            local hx, hy = tonumber(h.x) or 0, tonumber(h.y) or 0
            local hw, hh = tonumber(h.width) or 0, tonumber(h.height) or 0
            if hazard.type == "hazard" and trim((hazard.properties or {}).motion_type) ~= ""
                and trim((hazard.properties or {}).motion_type) ~= "none" then
                hx, hy, hw, hh = moving_hazard_bounds(hazard, hw, hh)
            end
            if hazard.type == "pendulum_hazard" then
                local p = hazard.properties or {}
                local bw = tonumber(p.blade_width) or 0
                if bw <= 0 then bw = hw end
                local dx, dy, sw, sh = require("mvtk.hazards.pendulum_geometry").swept_box(hh, bw, p.blade_height, p.arc_degrees)
                hx, hy, hw, hh = hx + hw / 2 + dx - sw / 2, hy - dy - sh / 2, sw, sh
            end
            if zone.room == hazard.room and x >= hx and y >= hy and x <= hx + hw and y <= hy + hh then
                issue("warning","return_zone_inside_hazard",zone,"return_zone_id",
                    "The return zone's bottom centre is inside a hazard.","Move the zone onto safe ground.")
                break
            end
        end
    end
end

local function check_positional_ambience(index, cfg, issue)
    local areas = {}
    local function optional(value)
        value = trim(value)
        return value ~= "" and value ~= "none" and value ~= "inherit" and value or nil
    end
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        if o.visible ~= false and o.type == "ambience_zone" and not p.positional then
            local id = optional(p.ambience_id)
            if id then areas[o.room] = areas[o.room] or {}; areas[o.room][id] = true end
        end
    end
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        if o.visible ~= false and o.type == "ambience_zone" and p.positional == true then
            if (tonumber(p.falloff_end) or 640) <= (tonumber(p.falloff_start) or 0) then
                issue("warning", "positional_falloff_range", o, "falloff_end",
                    "Falloff end must exceed Falloff start.", "Increase Falloff end in Positional audio.")
            end
            if (tonumber(p.music_volume_percent) or 100) < 100 then
                issue("warning", "positional_music_duck_ignored", o, "music_volume_percent",
                    "Positional ambience ignores music volume percent.", "Use an area-mode Ambience Zone for music ducking.")
            end
            local id = optional(p.ambience_id)
            local world = (cfg.world_rooms or {})[o.room] and cfg.world_properties or {}
            local room = (cfg.map_properties or {})[o.room] or {}
            local ambient = require("mvtk.tiled.world_properties").resolve(room, world).ambient_sound
            if id and ((areas[o.room] or {})[id] or optional(ambient) == id) then
                issue("warning", "positional_ambience_shared", o, "ambience_id",
                    "This id is shared with an area zone or room/world ambient sound; they control the same sound component.",
                    "Choose a separate ambience id for positional sources, export the room and run Project > Prepare & Check.")
            end
        end
    end
end

local function check_launch_pads(index, issue)
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and o.type == "bounce_pad" then
            local p = o.properties or {}
            local angle = tonumber(p.launch_angle) or 90
            if angle < 0 or angle > 180 then
                issue("warning", "launch_angle_range", o, "launch_angle",
                    "Launch angle is outside 0 to 180 degrees.", "Choose an upward launch angle in Launch.")
            end
            if (tonumber(p.control_lock_time) or 0) > 2 then
                issue("warning", "launch_lock_long", o, "control_lock_time",
                    "Control lock time exceeds 2 seconds.", "Shorten the lock in Launch unless this long flight is intentional.")
            end
        end
    end
end

local function check_launch_cannons(index, issue)
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and o.type == "launch_cannon" then
            local p = o.properties or {}
            local angle = tonumber(p.angle) or 45
            local sweep = p.aim_mode == "sweep" and math.abs(tonumber(p.sweep_range) or 90) / 2 or 0
            if sweep == 0 and p.aim_mode == "sweep" then
                issue("info", "cannon_empty_sweep", o, "sweep_range", "Sweep range is zero; aim stays fixed.", "Set Sweep range above zero to rotate while loaded.")
            end
            if angle - sweep < 0 or angle + sweep > 180 then
                issue("warning", "cannon_below_horizontal", o, "angle", "Cannon aim can point below horizontal.", "Check the whole player flight and landing, or choose an upward aim.")
            end
            if p.fire_on == "auto" and (tonumber(p.auto_delay) or 1) <= 0 then
                issue("error", "cannon_auto_delay", o, "auto_delay", "Auto delay must be positive.", "Set Auto delay above zero before exporting.")
            end
        end
    end
end

local function check_climb_rectangles(index, cfg, issue)
    local player = require("mvtk.player.player_scale").apply(cfg.player or {})
    local min_width = (tonumber(player.collider_half_width) or 30) * 4
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and o.type == "ladder" then
            local p, raw = o.properties or {}, o.raw or o
            if p.ladder_type == "hang_bar" and (tonumber(raw.height) or 0) > 64 then
                issue("warning", "hang_bar_too_tall", o, "ladder_type",
                    "This hang bar is taller than 64 pixels.",
                    "Make the rectangle wide and short, export the room and run Project > Prepare & Check.")
            elseif p.ladder_type == "climb_mesh" and (tonumber(raw.width) or 0) < min_width then
                issue("warning", "climb_mesh_too_narrow", o, "ladder_type",
                    "This climb mesh is narrower than twice the player collider width.",
                    "Widen the rectangle, export the room and run Project > Prepare & Check.")
            end
        end
    end
end

local function check_zip_line_clearance(index, cfg, issue)
    local player=require("mvtk.player.player_scale").apply(cfg.player or {})
    local hang=(player.zip_line or {}).hang_offset_px or 70
    local hw,hh=player.collider_half_width or 0,player.collider_half_height or 0
    local function crosses(a,b,x,y,w,h)
        local lo,hi=0,1
        for _,v in ipairs({{a.x,b.x-a.x,x-hw,x+w+hw},{a.y,b.y-a.y,y-hh,y+h+hh}}) do
            if math.abs(v[2])<0.000001 then
                if v[1]<v[3] or v[1]>v[4] then return false end
            else
                local t,u=(v[3]-v[1])/v[2],(v[4]-v[1])/v[2]
                if t>u then t,u=u,t end
                lo,hi=math.max(lo,t),math.min(hi,u)
                if lo>hi then return false end
            end
        end
        return true
    end
    for _,o in ipairs(index.objects or {}) do
        if o.visible~=false and o.type=="zip_line" and o.map then
            local map=o.map
            local mh=(map.height or 0)*(map.tileheight or 0)
            local encoded,points=require("hooks.core.path_points").resolve(map,(o.properties or {}).path_ref,mh,0,0,nil,o.object_id)
            if encoded then
                local hit=false
                local tw,th=map.tilewidth or 64,map.tileheight or 64
                local function walk(layers,ox,oy)
                    for _,layer in ipairs(layers or {}) do
                        local x,y=ox+(layer.offsetx or 0),oy+(layer.offsety or 0)
                        if layer.name=="solid" and layer.type=="tilelayer" then
                            local chunks=layer.chunks or {{x=layer.x or 0,y=layer.y or 0,width=layer.width or map.width,data=layer.data}}
                            for _,chunk in ipairs(chunks) do
                                for i,tile in ipairs(chunk.data or {}) do
                                    if tonumber(tile) and tonumber(tile)~=0 then
                                        local tx=x+((chunk.x or 0)+(i-1)%chunk.width)*tw
                                        local ty=y+((chunk.y or 0)+math.floor((i-1)/chunk.width))*th
                                        for j=1,#points-1 do
                                            local a,b=points[j],points[j+1]
                                            if crosses({x=a.x,y=mh-a.y+hang},{x=b.x,y=mh-b.y+hang},tx,ty,tw,th) then hit=true end
                                        end
                                    end
                                end
                            end
                        end
                        walk(layer.layers,x,y)
                    end
                end
                walk(map.layers,0,0)
                if hit then issue("warning","zip_line_solid_overlap",o,"path_ref",
                    "The hanging player collider overlaps solid tiles along this zip line; terrain collision will stop the ride.",
                    "Move the polyline or clear space below the cable for the player's body, export and run Project > Prepare & Check.") end
            end
        end
    end
end

local function check_breakable_props(index, cfg, issue)
    local persistent = {}
    local fix = "Select the Breakable Prop in Tiled, correct this field, export the room and run Project > Prepare & Check."
    for _, o in ipairs(index.objects or {}) do
        if o.type == "breakable_prop" and o.visible ~= false and o.top_level ~= false then
            local p, raw = o.properties or {}, o.raw or {}
            local function warn(code, field, message) issue("warning", code, o, field, message, fix) end
            if p.stays_broken == true then
                local id = trim(p.prop_id); if id == "" then id = o.instance_id end
                persistent[id] = persistent[id] or {}; table.insert(persistent[id], o)
            end
            local drop = trim(p.drop_collectible)
            if drop ~= "" and drop ~= "none" and cfg.collectible_types then
                local def = cfg.collectible_types[drop]
                if not def then warn("prop_drop_unknown", "drop_collectible", "Unknown collectible drop '" .. drop .. "'.")
                else
                    local item = ((cfg.grant_env or {}).items or {})[def.item_id] or {}
                    if def.category == "relic" or def.category == "lore" or def.unique or item.unique
                        or def.on_collect == "collect_relic" or def.on_collect == "collect_lore" then
                        warn("prop_drop_not_counted", "drop_collectible", "Prop drops are runtime pickups; relic, lore and unique drops are excluded from Journal census totals.")
                    end
                end
            end
            local name, map = p.painted_layer or "", o.map
            if name == "none" or trim(name) == "" then name = "" end
            if name ~= "" and map then
                if (tonumber(raw.rotation) or 0) ~= 0 then
                    warn("prop_painted_rotation", "painted_layer", "Painted prop rectangles must have Rotation 0.")
                end
                local Layers = require "mvtk.editor.tilemap_regen"
                if Layers.is_control_tile_layer(name) or Layers.is_tag_tile_layer(name) then
                    warn("prop_painted_control_layer", "painted_layer", "Props cannot cut a control or tag layer; use a decorative art layer.")
                end
                local found, count, collision, unreadable = false, 0, false, false
                local tw, th = tonumber(map.tilewidth) or 64, tonumber(map.tileheight) or 64
                local x, y, w, h = tonumber(raw.x) or 0, tonumber(raw.y) or 0, tonumber(raw.width) or 64, tonumber(raw.height) or 64
                -- Only top-level objects are checked above; the baker adds this
                -- object's layer offset before comparing with map-space tiles.
                for _, layer in ipairs(map.layers or {}) do
                    for _, candidate in ipairs(layer.objects or {}) do
                        if candidate == raw then
                            x, y = x + (tonumber(layer.offsetx) or 0), y + (tonumber(layer.offsety) or 0)
                        end
                    end
                end
                local function has_collision(gid)
                    gid = gid % 536870912 -- Tiled flip flags do not change the tile identity.
                    local selected
                    for _, ts in ipairs(map.tilesets or {}) do
                        if gid >= (ts.firstgid or 1) and (not selected or (ts.firstgid or 1) > (selected.firstgid or 1)) then selected = ts end
                    end
                    for _, tile in ipairs(selected and selected.tiles or {}) do
                        local group = tile.objectGroup or tile.objectgroup
                        if tile.id == gid - (selected.firstgid or 1) and group and #(group.objects or {}) > 0 then return true end
                    end
                    return false
                end
                local function walk(layers, ox, oy)
                    for _, layer in ipairs(layers or {}) do
                        local lx, ly = ox + (layer.offsetx or 0), oy + (layer.offsety or 0)
                        if layer.type == "tilelayer" and layer.name == name then
                            found = true
                            local chunks = layer.chunks or {{x = layer.x or 0, y = layer.y or 0, width = layer.width or map.width, data = layer.data}}
                            for _, chunk in ipairs(chunks) do
                                local ok, data, err = pcall(Layers.decode_tiled_layer_data, {
                                    data = chunk.data, encoding = chunk.encoding or layer.encoding,
                                    compression = chunk.compression or layer.compression,
                                }, o.room, name)
                                if not ok or type(data) ~= "table" then
                                    unreadable = true
                                    warn("prop_painted_layer_unreadable", "painted_layer", "Cannot inspect painted tiles: " .. tostring(ok and err or data))
                                else
                                    for i, gid in ipairs(data) do
                                        local cx = lx + ((chunk.x or 0) + (i - 1) % chunk.width + 0.5) * tw
                                        local cy = ly + ((chunk.y or 0) + math.floor((i - 1) / chunk.width) + 0.5) * th
                                        if tonumber(gid) and gid ~= 0 and cx + tw / 2 > x and cx - tw / 2 < x + w and cy + th / 2 > y and cy - th / 2 < y + h then
                                            count = count + 1; collision = collision or has_collision(gid)
                                        end
                                    end
                                end
                            end
                        end
                        walk(layer.layers, lx, ly)
                    end
                end
                walk(map.layers, 0, 0)
                if not found then warn("prop_painted_layer_missing", "painted_layer", "The named painted layer does not exist.")
                elseif count == 0 and not unreadable then warn("prop_painted_layer_empty", "painted_layer", "No painted cells lie inside the prop rectangle.") end
                if collision then warn("prop_painted_collision", "painted_layer", "These tiles have collision shapes that remain in the room after the prop breaks; use tiles without collision shapes.") end
            end
        end
    end
    for id, objects in pairs(persistent) do
        local rooms = {}; for _, o in ipairs(objects) do rooms[o.room] = true end
        local count = 0; for _ in pairs(rooms) do count = count + 1 end
        if count > 1 then
            for _, o in ipairs(objects) do issue("warning", "prop_id_duplicate", o, "prop_id",
                "Saved prop_id '" .. id .. "' is repeated across rooms.", fix) end
        end
    end
end

local function check_grouped_and_water_enemies(index, cfg, issue)
    local defaults = require("mvtk.enemies.enemy_respawn_policy").effective_defaults(
        cfg.enemy_defaults, cfg.creator_settings)
    for _, enemy in ipairs(index.objects or {}) do
        if enemy.type == "enemy" and enemy.visible ~= false and enemy.top_level ~= false then
            local props = require("mvtk.enemies.enemy_overrides").flatten_tiled_properties(enemy.properties or {})
            local preset = require("mvtk.enemies.enemy_type_overlay").resolve_with_archetype(
                props.enemy_type, props.archetype, cfg.enemy_types or {}, cfg.enemy_skins or {},
                {default_archetype=defaults.default_archetype}) or {}
            local resolved = require("mvtk.enemies.enemy_behavior_resolver").resolve({
                movement=props.movement or preset.movement, behavior=preset.behavior})
            local death = require("mvtk.enemies.enemy_overrides").resolve_death_effects(preset, props, defaults)
            if death.death_behavior == "hazard" and (tonumber(death.death_hazard_time) or 0) <= 0 then
                issue("error", "death_hazard_time_not_positive", enemy, "death_hazard_time",
                    "A death hazard needs a positive lifetime.",
                    "Set Death effects > Death hazard time to positive seconds, then run Prepare & Check.")
            end
            if resolved.movement == "swarm" and trim(props.group_id) == "" then
                issue("warning", "swarm_without_group", enemy, "group_id",
                    "This swarm enemy has no Group id and will move as a lone leader.",
                    "Set Stats > Group id to the same non-empty value on each swarm member.")
            end
            if resolved.movement == "swim" then
                local point, wet = enemy.raw or {}, false
                for _, water in ipairs(index.objects or {}) do
                    local rect = water.raw or {}
                    if water.room == enemy.room and water.type == "water_volume"
                        and water.visible ~= false and water.top_level ~= false
                        and (point.x or 0) >= (rect.x or 0) and (point.x or 0) <= (rect.x or 0)+(rect.width or 0)
                        and (point.y or 0) >= (rect.y or 0) and (point.y or 0) <= (rect.y or 0)+(rect.height or 0) then
                        wet=true;break
                    end
                end
                if not wet then issue("warning","swim_enemy_outside_water",enemy,"movement",
                    "This swimming enemy is outside every Water Volume in its room.",
                    "Place the Enemy inside a Water Volume, export the room and run Project > Prepare & Check.") end
            end
        end
    end
end

local function check_air_pockets(index, issue)
    local waters = {}
    for _, o in ipairs(index.objects or {}) do
        if o.type == "water_volume" and o.visible ~= false and o.top_level ~= false then
            waters[#waters + 1] = o
        end
    end
    for _, o in ipairs(index.objects or {}) do
        if o.type == "air_pocket" and o.visible ~= false and o.top_level ~= false then
            local a = o.raw or {}
            local wet = false
            for _, water in ipairs(waters) do
                local b = water.raw or {}
                if o.room == water.room and (a.x or 0) < (b.x or 0) + (b.width or 0)
                    and (b.x or 0) < (a.x or 0) + (a.width or 0)
                    and (a.y or 0) < (b.y or 0) + (b.height or 0)
                    and (b.y or 0) < (a.y or 0) + (a.height or 0) then
                    wet = true
                    break
                end
            end
            if not wet then
                issue("warning", "air_pocket_dry", o, "air_pocket_id",
                    "This Air Pocket overlaps no Water Volume.",
                    "Move the Air Pocket inside a Water Volume, export the room and run Project > Prepare & Check.")
            end
        end
    end
end

local function check_water_levels(index, issue)
    local function named_layer(layers, name)
        for _, layer in ipairs(layers or {}) do
            if layer.type == "tilelayer" and layer.name == name then return true end
            if named_layer(layer.layers, name) then return true end
        end
        return false
    end
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        if (o.type == "water_volume" or o.type == "hazard") and o.visible ~= false and o.top_level ~= false
            and p.level_mode and p.level_mode ~= "" and p.level_mode ~= "none" then
            local function report(severity, code, field, text)
                issue(severity,code,o,field,text,
                    "Select the object in Tiled, correct Level, export the room and run Project > Prepare & Check.")
            end
            if o.type == "hazard" then
                if trim(p.motion_type) ~= "" and trim(p.motion_type) ~= "none" then
                    report("error","level_and_motion","level_mode","A Hazard cannot use both Level and Path motion.")
                end
                if (p.retractable == true or trim(p.retract_visual_layer) ~= "") and p.retract_hides_tiles ~= false then
                    report("warning","level_retract_tiles","retract_hides_tiles",
                        "Retract hides tiles uses a separate rectangle; clear it and use Level art layer for rising art.")
                end
            end
            local offset = tonumber(p.level_offset) or 0
            if p.level_mode == "switch" and offset == 0 then
                report("warning","level_no_change","level_offset","The switched water level has no offset.")
            end
            local th = tonumber(o.map and o.map.tileheight) or 64
            if p.level_mode == "switch" and (tonumber(o.raw and o.raw.height) or 128) + offset*th <= 1 then
                report("info","level_fully_drained","level_offset","The water drains to the one-pixel collision floor.")
            end
            for _, art in ipairs(index.objects or {}) do
                if art.type == "object_art" and art.room == o.room then
                    local a = art.properties or {}
                    local ref = a.owner_ref
                    if type(ref) == "table" then ref=ref.id end
                    if tonumber(ref) == tonumber(o.object_id) or (a.owner_id and a.owner_id == (p.water_id or p.hazard_id)) then
                        report("warning","level_linked_art","level_mode","Linked object art moves with the volume centre; use Level art layer for water rows.")
                        break
                    end
                end
            end
            local layer = trim(p.level_art_layer)
            if layer ~= "" and not named_layer(o.map and o.map.layers,layer) then
                report("warning","level_art_layer_missing","level_art_layer","The named water art tile layer does not exist.")
            end
        end
    end
end

local function check_vehicles(index, issue)
    -- Match the registry's horizontal footprint and basin floor, including
    -- segments that cross a narrow volume without a waypoint inside it.
    local function crosses(points, water, map)
        local rect = water.raw or {}
        local x, y = rect.x or 0, rect.y or 0
        -- Only top-level volumes reach this check; apply their object layer's
        -- offset exactly as the room baker does before placing their bodies.
        for _, layer in ipairs(map.layers or {}) do
            for _, object in ipairs(layer.objects or {}) do
                if object == rect then
                    x, y = x + (tonumber(layer.offsetx) or 0), y + (tonumber(layer.offsety) or 0)
                    break
                end
            end
        end
        local left, right = x, x + (rect.width or 0)
        local bottom = (map.height or 0)*(map.tileheight or 0) - y - (rect.height or 0)
        for i = 2, #(points or {}) do
            local a, b = points[i-1], points[i]
            local lo, hi, dx = 0, 1, b.x-a.x
            if dx == 0 then
                if a.x < left or a.x > right then hi = -1 end
            else
                local t1, t2 = (left-a.x)/dx, (right-a.x)/dx
                lo, hi = math.max(0, math.min(t1,t2)), math.min(1, math.max(t1,t2))
            end
            if lo <= hi and math.max(a.y+(b.y-a.y)*lo, a.y+(b.y-a.y)*hi) >= bottom then return true end
        end
        return false
    end
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        local function get(_, key) return p[key] end
        if o.visible ~= false and (o.type == "platform" or o.type == "moving_platform")
            and require("hooks.core.platform_resources").vehicle_enabled(o.raw or {}, get) then
            local tracks, err, code = require("hooks.core.platform_resources").vehicle_tracks(o.map or {}, o.raw or {}, get)
            if not tracks then issue("error", code, o, code == "vehicle_alt_path_detached" and "vehicle_alt_path" or "path_name",
                err, "Draw named polylines through open space inside this room; start the second track on the first.") end
            if p.player_parent == false then issue("warning", "vehicle_no_carry", o, "player_parent",
                "This vehicle does not carry its player rider.", "Tick Player parent under Collision and rider.") end
            if tracks and p.vehicle_float == true then
                local wet = false
                for _, water in ipairs(index.objects or {}) do
                    if water.room == o.room and water.type == "water_volume" and water.visible ~= false
                        and water.top_level ~= false and (crosses(tracks.points, water, o.map or {})
                            or crosses(tracks.alternate, water, o.map or {})) then wet = true; break end
                end
                if not wet then issue("warning", "raft_without_water", o, "vehicle_float",
                    "This floating vehicle's tracks cross no Water Volume.",
                    "Draw its track over a Water Volume in this room, export the room and run Project > Prepare & Check.") end
            end
        end
    end
end

local function check_combat_music(index, cfg, issue)
    if not cfg.combat_music then return end
    local Model = require "mvtk.core.creator_settings_model"
    local creator = cfg.creator_settings or {}
    local overrides = creator.published and (creator.overrides or {}).combat_music or {}
    local config = Model.merge(Model.copy(cfg.combat_music), overrides)
    local tracks = (cfg.music_tracks or {}).tracks or {}
    local aliases = cfg.ambience_tracks or {}
    local function check(value, where, property)
        value = trim(value)
        if value == "" or value == "inherit" or value == "none" then return false end
        local alias = aliases[value]
        local id = alias and alias.cue and alias.cue:match("/([^/]+)%.sound$") or value
        if not tracks[id] then
            issue("warning", "combat_music_unknown_track", where, property,
                "Combat music track '" .. value .. "' is not registered.",
                "Choose a registered track id, or add its audio file and run Prepare & Check.")
        end
        return true
    end
    local where = {file="developer/config/combat_music.lua"}
    local any = check(config.default_track, where, "default_track")
    local maps = cfg.map_properties or (index or {}).normalized_maps or {}
    local rooms = {}
    for room in pairs(maps) do rooms[#rooms+1] = room end
    table.sort(rooms)
    for _, room in ipairs(rooms) do
        local properties = cfg.map_properties and maps[room] or maps[room].properties or {}
        if check(properties.combat_music, {room=room}, "combat_music") then any = true end
    end
    if config.enabled and not any then
        issue("info", "combat_music_without_track", where, "default_track",
            "Combat music is enabled without a default or room combat track.",
            "Set Combat track in Game Settings > Game > Combat music, or add a room combat_music property.")
    end
end

-- Extras relationship gate: startup schemas check shape only (bundled requires);
-- names that point at tracks, endings and achievements are checked here.
local function check_extras(cfg, issue)
    local extras = cfg.extras
    if type(extras) ~= "table" then return end
    local where = {file="developer/config/extras.lua"}
    local tracks = (cfg.music_tracks or {}).tracks or {}
    -- Prepare & Check writes the image table after the first relationship pass,
    -- so images are checked only when the caller passes the generated table.
    local gallery_images = type(cfg.extras_gallery) == "table" and type(cfg.extras_gallery.images) == "table"
        and cfg.extras_gallery.images or nil
    local achievements = type((cfg.achievements or {}).achievements) == "table" and cfg.achievements.achievements or {}
    local endings = {}
    local completion = cfg.game_completion
    if type(completion) == "table" then
        if trim(completion.id) ~= "" then endings[trim(completion.id)] = true end
        for _, ending in ipairs(type(completion.endings) == "table" and completion.endings or {}) do
            if type(ending) == "table" and trim(ending.id) ~= "" then endings[trim(ending.id)] = true end
        end
    end
    local fix = "Correct developer/config/extras.lua, then run Prepare & Check."
    local function unlock(row, path, kind)
        local u = row.unlock
        if type(u) ~= "table" then return end
        local property = path .. ".unlock"
        if u.type == "heard" and kind ~= "jukebox" then
            issue("warning", "extras_heard_outside_jukebox", where, property,
                "Only jukebox tracks can unlock by being heard; this entry never unlocks.",
                "Use another unlock type for gallery entries in developer/config/extras.lua.")
        elseif u.type == "flag" and trim(u.flag) == "" then
            issue("warning", "extras_flag_blank", where, property .. ".flag",
                "This flag unlock names no flag, so the entry never unlocks.", fix)
        elseif u.type == "achievement" and not achievements[trim(u.id)] then
            issue("warning", "extras_unknown_achievement", where, property .. ".id",
                "Achievement '" .. trim(u.id) .. "' is not in developer/config/achievements.lua; this entry never unlocks.", fix)
        elseif u.type == "ending" and trim(u.ending_id) ~= "" and cfg.game_completion and not endings[trim(u.ending_id)] then
            issue("warning", "extras_unknown_ending", where, property .. ".ending_id",
                "Ending '" .. trim(u.ending_id) .. "' is not configured; this entry never unlocks.",
                "Use an ending id from Project > Game Settings... > Ending, or leave ending_id blank for any ending.")
        end
    end
    local function rows(kind, list_key, id_key)
        local section = type(extras[kind]) == "table" and extras[kind] or {}
        local seen = {}
        for i, row in ipairs(type(section[list_key]) == "table" and section[list_key] or {}) do
            if type(row) == "table" then
                local path = kind .. "." .. list_key .. "." .. i
                local id = trim(row[id_key])
                if id ~= "" and seen[id] then
                    issue("warning", "extras_duplicate_id", where, path .. "." .. id_key,
                        "'" .. id .. "' is listed twice in " .. kind .. "; both rows share one unlock and one notice.", fix)
                end
                seen[id] = true
                if trim(row.title) == "" then
                    issue("warning", "extras_blank_title", where, path .. ".title",
                        "This " .. kind .. " entry has no title, so players see a blank row.", fix)
                end
                if kind == "gallery" and gallery_images and trim(row.image) == "" then
                    issue("warning", "extras_image_blank", where, path .. ".image",
                        "This gallery entry names no image, so it can never be shown.",
                        "Set image to a PNG name in developer/assets/extras/ (without .png).")
                elseif kind == "gallery" and gallery_images and not gallery_images[trim(row.image)] then
                    issue("warning", "extras_unknown_image", where, path .. ".image",
                        "Image '" .. trim(row.image) .. "' is not in developer/assets/extras/, so this entry cannot be shown.",
                        "Add " .. trim(row.image) .. ".png to developer/assets/extras/, or correct the name, then run Prepare & Check.")
                end
                if kind == "jukebox" and id ~= "" and not tracks[id] then
                    issue("warning", "extras_unknown_track", where, path .. ".track",
                        "Track '" .. id .. "' is not registered.",
                        "Choose a registered track id, or add its audio file and run Prepare & Check.")
                end
                unlock(row, path, kind)
            end
        end
    end
    rows("jukebox", "tracks", "track")
    rows("gallery", "entries", "id")
end

-- Countdowns (WM09). The startup schema checks countdowns.lua's shape with
-- bundled requires only; names that point at zones, rewards, music and the
-- hazard-return setting are checked here. An unknown zone id is reported by
-- check_catalogs when the countdowns dropdown is loaded, so only once.
local function check_countdowns(index, cfg, issue, ds)
    local config = cfg.countdowns
    if type(config) ~= "table" then return end
    local Rules = require "mvtk.game.countdown_rules"
    local where = {file="developer/config/countdowns.lua"}
    local known = {}
    for _, id in ipairs(Rules.ids(config)) do known[id] = {start=false, finish=false} end
    local catalog_checked = cfg.catalogs and cfg.catalogs.countdowns
    for _, o in ipairs(index.objects or {}) do
        if o.type == "countdown_zone" and o.visible ~= false then
            local p = o.properties or {}
            local id, role = trim(p.countdown_id), trim(p.role)
            if role == "" then role = "start" end
            if id == "" or id == "none" then
                issue("warning", "countdown_zone_blank", o, "countdown_id",
                    "This Countdown Zone names no countdown, so entering it does nothing.",
                    "In Tiled choose a countdown in Countdown id, then File > Export Current Room and run Prepare & Check.")
            elseif known[id] then
                if role == "start" or role == "finish" then known[id][role] = true end
            elseif not catalog_checked then
                issue("error", "countdown_zone_unknown", o, "countdown_id",
                    "Countdown '" .. id .. "' is not in developer/config/countdowns.lua, so this zone does nothing.",
                    "Choose a listed countdown in Countdown id, or add '" .. id .. "' to developer/config/countdowns.lua, then run Prepare & Check.")
            end
        end
    end
    local tracks = cfg.music_tracks and (cfg.music_tracks.tracks or {}) or nil
    for _, id in ipairs(Rules.ids(config)) do
        local spec = Rules.entry(config, id)
        local path = "countdowns." .. id
        local starts = known[id].start or spec.start_when ~= ""
        if not starts then
            issue("info", "countdown_unused", where, path,
                "Countdown '" .. id .. "' has no start_when and no start Countdown Zone, so it never runs.",
                "Place a Countdown Zone with role start that names it, set start_when, or remove the entry.")
        elseif not known[id].finish then
            issue("warning", "countdown_without_finish", where, path,
                "Countdown '" .. id .. "' can start but no Countdown Zone with role finish names it, so it can only time out or be cancelled.",
                "Place a Countdown Zone with role finish that names '" .. id .. "', then export the room and run Prepare & Check.")
        end
        if spec.reward:match("%S") and cfg.grant_env then
            M.check_grant_text(ds, where, path .. ".reward", spec.reward, cfg.grant_env,
                "countdown_reward_invalid", "Correct reward in developer/config/countdowns.lua, then run Prepare & Check.")
        end
        if spec.music ~= "" and tracks and not tracks[spec.music] then
            issue("warning", "countdown_unknown_music", where, path .. ".music",
                "Countdown music '" .. spec.music .. "' is not a registered track, so the room music keeps playing.",
                "Choose a registered track id, or add its audio file and run Prepare & Check.")
        end
        if spec.on_timeout == "return_safe" and cfg.hazard_return_enabled == false then
            issue("warning", "countdown_return_safe_kills", where, path .. ".on_timeout",
                "Countdown '" .. id .. "' returns the player to safety at zero, but hazard returns are off, so it kills instead.",
                "Turn on hazard returns in Game Settings, or set on_timeout to death or restart.")
        end
    end
end

-- World-state presence (G8-09): appear_when / remove_when must parse, and
-- presence_timing names a supported timing. Plain properties on any object.
local function check_presence(index, cfg, issue)
    local Condition = require "mvtk.world.presence_condition"
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        if o.visible ~= false then
            for _, field in ipairs({"appear_when", "remove_when"}) do
                local value = p[field]
                if value ~= nil then
                    local _, err
                    if type(value) ~= "string" then err = "condition must be text"
                    else _, err = Condition.parse(value) end
                    if err then
                        issue("error", "presence_condition_invalid", o, field,
                            "World-state condition '" .. tostring(value) .. "' does not parse: " .. err .. ".",
                            "Use a comma list of flag, !flag, ability:<id> or item:<id>[:count], with | between alternatives; leave blank for none.")
                    end
                end
            end
            local timing = trim(p.presence_timing)
            if timing ~= "" and timing ~= "enter" and timing ~= "live" then
                issue("error", "presence_timing_invalid", o, "presence_timing",
                    "presence_timing '" .. timing .. "' is not enter or live.",
                    "Set presence_timing to enter (the default: change on the next room entry) or live (remove at once).")
            end
        end
    end
    -- World-state tile layers (G8-10): the bake warns and keeps a rejected
    -- layer in the room tilemap; Prepare & Check reports it as an error.
    local maps, rooms = index.normalized_maps or {}, {}
    for room in pairs(maps) do rooms[#rooms + 1] = room end
    table.sort(rooms)
    for _, room in ipairs(rooms) do
        local _, problems = require("hooks.core.tilemap_split").state_layers(maps[room])
        for _, p in ipairs(problems) do
            issue("error", p.code, {room = room, layer = p.layer,
                file = "developer/assets/tiled/maps/" .. tostring(room) .. ".lua"}, p.property, p.message, p.fix)
        end
    end
end

-- Living NPCs (WM12a). A marker NPC needs a conversation that can clear it,
-- and each one carries a world label: labels share the engine's label pool
-- with signs, levers and damage numbers, so many in one room is a warning.
-- Journal > People (WM12c) lists npc_types with a journal block; one that no
-- exported room places can never be met, so it stays ??? for good.
M.LIVING_NPCS_PER_ROOM = 12
-- WM12b: barks, turning and wander. Number fields keep their npc.script
-- ranges; a wander line that leaves the map, or a changed Bark range with no
-- lines to show, is a warning.
local function npc_number(p, key, default)
    local value = p[key]
    if value == nil or value == "" then return default end
    return tonumber(value)
end

local function has_bark_lines(p, preset)
    if tostring(p.barks or ""):gsub("|", ""):match("%S") then return true end
    for _, line in ipairs(type(preset.barks) == "table" and preset.barks or {}) do
        if type(line) == "string" and line:match("%S") then return true end
    end
    return false
end

local function check_npc_motion(o, p, preset, issue)
    local fix = "Correct it in the NPC's Behavior group, then export the room and choose Project > Prepare & Check."
    local range = npc_number(p, "bark_range", 96)
    local cooldown = npc_number(p, "bark_cooldown", 8)
    local width = npc_number(p, "wander_width", 0)
    local speed = npc_number(p, "wander_speed", 30)
    if range == nil or range <= 0 then
        issue("error", "npc_bark_range", o, "bark_range", "Bark range must be a number above 0 pixels.", fix)
    end
    if cooldown == nil or cooldown < 0 then
        issue("error", "npc_bark_cooldown", o, "bark_cooldown", "Bark cooldown must be 0 seconds or more.", fix)
    end
    if width == nil or width < 0 then
        issue("error", "npc_wander_width", o, "wander_width", "Wander width must be 0 pixels or more.", fix)
    end
    if speed == nil or speed <= 0 then
        issue("error", "npc_wander_speed", o, "wander_speed", "Wander speed must be a number above 0 pixels a second.", fix)
    end
    if range and range > 0 and range ~= 96 and not has_bark_lines(p, preset) then
        issue("warning", "barks_no_text", o, "bark_range",
            "This NPC sets a Bark range but has no lines in Barks or in its npc_types.lua type, so it never speaks.",
            "Enter lines separated by | in Behavior > Barks, or reset Bark range, then export the room and choose Project > Prepare & Check.")
    end
    local raw, map = o.raw or {}, o.map or {}
    local map_width = (tonumber(map.width) or 0) * (tonumber(map.tilewidth) or 0)
    local x = tonumber(raw.x)
    if width and width > 0 and x and map_width > 0 then
        local centre = x + (tonumber(raw.width) or 0) / 2
        if centre - width / 2 < 0 or centre + width / 2 > map_width then
            issue("warning", "wander_outside_room", o, "wander_width",
                "This NPC's wander line (" .. tostring(math.floor(width + 0.5)) .. " px centred on it) leaves the room.",
                "Lower Behavior > Wander width or move the NPC, then export the room and choose Project > Prepare & Check.")
        end
    end
end

local function check_npc_behavior(index, cfg, issue)
    local types = type(cfg.npc_types) == "table" and cfg.npc_types or {}
    local per_room, rooms, placed = {}, {}, {}
    for _, o in ipairs(index.objects or {}) do
        local p = o.properties or {}
        if o.visible ~= false and o.type == "npc" then
            placed[trim(p.npc_type)] = true
            local preset = type(types[trim(p.npc_type)]) == "table" and types[trim(p.npc_type)] or {}
            local marker = p.show_new_dialogue_marker == true or p.show_new_dialogue_marker == "true"
                or preset.show_new_dialogue_marker == true
            if marker then
                local has_dialogue = trim(p.dialogue_id) ~= "" or trim(p.dialogue_text) ~= ""
                    or trim(preset.dialogue_id) ~= ""
                if not has_dialogue then
                    issue("warning", "marker_no_dialogue", o, "show_new_dialogue_marker",
                        "This NPC shows the new-dialogue marker but has no dialogue, so the marker never appears.",
                        "Set Dialogue > dialogue_id or dialogue_text, or untick Behavior > Show new dialogue marker, then export the room and choose Project > Prepare & Check.")
                end
            end
            check_npc_motion(o, p, preset, issue)
            -- Marker and bark NPCs each carry one world label (npc_living.go).
            if marker or has_bark_lines(p, preset) then
                local room = tostring(o.room or "")
                if not per_room[room] then per_room[room] = {count = 0, first = o}; rooms[#rooms + 1] = room end
                per_room[room].count = per_room[room].count + 1
            end
        end
    end
    table.sort(rooms)
    for _, room in ipairs(rooms) do
        local entry = per_room[room]
        if entry.count > M.LIVING_NPCS_PER_ROOM then
            issue("warning", "npc_living_many", entry.first, "show_new_dialogue_marker",
                "Room '" .. room .. "' has " .. tostring(entry.count) .. " NPCs with the new-dialogue marker or barks; more than "
                    .. tostring(M.LIVING_NPCS_PER_ROOM) .. " can use up the shared world label pool.",
                "Untick Behavior > Show new dialogue marker or clear Behavior > Barks on some NPCs in this room, then export the room and choose Project > Prepare & Check.")
        end
    end
    local journal_types = {}
    for id, def in pairs(types) do
        if type(id) == "string" and type(def) == "table" and type(def.journal) == "table" then journal_types[#journal_types + 1] = id end
    end
    table.sort(journal_types)
    for _, id in ipairs(journal_types) do
        if not placed[id] then
            issue("warning", "people_unplaced", {file = "developer/config/npc_types.lua"}, id .. ".journal",
                "NPC type '" .. id .. "' has a journal block, but no exported room places an NPC of that type, so Journal > People can never list them as met.",
                "Place an NPC with npc_type " .. id .. " in a room and choose File > Export Current Room in Tiled, or remove the journal block, then choose Project > Prepare & Check.")
        end
    end
end

local function check_fragments(index, cfg, issue)
    if not cfg.fragments then return end
    local sets, counts, locations = cfg.fragments.sets or {}, {}, {}
    -- Definitions can be used only by grants, so validate them even without a placement.
    local types, type_ids = cfg.collectible_types or {}, {}
    for id in pairs(types) do type_ids[#type_ids+1] = id end
    table.sort(type_ids)
    for _, id in ipairs(type_ids) do
        local def = types[id]
        if type(def) == "table" and def.on_collect == "add_fragment" and not sets[def.fragment_set] then
            issue("error", "fragment_set_unknown", {file="developer/config/collectible_types.lua"}, id..".fragment_set",
                "This Collectible type names an unknown fragment set.",
                "Set fragment_set to a key in developer/config/fragments.lua, then run Prepare & Check.")
        end
    end
    for _, o in ipairs(index.objects or {}) do
        if o.visible ~= false and o.type == "collectible"
            and (not cfg.published_rooms or cfg.published_rooms[o.room]) then
            local def = (cfg.collectible_types or {})[trim((o.properties or {}).collectible_type)] or {}
            if def.on_collect == "add_fragment" then
                local id, set = def.fragment_set, sets[def.fragment_set]
                if set then
                    counts[id], locations[id] = (counts[id] or 0) + 1, o
                    if set.upgrade == "heal_charges" and (cfg.healing or {}).model ~= "flask" then
                        issue("warning", "fragment_heal_not_flask", o, "collectible_type", "Flask fragments need the flask healing model.",
                            "Choose flask in Project > Game Settings... > Player > Healing, or remove the fragment.")
                    end
                end
            end
        end
    end
    local ids = {}; for id in pairs(counts) do ids[#ids+1] = id end; table.sort(ids)
    for _, id in ipairs(ids) do
        local pieces = tonumber(sets[id].pieces)
        if pieces and pieces > 0 and counts[id] % pieces ~= 0 then
            issue("info", "fragment_set_remainder", locations[id], "collectible_type",
                "Placed fragments do not make whole containers across the published rooms; reward fragments are not counted.",
                "Adjust placed pieces or the fragment count in Project > Game Settings... > Player > Health and resources.")
        end
    end
end

-- Trial rules inspect the same normalized room-local links as the baker.
local function check_combat_trials(index, cfg, ds, issue)
    local trials = {}
    for _, o in ipairs(index.objects or {}) do
        if o.type == "combat_trial" and o.visible ~= false and o.top_level ~= false then trials[#trials+1] = o end
    end
    if #trials == 0 then return end
    local Links = require "mvtk.tiled.encounter_links"
    local Flatten = require "mvtk.tiled.property_flattener"
    local player = require("mvtk.player.player_scale").apply(cfg.player or {})
    local hw, hh = player.collider_half_width or 0, player.collider_half_height or 0
    local ids = {}
    for _, o in ipairs(trials) do
        local p, map = o.properties or {}, o.map or (index.normalized_maps or {})[o.room] or {}
        local trial = trim(p.trial_id)
        if trial == "" then trial = o.instance_id end
        local label = "Room " .. tostring(o.room) .. ", trial " .. tostring(trial) .. " (object " .. tostring(o.object_id) .. "): "
        local function report(severity, code, field, message, fix)
            issue(severity, "combat_trial_" .. code, o, field, label .. message .. " Run Prepare & Check after correcting it.",
                fix .. " Export Current Room in Tiled, then run Project > Prepare & Check.")
        end
        local Limits = require "mvtk.game.trial_limits"
        for _, id in ipairs(Limits.ids(p.disabled_abilities)) do
            if not Limits.abilities[id] then
                report("info", "limit_passive", "disabled_abilities", "Ability " .. id .. " uses unlock-only or passive checks and cannot be disabled by a trial.",
                    "Remove it from limits > disabled_abilities; select an ability with a use check.")
            end
        end
        for _, tag in ipairs(Limits.ids(p.disabled_attacks)) do
            if not Limits.attacks[tag] then
                report("info", "limit_unsupported", "disabled_attacks", "Attack tag " .. tag .. " does not run through the attack executor.",
                    "Remove it from limits > disabled_attacks; use limits > disabled_abilities for supported movement abilities.")
            end
        end
        if ids[trial] then
            report("error", "duplicate_id", "trial_id", "This trial id is also used in room " .. tostring(ids[trial].room)
                .. " by object " .. tostring(ids[trial].object_id) .. ".", "Give each Combat Trial a permanent unique trial_id.")
        else ids[trial] = o end
        local encounters, spawns = Links.collect(map)
        local linked = Links.resolve(o.room, o.raw or o, encounters)
        local encounter
        for _, raw in ipairs(encounters) do if Links.id(o.room, raw) == linked then encounter = raw; break end end
        if encounter then
            local ep = Flatten.flatten(encounter.properties or {})
            if (ep.encounter_start or "on_enter") ~= "on_signal" then
                report("error", "encounter_not_signal", "encounter_ref", "The linked Encounter does not start on signal.",
                    "Set the linked Encounter's start > encounter_start to on_signal.")
            end
            if ep.repeatable ~= true then
                report("error", "encounter_not_repeatable", "encounter_ref", "The linked Encounter is not repeatable.",
                    "Tick rewards > repeatable on the linked Encounter.")
            end
            if trim(ep.reward_collectible) ~= "" and trim(ep.reward_collectible) ~= "none" then
                report("warning", "encounter_reward", "encounter_ref", "The repeatable Encounter grants its collectible reward on every clear.",
                    "Clear rewards > reward_collectible on the Encounter and use the trial's rewards > trial_reward for a first-clear reward.")
            end
            if ep.enemy_drops == true then
                report("warning", "enemy_drops", "encounter_ref", "The linked Encounter allows enemy drops on every attempt.",
                    "Untick flow > enemy_drops on the linked Encounter to avoid repeatable loot.")
            end
            if p.trial_goal == "defeat_count" then
                local total = 0
                for _, spawn in ipairs(spawns) do
                    if Links.resolve(o.room, spawn, encounters) == linked then
                        total = total + math.max(0, math.floor(tonumber(Flatten.flatten(spawn.properties or {}).spawn_count) or 1))
                    end
                end
                if (tonumber(p.defeat_target) or 10) > total then
                    report("error", "target_unreachable", "defeat_target", "The defeat target exceeds the linked Encounter's scheduled total of " .. total .. ".",
                        "Lower goal > defeat_target or add linked Encounter Spawn counts.")
                end
            end
        end
        if p.trial_goal == "survive" and (tonumber(p.time_limit) or 0) <= 0 then
            report("error", "survive_no_limit", "time_limit", "A survive goal needs a positive time limit.", "Set goal > time_limit above 0.")
        end
        local previous
        for i=1,3 do
            local threshold = tonumber(p["rank_" .. i]) or -1
            if threshold >= 0 then
                if previous and threshold < previous then
                    report("warning", "ranks_order", "rank_" .. i, "Enabled rank thresholds are out of order; lower times or hit counts are better.",
                        "Set ranks > rank_1, rank_2 and rank_3 in increasing order, using -1 for unused ranks.")
                    break
                end
                previous = threshold
            end
        end
        local first = #ds + 1
        if p.trial_reward ~= nil and (type(p.trial_reward) ~= "string" or trim(p.trial_reward) ~= "") then
            M.check_grant_text(ds, o, "trial_reward", p.trial_reward, cfg.grant_env, "combat_trial_reward_invalid",
                "Correct rewards > trial_reward using grant text. Export Current Room in Tiled, then run Project > Prepare & Check.")
        end
        for i=first,#ds do
            ds[i].severity = "error"
            ds[i].message = label .. ds[i].message .. " Correct trial_reward, then run Prepare & Check."
        end
        local boss, exit = false, false
        for _, other in ipairs((index.by_room or {})[o.room] or index.objects or {}) do
            if other.room == o.room and other.visible ~= false and other.top_level ~= false then
                local kind, props = other.type, other.properties or {}
                boss = boss or kind == "boss" or kind == "boss_arena" or (kind == "enemy" and props.champion == true)
                exit = exit or kind == "teleporter" or kind == "elevator" or kind == "elevator_cabin"
            end
        end
        if boss then
            report("warning", "in_boss_room", "encounter_ref", "A boss, boss arena or champion shares this room and can interfere with the trial.",
                "Use a separate room for the trial or combat-playtest their interaction without entering a boss arena during the trial.")
        end
        if exit then
            report("info", "room_exit", "encounter_ref", "A teleporter or elevator can carry the player out and abandon the trial.",
                "Move the exit to another room or playtest leaving during the trial.")
        end
        -- A pedestal anchor is only a proximity hint; runtime tests the player's
        -- actual collider against door spans. Do not treat ordinary floor as a door.
        local raw, near = o.raw or o, false
        local x, y = tonumber(raw.x) or 0, tonumber(raw.y) or 0
        local tw, th = tonumber(map.tilewidth) or 64, tonumber(map.tileheight) or 64
        local function walk(layers, ox, oy)
            for _, layer in ipairs(layers or {}) do
                local lx, ly = ox + (layer.offsetx or 0), oy + (layer.offsety or 0)
                if layer.visible ~= false then
                    local name = tostring(layer.name or ""):lower():gsub("[%s%-]+", "_"):gsub("__+", "_")
                    if layer.type == "tilelayer" and (name == "door" or name == "doors"
                        or name:match("^doors?_[lrud]$")
                        or name:match("^doors?_left$") or name:match("^doors?_right$")
                        or name:match("^doors?_top$") or name:match("^doors?_bottom$")
                        or name:match("^doors?_up$") or name:match("^doors?_down$")
                        or name:match("^left_doors?$") or name:match("^right_doors?$")
                        or name:match("^up_doors?$") or name:match("^down_doors?$")) then
                        local chunks = layer.chunks or {{x=layer.x or 0,y=layer.y or 0,width=layer.width or map.width,data=layer.data}}
                        for _, chunk in ipairs(chunks) do
                            for i, tile in ipairs(chunk.data or {}) do
                                if tonumber(tile) and tonumber(tile) ~= 0 and (chunk.width or 0) > 0 then
                                    local tx = lx + ((chunk.x or 0) + (i-1) % chunk.width) * tw
                                    local ty = ly + ((chunk.y or 0) + math.floor((i-1) / chunk.width)) * th
                                    if x+hw >= tx and x-hw <= tx+tw and y+hh >= ty and y-hh <= ty+th then near = true end
                                end
                            end
                        end
                    end
                    walk(layer.layers, lx, ly)
                end
            end
        end
        walk(map.layers, 0, 0)
        if near then
            report("warning", "near_door", "encounter_ref", "The pedestal is near a painted doorway; starting is refused until the player's body clears it.",
                "Move the Combat Trial farther from the doorway and leave space for the player collider.")
        end
    end
end

-- LuaJ ignores floating-point format precision: round first, then print integers.
local function player_size_number(value, factor)
    local rounded = math.floor(value * factor + 0.5)
    local whole, fraction = math.floor(rounded / factor), rounded % factor
    if fraction == 0 then return string.format("%d", whole) end
    local tail = factor == 100 and string.format("%02d", fraction) or string.format("%d", fraction)
    return string.format("%d", whole) .. "." .. tail:gsub("0+$", "")
end

local function check_player_size(cfg, issue)
    local limits = (cfg.world_lint or {}).player_size
    local tile_height = tonumber((cfg.tile_settings or {}).height or (cfg.tile_settings or {}).tile_height)
    if not limits or not cfg.player or not tile_height or tile_height <= 0 then return end
    -- Match runtime_settings.get_player_settings and the standing-box baker:
    -- the manifest records previous bake geometry, not a second scale factor.
    local player = require("mvtk.player.player_scale").apply(cfg.player)
    local half_height = tonumber(player.collider_half_height)
    if not half_height or half_height <= 0 then return end
    local pixels = half_height * 2
    local tiles = pixels / tile_height
    if tiles >= limits.min_height_tiles and tiles <= limits.max_height_tiles then return end
    local field = require("mvtk.core.creator_settings_model").fields.player_scale
    local target = player.player_scale * limits.target_height_tiles / tiles
    -- Floor to the field step so the suggestion stays at or below the target.
    -- The minimum itself is 1/7; use the first in-range step for plain decimals.
    local suggestion = math.max(math.ceil(field.min / field.step),
        math.min(math.floor(field.max / field.step), math.floor(target / field.step))) * field.step
    issue("warning", "player_size_out_of_proportion", {file="developer/config/player_settings.lua"}, "player_scale",
        "Your player is " .. player_size_number(tiles, 10) .. " tiles tall ("
            .. player_size_number(pixels, 10) .. " px on " .. player_size_number(tile_height, 10)
            .. " px tiles). If that is not what you want, open Project ▸ Game Settings… ▸ Player"
            .. " and set Player size to about " .. player_size_number(suggestion, 100) .. ".")
end

function M.validate(index, cfg)
    cfg = cfg or {}
    local ds = {}
    local function issue(severity, code, o, property, message, fix)
        ds[#ds + 1] = { severity = severity, code = code, message = message, fix = fix,
            file = o and o.file, room = o and o.room, layer = o and o.layer,
            object_id = o and o.object_id, property = property }
    end
    require("developer.tools.pickup_art_checks").validate(cfg.pickup_index or index, cfg, issue)
    check_player_size(cfg, issue)
    require("developer.tools.economy_checks").validate(index, cfg, ds, issue, M.check_grant_text)
    require("developer.tools.template_preset_checks").validate(index, cfg, issue)
    check_combat_trials(index, cfg, ds, issue)
    check_countdowns(index, cfg, issue, ds)
    check_fragments(index, cfg, issue)
    check_combat_music(index, cfg, issue)
    check_extras(cfg, issue)
    check_arena_phase_hazards(cfg, issue)
    check_map_icons(index, cfg, issue)
    check_presence(index, cfg, issue)
    check_npc_behavior(index, cfg, issue)
    local creator = cfg.creator_settings or {}
    if cfg.accessibility then
        local Model = require "mvtk.core.creator_settings_model"
        local effective = Model.merge(Model.copy(cfg.accessibility), creator.published and (creator.overrides or {}).accessibility or {})
        local assist = effective.assist or {}
        if assist.block_achievements and not assist.record_use then
            issue("warning", "assist_block_without_record", {file="developer/config/accessibility.lua"}, "assist.block_achievements",
                "No achievements on saves that used assist requires Record assist use.",
                "Tick Record assist use in Project > Game Settings... > Accessibility > Assist, or untick the achievement restriction.")
        end
    end
    if cfg.default_bindings then
        -- The relationship gate supplies fresh authored tables; startup schemas
        -- validate bundled modules instead of opening project files.
        local ok, problems = pcall(function()
            local Rules = require "mvtk.core.input_binding_rules"
            local merged, errors = Rules.apply_creator(cfg.default_bindings,
                (creator.overrides or {}).default_bindings, require "mvtk.rooms.input_actions")
            for _, problem in ipairs(Rules.validate(merged)) do errors[#errors + 1] = problem end
            return errors
        end)
        if not ok then problems = {tostring(problems)} end
        for _, problem in ipairs(problems) do
            issue("error", "creator_bindings_invalid", {file="developer/config/default_bindings.lua"},
                "default_bindings", problem,
                "Correct default_bindings.lua or Controls in Game Settings, then run Prepare & Check.")
        end
    end
    local max_energy = tonumber(cfg.max_energy)
    local healing = cfg.healing or {}
    if healing.model == "channel" then
        local where = {file="developer/config/healing.lua"}
        if max_energy == 0 then
            issue("error", "channel_heal_energy_off", where, "model",
                "Channel healing cannot work while Max energy is 0.",
                "Raise Max energy in Project > Game Settings... > Player > Health and resources, or change Healing under Player > Healing.")
        end
        if max_energy and (tonumber((healing.channel or {}).cost) or 0) > max_energy then
            issue("warning", "channel_heal_unaffordable", where, "channel.cost",
                "Energy per heal is above Max energy; a channel heal cannot be paid until an Energy Container raises the maximum.",
                "Lower Energy per heal under Player > Healing, or raise Max energy under Player > Health and resources in Project > Game Settings....")
        end
        if not (healing.energy or {}).enabled then
            issue("info", "channel_heal_no_combat_energy", where, "energy.enabled",
                "Channel healing gains energy only from pickups, energy stations and save points while Gain energy from combat is off.",
                "Enable Gain energy from combat in Project > Game Settings... > Combat > Resource gain to refill through combat.")
        end
    end
    local attack_ids = {}
    for id in pairs(cfg.combat_attacks or {}) do attack_ids[#attack_ids + 1] = id end
    table.sort(attack_ids)
    for _, id in ipairs(attack_ids) do
        local cost = tonumber(cfg.combat_attacks[id].energy_cost) or 0
        if max_energy and cost > max_energy then
            issue("warning", "attack_energy_cost", {file="developer/config/combat_config.lua"}, "attacks." .. id .. ".energy_cost",
                max_energy == 0 and ("Attack '" .. id .. "' has an energy cost that is ignored while Max energy is 0.")
                    or ("Attack '" .. id .. "' costs " .. tostring(cost) .. " energy, above Max energy " .. tostring(max_energy) .. "; it cannot be used until an Energy Container raises the maximum."),
                "Lower energy_cost in developer/config/combat_config.lua, or raise Max energy in Project > Game Settings... > Player > Health and resources.")
        end
    end
    local default = ((creator.overrides or {}).enemy_defaults or {}).default_archetype
    if creator.published == true and default ~= nil and cfg.enemy_types
        and type(cfg.enemy_types[default]) ~= "table" then
        issue("warning", "enemy_default_archetype_unknown", {file="developer/config/creator_settings.lua"},
            "enemy_defaults.default_archetype",
            "Published default enemy archetype '" .. tostring(default) .. "' is no longer in developer/config/enemy_types.lua; art-only enemies use the runtime fallback.",
            "Open Project > Game Settings > Enemies and elements, choose a listed Default archetype for art-only enemies, then choose Save and Prepare & Check and Build.")
    end
    for _, object in ipairs((index or {}).objects or {}) do
        if object.type == "enemy" and object.visible ~= false then
            local props = require("mvtk.enemies.enemy_overrides").flatten_tiled_properties(object.properties or {})
            if props.champion == true then
                if type(props.champion_name) ~= "string" or not props.champion_name:match("%S") then
                    issue("info", "champion_name_blank", object, "champion_name",
                        "This champion's health bar shows the fallback name Champion.",
                        "Set Rank > Champion name to the name players should see.")
                end
                if type(props.defeat_flag) ~= "string" or not props.defeat_flag:match("%S") then
                    issue("info", "champion_without_defeat_flag", object, "defeat_flag",
                        "This champion has no Defeat flag for gates; its generated persist key still keeps it gone when Respawn is inherited or never.",
                        "Set On defeat > Defeat flag to a stable flag if its defeat should open gates.")
                end
                for _, boss in ipairs((index or {}).objects or {}) do
                    if boss.room == object.room and (boss.type == "boss" or boss.type == "boss_arena")
                        and boss.visible ~= false and boss.top_level ~= false then
                        issue("info", "champion_in_boss_room", object, "champion_bar",
                            "This champion shares a room with a boss; the boss health bar takes priority.",
                            "Playtest both fights together, or place the champion in another room.")
                        break
                    end
                end
                if type(props.champion_reward) == "string" and props.champion_reward:match("%S") then
                    M.check_grant_text(ds, object, "champion_reward", props.champion_reward,
                        cfg.grant_env, "champion_reward_invalid")
                end
                if not require("mvtk.enemies.enemy_respawn_policy").is_inherit(props.respawn)
                    and props.respawn ~= "never" then
                    issue("info", "champion_respawn_overridden", object, "respawn",
                        "This champion can return and seal its room again; its reward is granted only once.",
                        "Set On defeat > Respawn to type_default or never to keep this champion defeated.")
                end
            end
            local side = props.cling_side
            if side and side ~= "" and side ~= "type_default" then
                local preset = (cfg.enemy_types or {})[props.archetype] or (cfg.enemy_types or {})[props.enemy_type] or {}
                local movement = props.movement
                if movement == nil or movement == "" or movement == "type_default" or movement == "none" then
                    movement = preset.movement or preset.behavior
                end
                local resolved = require("mvtk.enemies.enemy_behavior_resolver").resolve({movement=movement,behavior=preset.behavior})
                if resolved.movement ~= "surface_crawl" then
                    issue("info","cling_side_unused",object,"cling_side",
                        "Cling side is set on an enemy that does not crawl.",
                        "Choose surface_crawl for Movement, or restore Cling side to type_default.")
                end
            end
        end
    end
    for _, object in ipairs((index or {}).objects or {}) do
        if object.visible ~= false and object.top_level ~= false and object.type == "collectible" then
            local entry = (cfg.collectible_types or {})[(object.properties or {}).collectible_type]
            if entry and entry.on_collect == "grant_unique_item" and entry.unique_owner == "weapons"
                and not (cfg.weapons or {}).enabled then
                issue("warning", "weapon_pickup_while_off", object, "collectible_type",
                    "This weapon stays in place while Weapons is off.",
                    "Enable Weapons in Game Settings > Equipment > Weapons, then Save and Prepare & Check.")
            end
            if entry and entry.on_collect == "grant_unique_item" and entry.unique_owner == "charms"
                and not (cfg.charms or {}).enabled then
                issue("warning", "charm_pickup_while_off", object, "collectible_type",
                    "This charm stays in place while Charms is off.",
                    "Enable Charms in Game Settings > Equipment > Charms, then Save and Prepare & Check.")
            end
            if entry and entry.on_collect == "apply_powerup" and not (cfg.powerups or {}).enabled then
                issue("warning", "powerup_pickup_while_off", object, "collectible_type",
                    "This power-up stays in place while Power-ups is off.",
                    "Enable Power-ups in Game Settings > Equipment > Power-ups, then Save and Prepare & Check.")
            end
        end
    end
    local random = cfg.random_drops or {}
    if random.enabled then
        local possible = false
        for _, family in ipairs({{on=random.weapons and (cfg.weapons or {}).enabled,
            entries=(cfg.weapons or {}).weapons, starter=(cfg.weapons or {}).starting_weapon},
            {on=random.charms and (cfg.charms or {}).enabled, entries=(cfg.charms or {}).charms},
            {on=random.upgrades, entries=(cfg.upgrades or {}).upgrades}}) do
            if family.on then
                for id, entry in pairs(family.entries or {}) do
                    if type(entry) == "table" and entry.random_drop ~= false
                        and (family.starter == nil or entry.id ~= family.starter) then
                        possible = true
                    end
                end
            end
        end
        if not possible then
            issue("warning", "random_drops_empty_pool", {file="developer/config/random_drops.lua"}, "enabled",
                "Random drops is on, but no enabled family has an eligible catalog entry.",
                "Enable a family in Game Settings > Equipment > Random drops or allow an entry with random_drop, then Save and Prepare & Check.")
        end
    end
    check_bestiary(cfg,issue)
    check_enemy_loot_tables(index or {},cfg,issue)
    check_enemy_respawn(index or {},cfg,issue)
    check_enemy_defense(index or {},cfg,issue)
    check_projectile_counterplay(index or {},cfg,issue)
    if cfg.catalogs then check_catalogs(index or {}, cfg, issue) end
    check_region_unused(index or {}, cfg, issue)
    check_vehicles(index or {}, issue)
    check_water_levels(index or {}, issue)
    check_air_pockets(index or {}, issue)
    check_grouped_and_water_enemies(index or {}, cfg, issue)
    check_breakable_props(index or {}, cfg, issue)
    check_zip_line_clearance(index or {}, cfg, issue)
    check_climb_rectangles(index or {}, cfg, issue)
    check_launch_pads(index or {}, issue)
    check_launch_cannons(index or {}, issue)
    for _, o in ipairs((index or {}).objects or {}) do
        if o.visible ~= false and o.type == "carryable" then
            local p = o.properties or {}
            local speed = tonumber(p.move_speed_mult) or 0.8
            if speed ~= speed or speed < 0.25 or speed > 1 then
                issue("error", "carry_speed_range", o, "move_speed_mult",
                    "Carry speed multiplier must be in [0.25, 1].", "Set Move speed mult under Handling between 0.25 and 1.")
            elseif p.blocks_jump == true and speed == 1 then
                issue("info", "carry_heavy_full_speed", o, "blocks_jump",
                    "This object blocks Jump without slowing movement.", "Keep this intentional combination or lower Move speed mult.")
            end
            for _, key in ipairs({"throw_speed", "break_speed", "fuse_time"}) do
                local v = p[key]
                if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0 or v == math.huge) then
                    issue("error", "carry_motion_range", o, key, "Carry motion and fuse values must be finite and nonnegative.", "Use world pixels/second or fuse seconds.")
                end
            end
        end
    end
    check_positional_ambience(index or {}, cfg, issue)
    check_hazard_immunities(cfg, issue)
    check_hazard_returns(index or {}, cfg, issue)
    check_boss_summons(index or {}, cfg, issue)
    check_boss_groups(index or {}, cfg, issue)
    check_sequence_gates(index or {}, cfg, issue)
    check_ability_barriers(index or {}, cfg, issue)
    check_intangible_barriers(index or {}, cfg, issue)
    check_gate_groups(index or {}, issue)
    if cfg.cutscene_settings then
        local settings = cfg.cutscene_settings
        local Ids = require "mvtk.game.cutscene_ids"
        local Policy = require "mvtk.game.cutscene_policy"
        for _, warning in ipairs(require("mvtk.game.video_variants").validate(cfg.videos, cfg.languages)) do
            issue("warning", warning.code, {file="developer/config/narrative/videos.lua"}, warning.property,
                warning.message, warning.fix)
        end
        local clip_ids = {}; for id in pairs(cfg.videos or {}) do clip_ids[#clip_ids + 1] = id end
        table.sort(clip_ids)
        for _, id in ipairs(clip_ids) do
            local clip = cfg.videos[id]
            if type(clip) == "table" and trim(clip.fallback_title) == "" and trim(clip.fallback_caption) == "" then
                issue("info", "video_fallback_blank", {file="developer/config/narrative/videos.lua"}, id,
                    "Video clip '" .. id .. "' has no fallback text; nothing plays where video is unavailable.",
                    "Add fallback_title or fallback_caption to show a creator card instead.")
            end
        end
        local where = {file="developer/config/narrative/cutscene_settings.lua"}
        local opening = trim(settings.opening)
        if opening ~= "" and cfg.cutscenes and not Ids.known(opening, cfg.cutscenes, (index.definitions or {}).cutscene) then
            issue("warning", "unknown_cutscene_opening", where, "opening", "Unknown opening cutscene '"..opening.."'.", "Choose a configured or Tiled-generated scene id.")
        end
        local action = settings.skip_action
        if cfg.default_bindings and not (cfg.default_bindings.actions or {})[action] then
            issue("warning", "unknown_cutscene_skip_action", where, "skip_action", "Unknown skip action '"..tostring(action).."'.", "Choose an action from default_bindings.lua.")
        elseif action == "PAUSE_TOGGLE" or action == "SETTINGS_TOGGLE" then
            issue("warning", "cutscene_skip_menu_action", where, "skip_action", "Menu toggles cannot serve as the skip action.", "Choose a gameplay action.")
        end
        local scenes = {}
        for id,scene in pairs(cfg.cutscenes or {}) do scenes[id]={scene=scene,where={file="developer/config/narrative/cutscenes.lua"}} end
        for _,o in ipairs(index.objects or {}) do
            local p=o.properties or {}
            if o.visible ~= false and o.type=="cutscene" and Ids.generates(p) then
                scenes[Ids.resolve(p,o.room,o.object_id)]={where=o,scene={{type="dialogue",id=trim(p.cutscene_dialogue_id) ~= "" and trim(p.cutscene_dialogue_id) or trim(p.dialogue_id)}}}
            end
        end
        local ids={}; for id in pairs(scenes) do ids[#ids+1]=id end; table.sort(ids)
        for _,id in ipairs(ids) do
            local entry=scenes[id]
            for i,step in ipairs(Policy.steps(entry.scene)) do
                local kind = step.type
                if kind == "caption" then
                    if trim(step.text) == "" then
                        issue("warning", "caption_step_empty", entry.where, "steps."..i..".text",
                            "Cutscene '"..id.."' has an empty caption step.", "Write caption text or remove the step.")
                    end
                elseif kind ~= "fade" and kind ~= "wait" and kind ~= "dialogue" and kind ~= "video" and kind ~= "message" then
                    issue("warning", "unknown_cutscene_step", entry.where, "steps."..i..".type",
                        "Cutscene '"..id.."' has unknown step type '"..tostring(kind).."'.",
                        "Use fade, wait, dialogue, video, caption or message.")
                end
            end
            if Policy.dialogue_outcomes(entry.scene,cfg.dialogues) then
                issue("info", "cutscene_dialogue_unskippable", entry.where, "skippable", "Cutscene '"..id.."' cannot be skipped: its dialogue sets flags or offers choices.", "Keep the outcomes in dialogue; the scene will play in full.")
            end
        end
    end

    if cfg.movement_zone_types then
        for _, err in ipairs(require("mvtk.core.config_schemas").movement_zone_types.custom_validate(cfg.movement_zone_types)) do
            issue("error", "movement_zone_range", {file = "developer/config/movement_zone_types.lua"}, "preset", err,
                "Use the documented movement multiplier floors and ranges.")
        end
    end
    local objects = (index and index.objects) or {}
    local arenas_by_room = {}
    local has_energy_container = false
    local function container_resource(o)
        if o.type ~= "collectible" then return nil end
        local preset = (cfg.collectible_types or {})[trim((o.properties or {}).collectible_type)]
        if type(preset) ~= "table" then return nil end
        if preset.on_collect == "add_fragment" then
            local set = ((cfg.fragments or {}).sets or {})[preset.fragment_set] or {}
            if set.upgrade == "max_energy" then return "energy" end
            if set.upgrade == "max_stamina" then return "stamina" end
        end
        if preset.on_collect == "increase_max_energy" then return "energy" end
        if preset.on_collect == "increase_max_stamina" then return "stamina" end
    end
    for _, o in ipairs(objects) do
        if o.visible ~= false and o.type == "boss_arena" and o.room then arenas_by_room[o.room] = true end
        if o.visible ~= false and container_resource(o) == "energy" then has_energy_container = true end
    end

    local registered
    if type(cfg.chest_inline) == "table" then
        registered = {}
        for _, value in ipairs(cfg.chest_inline) do registered[trim(value)] = true end
    end

    for _, o in ipairs(objects) do
        local p = o.properties or {}
        if o.visible ~= false then
            if o.type == "movement_zone" then
                local schema = require("mvtk.core.config_schemas").movement_zone_types
                local preset = (cfg.movement_zone_types or {})[p.preset or "low_gravity"] or {}
                local overrides = {}
                for _, key in ipairs({"gravity_mult", "max_fall_mult", "speed_mult", "jump_mult", "sink_speed"}) do
                    if p[key] ~= nil and p[key] ~= -1 then overrides[key] = p[key] end
                end
                for _, values in ipairs({preset, overrides}) do
                    for _, err in ipairs(schema.custom_validate({zone = values})) do
                        issue("error", "movement_zone_range", o, "preset", err,
                            "Use movement_zone_types.lua ranges; -1 inherits the preset in Tiled.")
                    end
                end
            end
            if o.type == "ice_floor" then
                local preset = p.preset or "ice"
                if not ((cfg.player or {}).surfaces or {})[preset] then
                    issue("warning", "unknown_floor_surface_preset", o, "preset",
                        "Unknown floor surface preset '" .. tostring(preset) .. "'.",
                        "Choose a key from player_settings.lua surfaces; wall ice presets are separate.")
                end
            end
            if o.type == "wind_current" then
                if p.wind_mode == "lift" then
                    if p.direction == "left" or p.direction == "right" then
                        issue("warning", "wind_lift_direction", o, "direction",
                            "Lift currents need an up or down direction.", "Set Direction to up or down in Tiled.")
                    end
                    if (tonumber(p.lift_gravity_multiple) or 1.6) <= 1 then
                        issue("warning", "wind_lift_too_weak", o, "lift_gravity_multiple",
                            "This current cannot lift against gravity.", "Set Lift gravity multiple above 1 in Tiled.")
                    end
                elseif (tonumber(p.push_speed) or 300) <= 0 then
                    issue("warning", "wind_push_speed", o, "push_speed",
                        "Push speed must be positive to move the player.", "Set Push speed above 0 in Tiled.")
                end
            end
            if o.type == "wall_jump_surface" and require("mvtk.world.wall_surfaces").is_legacy(p.mvtk_template_version) then
                issue("info", "wall_surface_legacy", o, "mvtk_template_version",
                    "Wall Jump Surface '" .. tostring(p.surface_id or o.name or o.object_id)
                        .. "' inherits player movement; re-export to apply its fields.",
                    "In Tiled choose File > Export All Maps and Tiled World, then Project > Prepare & Check in Defold.")
            end
            local model = (cfg.healing or {}).model
            local collectible = trim(p.collectible_type)
            if o.type == "collectible" and collectible == "heal_charge_upgrade" and model and model ~= "flask" then
                issue("warning", "flask_upgrade_without_flask", o, "collectible_type",
                    "This flask upgrade has no effect with the selected healing model.",
                    "Choose flask in Project > Game Settings... > Player > Healing, or remove the upgrade.")
            end
            if model == "items" and ((o.type == "collectible" and collectible == "ability_healing")
                or (o.type == "ability" and trim(p.ability_id) == "healing")) then
                issue("warning", "healing_pickup_items_only", o, o.type == "ability" and "ability_id" or "collectible_type",
                    "The Healing ability has no effect in items-only healing.",
                    "Choose flask in Project > Game Settings... > Player > Healing, or remove the pickup.")
            end
            if o.type == "lore_item" then
                -- Match the baker's Lua truthiness: an explicitly empty id or
                -- name prevents its generated fallback and never persists.
                local id = p.lore_id or o.name or ("lore_" .. tostring(o.room) .. "_" .. tostring(o.object_id))
                if id == "" then
                    issue("warning", "lore_id_blank", o, "lore_id",
                        "This lore id is blank, so reading it cannot persist or count toward completion.",
                        "Set lore_id in Tiled, then File > Export Current Room and Project > Prepare & Check.")
                end
            elseif o.type == "ability" then
                local id = trim(p.ability_id)
                if id ~= "" and cfg.abilities and cfg.abilities[id] == true then
                    issue("warning", "ability_pickup_starts_unlocked", o, "ability_id",
                        string.format("'%s' starts unlocked, so this pickup removes itself on a new game.", id),
                        "Untick it under Project > Game Settings... > Abilities, Save, Build, then start a New Game; or remove the pickup.")
                end
            elseif o.type == "boss" then
                if trim(p.arena_id) == "" and not arenas_by_room[o.room] then
                    issue("info", "boss_without_arena", o, "arena_id",
                        "Boss has no boss_arena, so the fight starts when the player enters this room and the whole room is the fight area.",
                        "Place a boss_arena in this room and set arena_id to start the fight on entering a smaller area.")
                end
            elseif o.type == "gate" then
                local preset = type(cfg.gate_types) == "table" and cfg.gate_types[trim(p.gate_type)] or nil
                if type(preset) == "table" and preset.required_resource == "energy" then
                    local authored = tonumber(p.required_energy)
                    local cost = (authored and authored >= 0) and authored or tonumber(preset.resource_amount) or 0
                    local max_energy = tonumber(cfg.max_energy)
                    if max_energy == 0 then
                        issue(has_energy_container and "warning" or "error", "gate_energy_off", o, "gate_type",
                            "Energy starts off. This gate needs energy before it can open.",
                            "Raise Max energy in Project > Game Settings... > Player, or place an Energy Container before the gate.")
                    elseif max_energy and cost > max_energy then
                        issue("warning", "gate_energy_unaffordable", o, "required_energy",
                            string.format("Gate costs %s energy but the player holds at most %s, so it can never open.",
                                tostring(cost), tostring(max_energy)),
                            "Lower requirements.required_energy on the gate, or raise max_energy in Project > Game Settings... > Player.")
                    end
                end
            elseif o.type == "collectible" then
                local resource = container_resource(o)
                if resource and tonumber(cfg["max_" .. resource]) == 0 then
                    issue("warning", resource .. "_container_while_off", o, "collectible_type",
                        "This container turns on " .. resource .. ", which starts off at maximum 0.",
                        "Keep it to enable the resource during play, or raise its maximum in Project > Game Settings... > Player.")
                end
            elseif o.type == "energy_station" then
                local resource = trim(p.resource_type)
                if resource == "" then resource = "energy" end
                if (resource == "energy" or resource == "stamina") and tonumber(cfg["max_" .. resource]) == 0 then
                    issue("warning", "station_resource_off", o, "resource_type",
                        "This station restores " .. resource .. ", which starts off at maximum 0.",
                        "Raise its maximum in Project > Game Settings... > Player, place a matching container, or change the station resource.")
                end
            elseif o.type == "chest" and registered then
                local contents = trim(p.contents)
                if contents:find(":", 1, true) and not registered[contents] then
                    issue("error", "chest_inline_contents_unregistered", o, "contents",
                        string.format("Chest contents '%s' are missing from developer/config/chest_inline_contents.lua, so release builds drop no loot.", contents),
                        "Run Project > Prepare & Check to regenerate the chest contents list.")
                end
            end
        end
    end
    return ds
end

return M
