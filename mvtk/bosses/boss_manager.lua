--- Boss Manager
-- Central controller for all boss encounters
-- Handles spawning, phases, health, and defeat
--
-- @module boss_manager

local Util = require "mvtk.core.util"
local SafeSound = require "mvtk.audio.safe_sound"
local CombatFeedback = require "mvtk.combat.combat_feedback"
local DamageCalc = require "mvtk.combat.damage_calc"
local Multipliers = require "mvtk.combat.multipliers"
local GameEvents = require "mvtk.core.game_events"
local BossStagger = require "mvtk.bosses.boss_stagger"
local Logger = require "mvtk.core.logger"

local M = {}
M.groups = {}
local log = Logger.get_logger("BOSS_MANAGER")

-- Debug-gate all print() calls in this module so they only fire when enabled.
local _orig_print = print
local _Dbg = Util.require_config("developer.config.debug_config")
local function print(...)  -- luacheck: ignore 121
    if _Dbg.bosses and _Dbg.bosses.manager then
        _orig_print(...)
    end
end

local boss_types = Util.require_config("developer.config.boss_types")
-- Static require so Defold's bundler includes this framework file.
local attack_patterns = require "mvtk.bosses.patterns.attack_patterns"
local AttackScale = require "mvtk.bosses.attack_scale"
local TileSettings = require "developer.config.tile_settings"
local user_pattern_names = {}

-- Merge user-defined patterns from developer/config/attack_patterns.lua on top
-- of the framework patterns. User patterns override framework ones by name.
do
    -- Literal require: Bob builds only literal requires (AUDIT_BUILD_BUNDLING row 6).
    local user_patterns = require "developer.config.attack_patterns"
    if type(user_patterns) == "table" then
        for name, pat in pairs(user_patterns) do
            attack_patterns[name] = pat
            user_pattern_names[name] = true
        end
    end
end

-- Validate attack pattern library at load-time. Bad patterns surface here
-- instead of as silent failures mid-fight. Validation never throws.
do
    local PatternSchema = require "mvtk.bosses.attack_pattern_schema"
    if PatternSchema and PatternSchema.validate_all then
        local count, errors = PatternSchema.validate_all(attack_patterns)
        for _, err in ipairs(errors or {}) do
            _orig_print("[BOSS_MANAGER] attack_patterns: " .. tostring(err))
        end
        if count > 0 and #errors == 0 then
            _orig_print(string.format(
                "[BOSS_MANAGER] validated %d attack patterns OK", count))
        end
    end
end
local BossUI = require "mvtk.bosses.boss_ui"
local BossMusic = require "mvtk.bosses.boss_music"
-- Literal require: the named load failed in dev builds and installed a stub that
-- never granted boss i-frames (AUDIT_BUILD_BUNDLING row 5).
local Invulnerability = require "mvtk.combat.invulnerability"
local BossDefaults = Util.require_config("developer.config.boss_defaults", {
    iframes_on_hit = 0.2,
    iframes_on_phase_transition = 1.5,
    defeat_cleanup_delay = 2.0,
})
local Time = require "mvtk.core.time"
local Flags = require "mvtk.core.flags"

-- Storage
local active_bosses = {}  -- boss_id -> {type, health, phase, state_machine, etc.}
local boss_id_counter = 0
local encounter_metrics = {
    player_damage_taken = 0,  -- tracks damage during the current live encounter
    tracking_active = false,
}

local function has_undefeated_bosses()
    for _, boss in pairs(active_bosses) do
        if boss and not boss.defeated then
            return true
        end
    end
    return false
end

local function begin_encounter_tracking()
    encounter_metrics.player_damage_taken = 0
    encounter_metrics.tracking_active = true
end

local function stop_encounter_tracking()
    encounter_metrics.tracking_active = false
end

local function reset_encounter_tracking()
    encounter_metrics.player_damage_taken = 0
    encounter_metrics.tracking_active = false
end

-- Configuration
local config = {
    show_health_bar = true,
    enable_phase_transitions = true,
}

local function normalize_health_bar_position(value)
    local raw = Util.trim(value)
    if raw == "" then
        return nil
    end

    local position = string.lower(raw)
    if position == "top" or position == "bottom" then
        return position
    end

    return nil
end

local function boss_health_bar_enabled(boss)
    if not config.show_health_bar then
        return false
    end
    if boss and boss.config and boss.config.show_health_bar ~= nil then
        return Util.to_bool(boss.config.show_health_bar, true)
    end
    return true
end

local function trim_string(value)
    local s = Util.trim(value)
    if s == "" then
        return nil
    end
    return s
end

local function copy_table(value)
    if type(value) ~= "table" then
        return {}
    end
    if Util.deep_copy then
        return Util.deep_copy(value)
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

local function resolve_boss_preset(preset_id)
    local preset = trim_string(preset_id)
    if preset and type(boss_types[preset]) == "table" then
        return preset, copy_table(boss_types[preset])
    end

    if preset then
        print(string.format("[BOSS_MANAGER] Unknown boss preset '%s' - falling back to default authored baseline", preset))
    end

    local default_preset = type(boss_types.default_boss) == "table" and boss_types.default_boss or nil
    if default_preset then
        return nil, copy_table(default_preset)
    end

    return nil, {
        name = "Boss",
        max_health = 100,
        defense = 0,
        damage_resistance = 1.0,
        boss_visual_type = "sprite",
        visual_component = "sprite",
        phases = {
            {
                health_range = { min = 0.0, max = 1.0 },
                attacks = {},
                attack_interval = { min = 2.0, max = 4.0 },
                behavior = "aggressive",
                speed_multiplier = 1.0,
                damage_multiplier = 1.0,
            },
        },
    }
end

local function resolve_boss_display_name(config, preset_id, fallback_id)
    if type(config) ~= "table" then
        return fallback_id or preset_id or "Boss"
    end

    return trim_string(config.name)
        or trim_string(config.boss_name)
        or trim_string(config.display_name)
        or trim_string(config.spawn_name)
        or trim_string(config.boss_id)
        or trim_string(config.spawn_id)
        or trim_string(config.boss_tag)
        or trim_string(preset_id)
        or fallback_id
        or "Boss"
end

local function resolve_boss_identity_id(boss, fallback_id)
    return require("mvtk.bosses.boss_identity").runtime(boss, fallback_id)
end

-- Music is now delegated to mvtk/bosses/boss_music.lua.
-- Thin wrappers keep the internal call-sites unchanged.
local function start_boss_music(boss, boss_id)
    if boss and boss.config and boss.config.audio then
        BossMusic.push(boss_id, boss.config.audio, BossMusic.PRIORITY and BossMusic.PRIORITY.boss)
    end
end

local function stop_active_music(boss_id)
    BossMusic.pop(boss_id)
end

--- Initialize boss manager
-- @param custom_config Optional configuration overrides
function M.init(custom_config)
    if custom_config then
        for k, v in pairs(custom_config) do
            config[k] = v
        end
    end

    print("[BOSS_MANAGER] Initialized")
