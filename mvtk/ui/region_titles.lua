-- mvtk/ui/region_titles.lua
-- Region and landmark title cards, the pause menu's 'area' info line and the
-- region_entered event. A region is an entry in developer/config/biomes.lua
-- (see mvtk/world/regions.lua, the one region lookup).
--
-- Entering a room in another region decides whether to show its card: the
-- region's own `title_card` (first_visit, every_entry or never) wins over Game
-- Settings ▸ HUD and prompts ▸ Area titles ▸ When to show. `region_seen_<id>`
-- remembers a first visit, and `region_entered` fires on every region change.
-- A room with the map properties `room_title` and `room_title_card` = true
-- shows a landmark card once (`room_title_seen_<room>`).
--
-- This module never starts timers: the room listener runs in whichever script
-- fired on_room_enter. It only posts source text to the feature HUD's
-- area_title block, which owns the delay, the hold and the fade.
--
-- The room listener is bound per session from on_session_start, because
-- RoomManager.final() replaces every listener on Quit to menu. The pause info
-- provider is a plain function, so it registers at module load.
local Regions = require "mvtk.world.regions"
local PauseModel = require "mvtk.ui.pause_menu_model"
local M = {}

M.MODES = { first_visit = true, every_entry = true, never = true }
M.DEFAULT_DELAY = 0.5

local generation = 0
local death_listener = nil
local previous_region = nil
local settings_cache, settings_revision = nil, nil

-- Named, not literal: room_manager is bundled by its own literal requires and
-- must not gain a dependency edge through this module.
local ROOM_MANAGER_MODULE = "mvtk.map.streaming.room_manager"
local room_manager = nil
local function rooms()
    -- A failed lookup is not cached, so an early call cannot hide it all session.
    if room_manager == nil then
        local ok, mod = pcall(require, ROOM_MANAGER_MODULE)
        if ok and type(mod) == "table" then room_manager = mod end
    end
    return room_manager
end

local function layout_record(room_id)
    local manager = rooms()
    return manager and manager.get_room_data and manager.get_room_data(room_id) or nil
end

--- Whether an unshown card still belongs at the player's current location.
-- The HUD block calls this only when its delay and holds have ended.
function M.is_current(card)
    -- Preserve direct, unscoped HUD posts (including custom cards).
    if card.kind == "landmark" then
        if not card.room_id then return true end
    elseif not card.region_id then
        return true
    end
    local manager = rooms()
    local room_id = manager and manager.get_current_room and manager.get_current_room() or nil
    if not room_id then return false end
    if card.kind == "landmark" then return room_id == card.room_id end
    return Regions.of_room(room_id, layout_record(room_id)) == card.region_id
end

--- The hud_layout.area_title entry with creator overrides, cached per
-- RuntimeSettings revision.
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if settings_cache == nil or settings_revision ~= revision then
        local layout = Runtime.section("hud_layout", require "developer.config.hud_layout")
        settings_cache, settings_revision = type(layout.area_title) == "table" and layout.area_title or {}, revision
    end
    return settings_cache
end

local function mode_for(info)
    if info.title_card and M.MODES[info.title_card] then return info.title_card end
    local mode = M.settings().mode
    return (mode == "every_entry" or mode == "never") and mode or "first_visit"
end

local function post(card)
    local cfg = M.settings()
    card.seconds = tonumber(cfg.duration) or 3
    card.delay = tonumber(cfg.delay) or M.DEFAULT_DELAY
    require("mvtk.ui.hud_bus").post("area_title", card)
end

--- Handle one room entry. Public for tests; the session listener calls it.
function M.enter(room_id)
    if type(room_id) ~= "string" or room_id == "" then return end
    local Flags = require "mvtk.core.flags"
    local region = Regions.of_room(room_id, layout_record(room_id))
    if region ~= previous_region then
        previous_region = region
        if region then
            local first = not Flags.has("region_seen_" .. region)
            if first then Flags.set("region_seen_" .. region, true) end
            require("mvtk.core.game_events").emit("region_entered",
                { region_id = region, room_id = room_id, first_visit = first })
            local info = Regions.info(region)
            local mode = info and mode_for(info) or "never"
            if info and info.name ~= "" and (mode == "every_entry" or (mode == "first_visit" and first)) then
                post({ title = info.name, subtitle = info.subtitle, kind = "region",
                    room_id = room_id, region_id = region })
            end
        end
    end
    local title, card = Regions.room_title(room_id)
    if card and not Flags.has("room_title_seen_" .. room_id) then
        Flags.set("room_title_seen_" .. room_id, true)
        post({ title = title, subtitle = "", kind = "landmark", room_id = room_id, region_id = region })
    end
end

--- Pause info line: the region name, then the landmark title when the room has
-- one. An unnamed region (blank name) shows nothing.
function M.area_text(room_id)
    if type(room_id) ~= "string" or room_id == "" then return "" end
    local info = Regions.info(Regions.of_room(room_id, layout_record(room_id)))
    if not info or info.name == "" then return "" end
    local title = Regions.room_title(room_id)
    if not title then return info.name end
    return { parts = { info.name, title }, separator = { key = "pause.area_separator" } }
end

PauseModel.add_info("area", 50, function()
    local manager = rooms()
    return M.area_text(manager and manager.get_current_room and manager.get_current_room() or nil)
end)

function M.on_session_start()
    generation = generation + 1
    previous_region = nil
    settings_cache, settings_revision = nil, nil
    local token = generation
    -- A card still showing when the player dies is cut: after Try Again it would
    -- otherwise finish over the respawn room, often another region's.
    local Events = require "mvtk.core.game_events"
    if death_listener then Events.off(death_listener) end
    death_listener = Events.on("player_died", function()
        -- A reloaded copy of this module (tests) leaves its listener behind; only
        -- the loaded copy's current session acts.
        if token ~= generation or package.loaded["mvtk.ui.region_titles"] ~= M then return end
        require("mvtk.ui.hud_bus").post("area_title", { clear = true })
    end)
    local manager = rooms()
    if not (manager and manager.register_event) then return end
    manager.register_event("on_room_enter", function(room_id)
        if token ~= generation then return end
        M.enter(room_id)
    end)
end

-- Tests reload this module; each copy removes its own death listener.
function M._stop()
    if death_listener then require("mvtk.core.game_events").off(death_listener) end
    death_listener = nil
end

-- Tests replace the room manager; nil restores the lazy lookup.
function M._set_rooms(value)
    room_manager = value
end

return M
