-- Pure census of indexed objects actually present in baked room collections.
local Resource = require "mvtk.editor.resource_text"
local BossIdentity = require "mvtk.bosses.boss_identity"
local Species = require "mvtk.enemies.enemy_species"
local RespawnPolicy = require "mvtk.enemies.enemy_respawn_policy"
local Vendor = require "mvtk.economy.vendor"
local M = {}
M.KINDS = {
    combat_trial="trial",
    collectible="item", ability="item", chest="chest", lore_item="lore", secret="secret", boss="boss",
    gate="barrier", locked_door="barrier", timed_door="barrier", breakable_wall="barrier",
    fast_travel="travel", save_point="travel", spawn_point="travel", player_start="travel",
    player_spawn="travel", respawn_point="travel", map_station="map_station", map_marker="map_marker",
    bank="bank", offering_altar="offering_altar", skill_trainer="skill_trainer", upgrade_station="upgrade_station", shop="shop", health_station="health_station", energy_station="energy_station", teleporter="teleporter", npc="npc",
    enemy="enemy", encounter_spawn="enemy", boss_add_spawner="enemy",
}

function M.collection_instances(text)
    local result = {}
    local root = Resource.parse(text).root
    for _, field in ipairs(root.entries) do
        if field.name == "instances" or field.name == "embedded_instances" then
            local node, props = field.node, {}
            local position = Resource.one(node, "position")
            for _, component in ipairs(Resource.all(node, "component_properties")) do
                for _, property in ipairs(Resource.all(component.node, "properties")) do
                    local id = Resource.value(property.node, "id")
                    local value = Resource.value(property.node, "value")
                    local kind = Resource.value(property.node, "type")
                    if kind == "PROPERTY_TYPE_BOOLEAN" then value = value == "true"
                    elseif kind == "PROPERTY_TYPE_NUMBER" then value = tonumber(value) end
                    props[id] = value
                end
            end
            result[Resource.value(node, "id")] = {properties=props,
                x=position and tonumber(Resource.value(position.node,"x")) or 0,
                y=position and tonumber(Resource.value(position.node,"y")) or 0}
        end
    end
    return result
end

local TRADE = {shop=true, upgrade_station=true, bank=true, skill_trainer=true, offering_altar=true}

local function nonblank(value, fallback)
    if value == nil or tostring(value) == "" then return fallback end
    return value
end

local function make_entry(object, baked, opts)
    local t, source = object.type, object.properties or {}
    local kind = M.KINDS[t]
    -- Resolve the catalog as the runtime does: a baked vendor_shop, else the npc_types preset.
    local npc_type = nonblank(baked.properties.npc_type, source.npc_type)
    local vendor_shop = Vendor.catalog(baked.properties, ((opts.configs or {}).npc_types or {})[npc_type])
    if t == "npc" and not nonblank(source.map_icon) and not vendor_shop then kind = nil end
    -- Any other object with an explicit map_icon becomes a map point of interest.
    local icon = nonblank(source.map_icon)
    if not kind and not nonblank(source.progression_objective) then
        if not icon or icon == "auto" or icon == "hide" then return nil end
        kind = "poi"
    end
    local props = {}
    for k,v in pairs(source) do props[k]=v end
    for k,v in pairs(baked.properties) do props[k]=v end
    local instance = object.instance_id
    local e = {kind=kind or "objective", type=t, id=instance, instance_id=instance,
        room=object.room, x=baked.x or 0, y=baked.y or 0,
        appear_when=source.appear_when or "", remove_when=source.remove_when or "",
        map_icon=source.map_icon or "", hide_on_map=source.hide_on_map == true,
        objective=nonblank(source.progression_objective)}
    if kind == "item" then
        e.id = nonblank(props.collectible_id, instance)
        e.type = props.collectible_type or "health_container"
        for _,key in ipairs({"relic_id","relic_name","lore_id"}) do e[key]=props[key] end
        -- A type's defaults remain live; never freeze them into generated data.
        if source.respawns ~= nil then e.respawns = props.respawns end
    elseif kind == "trial" then
        e.id=nonblank(props.trial_id,instance);e.name=props.trial_name or "";e.clear_flag=props.clear_flag or ""
        e.trial_goal=props.trial_goal or "clear"
    elseif kind == "chest" then
        e.id=nonblank(props.chest_id,instance);e.single_use=props.single_use ~= false
    elseif kind == "lore" then
        e.id=props.lore_id or object.name or ("lore_"..object.room.."_"..tostring(object.object_id))
        e.lore_id=e.id;e.title=props.title or "";e.category=props.category or "lore"
    elseif kind == "secret" then
        e.id=nonblank(props.secret_id,"secret_"..object.room.."_"..tostring(object.object_id))
    elseif kind == "boss" then
        e.identity=BossIdentity.placed(props,instance);e.id="boss_defeated_"..e.identity
        e.preset=nonblank(props.boss_preset,props.boss_type or "")
        e.arena_id=props.arena_id or ""
    elseif kind == "barrier" then
        local field=({gate="gate_id",locked_door="door_id",timed_door="door_id",breakable_wall="wall_id"})[t]
        e.id=nonblank(props[field],instance);e[field]=e.id
        e.gate_type=props.gate_type;e.hidden=props.hidden == true or props.ability_marker == true
        if t == "gate" then
            local group=nonblank(tostring(props.group_id or ""):match("^%s*(.-)%s*$"))
            if group then e.group_id=group end
            -- An unset Persist unlock keeps the gate type's default (no field).
            if props.persist_unlock_override == true then e.persist_unlock=props.persist_unlock ~= false end
        end
    elseif kind == "travel" then
        if t == "fast_travel" then
            e.id=nonblank(props.station_id,instance);e.fast_travel=true
            e.name=props.station_name or object.name or "Travel Point"
            e.description=props.station_description or ""
        elseif t == "save_point" then
            e.id=nonblank(props.save_id,instance);e.fast_travel=props.is_fast_travel == true
            e.name=props.display_name or "Save Point";e.description=props.description or ""
        else
            e.type="player_start";e.id=nonblank(props.registration_id,instance)
            e.name=props.spawn_name or object.name or "Spawn Point";e.description="";e.fast_travel=false
        end
        e.show_on_map=props.show_on_map ~= false;e.facing=props.facing or props.respawn_facing or 1
    elseif kind == "enemy" then
        e.species,e.spawn_species=Species.from_object(t,props,opts.configs or {})
        e.in_bestiary=baked.properties.in_bestiary ~= false
        e.defeat_key=nonblank(props.defeat_key,instance)
        -- Only baked enemies have a placed defeat identity and effective policy.
        e.respawn=t == "enemy" and RespawnPolicy.for_object(props,opts.configs) or ""
        if t == "enemy" and props.champion == true then
            e.champion=true
            e.name=props.champion_name or ""
        end
        if e.respawn == "never" then
            e.guardian=true
            e.persist_key=RespawnPolicy.persist_key(props.defeat_flag,e.defeat_key)
        end
    elseif kind == "npc" and vendor_shop then
        e.vendor = true
        e.vendor_shop = vendor_shop
    elseif kind == "map_marker" then
        e.id=nonblank(props.marker_id,instance);e.marker_id=e.id
        for _,key in ipairs({"marker_type","marker_label","visible_from_start","show_on_world_map",
            "discovery_radius","show_on_minimap"}) do e[key]=props[key] end
    else
        e.id=nonblank(props.station_id or props.teleporter_id,instance)
    end
    if TRADE[t] then
        -- Map tracking reads these; the editor drops default-valued properties.
        e.show_on_map=props.show_on_map ~= false;e.name=props.menu_title or ""
        if t == "offering_altar" then e.remove_after_use=props.offer_remove_after_use == true end
        if t == "skill_trainer" then
            e.leave_when_done=props.leave_when_done == true;e.catalog_id=props.catalog_id or ""
        end
    end
    if kind == "npc" then e.despawn_flag=nonblank(props.despawn_flag) end
    return e