end

--- Spawn a boss
-- @param boss_type Optional preset id from boss_types.lua. Nil/empty means
--        "spawn a Tiled-authored boss using baseline defaults plus custom_config".
-- @param position World position
-- @param custom_config Optional config overrides
-- @return boss_id or nil if failed
function M.spawn_boss(boss_type, position, custom_config)
    local had_live_bosses = has_undefeated_bosses()

    local preset_id, type_def = resolve_boss_preset(boss_type)

    -- Generate unique ID
    boss_id_counter = boss_id_counter + 1
    local boss_id = "boss_" .. boss_id_counter

    -- Merge configs
    local final_config = copy_table(type_def)
    if custom_config then
        for k, v in pairs(custom_config) do
            if (k == "audio" or k == "on_defeat" or k == "size")
                and type(v) == "table"
                and type(final_config[k]) == "table" then
                local merged = {}
                for kk, vv in pairs(final_config[k]) do
                    merged[kk] = vv
                end
                for kk, vv in pairs(v) do
                    merged[kk] = vv
                end
                final_config[k] = merged
            else
                final_config[k] = v
            end
        end
    end

    final_config.name = resolve_boss_display_name(final_config, preset_id, boss_id)
    final_config.boss_name = final_config.name
    final_config.boss_preset = trim_string(final_config.boss_preset) or preset_id

    local health_factor = Multipliers.get("boss_health")
    local max_health = (final_config.max_health or 100) * health_factor
    -- Create boss data
    local boss = {
        id = boss_id,
        type = trim_string(final_config.spawn_id)
            or trim_string(final_config.boss_id)
            or trim_string(final_config.boss_tag)
            or preset_id
            or boss_id,
        preset_id = preset_id,
        position = position,
        config = final_config,

        -- Stats
        max_health = max_health,
        health = max_health,
        defense = final_config.defense or 0,
        damage_resistance = final_config.damage_resistance or 1.0,
        stagger = BossStagger.configure(BossDefaults.stagger, type_def.stagger, custom_config, health_factor),

        -- State
        invulnerable = false,
        stunned = false,
        defeated = false,

        -- Modifiers (changed by phases)
        speed_multiplier = 1.0,
        damage_multiplier = 1.0,
        available_attacks = {},

        -- Cooldowns
        attack_cooldowns = {},

        -- Spawned time
        spawn_time = Time.gettime(),
    }

    require("mvtk.combat.actor_elements").configure(boss, type_def, custom_config)

    -- Optional tag for external references (Tiled, spawners, triggers)
    boss.tag = final_config.boss_tag or final_config.spawn_id or final_config.boss_id or final_config.tiled_id
    boss.spawn_id = final_config.spawn_id or boss.tag
    boss.boss_type = boss.type

    -- Store boss
    active_bosses[boss_id] = boss
    CombatFeedback.register_boss(boss_id, final_config.player_hit_feedback)

    -- Start a fresh encounter only when no other live boss is active.
    if not had_live_bosses then
        begin_encounter_tracking()
    end

    print(string.format("[BOSS_MANAGER] Spawned %s (%s) at (%.0f, %.0f)",
        tostring(final_config.name), tostring(preset_id or "tiled_authored"), position.x, position.y))

    local Group = require "mvtk.bosses.boss_group"
    Group.join_pool(M.groups, active_bosses, boss_id)

    -- Show boss health bar
    if boss_health_bar_enabled(boss) then
        M.show_boss_health_bar(boss_id)
    end

    local group_key = Group.key(boss)
    local first_member = not group_key or #Group.live_members(active_bosses, group_key) == 1
    -- The first (sorted lead) member owns the encounter's music and arena.
    if first_member then start_boss_music(boss, group_key or boss_id) end

    -- Lock arena doors if configured
    if first_member and final_config.arena then
        M.lock_arena(final_config.arena, final_config.room_id)
    end

    -- Auto-setup arena runtime (hazards, platforms, effects) from
    -- developer/config/boss_arenas.lua so users don't have to call
    -- BossArena.setup_arena manually in their room scripts.
    local arena_id = final_config.arena_id or final_config.arena
    if first_member and arena_id then
        local ArenaCfg = Util.require_config("developer.config.boss_arenas", {})
        local arena_def = (ArenaCfg.arenas and ArenaCfg.arenas[arena_id]) or ArenaCfg[arena_id]
        local BossArena = Util.require_module("mvtk.bosses.boss_arena")
        local existing_arena = BossArena and BossArena.get_arena and BossArena.get_arena(arena_id) or nil

        -- Prefer a Tiled-authored arena that was already registered during room
        -- import. Fall back to developer/config/boss_arenas.lua only when no
        -- runtime arena record exists yet.
        if not existing_arena and arena_def and BossArena and BossArena.setup_arena then
            -- Config phase_hazards are not spawned: arena hazards are Tiled
            -- hazards with active_phases. Prepare & Check warns when set.
            pcall(BossArena.setup_arena, arena_id, {
                boss_id = boss_id,
                bounds = arena_def.bounds,
                phases = arena_def.phases or {},
                on_phase_change = arena_def.on_phase_change,
            })
        end

        if BossArena and BossArena.get_arena and BossArena.get_arena(arena_id) then
            -- Activate the arena so transition_to_phase / apply_phase
            -- actually run (they early-return when active_arena is nil).
            if BossArena.activate_arena then
                pcall(BossArena.activate_arena, arena_id)
            end
            if BossArena.apply_phase then
                pcall(BossArena.apply_phase, 1)
            end
        end
    end

    return boss_id
end

local function send_stagger(boss)
    if boss.shared_pool then return end
    if boss.stagger.threshold > 0 and boss_health_bar_enabled(boss) then
        boss.stagger.sent_fraction = BossStagger.fraction(boss.stagger)
        boss.stagger.sent_staggered = boss.staggered == true
        BossUI.send("update_boss_stagger", {boss_id = boss.id,
            fraction = boss.stagger.sent_fraction, staggered = boss.stagger.sent_staggered})
    end
end

local function add_stagger(boss, amount)
    local state = boss.state_machine and boss.state_machine.current_state
    if boss.defeated or boss.stagger_immune or boss.staggered
        or state == "transitioning" or state == "defeated" then return end
    if BossStagger.add(boss.stagger, amount) and boss.go_url then
        msg.post(boss.go_url, "mvtk_boss_stagger", {duration = boss.stagger.stun_time})
    end
    if boss.stagger.threshold > 0 then send_stagger(boss) end
end

-- Called only after the script's pause gate; no per-frame settings copies.
function M.tick_stagger(boss_id, dt)
    local boss = active_bosses[boss_id]
    if not boss or boss.defeated then return end
    BossStagger.tick(boss.stagger, dt)
    if boss.stagger.sent_fraction ~= BossStagger.fraction(boss.stagger)
        or boss.stagger.sent_staggered ~= (boss.staggered == true) then send_stagger(boss) end
