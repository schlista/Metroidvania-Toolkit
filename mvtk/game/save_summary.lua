-- mvtk/game/save_summary.lua
-- Builds meta.summary for every full save, so the save slot screen can tell
-- slots apart without loading them. The summary holds ids and integers only,
-- never display text (saves hold no translated words); the slot screen
-- resolves names when it draws a card.
--
--   region     region id (developer/config/biomes.lua) of the checkpoint room
--   room       checkpoint room id, else the current room
--   percent    completion percent: the weighted tracker when it is on, else
--              found / total of the world census; absent when neither has one
--   abilities  number of unlocked abilities
--   bosses     number of defeated bosses in the world census
--   level      player level, only while leveling is on
--   ending     id of the ending reached, absent before any ending
--
-- Registered at module load from mvtk/game/gameplay_services.lua. It runs on
-- every full save, so it caches the census results per Census.revision() and
-- the leveling switch per RuntimeSettings.revision(). Census, room_manager and
-- the trackers are required at call time: census pulls room_manager and the
-- boss manager on load.

local Checkpoint = require "mvtk.core.checkpoint"
local Util = require "mvtk.core.util"

local M = {}

M.FIELDS = { "region", "room", "percent", "abilities", "bosses", "level", "ending" }

local census_cache = nil -- { revision, percent, bosses }
local leveling_cache = nil -- { revision, enabled }

local function census_counts()
    local Census = require "mvtk.world.census"
    local revision = Census.revision()
    if not census_cache or census_cache.revision ~= revision then
        local all = Census.totals()
        local percent = nil
        if all.total > 0 then percent = math.floor(100 * all.found / all.total) end
        census_cache = {
            revision = revision,
            percent = percent,
            bosses = Census.totals({ kind = "boss" }).found,
        }
    end
    return census_cache
end

local function leveling_enabled()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if not leveling_cache or leveling_cache.revision ~= revision then
        local Progression = require "mvtk.game.progression.progression_manager"
        leveling_cache = { revision = revision, enabled = Progression.leveling_settings().enabled == true }
    end
    return leveling_cache.enabled
end

-- Continue puts the player at the checkpoint, so its room names the region a
-- slot resumes in; the current room covers a save made before any checkpoint.
local function summary_room(data)
    local checkpoint = type(data) == "table" and data.checkpoint or nil
    local room = Util.normalize_hash_string(type(checkpoint) == "table" and checkpoint.room_id or nil)
    if room then return room end
    return Util.normalize_hash_string(require("mvtk.map.streaming.room_manager").get_current_room())
end

local function ending_id(data)
    local modules = type(data) == "table" and data.modules or nil
    local entry = type(modules) == "table" and modules.game_completion or nil
    local id = type(entry) == "table" and type(entry.data) == "table" and entry.data.id or nil
    return Util.normalize_hash_string(id)
end

local function integer(value)
    if type(value) ~= "number" or value ~= value then return nil end
    return math.floor(value)
end

--- The summary for `data` (the snapshot being saved, after provider capture).
function M.build(data)
    data = data or Checkpoint.data
    local summary = {}
    local room = summary_room(data)
    if room then
        summary.room = room
        local RoomManager = require "mvtk.map.streaming.room_manager"
        summary.region = require("mvtk.world.regions").of_room(room, RoomManager.get_room_data(room))
    end
    local census = census_counts()
    summary.percent = integer(require("mvtk.game.completion_tracker").percent()) or census.percent
    summary.bosses = census.bosses
    summary.abilities = #require("mvtk.abilities.ability_manager").get_unlocked_abilities()
    if leveling_enabled() then
        summary.level = integer(require("mvtk.game.progression.progression_manager").get_level())
    end
    summary.ending = ending_id(data)
    return summary
end

--- Test seam: drop the cached census and leveling results.
function M.reset_cache()
    census_cache = nil
    leveling_cache = nil
end

Checkpoint.set_summary_builder(M.build)

return M