end

function M.build(index, collections, opts)
    opts=opts or {}
    local census={version=1,rooms={}}
    local room_ids=opts.room_ids or {}
    if not opts.room_ids then for room in pairs(collections) do room_ids[#room_ids+1]=room end end
    for _,room in ipairs(room_ids) do
        local text=collections[room]
        assert(text,"Missing baked collection for census room "..room)
        local instances=M.collection_instances(text)
        local entries,seen={},{}
        for _,object in ipairs(index.by_room and index.by_room[room] or index.objects or {}) do
            local baked=instances[object.instance_id]
            if object.room==room and object.visible ~= false and baked and not seen[object.instance_id] then
                local entry=make_entry(object,baked,opts)
                if entry then entries[#entries+1]=entry;seen[object.instance_id]=true end
            end
        end
        table.sort(entries,function(a,b)
            if a.id~=b.id then return a.id<b.id end
            if a.kind~=b.kind then return a.kind<b.kind end
            return a.instance_id<b.instance_id
        end)
        census.rooms[room]=entries
    end
    return census
end

local function encode(value)
    if type(value)=="string" then return string.format("%q",value) end
    if type(value)=="number" then return string.format("%d",math.floor(value+0.5)) end
    if type(value)=="boolean" then return tostring(value) end
    local rows={}
    if #value>0 then
        for _,v in ipairs(value) do rows[#rows+1]=encode(v) end
    else
        local keys={};for k in pairs(value) do keys[#keys+1]=k end;table.sort(keys)
        for _,k in ipairs(keys) do rows[#rows+1]="["..encode(k).."]="..encode(value[k]) end
    end
    return "{"..table.concat(rows,",").."}"
end

function M.encode(census)
    local rows={"-- Generated world census. DO NOT EDIT; run Prepare & Check.","local R = {}"}
    local rooms={};for room in pairs(census.rooms) do rooms[#rooms+1]=room end;table.sort(rooms)
    -- Table fields avoid one local per room and bound constants per function.
    for _,room in ipairs(rooms) do
        rows[#rows+1]="R["..encode(room).."] = function() return "..encode(census.rooms[room]).." end"
    end
    rows[#rows+1]="local rooms = {}"
    rows[#rows+1]="for id, build in pairs(R) do rooms[id] = build() end"
    rows[#rows+1]="return {version=1, rooms=rooms}"
    return table.concat(rows,"\n").."\n"
end
return M
