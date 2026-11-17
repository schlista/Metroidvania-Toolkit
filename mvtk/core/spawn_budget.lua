-- Live caps for objects the game spawns while playing (CP04d).
--
-- All rooms share one engine world, so shots and damage numbers created
-- during play take slots from the same pools as every streamed room. Past a
-- pool's limit the engine refuses new objects, including a room's own
-- objects while it streams in. This module keeps the two short-lived kinds
-- bounded:
--
--   projectile     Every shot runs mvtk/attacks/projectile.script, which
--                  enters in init and leaves in final. Over the cap, the
--                  oldest enemy shot is returned for deletion; player shots
--                  go only when no enemy shot remains. Nothing is recycled
--                  while a boss arena is locked, so boss patterns stay whole.
--   damage_number  Gamefeel.damage_number asks allow() before it creates
--                  one; a skipped number is cosmetic.
--
-- Reward pickups are never capped (decision D-S7A-3): only the world budget
-- report's reserve counts them.
--
-- Caps come from performance_budgets.spawn_caps, read through
-- RuntimeSettings.section once per settings revision, so Game Settings
-- overrides arrive without a per-shot copy of the section. Pure Lua: nothing
-- here touches the engine, and callers delete the ids enter() returns.

local PerformanceBudgets = require "developer.config.performance_budgets"
-- Named in a variable: the boss arena is bundled through the boss scripts'
-- literal requires, and a literal one here would tie every shot to it.
local BOSS_ARENA_MODULE = "mvtk.bosses.boss_arena"

local M = {}

M.KINDS = { projectile = true, damage_number = true }
-- Smallest cap each kind accepts; a projectile cap of 0 would delete every
-- enemy shot as it is fired.
local MIN_CAP = { projectile = 1, damage_number = 0 }

local live = {}
local cached_caps, cached_revision

local function bucket(kind)
    local b = live[kind]
    if not b then
        b = { list = {}, info = {}, count = 0 }
        live[kind] = b
    end
    return b
end

local function read_caps(section)
    local caps = {}
    local source = type(section) == "table" and section.spawn_caps or nil
    for kind in pairs(M.KINDS) do
        local value = type(source) == "table" and tonumber(source[kind]) or nil
        if value and value == value and value < math.huge then
            caps[kind] = math.max(MIN_CAP[kind], math.floor(value))
        end
    end
    return caps
end

-- The cap for kind, or nil when none is configured.
function M.cap(kind)
    local RuntimeSettings = require "developer.config.runtime_settings"
    local revision = RuntimeSettings.revision and RuntimeSettings.revision()
    if revision == nil or cached_caps == nil or cached_revision ~= revision then
        cached_caps = read_caps(RuntimeSettings.section("performance_budgets", PerformanceBudgets))
        cached_revision = revision
    end
    return cached_caps[kind]
end

-- Number of live objects of kind.
function M.count(kind)
    local b = live[kind]
    return b and b.count or 0
end

-- True when another object of kind fits under its cap.
function M.allow(kind)
    local cap = M.cap(kind)
    return cap == nil or M.count(kind) < cap
end

local function remove(b, id)
    if not b.info[id] then return false end
    b.info[id] = nil
    b.count = b.count - 1
    for i = 1, #b.list do
        if b.list[i] == id then table.remove(b.list, i); break end
    end
    return true
end

local function arena_locked()
    local ok, BossArena = pcall(require, BOSS_ARENA_MODULE)
    return ok and type(BossArena) == "table" and BossArena.is_locked and BossArena.is_locked() and true or false
end

-- The oldest live projectile that may be recycled: enemy shots first, then
-- player shots.
local function oldest(b)
    for i = 1, #b.list do
        local id = b.list[i]
        if b.info[id].owner ~= "player" then return id end
    end
    return b.list[1]
end

-- Record a new live object. opts.owner is "player" for the player's shots;
-- anything else counts as an enemy shot. Returns a list of ids the caller
-- must delete to get back under the cap, or nil. Entering twice is harmless.
function M.enter(kind, id, opts)
    if not M.KINDS[kind] or id == nil then return nil end
    local b = bucket(kind)
    if b.info[id] then return nil end
    b.info[id] = { owner = type(opts) == "table" and opts.owner or "enemy" }
    b.list[#b.list + 1] = id
    b.count = b.count + 1
    if kind ~= "projectile" then return nil end
    local cap = M.cap(kind)
    if cap == nil or b.count <= cap or arena_locked() then return nil end
    local victims = {}
    while b.count > cap do
        local victim = oldest(b)
        if victim == nil then break end
        remove(b, victim)
        victims[#victims + 1] = victim
    end
    return victims
end

-- Forget a live object. Leaving twice, or leaving an unknown id, is harmless.
function M.leave(kind, id)
    local b = live[kind]
    if b and id ~= nil then remove(b, id) end
end

-- Forget every live object (a new session starts with an empty world).
function M.reset()
    live = {}
end

-- GameplayServices hook: each session starts with nothing counted.
function M.on_session_start()
    M.reset()
end

-- Test hook: forget the cached caps as well.
function M._reset()
    M.reset()
    cached_caps, cached_revision = nil, nil
end

return M