end

--- Damage a boss
-- @param boss_id Boss identifier
-- @param damage Damage amount
-- @param source Damage source
-- @return true, applied amount, affinity verdict on an accepted hit
function M.damage_boss(boss_id, damage, source)
    if require("mvtk.core.pause").get() then return false end
    local boss = active_bosses[boss_id]

    if not boss or boss.defeated then
        return false
    end

    -- A parry reaction is not a damage hit, even if its payload has damage.
    if type(source) == "table" and source.source_attack == "parry_stun" then
        if not Invulnerability.is_invulnerable(boss) then
            add_stagger(boss, boss.stagger.parry_amount or 0)
        end
        return false
    end
    if damage <= 0 then
        return false
    end

    local dot = type(source) == "table" and source.damage_over_time == true
    -- Check if vulnerable (timer-driven i-frames or hard flag)
    if not dot and Invulnerability.is_invulnerable(boss) then
        return false
    end

    -- DoT bypasses stances and shields, and never contributes pressure.
    if not dot and boss.parry_active then
        local pattern = boss.parry_counter_pattern
        boss.parry_active, boss.parry_counter_pattern = false, nil
        if boss.go_url then msg.post(boss.go_url, "mvtk_boss_counter", {pattern = pattern}) end
        return true, 0
    end

    -- Apply defense
    local final_damage = dot and damage or math.max(1, damage - boss.defense)

    -- Apply global resistance multiplier (from boss_types config)
    final_damage = final_damage * boss.damage_resistance

    local dtype = type(source) == "table" and (source.damage_type or source.dtype) or nil
    local scaled, immune, verdict = DamageCalc.apply(final_damage, dtype, { target = "boss", profile = boss._elements })
    -- A placed weak point displays the final number at its own position.
    local numbers = not (type(source) == "table" and source.weak_point_numbers == true)
    if immune then
        require("mvtk.combat.actor_elements").feedback(0, boss.position, dtype, "immune", boss.anim_url, numbers, boss.go_url)
        return false, 0, "immune"
    end
    final_damage = scaled
    if DamageCalc.damage_probe then DamageCalc.damage_probe(boss_id, final_damage) end

    -- The probe intentionally counts absorbed damage; accepted-hit energy does not.
    if not dot and (boss.shield_hp or 0) > 0 then
        boss.shield_hp = math.max(0, boss.shield_hp - final_damage)
        if boss.shield_hp == 0 then
            boss.shield_expires_at = nil
            if boss.go_url then msg.post(boss.go_url, "mvtk_boss_shield_break") end
            add_stagger(boss, boss.stagger.shield_break_amount or 0)
        end
        return true, 0, verdict
    end
    if boss.staggered and boss.stagger.threshold > 0 then
        final_damage = final_damage * (boss.stagger.damage_mult or 1)
    end

    -- Apply damage
    require("mvtk.bosses.boss_group").apply_damage(active_bosses, boss, final_damage)
    if final_damage > 0 and damage > 0 and not (type(source) == "table" and source.source_attack == "parry_stun") then
        GameEvents.emit("enemy_damaged", {
            amount = final_damage,
            by_player = require("mvtk.combat.damage_payload").source_is(source, require("mvtk.core.constants").URL.PLAYER),
            boss = true, defeated = boss.health <= 0, over_time = dot,
        })
    end
    require("mvtk.combat.status_effects").on_hit(boss.go_url, type(source) == "table" and source or nil, "boss", boss._status_immune)

    -- Start i-frames so rapid multi-hits can't stunlock / delete health.
    -- Per-attack override: source.iframes_on_hit; else boss config; else defaults.
    local iframes = (type(source) == "table" and source.iframes_on_hit)
        or (boss.config and boss.config.iframes_on_hit)
        or BossDefaults.iframes_on_hit
    if not dot and iframes and iframes > 0 then
        Invulnerability.start(boss, iframes, "hit")
    end

    print(string.format("[BOSS_MANAGER] %s took %.1f damage (%.0f / %.0f)",
        boss.id, final_damage, boss.health, boss.max_health))

    -- Update health bar
    if boss.shared_pool or boss_health_bar_enabled(boss) then
        M.update_boss_health_bar(boss_id)
    end

    -- Feedback belongs to accepted damage so weak points also trigger it.
    -- Preserve custom component audio, otherwise use the configured sound bank.
    if not dot then
        local feedback = Util.deep_copy(boss.config.boss_hit_feedback or {})
        if not boss.config.boss_hit_feedback and boss.config.audio and boss.config.audio.hurt then
            SafeSound.play(boss.config.audio.hurt)
            feedback.sfx = false
        end
        CombatFeedback.impact("boss_hurt", final_damage, feedback)
        if boss.anim_url then
            local color = feedback.flash_color or boss.config.hurt_flash_color or BossDefaults.hurt_flash_color
            local duration = feedback.flash_duration or boss.config.hurt_flash_duration or BossDefaults.hurt_flash_duration
            if color and duration and duration > 0 then
                msg.post(boss.anim_url, "anim.flash", {
                    color = vmath.vector4(color[1], color[2], color[3], color[4]),
                    duration = duration,
                })
            end
        end
    end -- DoT uses the status ticker flash and no per-hit hurt feedback.

    require("mvtk.combat.actor_elements").feedback(final_damage, boss.position, dtype, verdict,
        not dot and boss.anim_url or nil, numbers, boss.go_url, source, boss.config.boss_hit_feedback)

    if not dot and boss.health > 0 then
        local weak_mult = type(source) == "table" and source.weak_point and (boss.stagger.weak_point_mult or 1) or 1
        add_stagger(boss, final_damage * weak_mult)
    end

    -- Check if defeated
    require("mvtk.bosses.boss_group").finish_damage(active_bosses, boss_id, source, M.kill_boss)

    return true, final_damage, verdict
end

