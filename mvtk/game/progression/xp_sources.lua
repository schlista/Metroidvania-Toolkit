-- Event-time settings reads; the GUI renders snapshots and callers own saves.
local Events = require "mvtk.core.game_events"
local M = {}
local function award(amount, source)
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then return 0 end
    return require("mvtk.game.progression.progression_manager").add_experience(
        amount * require("mvtk.player.player_stats").mult("xp_mult"), source)
end
local function settings() return require("mvtk.game.progression.progression_manager").leveling_settings() end
Events.on("enemy_defeated", function(p)
    local cfg = settings()
    local sources = cfg.sources or {}
    if not cfg.enabled or (sources.skip_spawned and p.spawned) or (sources.skip_causes or {})[p.cause] then return end
    local amount = p.xp_value
    if type(amount) ~= "number" or amount < 0 then
        amount = (sources.enemy_default or 0) * (p.elite and (sources.elite_mult or 1) or 1)
    end
    award(amount, "enemy_defeated")
end)
Events.on("boss_defeated", function(p)
    local cfg = settings()
    if cfg.enabled then award(type(p.xp) == "number" and p.xp > 0 and p.xp or (cfg.sources or {}).boss_default, "boss_defeated") end
end)
Events.on("secret_found", function()
    local cfg = settings(); if cfg.enabled then award((cfg.sources or {}).secret_found, "secret_found") end
end)
-- room_visited is emitted by Discovery only on the first saved visit.
Events.on("room_visited", function()
    local cfg = settings(); if cfg.enabled then award((cfg.sources or {}).room_first_visit, "room_visited") end
end)
Events.on("collectible_collected", function(p)
    local cfg = settings()
    if cfg.enabled then award(((cfg.sources or {}).collectible_type_xp or {})[p.collectible_type], "collectible_collected") end
end)
function M.section()
    return {id = "level", order = 40, header = function() return {key = "journal.level"} end,
        visible = function() return settings().enabled == true end,
        lines = function()
            local data = require("mvtk.game.progression.progression_manager").get_save_data()
            return {{label = {key = "records.level"}, value = data.level},
                {label = {key = "records.total_xp"}, value = data.experience}}
        end}
end
local function post_hud()
    local P = require "mvtk.game.progression.progression_manager"
    if P.leveling_settings().enabled then
        require("mvtk.ui.hud_bus").post("level_xp", P.get_progress())
    end
end
Events.on("xp_gained", post_hud)
function M.on_session_start()
    require("mvtk.ui.screens.journal_records").add_section(M.section())
    post_hud()
end
return M
