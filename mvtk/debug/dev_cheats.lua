-- Debug-only actions register runtime policies; shared services never load us.
local Checkpoint = require "mvtk.core.checkpoint"
local Multipliers = require "mvtk.combat.multipliers"
local Energy = require "mvtk.player.energy_state"
local Ability = require "mvtk.abilities.ability_manager"
local Pause = require "mvtk.core.pause"
local Game = require "mvtk.game.game_manager"
local Config = require "developer.config.debug_config"
local Prefab = require "mvtk.prefabs.prefab_utils"
local M = {}
local session, toggles, ending = nil, {}, false

function M.available()
    return Prefab.is_dev_build() and Config.dev_tools and Config.dev_tools.enabled == true
        and Config.dev_tools.cheats == true
end

local function reset_cheats()
    require("mvtk.hazards.hazard_contact").unregister_player_mode("dev")
    Multipliers.unregister_source("dev")
    Energy.set_cost_waiver(nil)
    Ability.set_cost_waiver(nil)
    Pause.set_speed_factor("dev", nil)
    session, toggles, ending = nil, {}, false
end

function M.update()
    if session and not Checkpoint.is_save_suspended_by("dev_tools") then reset_cheats() end
end

function M.enabled(name)
    return Checkpoint.is_save_suspended_by("dev_tools") and toggles[name] == true
end

function M.start_session()
    if not M.available() then return false, "Cheats are disabled." end
    M.update()
    if ending then return false, "Waiting for the saved game to restart." end
    if session then return true end
    -- Must precede every action, especially ability grants and their autosave.
    Checkpoint.suspend_saves("dev_tools")
    session = {}
    local token = session
    require("mvtk.hazards.hazard_contact").register_player_mode("dev", function(mode, lethal, damage)
        if not M.enabled("god") then return mode, damage end
        if lethal then return "safe_return", 0 end
        return "damage", damage
    end)
    Multipliers.register_source({id="dev", order=90, challenge=false,
        immune_all=function() return M.enabled("god") end})
    Energy.set_cost_waiver(function() return M.enabled("energy") end)
    Ability.set_cost_waiver(function() return M.enabled("stamina") end)
    Game.register_state_callback(Game.STATE.PLAYING, function(old_state)
        if session == token and ending and old_state == Game.STATE.LOADING then
            Checkpoint.resume_saves("dev_tools")
            reset_cheats()
        end
    end)
    return true
end

function M.end_session()
    if not Checkpoint.is_save_suspended_by("dev_tools") then return false, "No test session is active." end
    if ending then return false, "Restart already requested." end
    ending = true
    -- GUI callers cannot load/apply gameobjects. The main script owns restart
    -- and keeps the sandbox until room arrival completes and enters PLAYING.
    local ok, err = pcall(msg.post, "main:/main_go#script", "restart_game")
    if not ok then ending = false; return false, tostring(err) end
    Checkpoint.discard_test_snapshot()
    return true
end

function M.toggle(name)
    if name ~= "god" and name ~= "energy" and name ~= "stamina" then return false, "Unknown toggle." end
    local ok, err = M.start_session(); if not ok then return false, err end
    toggles[name] = not toggles[name]
    return true
end

local function grant(gives)
    local ok, err = M.start_session(); if not ok then return false, err end
    local granted, result = require("mvtk.game.grants").grant(gives, {source="debug", durable=false, notify=true})
    return granted, not granted and (result.message or result.code) or nil
end

