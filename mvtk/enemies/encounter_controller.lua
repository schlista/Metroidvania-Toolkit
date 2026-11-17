-- Script-context adapter for baked encounters. No world work in event listeners.
local Runtime = require "mvtk.enemies.encounter_runtime"
local Registry = require "mvtk.enemies.encounter_registry"
local M = {}

local function persisted(self)
    return not self.repeatable and require("mvtk.core.flags").has(self.clear_flag)
end

-- keep_actors: a clear leaves defeated wave actors to finish their death
-- presentation (nothing owned is alive by then); reset and final despawn.
local function release(self, reason, keep_actors)
    if not keep_actors then
        require("mvtk.enemies.enemy_spawn_service").despawn_owner(self.owner, reason)
    end
    require("mvtk.bosses.fight_lock").unseal(self.room_id, self.owner)
    if self._sealed then
        msg.post("main:/room_manager#script", "unlock_room", {room_id=self.room_id, source=self.owner})
        self._sealed = false
    end
    require("mvtk.bosses.boss_music").pop(self.owner)
end

local function toast(self, key, params)
    msg.post("main:/toast_gui#toast", "toast", {key=key, params=params or {}, duration=self.settings.toast_duration})
end

local function clear(self, count)
    release(self, "cleared", true)
    local Music = require "mvtk.bosses.boss_music"
    -- A lower-priority clear must not interrupt a boss or champion still playing.
    if self.victory_music ~= "" and not Music.is_playing() then
        require("mvtk.audio.audio").music(self.victory_music, {t=0.3})
    end
    if self.reward_collectible ~= "" then
        local Drops = require "mvtk.collectibles.reward_drops"
        local plan, collected
        repeat
            local prefix = self.encounter_id .. "_reward_"
            if self.repeatable then prefix = prefix .. count .. "_" end
            plan = Drops.plan({{type=self.reward_collectible, amount=self.reward_amount}},
                require "developer.config.collectible_types", prefix)
            collected = false
            if self.repeatable then
                for _, drop in ipairs(plan) do
                    if require("mvtk.collectibles.collectible_manager").is_collected(drop.id) then collected = true end
                end
                if collected then count = count + 1 end
            end
        until not collected
        -- A reloaded repeatable fight must not reuse a saved collected pickup id.
        self.runtime.clear_count = count
        Drops.spawn(plan, self.position)
    end
    local function publish()
        local Flags = require "mvtk.core.flags"
        if not self.repeatable then
            if self.target_id ~= "" then
                require("mvtk.world.switch_state").write_channel(Flags, self.target_id, true, self.clear_message)
            end
            Flags.set(self.clear_flag, true)
        end
        require("mvtk.core.game_events").emit("encounter_cleared", {encounter_id=self.encounter_id,
            room_id=self.room_id, repeatable=self.repeatable, clear_count=count})
        if self.target_id ~= "" then
            require("mvtk.world.trigger_bus").emit(self.target_id, self.clear_message, {persist=not self.repeatable})
        end
    end
    if self.settings.autosave_on_clear then
        local ok, err = require("mvtk.core.checkpoint").batch("encounter_cleared", publish)
        if not ok then print("[ENCOUNTER] Clear save failed: " .. tostring(err)) end
    else publish() end
    if not require("mvtk.game.fight_session").owns_encounter(self.room_id, self.encounter_id) then
        toast(self, "encounter.cleared")
    end
end

local function spawn(self, point, wave)
    local facing = point.facing
    if facing == 0 then
        local url = require("mvtk.prefabs.prefab_utils").get_player_url()
        local pos = url and go.exists(url) and go.get_world_position(url)
        facing = pos and pos.x < point.position.x and -1 or 1
    end
    local overrides = {group_id="encounter_" .. self.encounter_id .. "_w" .. wave,
        facing=facing, elite=point.elite}
    if not self.enemy_drops then overrides.drops = "none" end
    return require("mvtk.enemies.enemy_spawn_service").spawn({owner=self.owner, room_id=self.room_id,
        enemy_type=point.enemy_type, archetype=point.archetype ~= "" and point.archetype or nil,
        size=point.size, position=point.position, max_enemies_per_room=0,
        settle_to_ground=true, overrides=overrides})
end

