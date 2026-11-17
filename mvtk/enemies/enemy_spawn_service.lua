-- Runtime actors share one spawn and cleanup contract. State belongs to the
-- current game session; requiring this module does not bind or load services.
local M = {}
local records, warnings = {}, {}
local bound, generation = false, 0

-- Fixed text prefixes for runtime owners; suffixes are text ids or hash_to_hex.
M.OWNER_PREFIXES = {boss_adds = "boss_adds:", boss = "boss:", arena = "arena:",
    summoner = "summoner:", encounter = "encounter:", split = "split:"}

local function warn(owner, kind, category, message)
    warnings[owner] = warnings[owner] or {}
    local key = kind .. ":" .. category
    if warnings[owner][key] then return end
    warnings[owner][key] = true
    print("[ENEMY_SPAWN] " .. owner .. " / " .. kind .. ": " .. message)
end

local function normalize_room(room)
    return require("mvtk.map.streaming.room_geometry").normalize_room_id(room)
end

function M.spawn(spec)
    if type(spec) ~= "table" or type(spec.owner) ~= "string" or spec.owner == ""
        or type(spec.enemy_type) ~= "string" or spec.enemy_type == "" or not spec.position then return nil end
    local owner, kind = spec.owner, spec.enemy_type
    local RoomManager = require "mvtk.map.streaming.room_manager"
    local room = normalize_room(spec.room_id)
        or normalize_room(RoomManager.get_room_for_position(spec.position))
        or normalize_room(RoomManager.get_current_room())
    if not room then
        warn(owner, kind, "room", "cannot resolve a room; nothing spawned")
        return nil
    end
    local payload, invalid = {}, false
    for key, value in pairs(spec.overrides or {}) do
        local t = type(value)
        if type(key) == "string" and (t == "string" or t == "number" or t == "boolean") then
            payload[key] = value
        else invalid = true end
    end
    if invalid then warn(owner, kind, "overrides", "ignored non-scalar overrides") end
    local archetype = type(spec.archetype) == "string" and spec.archetype or nil
    local EnemyManager = require "mvtk.enemies.enemy_manager"
    local spawn_id = EnemyManager.spawn_enemy(archetype or kind, spec.position, {
        room_id = room, max_enemies_per_room = spec.max_enemies_per_room,
        health_multiplier = payload.health_mult, damage_multiplier = payload.damage_mult,
        contact_damage_multiplier = payload.damage_mult,
    })
    if not spawn_id then
        warn(owner, kind, "rejected", "unknown type or room cap reached; nothing spawned")
        return nil
    end
    local C = require "mvtk.core.constants"
    local scale = tonumber(spec.size) or 1
    if scale <= 0 then scale = 1 end
    local SkinSync = require "mvtk.enemies.enemy_skin_sync"
    local manifest = require "developer.config.enemy_skins_generated"
    local cfg = EnemyManager.get_enemy_type(kind, archetype) or {}
    local requested_skin = manifest.skins[payload.skin] and payload.skin or cfg.skin
    local skin = SkinSync.resolve_active_skin_id(requested_skin, manifest)
    local id
    if skin then
        local url = msg.url(C.URL.ENEMY_SPAWN_FACTORIES)
        url.fragment = hash("enemy_" .. skin)
        local created, instance = pcall(factory.create, url, spec.position, nil, {}, scale)
        if created then id = instance end
    end
    local ok, ids
    if not id then
        ok, ids = pcall(collectionfactory.create, C.URL.FACTORY.enemy_collection, spec.position, nil, {}, scale)
        id = ok and type(ids) == "table" and ids[hash("/enemy")]
    end
    if not id then
        -- A malformed collection can have created objects without the expected
        -- root. Delete those too, before returning its registry slot.
        if ok and type(ids) == "table" then
            for _, orphan in pairs(ids) do if go.exists(orphan) then go.delete(orphan, true) end end
        end
        EnemyManager.unregister_enemy_instance(spawn_id)
        warn(owner, kind, "factory", "enemy collection creation failed or has no /enemy root")
        return nil
    end
    EnemyManager.register_enemy_instance(spawn_id, id)
    payload.spawn_id, payload.enemy_type, payload.archetype = spawn_id, kind, archetype
    payload.owner, payload.room_id = owner, room
    payload.settle_to_ground = spec.settle_to_ground == true
    msg.post(id, "apply_tiled_overrides", payload)
    records[spawn_id] = {id = id, owner = owner, room_id = room}
    return spawn_id
end

function M.alive(spawn_id)
    return require("mvtk.enemies.enemy_manager").is_alive(spawn_id)
end

function M.outcome(spawn_id)
    local record = records[spawn_id]
    if not record then return nil end
    return record.ended or (M.alive(spawn_id) and "alive" or "gone")
end

function M.note_defeated(spawn_id)
    local record = records[spawn_id]
    if record and not record.ended then record.ended = "defeated" end
end

-- Returned ids are a snapshot; finished outcomes survive until explicit cleanup.
function M.list(owner)
    local ids = {}
    for id, record in pairs(records) do if record.owner == owner then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
end

function M.count_alive(owner)
    local count = 0
    for id, record in pairs(records) do
        if record.owner == owner and M.alive(id) then count = count + 1 end
    end
    return count
end

function M.count_defeated(owner)
    local count = 0
    for _, record in pairs(records) do
        if record.owner == owner and record.ended == "defeated" then count = count + 1 end
    end
    return count
end

local function despawn(matches, reason)
    local owners = {}
    for spawn_id, record in pairs(records) do
        if matches(record) then
            if go.exists(record.id) then go.delete(record.id, true) end
            -- Resolve per record: game restart can replace the manager binding.
            local EnemyManager = require "mvtk.enemies.enemy_manager"
            EnemyManager.unregister_enemy_instance(spawn_id)
            -- Forget ended records so storage stays bounded per session.
            owners[record.owner] = true
            records[spawn_id] = nil
        end
    end
    for owner in pairs(owners) do
        if #M.list(owner) == 0 then warnings[owner] = nil end
    end
end

function M.despawn_owner(owner, reason)
    despawn(function(record) return record.owner == owner end, reason)
    warnings[owner] = nil
end

function M.despawn_room(room, reason)
    room = normalize_room(room)
    if room then despawn(function(record) return record.room_id == room end, reason) end
end

function M.despawn_all(reason)
    despawn(function() return true end, reason)
    warnings = {}
end

function M.reset()
    records, warnings = {}, {}
end

function M.init()
    if bound then return end
    local RoomManager = require "mvtk.map.streaming.room_manager"
    -- Lightweight headless hosts need not implement the streaming event API.
    if not RoomManager.register_event or not RoomManager.on_room_unload then return end
    bound = true
    generation = generation + 1
    local token = generation
    RoomManager.register_event("on_room_exit", function(room)
        if token ~= generation then return end
        local settings = require "developer.config.enemy_settings"
        if settings.remove_spawned_enemies_on_room_exit ~= false then M.despawn_room(room, "room_exit") end
    end)
    RoomManager.on_room_unload(function(room)
        if token == generation then M.despawn_room(room, "room_unload") end
    end)
end

function M.final()
    generation = generation + 1
    bound = false
    M.reset()
end

return M
