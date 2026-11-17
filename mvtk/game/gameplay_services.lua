-- Literal module paths go here as services gain providers/listeners. Loading
-- this module at main.script scope registers them before SaveManager.init.
local GameEvents = require "mvtk.core.game_events"
local Debug = require "developer.config.debug_config"
local M = { modules = { require "mvtk.player.healing", require "mvtk.core.difficulty", require "mvtk.player.compact_form", require "mvtk.combat.ability_resistances", require "mvtk.combat.status_effects", require "mvtk.combat.resource_loop", require "mvtk.enemies.enemy_defeats", require "mvtk.audio.combat_music", require "mvtk.collectibles.fragment_records", require "mvtk.economy.upgrades", require "mvtk.economy.bank", require "mvtk.game.run_stats", require "mvtk.game.progression.xp_sources", require "mvtk.game.bestiary", require "mvtk.game.progression.achievements", require "mvtk.game.quests.quests", require "mvtk.game.powerups", require "mvtk.combat.weapon_state", require "mvtk.player.charms", require "mvtk.game.crafting", require "mvtk.game.completion_tracker", require "mvtk.game.new_game_plus", require "mvtk.game.goals", require "mvtk.ui.region_titles", require "mvtk.game.extras", require "mvtk.core.spawn_budget", require "mvtk.game.save_summary", require "mvtk.map.map_stamps", require "mvtk.world.presence", require "mvtk.game.countdown", require "mvtk.npcs.npc_memory", require "mvtk.bosses.boss_arena", require "mvtk.bosses.boss_manager", require "mvtk.player.assist", require "mvtk.platform.rich_presence" } }
-- Register storage and Records at bootstrap; RunStats itself stays safe to load alone.
for _, service in ipairs(M.modules) do
    if service.ensure_checkpoint_provider then service.ensure_checkpoint_provider() end
end
-- Entries are literal require expressions, preserving bundler discovery.
local services = M.modules
local function trace(name, payload)
    local fields = {}
    for key, value in pairs(payload) do fields[#fields + 1] = key .. "=" .. tostring(value) end
    table.sort(fields)
    print("[GAME_EVENTS] " .. name .. " " .. table.concat(fields, " "))
end
function M.on_session_start(ctx)
    GameEvents.set_trace(Debug.gameplay and Debug.gameplay.game_events and trace or nil)
    -- Transform the loaded slot before any service publishes startup state.
    local NewGamePlus = require "mvtk.game.new_game_plus"
    if NewGamePlus.apply_pending then NewGamePlus.apply_pending(ctx) end
    -- Preferences can already be active on a fresh save. Mark before achievements
    -- or any other startup listener can publish facts from the restored slot.
    local mark = GameEvents.hold()
    local ok, err = pcall(function()
        require("mvtk.player.assist").begin_session(ctx)
        -- Flags are ready for every startup reader, but their events must not
        -- reach derived listeners until the previous slot's state is reset.
        for _, service in ipairs(services) do
            if service.before_session_start then service.before_session_start(ctx) end
        end
    end)
    if not ok then GameEvents.discard(mark); error(err, 0) end
    GameEvents.release(mark)
    for _, service in ipairs(services) do
        if service.on_session_start then service.on_session_start(ctx) end
    end
end
return M
