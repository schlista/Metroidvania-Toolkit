-- NPC memory (WM12a): which conversation each placed NPC last finished, and
-- the last line each NPC type said. Saved per slot by the versioned provider
-- 'npc_memory' (v1, order 215); a new game, and a New Game+ cycle, start empty.
--
-- Payload: {seen = {[npc_id] = signature}, people = {[npc_type] = {last = text}}}.
-- A signature is DialoguePreview.signature of the lines the NPC would show,
-- read after the conversation ended. Saves hold ids, numbers and source text.
--
--   NpcMemory.seen(npc_id)            -- the stored signature, or nil
--   NpcMemory.note_talk(npc_id, npc_type, room_id, signature, last_line)
--   NpcMemory.snapshot()              -- a copy of the payload
--   NpcMemory.revision()              -- changes on every write or restore
--
-- The first talk with an npc_id in a save emits `npc_met`. No listeners.
local Checkpoint = require "mvtk.core.checkpoint"
local GameEvents = require "mvtk.core.game_events"

local M = {}

local state = { seen = {}, people = {} }
local serial = 0

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sanitize(data)
    local out = { seen = {}, people = {} }
    data = type(data) == "table" and data or {}
    for id, signature in pairs(type(data.seen) == "table" and data.seen or {}) do
        if text(id) and finite(signature) then out.seen[id] = signature end
    end
    for npc_type, person in pairs(type(data.people) == "table" and data.people or {}) do
        if text(npc_type) and type(person) == "table" then
            out.people[npc_type] = { last = text(person.last) }
        end
    end
    return out
end

local function copy(source)
    local out = { seen = {}, people = {} }
    for id, signature in pairs(source.seen) do out.seen[id] = signature end
    for npc_type, person in pairs(source.people) do out.people[npc_type] = { last = person.last } end
    return out
end

function M.seen(npc_id)
    return text(npc_id) and state.seen[npc_id] or nil
end

function M.snapshot() return copy(state) end
function M.revision() return serial end

-- Called once per finished NPC conversation. A nil signature (no visible
-- lines) still counts as met, and stores 0 so the NPC stays clear.
function M.note_talk(npc_id, npc_type, room_id, signature, last_line)
    npc_id = text(npc_id)
    if not npc_id then return false end
    local first = state.seen[npc_id] == nil
    state.seen[npc_id] = finite(signature) and signature or 0
    local kind = text(npc_type)
    if kind then
        local person = state.people[kind] or {}
        person.last = text(last_line) or person.last
        state.people[kind] = person
    end
    serial = serial + 1
    if first then
        GameEvents.emit("npc_met", { npc_id = npc_id, npc_type = kind or "", room_id = text(room_id) or "" })
    end
    return true
end

Checkpoint.register_provider("npc_memory", {
    version = 1,
    order = 215,
    description = "NPC memory: last heard conversation signatures and last lines",
    migrations = {},
    capture = function() return copy(state) end,
    apply = function(data) state = sanitize(data); serial = serial + 1 end,
    defaults = function() state = { seen = {}, people = {} }; serial = serial + 1 end,
})

return M