function M.unlock_all()
    local gives = {}
    -- Grants take reward text (mvtk/game/grant_spec.lua), never tables.
    for id in pairs(require("developer.config.abilities").abilities) do
        gives[#gives + 1] = "ability:" .. id
    end
    table.sort(gives)
    return grant(gives)
end

function M.give_currency(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 or amount == math.huge or amount ~= math.floor(amount) then
        return false, "Type a positive whole currency amount in the filter."
    end
    return grant({string.format("currency:%d", amount)})
end

function M.give_item(id)
    id = require("mvtk.core.key_ids").canonicalize(id)
    return grant({"item:" .. id})
end

function M.refill()
    local ok, err = M.start_session(); if not ok then return false, err end
    msg.post(require("mvtk.core.constants").URL.PLAYER, require("mvtk.core.constants").MSG.RESTORE_HEALTH)
    local _, maximum = Energy.get(); Energy.set_current(maximum)
    require("mvtk.player.healing").refill("cheat")
    return true
end

function M.kill_room()
    local ok, err = M.start_session(); if not ok then return false, err end
    local enemies = require "mvtk.enemies.enemy_manager"
    local room = require("mvtk.map.streaming.room_manager").get_current_room()
    for _, enemy in ipairs(enemies.get_living_enemies()) do
        if room and enemy.room_id == room then enemies.kill_enemy(enemy.id, "debug") end
    end
    return true
end

function M.reveal_map()
    local ok, err = M.start_session(); if not ok then return false, err end
    local discovery = require "mvtk.map.discovery"
    for _, id in ipairs(require("mvtk.map.streaming.room_manager").list_rooms()) do discovery.reveal_room(id) end
    return true
end

function M.set_flag(name, value)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then return false, "Type the flag name in the filter." end
    local ok, err = M.start_session(); if not ok then return false, err end
    local flags = require "mvtk.core.flags"
    if value then flags.set(name, true) else flags.clear(name) end
    return true
end

function M.set_speed(factor)
    local ok, err = M.start_session(); if not ok then return false, err end
    Pause.set_speed_factor("dev", factor)
    return true
end

function M.register_menu(menu)
    if not M.available() then return end
    menu.register("cheats", "Cheats", {
        rows = function(ctx)
            M.update()
            local rows = {}
            local function add(id,label,action) rows[#rows+1]={id=id,label=label,action=action,hold=0} end
            add("start", "Start test session (saving off)", M.start_session)
            add("end", "End test session", M.end_session)
            for _, toggle in ipairs({{"god","God mode"},{"energy","Infinite energy"},{"stamina","Infinite stamina"}}) do
                local id = toggle[1]
                add(id, toggle[2] .. (M.enabled(id) and " [ON]" or " [OFF]"), function() return M.toggle(id) end)
            end
            add("unlock", "Unlock all abilities", M.unlock_all)
            add("refill", "Refill health, energy and flask", M.refill)
            add("kill", "Kill living enemies in current room", M.kill_room)
            add("map", "Reveal map", M.reveal_map)
            local query = ctx.context.query
            add("currency", "Give currency (type amount): " .. query, function() return M.give_currency(query) end)
            add("set_flag", "Set flag (type name): " .. query, function() return M.set_flag(query,true) end)
            add("clear_flag", "Clear flag (type name): " .. query, function() return M.set_flag(query,false) end)
            for _, factor in ipairs({0.25,0.5,1,2}) do
                local f = factor
                add("speed:"..f, "Game speed x"..f, function() return M.set_speed(f) end)
            end
            local items = {}
            for id in pairs(require "developer.config.items") do items[id]=true end
            for _, id in ipairs(require("mvtk.core.key_ids").canonical_ids()) do items[id]=true end
            for _, def in pairs(require "developer.config.collectible_types") do
                if def.on_collect == "grant_unique_item" then items[def.item_id] = true end
            end
            local sorted = {}; for id in pairs(items) do sorted[#sorted+1]=id end; table.sort(sorted)
            for _, id in ipairs(sorted) do
                local item = id
                if item:lower():find(query:lower(),1,true) then
                    add("item:"..item, "Give item/key: "..item, function() return M.give_item(item) end)
                end
            end
            return rows
        end,
        on_confirm = function(_, row)
            local ok, err = row.action()
            return {close=ok and row.id=="end", refresh=true, status=err or "Applied (saving off)."}
        end,
    })
end
return M
