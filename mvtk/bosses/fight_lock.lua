-- Shared room confinement predicate for travel and hazard returns.
local M = {}
local sealed_rooms = {}

-- Transient per-source seals. Repeated sealing is idempotent, not a refcount.
function M.seal(room_id, source)
    room_id = require("mvtk.map.streaming.room_geometry").normalize_room_id(room_id)
    if not room_id then return false end
    local sources = sealed_rooms[room_id]
    if not sources then sources = {}; sealed_rooms[room_id] = sources end
    sources[source or ""] = true
    return true
end

function M.unseal(room_id, source)
    room_id = require("mvtk.map.streaming.room_geometry").normalize_room_id(room_id)
    local sources = room_id and sealed_rooms[room_id]
    if not sources then return false end
    local existed = sources[source or ""] == true
    sources[source or ""] = nil
    if not next(sources) then sealed_rooms[room_id] = nil end
    return existed
end

function M.is_sealed(room_id)
    room_id = require("mvtk.map.streaming.room_geometry").normalize_room_id(room_id)
    return room_id ~= nil and sealed_rooms[room_id] ~= nil
end

function M.clear_all()
    for room_id in pairs(sealed_rooms) do sealed_rooms[room_id] = nil end
end

function M.is_locked(room_id)
    local Arena = require "mvtk.bosses.boss_arena"
    if Arena.is_locked() then return true end
    local Geometry = require "mvtk.map.streaming.room_geometry"
    room_id = Geometry.normalize_room_id(room_id)
    if not room_id then return false end
    if M.is_sealed(room_id) then return true end
    local Bosses = require "mvtk.bosses.boss_manager"
    for _, id in ipairs(Bosses.get_active_bosses()) do
        local boss = Bosses.get_boss(id)
        local cfg = boss and boss.config or {}
        if boss and not boss.defeated and cfg.arena and cfg.arena ~= ""
            and Geometry.normalize_room_id(cfg.room_id) == room_id then
            -- Use the manager's explicit live-id match, also used by encounter
            -- phase resolution. A boss instance id need not be an authored tag.
            if Bosses.find_boss_id({id=id}) == id then return true end
        end
    end
    return false
end
return M
