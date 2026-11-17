-- developer/config/config_schema.lua
-- Lightweight, human-readable schema to surface inline help for common config files.
-- Add/extend here to keep tooltips/docs in sync with config expectations.

local Schema = {
    ["achievements.lua"] = {
        desc = "Optional per-game profile goals: source names, descriptions and category names, hidden rows, event filters and state triggers, grant-text rewards and sound-bank unlock feedback.",
        fields = {"enabled", "notify", "show_hidden_count", "sfx", "categories", "achievements"},
    },
    ["countdowns.lua"] = {
        desc = "Countdown events: labels (120 bytes), positive durations, start_when conditions, timeouts (death, restart or return_safe), finish flags, once-only grant rewards, best times, music, tint, save and travel blocking, warning times and sound-bank feedback ids.",
        fields = {"warning_sfx", "finish_sfx", "fail_sfx", "tenths_below", "autosave_on_finish", "return_fade_out", "return_fade_in", "result_duration", "countdowns"},
    },
    ["npc_settings.lua"] = {
        desc = "Living NPC settings: whether opted-in NPCs show the new-dialogue marker, and its source texts for new lines and for lines that start or turn in a quest; whether ambient lines (barks) show and for how long; and how long wandering NPCs pause at each end.",
        fields = {"markers", "barks", "wander"},
    },
    ["goals.lua"] = {
        desc = "Optional ordered goals: stable ids, source titles (120 bytes), Journal text and hints (1024 bytes), nonempty done_when requirements and an optional objective or marker target. Ships off and empty.",
        fields = {"enabled", "hint_reveals_target", "goals"},
    },
    ["shops.lua"] = {
        desc = "Purchase catalogs with shared stock, grant text, integer prices, item costs, flags and optional confirmations; autosave, sell_share from 0 to 1, bank transfer steps and autosave, and sound-bank feedback ids.",
        fields = {"settings", "catalogs"},
    },
    ["upgrades.lua"] = {
        desc = "Named permanent upgrades: max_health, max_energy, max_stamina, damage_mult and acyclic prerequisite upgrade ids.",
        fields = {"upgrades"},
    },
    ["items.lua"] = {
        desc = "Inventory ids, translated names and descriptions, integer buying/selling base price, optional sellable flag, uniqueness, Quick Use healing, use time in seconds and reveal radius in world pixels.",
        fields = {"id", "name", "desc", "price", "sellable", "unique", "quick_use", "heal", "use_time", "reveal_radius"},
    },
    ["combat_music.lua"] = {
        desc = "Optional combat layer: registered default_track or room combat_music (inherit/none), living same-room proximity count/radius/min_time or player hits, quiet release_delay, fade_in/fade_out >= 0.5 seconds, and ignore_spawned. Boss, champion and encounter music win; explicit music blocks combat until the next room. Pause freezes timers.",
        fields = {"enabled", "default_track", "engage", "release_delay", "fade_in", "fade_out", "ignore_spawned"}
    },
    ["encounter_settings.lua"] = {
        desc = "Default wave timing, living cap, telegraphs, toasts and clear autosaves",
        fields = {"wave_delay", "max_alive", "spawn_telegraph_time", "telegraph_effect",
            "show_wave_messages", "toast_duration", "autosave_on_clear"},
    },
    ["status_effects.lua"] = {
        desc = "Transient statuses: positive durations and tick intervals, damage per stack, walking speed [0.25,1], immune ids and RGB tick tints. Death and respawn clear statuses. No save data.",
        fields = {"enabled", "defaults", "effects", "player", "bosses", "feedback"}
    },
    ["damage_types.lua"] = {
        desc = "Damage vocabulary and families, RGB colours, outgoing enemy/boss factors, player_taken [0,10], optional ability_taken [0.1,10], target tags, attack defaults/infusions and water types. Lethal player hits bypass type factors; hazard protection is separate.",
        fields = { "weak_multiplier", "resist_multiplier", "types", "player_taken", "ability_taken", "tag_multipliers", "player_attacks", "player_attack_infusions", "water_types", "feedback" }
    },
    ["carry_settings.lua"] = {
        desc = "Carry and throw: hold height in player collider half heights, throw angles in degrees, return delay in seconds, kind impact damage/tags and bomb radius in tiles. Per-object speed multiplier floor 0.25; blank carry animations retain normal states.",
        fields = { "hold_above_ratio", "throw_angle", "up_throw_angle", "return_delay", "kinds", "animations" }
    },
    ["movement_zone_types.lua"] = {
        desc = "Movement Zone presets: gravity_mult [0.1,3], max_fall_mult [0.01,3], speed_mult and jump_mult [0.25,3]. sink_speed is nonnegative px/s; escape_jumps permits repeated floorless jumps. Tiled -1 inherits; overlapping zones keep the strongest value per key.",
        fields = { "gravity_mult", "max_fall_mult", "speed_mult", "jump_mult", "sink_speed", "escape_jumps" }
    },
    ["progression_analysis.lua"] = {
        desc = "Analyze Progression: light_ability gates entry into rooms marked requires_light and warns for unmarked darkness 1 rooms. Blank disables both light rules; darkness alone never gates progression.",
        fields = { "light_ability", "max_states", "max_seconds", "start", "default_preset", "presets", "rooms", "objectives", "ui" }
    },
    ["lighting.lua"] = {
        desc = "Dark rooms: Light mask reveals art near lights and permits full black at max_darkness 1. Glow only keeps the 0.9 tint ceiling. RGB colours, falloff, mask resolution, optional additive glow, atlas shape and brightest-light cap.",
        fields = { "mode", "max_darkness", "shadow_color", "light_color", "falloff", "mask_scale", "glow_with_mask", "light_shape", "max_lights" }
    },
    ["positional_audio.lua"] = {
        desc = "Positional ambience: camera/player listener, gain fade per second, quiet threshold, stereo strength and pan distance in pixels (0 follows half the visible world width).",
        fields = { "listener", "fade_per_second", "stop_below_gain", "pan_strength", "pan_distance_px" }
    },
    ["healing.lua"] = {
        desc = "Quick Use: flask, items or channel, charges, heal amount and drink time in seconds; rest/respawn refills; movement multiplier minimum 0.25, air/water and cancellation rules, sound IDs and FX. channel sets health per heal, shared energy cost, seconds per heal, held repeat and tutorial event; Max energy 0 prevents channel healing. quick sets item order, empty-selection fallback and hold step repeat. energy optionally grants energy on accepted player hits, parries and defeats in every model, capped by Max energy; 0 disables gains. Energy is not saved. Initial hold time is default_bindings.hold_seconds.QUICK_USE.",
        fields = { "model", "heal_name", "flask", "use", "quick", "hint_event", "channel", "energy" }
    },
    ["world_lint.lua"] = {
        desc = "Cross-room flag ledger: flags.errors defaults false (warnings); true blocks preparation, validation and Build. flags.allow lists exact custom-script flags or prefix_* patterns. pacing: enabled, max_rooms_without_save (room hops from a save point, checkpoint, fast travel station or the start room) and dead_end_info; warnings only.",
        fields = { "flags", "pacing" }
    },
    ["reward_text.lua"] = {
        desc = "Grant notices: entry separator, {name}/{count} formats, duration in seconds, and hidden kinds.",
        fields = { "separator", "count_format", "fast_travel_format", "notice_duration", "hidden_kinds" }
    },
    ["menu_settings.lua"] = {
        desc = "List menus: rows per page (1-12), hold and stick repeat times in seconds, sound ids, default pause rule, book titles and pause policies. Navigation lists physical action ids; their first keyboard and controller inputs supply prompts. Older screens combine Back and Close. controller_disconnect_text is the pause info line when the controller in use disconnects.",
        fields = { "navigation", "list", "pause_while_open", "books", "controller_disconnect_text" }
    },
    ["default_bindings.lua"] = {
        desc = "Action defaults and ordered Controls rows. Each keyboard/controller slot reads its whole input list from actions; player/optional control visibility. hold_seconds maps actions to 0.05-5 second tap/hold thresholds. Pad buttons have one owner; Guide and key_r cannot be defaults.",
        fields = { "inputs", "actions", "remappable", "hold_seconds" }
    },
    ["player_settings.lua"] = {
        desc = "Player movement/combat tuning. Lantern: ability_id, unscaled world-pixel radius, intensity, flicker fraction and flicker_hz, min_darkness threshold; light colour comes from lighting.lua.",
        fields = {
            "player_scale", "scale_movement", "units_version",
            "walk_speed", "run_speed", "locomotion_animation", "footsteps", "jump_force", "double_jump_enabled",
            "max_health", "max_energy", "friction_ground", "gravity_scale",
            "landing_snap_distance", "head_margin", "collision_response",
            "spine_physics", "wall_climb", "block_grab", "surfaces", "lantern"
        }
    },
    ["game_config.lua"] = {
        desc = "Project-wide player, world, and rendering defaults",
        fields = {
            "player", "swim", "enabled", "require_ability", "ability_id",
            "gravity_mult", "max_fall_speed", "no_swim_sink_speed",
            "no_swim_horizontal_mult", "surface_jump_out", "surface_jump_band",
            "surface_jump_boost",
        }
    },
    ["player_actions.lua"] = {
        desc = "Input → action tuning and cooldowns",
        fields = { "attack", "dash", "air_dash", "wall_jump", "action_tag", "contact_attack", "damage_type" }
    },
    ["combat_config.lua"] = {
        desc = "Player attack data and its pixel-unit generation",
        fields = { "units_version", "default_attack_set", "attacks", "features", "parry", "feedback", "combo" }
    },
    ["combat_overrides.lua"] = {
        desc = "Wizard-generated attack overrides and their pixel-unit generation",
        fields = { "units_version", "combat" }
    },
    ["player_art.lua"] = {
        desc = "Designer player artwork and its display units",
        fields = { "units_version", "source", "mode", "frame_width", "frame_height", "width", "height", "offset_x", "offset_y" }
    },
    ["abilities.lua"] = {
        desc = "Ability unlocks and stamina costs",
        fields = { "double_jump", "dash", "air_dash", "wall_climb", "swim", "glide" }
    },
    ["ability_defaults.lua"] = {
        desc = "Starting ability baseline flags; Project > Game Settings... > Abilities saves overrides",
        fields = { "abilities", "unlocked", "enabled" }
    },
    ["enemy_types.lua"] = {
        desc = "Enemy definitions: stats, AI patterns, drops",
        fields = { "health", "speed", "ai_type", "loot_drops", "aggro_range", "projectile" }
    },
    ["enemy_settings.lua"] = {
        desc = "Global enemy tuning and shared constants",
        fields = { "default_knockback", "spawn_cooldowns" }
    },
    ["boss_types.lua"] = {
        desc = "Boss definitions and phase data",
        fields = { "phases", "attacks", "loot", "intro_cutscene" }
    },
    ["gates.lua"] = {
        desc = "Placed gates/locks mapped to abilities/items",
        fields = { "gate_id", "gate_type", "target_room", "required_action", "required_ability", "required_item" }
    },
    ["gate_types.lua"] = {
        desc = "Gate archetypes and default requirements",
        fields = { "required_action", "required_ability", "required_key", "visual", "sfx" }
    },
    ["hazard_types.lua"] = {
        desc = "Hazard archetypes with damage rates, FX, and SFX",
        fields = { "damage", "damage_interval", "fx", "sfx" }
    },
    ["collectible_types.lua"] = {
        desc = "Collectibles/items definitions",
        fields = { "id", "name", "value", "ability_unlock", "sprite" }
    },
    ["ui_theme.lua"] = {
        desc = "HUD/menu colors, fonts, sizing",
        fields = { "fonts", "colors", "panel", "buttons", "hud" }
    },
    ["hud_layout.lua"] = {
        desc = "HUD element positions/visibility",
        fields = { "health", "energy", "minimap", "boss_health", "notifications" }
    },
    ["stream_settings.lua"] = {
        desc = "Room streaming distances and minimap sampling",
        fields = { "preload_radius", "keep_loaded_radius", "minimap_sampling" }
    },
    ["rooms_config.lua"] = {
        desc = "Generated by Create Rooms: room id to factory URL mapping used by streaming/loading",
        fields = { "factories" }
    },
    ["tile_settings.lua"] = {
        desc = "Base tile dimensions used by streaming/layout; keep in sync with your Tiled tile size",
        fields = { "width", "height", "tile_width", "tile_height", "size", "half_width", "half_height" }
    },
    ["tiled_object_config.lua"] = {
        desc = "Tiled object import paths, offsets, and type mappings",
        fields = { "paths", "y_offsets" }
    },
    ["tileset_mapping.lua"] = {
        desc = "Tileset-to-tilesource mapping for editor imports",
        fields = { "tilesets", "discovered", "get_tilesource" }
    },
    ["render_settings.lua"] = {
        desc = "Render z bands for player, enemies, bosses and imported foreground visuals",
        fields = { "player_z", "enemy_z", "boss_z", "foreground_base_z", "foreground_layer_step", "foreground_object_step" }
    },
    ["ambience_tracks.lua"] = {
        desc = "Background ambience per biome/room",
        fields = { "biome_id", "room_id", "sound", "volume" }
    },
    ["ambient_zones.lua"] = {
        desc = "Ambient zone definitions per room/area",
        fields = { "zones", "track", "volume", "priority" }
    },
    ["sound_bank.lua"] = {
        desc = "Logical SFX/BGM ids mapped to sound resources and defaults",
        fields = { "sfx", "bgm", "settings" }
    },
    ["secret_settings.lua"] = {
        desc = "Global secret and breakable-wall tuning",
        fields = { "wall_defaults", "reveal_fx", "marker" }
    },
    ["secret_types.lua"] = {
        desc = "Secret archetypes such as cracked walls and hidden platforms",
        fields = { "health", "required_action", "fx", "flag" }
    },
    ["secret_rooms.lua"] = {
        desc = "Secret room ids and reveal behavior",
        fields = { "room_id", "reveal_flag", "marker" }
    },
    ["settings_defaults.lua"] = {
        desc = "Default user audio, graphics and gameplay settings; accessibility defaults live in accessibility.lua",
        fields = { "audio", "graphics", "gameplay", "language" }
    },
    ["accessibility.lua"] = {
        desc = "Player accessibility defaults, press-instead-of-hold choices for grab, grapple, heal, run, glide and aim, visible options, reading-text sizes and reduced effect limits",
        fields = { "player", "show", "text_sizes", "reduced" }
    },
}

return Schema