--- Kill a boss
-- Two-phase defeat: on_defeat_start fires immediately (cinematic window),
-- then after defeat_cleanup_delay on_defeat_complete fires (rewards, cleanup).
-- @param boss_id Boss identifier
-- @param source What killed the boss
function M.kill_boss(boss_id, source)
    local boss = active_bosses[boss_id]

    if not boss or boss.defeated then
        return
    end

    if boss.go_url then require("mvtk.combat.status_effects").clear(boss.go_url) end
    boss.defeated = true
    boss.health = 0
    boss.defeat_source = source
    boss.defeat_time = Time.gettime()
    boss.encounter_player_damage_taken = encounter_metrics.player_damage_taken

    if not has_undefeated_bosses() then
        stop_encounter_tracking()
    end

    print(string.format("[BOSS_MANAGER] %s defeated!", boss.config.name))

    local Group = require "mvtk.bosses.boss_group"
    local group_key = Group.key(boss)
    Group.partner_defeated(active_bosses, boss_id)
    local members = Group.encounter_members(active_bosses, boss_id)
    local group_last = not group_key or Group.is_last(active_bosses, group_key)
    local dead_count = 0
    for _, id in ipairs(members) do
        if active_bosses[id].defeated then dead_count = dead_count + 1 end
    end
    boss.group_defeat_order = dead_count
    boss.group_final_member = group_last
    local boss_type_id = resolve_boss_identity_id(boss, boss_id)
    if group_last then
        -- Only the final kill commits the encounter, before delayed cleanup.
        local CP = require "mvtk.core.checkpoint"
        local saved, save_error = CP.batch("boss_defeated", function()
            for _, member_id in ipairs(members) do
                local member = active_bosses[member_id]
                local boss_type_id = resolve_boss_identity_id(member, member_id)
                local rewarded, reward_error = pcall(M.process_defeat_rewards, member_id, member.defeat_source)
                if not rewarded then log.warn("Boss rewards failed: %s", tostring(reward_error)) end
                if member.config.on_defeat and member.config.on_defeat.unlock_flag then
                    M.set_unlock_flag(member.config.on_defeat.unlock_flag)
                end
                Flags.set("boss_defeated_" .. tostring(boss_type_id), true)
                GameEvents.emit("boss_defeated", {
                    boss_id = boss_type_id, preset = member.preset_id or "", room_id = member.config.room_id or "",
                    x = member.position.x, y = member.position.y, xp = (member.config.on_defeat or {}).xp or 0,
                })
                member.group_committed = true
                if #members > 1 then
                    -- Not a literal require: boss_setup requires this module, and Bob refuses require cycles.
                    local setup_module = "mvtk.game.boss_setup"
                    require(setup_module).mark_defeat_scene_seen(boss_type_id, Flags)
                end
            end
        end)
        if not saved then
            log.warn("Boss progress could not be saved: %s", tostring(save_error))
            pcall(msg.post, "main:/toast_gui#toast", "toast", { key = "boss.save_failed" })
        end
        if #members > 1 then boss.group_defeat_scene = Group.defeat_scene(active_bosses, members) end
    end

    -- ---- Phase 1: on_defeat_start (cinematic / dramatic pause) ----

    -- Broadcast so listeners (cutscenes, cameras, UI) can react immediately.
    BossUI.send("boss_defeat_start", {
        boss_id = boss_id,
        boss_name = boss.config.name,
    })
    pcall(msg.post, "main:/main_go#script", hash("boss_defeat_start"), {
        boss_id = boss_id,
        boss_type = boss_type_id,
    })

    -- Play death sound / animation cue
    if boss.config.audio and boss.config.audio.death then
        SafeSound.play(boss.config.audio.death)
    end

    -- Stop boss music
    if group_last then stop_active_music(group_key or boss_id) end

    -- Optional victory music cue after the boss theme is released.
    if group_last and boss.config.audio and boss.config.audio.victory then
        local Audio = Util.require_module("mvtk.audio.audio")
        if Audio and Audio.music then
            pcall(Audio.music, boss.config.audio.victory, { t = 0.3 })
        end
    end

    if #members > 1 then
        require("mvtk.enemies.enemy_spawn_service").despawn_owner("boss:" .. boss_id, "boss_defeated")
        if boss.shared_pool or boss_health_bar_enabled(boss) then M.hide_boss_health_bar(boss_id) end
    end

    -- Configurable delay before cleanup (gives cinematic / loot time)
    local cleanup_delay = (boss.config.defeat_cleanup_delay)
        or BossDefaults.defeat_cleanup_delay
        or 2.0

    require("mvtk.core.pause").delay(cleanup_delay, function()
        M._on_defeat_complete(boss_id, source, boss_type_id)
    end)
end

