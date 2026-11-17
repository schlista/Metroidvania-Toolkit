-- The single defeat fact; persistence and rewards extend record here.
local GameEvents = require "mvtk.core.game_events"
local EnemyDefeatEvent = require "mvtk.enemies.enemy_defeat_event"
local EnemySpecies = require "mvtk.enemies.enemy_species"
local M = {}
local function text(value) return type(value) == "string" and value or "" end
local warned = {}
local session_rest, session_room, dormant = {}, {}, {}
local generation, bound = 0, false

-- Function-local dependencies preserve the record module's inert load contract.
function M.resolve_policy(instance_value, type_value, project_default, opts)
    return require("mvtk.enemies.enemy_respawn_policy").resolve_policy(instance_value, type_value, project_default, opts)
end
function M.persist_key(defeat_flag, defeat_key)
    return require("mvtk.enemies.enemy_respawn_policy").persist_key(defeat_flag, defeat_key)
end
function M.policy_for(self)
    if self._spawn_owner ~= nil or text(self.defeat_key) == "" then return "room_reload", {} end
    local defaults = require("developer.config.runtime_settings").section("enemy_defaults", require "developer.config.enemy_defaults")
    local policy, invalid = M.resolve_policy(self.respawn, (self.enemy_type_config or {}).respawn, defaults.respawn_policy,
        {champion=self._champion ~= nil})
    if invalid and not warned[invalid] then
        warned[invalid] = true
        print("[ENEMY] Unknown respawn policy '" .. invalid .. "'; using project default '" .. policy .. "'. Run Prepare & Check.")
    end
    return policy, defaults
end

function M.record(self, ctx)
    ctx = ctx or {}
    local payload = EnemyDefeatEvent.payload(self, {x=ctx.x or 0, y=ctx.y or 0})
    local xp = self.xp_value
    if type(xp) ~= "number" or xp ~= xp or xp < 0 or xp == math.huge then xp = (self.enemy_type_config or {}).xp end
    payload.xp_value = type(xp) == "number" and xp == xp and xp >= 0 and xp < math.huge and xp or -1
    payload.skin = text(self.skin)
    payload.species = EnemySpecies.resolve(self)
    payload.in_bestiary = self.in_bestiary ~= false
    payload.spawned = self._spawn_owner ~= nil
    payload.spawn_owner = text(self._spawn_owner)
    payload.defeat_key = payload.spawned and "" or text(self.defeat_key)
    local policy, defaults = M.policy_for(self)
    payload.respawn = policy
    payload.cause = text(ctx.cause)
    payload.source_attack = text(ctx.source_attack)
    payload.damage_type = text(ctx.damage_type)
    if payload.spawned then
        local EnemySpawnService = require "mvtk.enemies.enemy_spawn_service"
        EnemySpawnService.note_defeated(self.spawn_id)
    end
    local defeat_flag = text(self.defeat_flag):match("^%s*(.-)%s*$")
    local persist_key = M.persist_key(defeat_flag, payload.defeat_key)
    if policy == "save" then session_rest[payload.defeat_key] = text(self._room_id or self.room_id) end
    if policy == "always" then session_room[payload.defeat_key] = text(self._room_id or self.room_id) end
    local function publish()
        if defeat_flag ~= "" or (policy == "never" and persist_key ~= "") then
            local Flags = require "mvtk.core.flags"
            if defeat_flag ~= "" then Flags.set(defeat_flag, true) end
            if policy == "never" and persist_key ~= "" and persist_key ~= defeat_flag then
                Flags.set(persist_key, true)
            end
        end
        if self._champion then self._champion:on_defeat(self, {persist_key=persist_key}) end
        GameEvents.emit("enemy_defeated", payload)
    end
    if self._champion or (policy == "never" and defaults.autosave_on_permanent_defeat == true) then
        local saved, err = require("mvtk.core.checkpoint").batch("enemy_defeated", publish)
        if not saved then print("[ENEMY] Permanent defeat save failed: " .. tostring(err)) end
    else
        publish()
    end
    if self._champion then self._champion:release(self, "defeated") end
    return policy ~= "room_reload" and payload.defeat_key ~= ""
end

function M.is_suppressed(self)
    local policy = M.policy_for(self)
    local key = text(self.defeat_key)
    if policy == "never" then
        return require("mvtk.core.flags").has(M.persist_key(self.defeat_flag, key))
    end
    if policy == "save" then return session_rest[key] ~= nil end
    if policy == "always" then return session_room[key] ~= nil end
    return false
end

function M.register_dormant(key, url, room_id, self)
    if text(key) == "" then return end
    dormant[key] = {url=url, room_id=room_id, actor=self}
    -- A rest/room entry can lift suppression while the death animation runs.
    -- Complete that pending revival once the baked actor actually goes dormant.
    if not M.is_suppressed(self) then
        local RoomManager = require "mvtk.map.streaming.room_manager"
        if RoomManager.get_current_room and RoomManager.get_current_room() == room_id then
            msg.post(url, "enemy_revive")
        end
    end
end

function M.unregister_dormant(key, url)
    local entry = dormant[key]
    if entry and tostring(entry.url) == tostring(url) then dormant[key] = nil end
end

local function revive_room(room)
    if not room then return end
    for _, entry in pairs(dormant) do
        if entry.room_id == room and not M.is_suppressed(entry.actor) then
            msg.post(entry.url, "enemy_revive")
        end
    end
end

function M.on_room_enter(room)
    for key, value in pairs(session_room) do
        if value == room then session_room[key] = nil end
    end
    revive_room(room)
end

function M.on_room_unloaded(room)
    for key, entry in pairs(dormant) do
        if entry.room_id == room then dormant[key] = nil end
    end
    for key, value in pairs(session_room) do
        if value == room then session_room[key] = nil end
    end
end

function M.world_reset(reason)
    session_rest, session_room = {}, {}
    if next(dormant) == nil then return end
    local RoomManager = require "mvtk.map.streaming.room_manager"
    if RoomManager.get_current_room then revive_room(RoomManager.get_current_room()) end
end

function M.on_session_start()
    M.world_reset("session")
end

function M.init()
    if bound then return end
    local RoomManager = require "mvtk.map.streaming.room_manager"
    if not RoomManager.register_event then return end
    bound, generation = true, generation + 1
    local token = generation
    RoomManager.register_event("on_room_enter", function(room)
        if token == generation then M.on_room_enter(room) end
    end)
    RoomManager.register_event("on_room_unloaded", function(room)
        if token == generation then M.on_room_unloaded(room) end
    end)
end

function M.final()
    generation, bound = generation + 1, false
    session_rest, session_room, dormant = {}, {}, {}
end

return M
