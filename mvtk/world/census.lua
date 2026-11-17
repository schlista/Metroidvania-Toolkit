-- One catalog and persistence join for the whole published world.
local Util=require "mvtk.core.util"
local Flags=require "mvtk.core.flags"
local Collectibles=require "mvtk.collectibles.collectible_manager"
local Bosses=require "mvtk.bosses.boss_manager"
local Gates=require "mvtk.world.gates.gate_manager"
local Doors=require "mvtk.rooms.door_state"
local Discovery=require "mvtk.map.discovery"
local Rooms=require "mvtk.map.streaming.room_manager"
local Geometry=require "mvtk.map.streaming.room_geometry"
local Chests=require "mvtk.world.chest_state"
local Walls=require "mvtk.world.wall_state"
local Presence=require "mvtk.world.presence"
local Catalog=Util.require_config("developer.config.world_census_generated",{rooms={}})
local Config=Util.require_config("developer.config.world_census",{})
local Types=Util.require_config("developer.config.collectible_types",{})
local M={}

function M.entries(room)
    local out={}
    for _,id in ipairs(Rooms.list_rooms()) do
        if room==nil or room==id then
            for _,entry in ipairs((Catalog.rooms or {})[id] or {}) do out[#out+1]=entry end
        end
    end
    return out
end
function M.find(kind,id)
    for _,entry in ipairs(M.entries()) do if entry.kind==kind and entry.id==id then return entry end end
end
function M.objective(id)
    for _,entry in ipairs(M.entries()) do if entry.objective==id then return entry end end
end
function M.travel_points()
    local out={}
    for _,entry in ipairs(M.entries()) do
        -- A station removed by its world-state condition is no destination.
        if entry.kind=="travel" and (entry.type=="fast_travel" or entry.type=="player_start" or entry.fast_travel==true)
            and M.present(entry) then
            local point={};for k,v in pairs(entry) do point[k]=v end
            local x,y=Geometry.compute_spawn_xy(Rooms.get_room_data(entry.room))
            point.local_x,point.local_y=entry.x or 0,entry.y or 0
            point.x,point.y=x+point.local_x,y+point.local_y
            point.room_id=entry.room;point.kind=entry.type
            out[#out+1]=point
        end
    end
    return out
end
-- World-state presence (G8-09): blank conditions are always present.
function M.present(entry)
    local appear,remove=entry.appear_when,entry.remove_when
    if (appear==nil or appear=="") and (remove==nil or remove=="") then return true end
    return Presence.present(appear,remove)
end
function M.state(entry)
    local kind,id=entry.kind,entry.id
    if kind=="item" then return Collectibles.is_collected(id)
    elseif kind=="trial" then return Flags.has(entry.clear_flag and entry.clear_flag ~= "" and entry.clear_flag or "trial_cleared_"..id)
    elseif kind=="chest" then return Chests.is_opened(id)
    elseif kind=="lore" then return id~="" and Flags.has("collected_lore_"..id)
    elseif kind=="secret" then return Flags.has("secret_"..id)
    elseif kind=="boss" then return Bosses.is_boss_defeated(entry.identity or id:sub(#"boss_defeated_"+1))
    elseif kind=="enemy" then return entry.guardian == true and Flags.has(entry.persist_key)
    elseif kind=="barrier" then
        if entry.type=="gate" then
            if not entry.group_id then return Gates.is_gate_unlocked(id) end
            -- A grouped gate opens with its group, even in a room never loaded.
            return Gates.is_gate_unlocked(id,{group_id=entry.group_id,persist_unlock=entry.persist_unlock,
                type=(Gates.get_gate_type(entry.gate_type) or {}).type})
        elseif entry.type=="locked_door" then return Doors.is_open(id)
        elseif entry.type=="breakable_wall" then return Walls.is_broken(id) end
    end
    return false
end
local function category(entry)
    if entry.kind=="item" then return (Types[entry.type] or {}).category or "" end
    return entry.category or entry.kind
end
local function includes(set,key)
    if set[key]~=nil then return set[key]==true end
    for _,v in ipairs(set) do if v==key then return true end end
    return false
end
function M.counts(entry)
    if Config.count_presence_gated~="always" and not M.present(entry) then return false end
    if entry.kind=="item" then
        local def=Types[entry.type] or {}
        if def.count_in_census==false then return false end
        local respawns=entry.respawns
        if respawns==nil then respawns=def.respawns end
        if respawns then return false end
        local cat=category(entry)
        return includes(Config.count_categories or {},cat) and not includes(Config.exclude_categories or {},cat)
    end
    if entry.kind=="chest" then return entry.single_use~=false end
    if entry.kind=="lore" then return entry.id~="" end
    return entry.kind=="secret" or entry.kind=="boss"
end
local function matches(entry,filter)
    if not filter then return true end
    if type(filter)=="function" then return filter(entry) end
    if filter.kind and entry.kind~=filter.kind then return false end
    if filter.category and category(entry)~=filter.category then return false end
    if filter.room and entry.room~=filter.room then return false end
    if filter.rooms and not includes(filter.rooms,entry.room) then return false end
    if filter.region then
        local room=Rooms.get_room_data(entry.room) or {}
        if (room.region or (room.tags or {}).region)~=filter.region then return false end
    end
    return true
end
function M.totals(filter)
    local out={found=0,total=0,by_kind={},by_category={},by_room={},by_region={}}
    for _,entry in ipairs(M.entries()) do
        if matches(entry,filter) and M.counts(entry) then
            local found=M.state(entry) and 1 or 0
            out.total=out.total+1;out.found=out.found+found
            local room=Rooms.get_room_data(entry.room) or {}
            local keys={by_kind=entry.kind,by_category=category(entry),by_room=entry.room,
                by_region=room.region or (room.tags or {}).region or ""}
            for field,key in pairs(keys) do
                local bucket=out[field][key] or {found=0,total=0};out[field][key]=bucket
                bucket.total=bucket.total+1;bucket.found=bucket.found+found
            end
        end
    end
    return out
end
-- Presence covers flags and inventory events, so item-gated objects refresh too.
function M.revision() return Presence.revision()+Discovery.revision() end
-- The prepared catalog, read-only. It is fixed once loaded: with the layout it is
-- all entries() depends on, so layout caches key on it instead of revision().
function M.catalog() return Catalog end
return M