--- Internal: second phase of defeat, called after the cinematic delay.
function M._on_defeat_complete(boss_id, source, boss_type_id)
    local boss = active_bosses[boss_id]
    if not boss then return end
    -- Group adds and slots were already cleaned at the kill.
    local members = require("mvtk.bosses.boss_group").encounter_members(active_bosses, boss_id)
    if #members > 1 and boss.defeat_cleanup_complete then return end
    if #members == 1 then
        require("mvtk.enemies.enemy_spawn_service").despawn_owner("boss:" .. boss_id, "boss_defeated")
    end
    if #members == 1 and boss_health_bar_enabled(boss) then
        M.hide_boss_health_bar(boss_id)
    end

    -- Keep the arena intact until every linked boss has fallen. Authored
    -- arenas take precedence; bosses without one share their room's cleanup.
    local room_id = trim_string(boss.config.room_id)
    local arena_id = trim_string(boss.config.arena_id) or trim_string(boss.config.arena)
    if not trim_string(boss.config.arena_id) and room_id and arena_id == "arena_" .. room_id then
        arena_id = nil -- A synthetic door-lock key still belongs to the room fallback.
    end
    local has_living_partner = false
    for other_id, other in pairs(active_bosses) do
        if other_id ~= boss_id and other and not other.defeated then
            local other_room = trim_string(other.config.room_id)
            local other_arena = trim_string(other.config.arena_id) or trim_string(other.config.arena)
            if not trim_string(other.config.arena_id) and other_room and other_arena == "arena_" .. other_room then
                other_arena = nil
            end
            if (arena_id and other_arena == arena_id)
                or (not arena_id and not other_arena and room_id and other_room == room_id) then
                has_living_partner = true
                break
            end
        end
    end

    if not has_living_partner and (#members == 1 or boss.group_final_member) then
        -- The boss that took the lock may already have been removed. Release
        -- the room's manager lock even when the last boss opted out of locking.
        if boss.config.arena or room_id then
            M.unlock_arena(boss.config.arena, boss.config.room_id)
        end

        -- Tear down arena hazards / platforms so the defeated room is safe to
        -- walk through (no leftover spikes, lava, etc.).
        local BossArena = Util.require_module("mvtk.bosses.boss_arena")
        if BossArena then
            if BossArena.clear_all_hazards then pcall(BossArena.clear_all_hazards) end
            if BossArena.clear_all_platforms then pcall(BossArena.clear_all_platforms) end
            if BossArena.clear_all_effects then pcall(BossArena.clear_all_effects) end
            if BossArena.deactivate_arena then pcall(BossArena.deactivate_arena) end
        end
    end

    boss.defeat_cleanup_complete = true
    -- Broadcast defeat complete
    BossUI.send("boss_defeat_complete", {
        boss_id = boss_id,
        boss_name = boss.config and boss.config.name,
    })
    if #members > 1 then
        if boss.group_final_member and not boss.group_completion_sent then
            boss.group_completion_sent = true
            for index, member_id in ipairs(members) do
                local member = active_bosses[member_id]
                pcall(msg.post, "main:/main_go#script", hash("boss_defeated"), {
                    boss_id = member_id, boss_type = resolve_boss_identity_id(member, member_id),
                    group_id = require("mvtk.bosses.boss_group").key(boss),
                    group_last = index == #members, group_scene = boss.group_defeat_scene,
                })
            end
        end
    else
        pcall(msg.post, "main:/main_go#script", hash("boss_defeated"), {
            boss_id = boss_id, boss_type = boss_type_id,
        })
    end
end

--- Process defeat rewards
-- Supports conditional bonus drops based on fight performance:
--   no_hit_bonus   — extra drops if the player took zero damage
--   time_bonus     — extra drops if the fight lasted less than max_time seconds
--   difficulty_bonus — extra drops if difficulty multiplier >= threshold
-- @param boss_id Boss identifier
-- @param source Who defeated the boss
function M.process_defeat_rewards(boss_id, source)
    local boss = active_bosses[boss_id]
    if not boss or boss.rewards_processed then return end
    local rewards = boss.config.on_defeat

    if not rewards then
        return
    end


    -- Guaranteed grants share validation, compensation and the caller's batch.
    local gives = {}
    if rewards.currency then
        local amount = Multipliers.scale_amount("loot", math.random(rewards.currency.min, rewards.currency.max))
        if amount > 0 then gives[#gives + 1] = "currency:" .. tostring(amount) end
    end
    if rewards.unlock_fast_travel then
        gives[#gives + 1] = "fast_travel:" .. rewards.unlock_fast_travel
    end
    if #gives > 0 then
        -- Not a literal require: grants reaches this module through fast travel, and Bob refuses require cycles.
        local grants_module = "mvtk.game.grants"
        local granted, result = require(grants_module).grant(table.concat(gives, ","), {
            source = "boss", reason = "boss_defeated", durable = false, drop_invalid = true,
        })
        if not granted then log.warn("Boss reward refused: %s", tostring(result and result.message)) end
    end

    -- Spawn standard drops
    if rewards.drops then
        M.spawn_drops(boss.position, rewards.drops, {
            id_prefix = "boss_" .. resolve_boss_identity_id(boss, boss_id) .. "_standard_loot_",
            room_id = boss.config.room_id,
        })
    end

    -- ---- Conditional bonus drops ----
    local fight_duration = boss.defeat_time and boss.spawn_time
        and (boss.defeat_time - boss.spawn_time) or math.huge

    -- No-hit bonus: extra drops when the player wasn't damaged during the fight.
    -- Config example: no_hit_bonus = { drops = { health_up = { chance = 1, amount = 1 } } }
    -- Call M.on_player_damaged() from your player damage handler to track hits.
    if rewards.no_hit_bonus then
        local player_took_damage = (boss.encounter_player_damage_taken
            or encounter_metrics.player_damage_taken) > 0
        if not player_took_damage and rewards.no_hit_bonus.drops then
            print("[BOSS_MANAGER] No-hit bonus drops!")
            M.spawn_drops(boss.position, rewards.no_hit_bonus.drops, {
                id_prefix = "boss_" .. resolve_boss_identity_id(boss, boss_id) .. "_no_hit_bonus_loot_",
                room_id = boss.config.room_id,
            })
        end
    end

    -- Time bonus: extra drops when the fight was completed quickly.
    -- Config example: time_bonus = { max_time = 60, drops = { speed_gem = { chance = 1, amount = 1 } } }
    if rewards.time_bonus and rewards.time_bonus.max_time then
        if fight_duration <= rewards.time_bonus.max_time and rewards.time_bonus.drops then
            print(string.format("[BOSS_MANAGER] Time bonus drops! (%.1fs <= %.1fs)",
                fight_duration, rewards.time_bonus.max_time))
            M.spawn_drops(boss.position, rewards.time_bonus.drops, {
                id_prefix = "boss_" .. resolve_boss_identity_id(boss, boss_id) .. "_time_bonus_loot_",
                room_id = boss.config.room_id,
            })
        end
    end

    -- Difficulty bonus: extra drops on harder difficulties.
    -- Config example: difficulty_bonus = { min_multiplier = 1.2, drops = { rare_gem = { chance = 0.5, amount = 1 } } }
    if rewards.difficulty_bonus and rewards.difficulty_bonus.min_multiplier then
        local ok_diff, Difficulty = pcall(require, "mvtk.core.difficulty")
        local current_mult = ok_diff and Difficulty and Difficulty.get_multiplier and Difficulty.get_multiplier() or 1.0
        if current_mult >= rewards.difficulty_bonus.min_multiplier and rewards.difficulty_bonus.drops then
            print("[BOSS_MANAGER] Difficulty bonus drops!")
            M.spawn_drops(boss.position, rewards.difficulty_bonus.drops, {
                id_prefix = "boss_" .. resolve_boss_identity_id(boss, boss_id) .. "_difficulty_bonus_loot_",
                room_id = boss.config.room_id,
            })
        end
    end

    boss.rewards_processed = true
end

--- Get boss health percentage
-- @param boss_id Boss identifier
-- @return Health as percentage (0.0 to 1.0)
function M.get_boss_health_percent(boss_id)
    local boss = active_bosses[boss_id]
    if not boss then
        return 0
    end

    if boss.shared_pool then return boss.shared_pool.pool / boss.shared_pool.pool_max end
    return boss.health / boss.max_health
end

--- Get boss data
-- @param boss_id Boss identifier
-- @return Boss data or nil
function M.get_boss(boss_id)
    return active_bosses[boss_id]
end

--- Find a live boss by identity/type, or by arena when no boss selector is set.
-- @param criteria table { boss_id?, boss_tag?, boss_type?, id?, arena_id? }
-- @return boss_id or nil
function M.find_boss_id(criteria)
    criteria = criteria or {}
    if criteria.id and active_bosses[criteria.id] and not active_bosses[criteria.id].defeated then
        return criteria.id
    end

    local tag = trim_string(criteria.boss_id) or trim_string(criteria.boss_tag) or trim_string(criteria.tag)
    local boss_type = trim_string(criteria.boss_type) or trim_string(criteria.type)
    local arena_id = not (tag or boss_type or trim_string(criteria.id)) and trim_string(criteria.arena_id)

    for id, boss in pairs(active_bosses) do
        if not boss.defeated then
            if tag then
                if boss.tag == tag or boss.spawn_id == tag then
                    return id
                end
                if boss.config and (boss.config.boss_tag == tag or boss.config.spawn_id == tag or boss.config.boss_id == tag) then
                    return id
                end
            end
            if boss_type and boss.type == boss_type then
                return id
            end
            if arena_id and boss.config and (boss.config.arena_id == arena_id or boss.config.arena == arena_id) then
                return id
            end
        end
    end

    return nil
end

-- The overlay installs actor_probe at runtime. No debug dependency is bundled
-- through this manager or the baked actor scripts.
function M.report_actor(actor, id, world_pos)
    local boss = actor.boss_data
    local state = actor.state_machine and actor.state_machine.current_state or "idle"
    if boss.stagger and boss.stagger.threshold > 0 then
        state = state .. " / stagger " .. tostring(boss.stagger.value) .. "/" .. tostring(boss.stagger.threshold)
    end
    M.actor_probe(id, world_pos,
        state,
        M.get_boss_phase(actor.boss_id) or 1, boss.health, boss.max_health)
end

--- Save/music encounter identity; cleanup retains its wider room fallback.
function M.group_of(boss_id)
    return require("mvtk.bosses.boss_group").key(active_bosses[boss_id])
end

function M.group_live_count(key)
    return #require("mvtk.bosses.boss_group").live_members(active_bosses, key)
end

function M.arena_live_phase(arena_id)
    return require("mvtk.bosses.boss_group").highest_live_phase(active_bosses, arena_id, M.get_boss_phase)
end

function M.should_advance_arena(boss_id, current, next_phase)
    local advance, grouped = require("mvtk.bosses.boss_group").should_advance(active_bosses, boss_id, current, next_phase)
    if advance and grouped then active_bosses[boss_id].group_arena_phase = next_phase end
    return advance, grouped
end

--- Get boss current phase (for phase controller)
-- @param boss_id Boss identifier
-- @return Phase index
function M.get_boss_phase(boss_id)
    local boss = active_bosses[boss_id]
    if not boss or not boss.phase_controller then
        return 1
    end

    return boss.phase_controller:get_current_phase_index()
end

--- Force a boss to a specific phase (if it has a phase controller)
-- @param boss_id Boss identifier
-- @param phase_index Target phase index (1-based)
-- @return true if forced
function M.force_phase(boss_id, phase_index)
    local boss = active_bosses[boss_id]
    if not boss or not boss.phase_controller or not boss.phase_controller.force_phase then
        return false
    end
    boss.phase_controller:force_phase(phase_index)
    return true
end

--- Remove a boss
-- @param boss_id Boss identifier
-- @param retire_defeated Explicit practice re-arm may retire completed group records.
function M.remove_boss(boss_id, retire_defeated)
    CombatFeedback.remove_boss(boss_id)
    if active_bosses[boss_id] then
        print(string.format("[BOSS_MANAGER][MUSIC] remove_boss clearing music for %s", tostring(boss_id)))
        local boss = active_bosses[boss_id]
        local Group = require "mvtk.bosses.boss_group"
        if not retire_defeated and boss.defeated and #Group.encounter_members(active_bosses, boss_id) > 1 then
            -- The actor can disappear before the last kill / delayed cleanup.
            -- Keep its rewards, identity and death order until encounter reset.
            boss.go_url = nil
            -- Defold removes a deleted actor's timers. Its final callback is a
            -- fallback completion boundary if the configured delay has not run.
            M._on_defeat_complete(boss_id, boss.defeat_source, resolve_boss_identity_id(boss, boss_id))
            return
        end
        -- A lone boss's actor can also go before its delayed cleanup: its death animation can end first, and
        -- Defold drops the timers of a deleted script. Its removal is then the completion boundary, so its bar
        -- hides, its doors open and main hears of the defeat; a cleanup timer that survives finds nothing left.
        if not retire_defeated and boss.defeated and not boss.defeat_cleanup_complete then
            M._on_defeat_complete(boss_id, boss.defeat_source, resolve_boss_identity_id(boss, boss_id))
        end
        local owner = Group.key(boss) or boss_id
        active_bosses[boss_id] = nil
        if not Group.key(boss) or Group.is_last(active_bosses, owner) then stop_active_music(owner) end
        if not has_undefeated_bosses() then
            stop_encounter_tracking()
        end
        print(string.format("[BOSS_MANAGER] Removed boss %s", boss_id))
    end
end

--- Get attack pattern definition
-- @param pattern_name Pattern name
-- @return Pattern table or nil
function M.get_attack_pattern(pattern_name)
    return attack_patterns[pattern_name]
end

local CHARGE_PATTERN_OVERRIDES = {
    charge_speed = "dash_speed",
    charge_distance = "dash_distance",
    charge_telegraph_time = "telegraph_time",
    charge_duration = "duration",
    charge_cooldown = "cooldown",
    charge_recovery = "recovery",
    charge_edge_padding = "edge_padding",
}

local POSITIVE_CHARGE_OVERRIDES = {
    charge_speed = true,
    charge_distance = true,
}

local function apply_direct_charge_pattern_overrides(pattern, source)
    for source_key, pattern_key in pairs(CHARGE_PATTERN_OVERRIDES) do
        local value = tonumber(source[source_key])
        local accepts_value = value ~= nil and value >= 0
            and (not POSITIVE_CHARGE_OVERRIDES[source_key] or value > 0)
        if accepts_value then
            pattern[pattern_key] = value
        end
    end
end

local function apply_charge_pattern_overrides(pattern, source)
    if type(pattern) ~= "table" or type(source) ~= "table" then
        return
    end

    -- Also accept an explicit attack_tuning table for hand-authored presets.
    -- Tiled class properties are flattened, so their values are applied by
    -- the second pass and take precedence over this optional nested form.
    if type(source.attack_tuning) == "table" then
        apply_direct_charge_pattern_overrides(pattern, source.attack_tuning)
    end
    apply_direct_charge_pattern_overrides(pattern, source)
end

local function resolve_boss_reference(boss_or_id)
    if type(boss_or_id) == "string" then
        return active_bosses[boss_or_id]
    end
    if type(boss_or_id) ~= "table" then
        return nil
    end
    if type(boss_or_id.boss_data) == "table" then
        return boss_or_id.boss_data
    end
    return boss_or_id
end

local function resolve_phase_reference(boss, phase)
    if type(phase) == "table" then
        return phase
    end
    if type(phase) == "number" then
        local phases = boss and boss.config and boss.config.phases
        return type(phases) == "table" and phases[phase] or nil
    end

    local controller = boss and boss.phase_controller
    if controller and controller.get_current_phase then
        return controller:get_current_phase()
    end
    return nil
end

--- Resolve an independent attack pattern for one boss and phase.
-- Precedence is framework pattern < merged boss preset/Tiled instance config
-- < current Tiled phase. The manager's spawn merge already establishes the
-- preset-versus-instance portion of that ordering.
-- @param pattern_name Pattern name
-- @param boss_or_id Boss manager record, boss script instance, or manager id
-- @param phase Optional phase table/index; defaults to the boss's current phase
-- @return A deep-copied resolved pattern, or nil
function M.resolve_attack_pattern(pattern_name, boss_or_id, phase)
    local base_pattern = attack_patterns[pattern_name]
    if type(base_pattern) ~= "table" then
        return nil
    end

    local boss = resolve_boss_reference(boss_or_id)
    local factor = 1
    if not user_pattern_names[pattern_name] or base_pattern.scale_with_tiles == true then
        factor = tonumber(boss and boss.config and boss.config.attack_pixel_scale)
            or TileSettings.width / 64
    end
    local pattern = AttackScale.scale_pattern(base_pattern, factor)
    if pattern.type ~= "charge" then
        return pattern
    end

    -- Authored charge overrides are already in world pixels, so apply them
    -- after converting the framework pattern into this world's tile units.
    apply_charge_pattern_overrides(pattern, boss and boss.config)
    apply_charge_pattern_overrides(pattern, resolve_phase_reference(boss, phase))
    return pattern
end

--- Check if attack is ready (cooldown)
-- @param boss_id Boss identifier
-- @param attack_name Attack name
-- @param resolved_pattern Optional per-boss/per-phase pattern snapshot
-- @return true if ready
function M.is_attack_ready(boss_id, attack_name, resolved_pattern)
    local boss = active_bosses[boss_id]
    if not boss then
        return false
    end

    local pattern = resolved_pattern or M.resolve_attack_pattern(attack_name, boss)
    if not pattern then
        return false
    end

    local last_used = boss.attack_cooldowns[attack_name]
    if last_used == nil then
        return true
    end
    local current_time = Time.gettime()
    local cooldown = tonumber(pattern.cooldown) or 3.0

    return (current_time - last_used) >= cooldown
end

--- Mark attack as used (start cooldown)
-- @param boss_id Boss identifier
-- @param attack_name Attack name
function M.use_attack(boss_id, attack_name)
    local boss = active_bosses[boss_id]
    if not boss then
        return
    end

    local current_time = Time.gettime()
    boss.attack_cooldowns[attack_name] = current_time
end

--[[============================================================================
    INTEGRATION POINTS
==============================================================================]]

--- Show boss health bar
-- @param boss_id Boss identifier
function M.show_boss_health_bar(boss_id)
    local boss = active_bosses[boss_id]
    if not boss then
        return
    end
    if not boss_health_bar_enabled(boss) then
        return
    end

    print(string.format("[BOSS_MANAGER] Showing health bar: %s", boss.config.name))

    local bar = require("mvtk.bosses.boss_group").bar_state(active_bosses, boss)
    BossUI.send("show_boss_health", {
        stagger = not boss.shared_pool and boss.stagger ~= nil and boss.stagger.threshold > 0,
        stagger_fraction = BossStagger.fraction(boss.stagger),
        staggered = boss.staggered == true,
        boss_id = bar.id,
        group_id = require("mvtk.bosses.boss_group").key(boss) or boss_id,
        priority = 2,
        boss_name = bar.name,
        hp = bar.hp,
        hp_max = bar.hp_max,
        current_phase = bar.lead.phase_controller and bar.lead.phase_controller:get_current_phase_index() or 1,
        total_phases = bar.lead.config.phases and #bar.lead.config.phases or 1,
        health_bar_position = normalize_health_bar_position(boss.config.health_bar_position),
    })

    if BossUI.count() == 0 then
        _orig_print(string.format("[BOSS_MANAGER] WARNING: No boss HUD registered for '%s'. Add a boss health bar GUI or set show_health_bar=false in the boss config.", boss_id))
    end
end

--- Update boss health bar
-- @param boss_id Boss identifier
function M.update_boss_health_bar(boss_id)
    local boss = active_bosses[boss_id]
    if not boss then
        return
    end
    if not boss.shared_pool and not boss_health_bar_enabled(boss) then
        return
    end

    local bar = require("mvtk.bosses.boss_group").bar_state(active_bosses, boss)
    BossUI.send("update_boss_health", {
        boss_id = bar.id,
        hp = bar.hp,
        hp_max = bar.hp_max,
    })
end

--- Hide boss health bar
-- @param boss_id Boss identifier
function M.hide_boss_health_bar(boss_id, force)
    local boss = active_bosses[boss_id]
    if boss and not boss.shared_pool and not boss_health_bar_enabled(boss) then
        return
    end
    if boss and boss.shared_pool and not force
        and not require("mvtk.bosses.boss_group").is_last(active_bosses, boss.shared_pool.key) then return end
    print("[BOSS_MANAGER] Hiding health bar")
    BossUI.send("boss_defeated", {boss_id = boss and require("mvtk.bosses.boss_group").ui_id(boss) or boss_id})
end

--- Re-send boss health bar state to any newly-registered HUD listeners.
-- Useful when the boss spawns before the GUI script has initialized.
function M.refresh_boss_health_bars()
    for boss_id, boss in pairs(active_bosses) do
        if boss and not boss.defeated and boss_health_bar_enabled(boss) then
            M.show_boss_health_bar(boss_id)
        end
    end
end

--- Lock arena doors
-- @param arena_id Arena identifier (optional, may be prefixed with "arena_")
-- @param room_id Room identifier for door locking (preferred)
function M.lock_arena(arena_id, room_id)
    print(string.format("[BOSS_MANAGER] Locking arena: %s", tostring(arena_id)))

    local target_room = room_id
    if not target_room and type(arena_id) == "string" then
        target_room = arena_id:gsub("^arena_", "")
    end

    if target_room and target_room ~= "" then
        pcall(msg.post, "main:/room_manager#script", hash("lock_room"), {
            room_id = target_room,
            source = "boss_manager",
        })
    else
        print("[BOSS_MANAGER] Warning: no room_id provided for arena lock")
    end
end

--- Unlock arena doors
-- @param arena_id Arena identifier (optional, may be prefixed with "arena_")
-- @param room_id Room identifier for door unlocking (preferred)
function M.unlock_arena(arena_id, room_id)
    print(string.format("[BOSS_MANAGER] Unlocking arena: %s", tostring(arena_id)))

    local target_room = room_id
    if not target_room and type(arena_id) == "string" then
        target_room = arena_id:gsub("^arena_", "")
    end

    if target_room and target_room ~= "" then
        pcall(msg.post, "main:/room_manager#script", hash("unlock_room"), {
            room_id = target_room,
            source = "boss_manager",
        })
    else
        print("[BOSS_MANAGER] Warning: no room_id provided for arena unlock")
    end
end

--- Reset all active bosses (e.g., on player death)
-- @param reason Optional reason string for logging
function M.reset_active_bosses(reason)
    local count = 0
    for boss_id, boss in pairs(active_bosses) do
        require("mvtk.enemies.enemy_spawn_service").despawn_owner("boss:" .. boss_id, reason)
        if boss and not boss.defeated then
            -- Unlock arena if it was locked
            if boss.config and boss.config.arena then
                M.unlock_arena(boss.config.arena, boss.config.room_id)
            end
            -- Hide health bar and stop music
            if boss.shared_pool or boss_health_bar_enabled(boss) then
                M.hide_boss_health_bar(boss_id, true)
            end
        end
        stop_active_music(require("mvtk.bosses.boss_group").key(boss) or boss_id)
        active_bosses[boss_id] = nil
        count = count + 1
    end
    M.groups = {}
    reset_encounter_tracking()
    print(string.format("[BOSS_MANAGER] Reset active bosses: %d (reason=%s)", count, tostring(reason)))
    return count
end

--- Reset the fight of one room after the player has left it (a door, a teleport, a warp): what
-- reset_active_bosses does on a death, for that room only. Its live bosses go, and so does a group
-- partner's kill, which only the group's last kill commits. A won fight keeps its records for its save
-- and cleanup, and other rooms' fights are untouched.
-- @return the number of boss records reset, and the set of their arena ids
function M.reset_room_bosses(room_id, reason)
    local Group = require "mvtk.bosses.boss_group"
    local room = Util.normalize_room_id(room_id)
    local count, arenas = 0, {}
    if room == "" then return count, arenas end
    for boss_id, boss in pairs(active_bosses) do
        local cfg = boss and boss.config or {}
        if not boss.group_committed and Util.normalize_room_id(cfg.room_id) == room then
            require("mvtk.enemies.enemy_spawn_service").despawn_owner("boss:" .. boss_id, reason)
            if cfg.arena then
                arenas[cfg.arena] = true
                M.unlock_arena(cfg.arena, cfg.room_id)
            end
            if not boss.defeated and (boss.shared_pool or boss_health_bar_enabled(boss)) then
                M.hide_boss_health_bar(boss_id, true)
            end
            local key = Group.key(boss)
            stop_active_music(key or boss_id)
            if key then M.groups[key] = nil end
            active_bosses[boss_id] = nil
            count = count + 1
        end
    end
    if count > 0 and not has_undefeated_bosses() then
        reset_encounter_tracking()
    end
    print(string.format("[BOSS_MANAGER] Reset %d boss(es) of room %s (reason=%s)", count, room, tostring(reason)))
    return count, arenas
end

--- Award currency to player
-- @param player_id Player identifier
-- @param amount Currency amount
function M.award_currency(player_id, amount)
    local value = math.floor(math.max(0, tonumber(amount) or 0))
    if value <= 0 then
        return true
    end

    local Inventory = Util.require_module("mvtk.core.inventory")
    if not (Inventory and Inventory.add_currency) then
        log.warn("Could not award %d currency; inventory backend is unavailable", value)
        return false
    end

    local ok, err = pcall(Inventory.add_currency, value)
    if not ok then
        log.warn("Could not award %d currency: %s", value, tostring(err))
        return false
    end

    print(string.format("[BOSS_MANAGER] Awarded %d currency", value))
    return true
end

--- Spawn drops at position
-- @param position Drop position
-- @param drops Table of drops { item_id = { chance = 0.5, amount = 1 }, ... }
-- @param opts Stable id_prefix for this boss/reward kind, and owning room_id.
function M.spawn_drops(position, drops, opts)
    opts = opts or {}
    local RewardDrops = require "mvtk.collectibles.reward_drops"
    local types = require "developer.config.collectible_types"
    -- Sorting keeps both identities and circular spread independent of pairs order.
    local keys = {}
    for item_id in pairs(drops) do keys[#keys + 1] = item_id end
    table.sort(keys)
    local created = 0
    for drop_index, item_id in ipairs(keys) do
        local drop_config = drops[item_id]
        local chance = drop_config.chance or 1.0
        local min_amount = tonumber(drop_config.min or drop_config.amount) or 1
        local max_amount = tonumber(drop_config.max or drop_config.amount) or min_amount
        if max_amount < min_amount then max_amount = min_amount end
        local amount = (max_amount > min_amount) and math.random(min_amount, max_amount) or min_amount
        if chance > 0 and math.random() <= chance and amount > 0 then
            local prefix = opts.id_prefix or ("boss_" .. tostring(opts.boss_id or "drop") .. "_loot_")
            local planned = RewardDrops.plan({{type = item_id, amount = amount}}, types,
                prefix .. item_id .. "_")
            for i, drop in ipairs(planned) do
                -- Preserve the original circle for noncurrency units; a grouped
                -- currency pickup occupies the first unit's position.
                local angle = ((drop_index - 1) / math.max(#keys, 1)) * math.pi * 2 + (i * 0.3)
                local spread = 30 + (i * 15)
                local drop_pos = vmath.vector3(
                    position.x + math.cos(angle) * spread,
                    position.y + math.sin(angle) * spread + 20,
                    position.z or 0)
                created = created + RewardDrops.spawn({drop}, drop_pos, {
                    spacing = 0, lift = 0,
                    config = {room_id = opts.room_id, from_boss = true, boss_drop = true},
                })
            end
        end
    end
    return created
end

--- Set unlock flag
-- @param flag_name Flag to set
function M.set_unlock_flag(flag_name)
    print(string.format("[BOSS_MANAGER] Setting unlock flag: %s", flag_name))
    Flags.set(flag_name, true)
end

--[[============================================================================
    UTILITY
==============================================================================]]

--- Get all active bosses
-- @return Table of boss IDs
function M.get_active_bosses()
    local boss_ids = {}
    for boss_id, _ in pairs(active_bosses) do
        table.insert(boss_ids, boss_id)
    end
    return boss_ids
end

--- Get active boss count
-- @return Number of active bosses
function M.get_boss_count()
    local count = 0
    for _ in pairs(active_bosses) do
        count = count + 1
    end
    return count
end

--- Check if any boss is active
-- @return true if at least one boss is active
function M.completion_pending()
    for _,boss in pairs(active_bosses) do
        if not boss.defeated or not boss.defeat_cleanup_complete then return true end
    end
    return false
end
function M.has_active_boss()
    return M.get_boss_count() > 0
end

--- Clear all bosses
function M.clear_all()
    CombatFeedback.clear_bosses()
    print("[BOSS_MANAGER][MUSIC] clear_all -> stop_active_music()")
    stop_active_music()
    active_bosses = {}
    M.groups = {}
    boss_id_counter = 0
    reset_encounter_tracking()
    print("[BOSS_MANAGER] Cleared all bosses")
end

-- A new session (fresh start, another slot, New Game+ or Continue after quit
-- to title) starts with no boss records, so defeated group members of an
-- earlier fight never join a new one, pay their rewards or report again.
function M.before_session_start()
    M.clear_all()
end

--- Print debug info
function M.print_debug()
    print("=== BOSS MANAGER DEBUG ===")
    print(string.format("Active bosses: %d", M.get_boss_count()))

    for boss_id, boss in pairs(active_bosses) do
        print(string.format("  %s (%s): %.0f / %.0f HP (%.0f%%)",
            boss.config.name, boss_id,
            boss.health, boss.max_health,
            (boss.health / boss.max_health) * 100))
    end

    print("==========================")
end

--- Check if a boss identity has been defeated (persistence check)
-- @param boss_type_id Boss preset id or authored boss_id
-- @return true if boss has been defeated in a previous session
function M.is_boss_defeated(boss_type_id)
    return Flags.get("boss_defeated_" .. tostring(boss_type_id)) == true
end

--- Notify the boss manager that the player took damage while a boss is active.
--- Call this from your player damage handler to enable encounter-scoped
--- no-hit bonus tracking.
function M.on_player_damaged()
    if encounter_metrics.tracking_active then
        encounter_metrics.player_damage_taken = encounter_metrics.player_damage_taken + 1
    end
end

return M
