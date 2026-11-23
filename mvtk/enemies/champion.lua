-- Presentation and room ownership for a baked champion Enemy.
-- Text stays as source/descriptions until the boss GUI renders it.
local Registry = require "mvtk.enemies.champion_registry"
local M = {}
local Champion = {}
Champion.__index = Champion

function M.attach(actor, overrides)
    if actor._champion then return actor._champion end
    if not overrides.champion then return nil end
    local settings = require "developer.config.runtime_settings"
    local cfg = settings.section("enemy_defaults", require "developer.config.enemy_defaults").champion or {}
    local function inherited(key, fallback)
        if overrides[key] ~= nil then return overrides[key] end
        return fallback
    end
    local key = actor.defeat_key
    local room = actor._room_id
    return setmetatable({state="idle", owner="champion:" .. key,
        source="champion:" .. room .. ":" .. key, room_id=room,
        name=overrides.champion_name or {key="champion.name"},
        seal=overrides.champion_seal,
        bar=overrides.champion_bar,
        range=inherited("champion_engage_range", cfg.engage_range or 0),
        threshold=inherited("champion_enrage_below", cfg.enrage_below or 0),
        pattern=overrides.champion_enrage_pattern, music=overrides.champion_music,
        reward=overrides.champion_reward, enrage_sfx=cfg.enrage_sfx}, Champion)
end

function Champion:release(actor, reason)
    require("mvtk.bosses.fight_lock").unseal(self.room_id, self.source)
    if self.sealed then
        msg.post("main:/room_manager#script", "unlock_room", {room_id=self.room_id, source=self.source})
        self.sealed = nil
    end
    if self.state == "engaged" and self.bar then
        require("mvtk.bosses.boss_ui").send(reason == "defeated" and "boss_defeated" or "hide_boss_health",
            {boss_id=self.owner})
    end
    require("mvtk.bosses.boss_music").pop(self.owner)
    Registry.unregister(self)
    self.state = "released"
end

function Champion:reset(actor, reason)
    self:release(actor, reason)
    actor.health = actor.max_health
    actor.stunned_t, actor.poise = 0, 0
    if actor.vel then actor.vel.x, actor.vel.y = 0, 0 end
    require("mvtk.enemies.decision_clock").reset(actor)
    for i=#(actor.patterns or {}),1,-1 do
        if actor.patterns[i] == self.enrage_pattern then table.remove(actor.patterns, i) end
    end
    self.enrage_pattern, self.enraged = nil, nil
    self.state = "idle"
end

function Champion:update(actor, dt, opening_position)
    if actor._dormant or actor._dying or actor.health <= 0 then return end
    local Rooms = require "mvtk.map.streaming.room_manager"
    if Rooms.get_current_room() ~= self.room_id then
        if self.state == "engaged" then self:reset(actor, "room_exit") end
        return
    end
    if self.state ~= "idle" then return end
    local player = require("mvtk.prefabs.prefab_utils").get_player_url()
    if not player or not go.exists(player) then return end
    local pos = go.get_world_position(player)
    -- The native callback reads the cached position from before movement.
    -- On a frame containing several decisions, use each step's own opening.
    local origin = opening_position or go.get_world_position()
    local dx, dy = pos.x-origin.x, pos.y-origin.y
    if self.range > 0 and dx*dx + dy*dy > self.range*self.range then return end
    local Settings = require "developer.config.runtime_settings"
    if self.settings_revision ~= Settings.revision() then
        self.player_settings = Settings.get_player_settings()
        self.settings_revision = Settings.revision()
    end
    local p, tiles = self.player_settings, require "developer.config.tile_settings"
    if not require("mvtk.game.boss_setup").room_entry_clear(pos, Rooms.get_room_bounds(self.room_id),
        p.collider_half_width, p.collider_half_height, tiles.width, tiles.height,
        Rooms.get_room_doors(self.room_id)) then return end
    self.state = "engaged"
    if self.seal then
        require("mvtk.bosses.fight_lock").seal(self.room_id, self.source)
        self.sealed = true
        msg.post("main:/room_manager#script", "lock_room", {room_id=self.room_id, source=self.source})
    end
    if self.bar then
        require("mvtk.bosses.boss_ui").send("show_boss_health", {boss_id=self.owner,
            group_id="champions:" .. self.room_id, priority=1, boss_name=self.name,
            hp=actor.health, hp_max=actor.max_health, total_phases=1})
    end
    if self.music then
        local Music = require "mvtk.bosses.boss_music"
        Music.push(self.owner, {music_theme=self.music}, Music.PRIORITY.champion)
    end
    Registry.register(self, actor)
    self:on_damage(actor)
end

function Champion:on_damage(actor)
    if self.state ~= "engaged" then return end
    if self.bar then require("mvtk.bosses.boss_ui").send("update_boss_health",
        {boss_id=self.owner, hp=actor.health, hp_max=actor.max_health}) end
    if actor.health <= 0 or self.enraged or self.threshold <= 0
        or actor.health > actor.max_health*self.threshold then return end
    self.enraged = true
    local constructor = self.pattern and require("mvtk.enemies.patterns.attack_patterns")[hash(self.pattern)]
    if constructor then
        local pattern = constructor()
        pattern.name = self.pattern
        pattern.role = (require("mvtk.enemies.enemy_behavior_resolver").PATTERN_META[self.pattern] or {}).role
        actor.patterns[#actor.patterns+1] = pattern
        self.enrage_pattern = pattern
    end
    if self.enrage_sfx and self.enrage_sfx ~= "" then require("mvtk.audio.audio").sfx(self.enrage_sfx) end
end

-- Called inside EnemyDefeats' batch; cleanup happens after that batch returns.
function Champion:on_defeat(actor, payload)
    if self.reward and self.reward ~= "" then
        require("mvtk.game.grants").grant(self.reward, {source="champion", reason="champion_defeated",
            once_key="champion:" .. payload.persist_key, position=go.get_world_position()})
    end
end

return M