function M.init(self)
    self.owner = "encounter:" .. self.room_id .. ":" .. self.encounter_id
    if self.clear_flag == "" then self.clear_flag = "encounter_cleared_" .. self.encounter_id end
    self.runtime = Runtime.new({
        start=function()
            if self.lock_room then
                require("mvtk.bosses.fight_lock").seal(self.room_id, self.owner)
                self._sealed = true
                msg.post("main:/room_manager#script", "lock_room", {room_id=self.room_id, source=self.owner})
            end
            local Music = require "mvtk.bosses.boss_music"
            Music.push(self.owner, {music_theme=self.battle_music}, Music.PRIORITY.encounter)
        end,
        wave=function(number, total)
            if self.show_wave_messages and self.settings.show_wave_messages then
                toast(self, "encounter.wave", {wave=number, total=total})
            end
        end,
        telegraph=function(point)
            local effect = point.telegraph_effect ~= "" and point.telegraph_effect or self.settings.telegraph_effect
            if effect ~= "" then require("mvtk.fx.fx").play(effect, point.position) end
        end,
        spawn=function(point, wave) return spawn(self, point, wave) end,
        outcome=function(id) return require("mvtk.enemies.enemy_spawn_service").outcome(id) end,
        count_alive=function() return require("mvtk.enemies.enemy_spawn_service").count_alive(self.owner) end,
        count_defeated=function() return require("mvtk.enemies.enemy_spawn_service").count_defeated(self.owner) end,
        list=function() return require("mvtk.enemies.enemy_spawn_service").list(self.owner) end,
        clear=function(count) clear(self, count) end,
        reset=function(reason) release(self, reason) end,
    }, persisted(self))
    -- Capture a normal callback, never a lifecycle global (the engine clears those).
    self.reset = function(reason)
        self.inside = false
        Runtime.reset(self.runtime, reason, persisted(self))
    end
    require("mvtk.world.trigger_bus").register(self.encounter_id, self.url)
end

local function start(self)
    if not require("mvtk.game.game_manager").is_playing() then return end
    if self.runtime.state ~= "idle" and not (self.repeatable and self.runtime.state == "cleared") then return end
    if self.requires_flag ~= "" and not require("mvtk.core.flags").has(self.requires_flag) then return end
    local Settings = require "developer.config.runtime_settings"
    self.settings = Settings.section("encounter_settings", require "developer.config.encounter_settings")
    local settings = {start_delay=self.start_delay, spawn_telegraph_time=self.settings.spawn_telegraph_time,
        wave_delay=self.wave_delay >= 0 and self.wave_delay or self.settings.wave_delay,
        max_alive=self.max_alive > 0 and self.max_alive or self.settings.max_alive}
    Runtime.start(self.runtime, Registry.points(self.room_id, self.encounter_id), settings, self.repeatable)
end

function M.update(self, dt)
    local Pause = require "mvtk.core.pause"
    if Pause.get() or not require("mvtk.game.game_manager").is_playing() then return end
    local Rooms = require "mvtk.map.streaming.room_manager"
    if not self.lock_room and Rooms.get_current_room() ~= self.room_id
        and self.runtime.state ~= "idle" and self.runtime.state ~= "cleared" then
        self.reset("room_exit"); return
    end
    if self.inside and self.encounter_start == "on_enter" and self.runtime.state == "idle"
        and Rooms.get_current_room() == self.room_id then
        local url = require("mvtk.prefabs.prefab_utils").get_player_url()
        local pos = url and go.exists(url) and go.get_world_position(url)
        -- Resolve collider sizes once per settings revision, not every frame.
        local Settings = require "developer.config.runtime_settings"
        if self._settings_revision ~= Settings.revision() then
            self._player_settings = Settings.get_player_settings()
            self._settings_revision = Settings.revision()
        end
        local p, tiles = self._player_settings, require "developer.config.tile_settings"
        if require("mvtk.game.boss_setup").room_entry_clear(pos, Rooms.get_room_bounds(self.room_id),
            p.collider_half_width, p.collider_half_height, tiles.width, tiles.height, Rooms.get_room_doors(self.room_id)) then
            start(self)
        end
    end
    Runtime.update(self.runtime, dt * Pause.dt_scale())
end

function M.on_message(self, id, message)
    if id == hash("encounter_reset") then self.reset(message.reason or "reset"); return end
    if id == hash("trigger_response") and message.other_group == hash("player") then
        self.inside = message.enter
        if not message.enter and self.repeatable and self.runtime.state == "cleared" then
            Runtime.reset(self.runtime, "rearm")
        end
        return
    end
    if self.encounter_start ~= "on_signal" then return end
    local signal = require("mvtk.world.switch_state").read_signal(message)
    if (signal and signal.on) or (not signal and id == hash("activate")) then start(self) end
end

function M.final(self)
    release(self, "final")
    require("mvtk.world.trigger_bus").unregister(self.encounter_id, self.url)
    self.reset = nil
end

return M
