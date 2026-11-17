-- mvtk/tiled/tiled_properties_reference.lua
-- ============================================================================
-- Tiled Properties Reference
-- ============================================================================
-- This file documents all supported Tiled object properties for MVTK systems.
-- Use this as a reference when setting up objects in your Tiled maps.
--
-- To use: Add an object layer in Tiled and set the "type" property to one of
-- the supported types below. Then configure additional properties as needed.

local M = {}

-- ============================================================================
-- PROPERTY CATEGORY GUIDE
-- ============================================================================
-- Identity fields name the object for saves, flags, and cross-object links.
-- Runtime fields tune behavior such as health, damage, movement, and timers.
-- Presentation fields select sprites, effects, sounds, prompts, and UI text.
-- Non-character world artwork now comes from collection-image objects. Legacy
-- use_defold_sprite / sprite_atlas fields below are ignored by room generation;
-- see docs/TILED_OBJECT_ART.md for the current authoring workflow.
-- Gating fields connect objects to abilities, items, or game flags.
-- Placement fields use Tiled coordinates, rectangle size, and optional paths.

-- ============================================================================
-- OBJECT TYPES
-- ============================================================================

M.OBJECT_TYPES = {
    -- Player & Spawning
    "player_spawn",     -- Player spawn/start location
    "player_start",     -- Alias for player_spawn
    "respawn_point",    -- Alias for player_spawn
    "checkpoint",       -- Auto-save checkpoint
    "save_point",       -- Manual save and recovery point
    "fast_travel",      -- Activate once, then open travel from the station

    -- Enemies
    "combat_trial",
    "encounter",
    "encounter_spawn",
    "enemy",            -- Single enemy spawn
    "enemy_group",      -- Coordinated group of enemies
    "spawn_point",      -- Respawning enemy point

    -- Bosses
    "boss",             -- Boss with all systems
    "boss_arena",       -- Boss arena mechanics
    "end_game",         -- Baked ending region; completion_id selects game_completion.id.
    "boss_phase",       -- Boss phase definition
    "boss_phase_trigger", -- Boss phase trigger zone
    "boss_weak_point",  -- Targetable weak point
    "arena_boundary",   -- Arena boundary wall
    "boss_add_spawner", -- Boss add spawner

    -- Hazards
    "hazard_return_zone", -- Baked challenge return point
    "hazard",           -- Environmental hazard (generic)
    "spike_hazard",     -- Spike damage zone
    "spikes",           -- Alias for spike_hazard
    "lava_hazard",      -- Lava/fire damage zone
    "lava",             -- Alias for lava_hazard
    "void_hazard",      -- Instant death pit
    "pit",              -- Alias for void_hazard
    "void",             -- Alias for void_hazard
    "breakable_wall",   -- Destructible collision wall
    "breakable_prop",   -- Nonblocking breakable scenery with optional drops

    -- Platforms & Movement
    "zip_line",         -- Baked polyline ride, with terrain collision and streaming
    "socket", -- Baked carryable receiver with optional saved consumption.
    "carryable", -- Baked carry, drop, throw and return objects.
    "movement_zone",    -- Baked leased movement multipliers and sinking escape jumps
    "ice_floor",        -- Baked slippery floor zones; separate from wall ice
    "pendulum_hazard",  -- Baked swinging blades with hazard contact choices
    "wind_current",     -- Player push zones and updraft shafts
    "moving_platform",  -- Platform that moves along a path
    "platform",         -- Alias for moving_platform
    "elevator",         -- Persistent vertical cabin crossing streamed rooms
    "elevator_node",    -- Landing or pass-through route marker
    "crumble_platform",
    "bounce_pad",
    "launch_cannon",
    "conveyor",
    "ladder",           -- Climbable authored volume
    "water_volume",     -- Authored swimming volume
    "air_pocket",       -- Underwater oxygen refill zone
    "teleporter",
    "grapple_point",
    "grapple_surface",   -- Baked rectangle tagging an entire grapple surface
    "grapple_box",       -- Grapple Box: exact static rectangle tagging a hook target
    "grapple_slope",     -- Grapple Slope: exact static polygon tagging a hook target
    "wall_jump_surface", -- Wall that allows wall jump/slide
    "one_way_platform",
    "camera_zone",

    -- Static Collision (physics templates; decoupled from the art tilesheet)
    "collision_box",     -- Solid Box: static box collider sized to the rect
    "collision_slope",   -- Solid Slope: static triangle collider
    "solid",             -- Alias for collision_box
    "ground",            -- Alias for collision_box
    "collision",         -- Alias for collision_box
    "slope",             -- Alias for collision_slope

    -- Stations & Recovery
    "shop",             -- Purchase catalog station
    "upgrade_station",  -- Permanent stat upgrade catalog station
    "bank",              -- Carried and saved banked currency transfers
    "offering_altar",    -- One-time exchange authored on the object
    "skill_trainer",    -- Ability training catalog station
    "health_station",   -- Healing station
    "healing_fountain", -- Alias for health_station
    "energy_station",   -- Mana/energy refill
    "mana_fountain",    -- Alias for energy_station
    "map_station",      -- Map reveal station
    "cartographer",     -- Alias for map_station

    -- Collectibles & Lore
    "lore_item",        -- Journal entry/note
    "collectible",
    "ability",
    "chest",
    "journal_entry",    -- Alias for lore_item
    "note",             -- Alias for lore_item

    -- Interactive Objects
    "npc",              -- Authored dialogue character
    "light_source",
    "torch_holder",
    "map_marker",      -- Minimap/world map marker (POI)
    "pushable_block",
    "pressure_plate",
    "timed_door",
    "sign",
    "lever",
    "strike_switch",
    "warp_statue",
    "hint_stone",
    "gate",
    "locked_door",
    "secret",
    "quest_trigger",
    "countdown_zone",
    "dialogue_trigger",
    "cutscene",

    -- Audio/Visual
    "music_trigger",
    "ambience_zone",
    "particle_emitter",
    "screen_effect_zone",
}

-- ============================================================================
-- ENEMY PROPERTIES
-- ============================================================================
-- Identity: type, enemy_type, template, group_id
-- Runtime: behaviors, movement ranges, chase/attack tuning
-- Placement: facing, patrol_distance, patrol_height

M.ENCOUNTER = {
    type="encounter", encounter_id="", encounter_start="on_enter", requires_flag="", start_delay=0,
    lock_room=true, wave_delay=-1, max_alive=0, enemy_drops=false, show_wave_messages=true,
    battle_music="none", victory_music="none", reward_collectible="none", reward_amount=1,
    clear_flag="", repeatable=false, clear_message="open", target_id="",
}
M.ENCOUNTER_SPAWN = {
    type="encounter_spawn", encounter_wave=1, enemy_type="default", archetype="none",
    spawn_count=1, elite=false, size=-1, spawn_delay=0, spawn_interval=0.5, facing=0, telegraph_effect="none",
}

M.ENEMY = {
    -- Rank: optional champion presentation on this same baked Enemy. The room
    -- seals only after the player clears the doorway; bosses take HUD/music priority.
    champion = false,
    -- Exact source text; blank uses the translated Champion fallback.
    champion_name = "",
    -- Display the name above a priority-1 health bar while engaged.
    champion_bar = true,
    champion_seal = true,
    -- World pixels; -1 inherits enemy_defaults.champion, 0 means the whole room.
    champion_engage_range = -1,
    champion_music = "none",
    -- Grant text (for example currency:25,flag:warden_down), given directly
    -- once with the defeat save; once_key is champion:<persist key>.
    champion_reward = "",
    -- -1 inherits; 0 disables. Adds one attack without replacing the originals.
    champion_enrage_below = -1,
    champion_enrage_pattern = "none",
    -- Required
    type = "enemy",              -- Object type

    -- Enemy Configuration
    enemy_type = "default",      -- Synced art id; choose this first. With archetype=none, a matching preset still supplies stats.
    art = "",                   -- Optional external skin frame path (file); blank or an existing <state>_<NN>.png outside the project. Links art while preserving a deliberate preset.
    weak_to = "",              -- Elements > Weak to: damage_type_flags CSV; blank inherits.
    resist_to = "",            -- Elements > Resists: CSV; default factor 0.5.
    immune_to = "",            -- Elements > Immune to: CSV; zero damage and immune feedback.
    vulnerable_to = "",        -- Elements > Only hurt by: every other type is immune.
    -- Defense: type_default and blank tag lists inherit archetype, then enemy_defaults.defense.
    -- Numeric -1 inherits; tags export as one comma-separated string in enum order.
    guard = "type_default",
    guard_break = "",
    guard_hits = -1,
    swim_speed = -1,
    hop_height = -1,
    hop_interval = -1,
    leash_distance = -1,
    leash_time = -1,
    crawl_speed = -1,
    cling_side = "type_default",
    ambush_style = "type_default",
    ambush_range = -1,
    ambush_trigger_id = "",
    guard_open_time = -1,
    armor_hits = -1,
    armor_requires = "",
    rear_damage_mult = -1,
    -- Stats > Ledge behaviour inherits the archetype, then the project default.
    ledge_behavior = "type_default",
    required_action = "none",
    status_immune = "",        -- Elements: status_effect_flags CSV, added to archetype immunities.
    status_on_hit = "none",    -- Elements: status_effects id; none inherits archetype.
    status_chance = -1,        -- Elements: probability [0,1]; -1 inherits archetype.
    damage_type = "none",      -- Elements > Damage type: inherit preset; defaults physical/contact, projectile/shots.
    archetype = "none",         -- enemy_types.lua key for stats/behaviour; none keeps matching-preset or default_archetype resolution.
    -- On defeat > Respawn: always, room_reload, save or never; type_default uses the archetype, then enemy_defaults.respawn_policy.
    -- Own-line comments: the README generator keys trailing comments by name, and checkpoint/boss reuse these names.
    respawn = "type_default",
    -- On defeat > Defeat flag: ordinary saved story flag, written under every policy; staged gates may count it.
    defeat_flag = "",
    species = "", -- Enemy On defeat: optional species identity; blank keeps art-first identity.
    in_bestiary = true, -- Enemy On defeat: false excludes this enemy from bestiary recording and totals.
    size = -1,                  -- Stats > Size: positive body/art multiplier; -1 inherits. Bakes as instance scale, keeping feet where they are at Size 1.
    template = "elite_slime",    -- Legacy enemy_templates.lua template id; its tank/glass_cannon archetypes are separate from the Tiled Archetype dropdown.

    -- Behavior Configuration
    movement = "type_default",   -- Movement slot; type_default/inherit/legacy none keeps the resolved archetype
    death_behavior = "type_default",
    death_burst_count = -1,
    death_burst_speed = -1,
    split_type = "none",
    split_archetype = "none",
    split_count = -1,
    death_hazard_type = "spikes",
    death_hazard_time = -1,
    summon_enemy_type = "none",      -- Minion art; none inherits the archetype choice.
    summon_archetype = "none",       -- Minion stats/behaviour; none inherits the summon preset.
    summon_count = -1,               -- Attempts per charge; -1 inherits, 0 disables.
    summon_interval = -1,            -- Positive cooldown seconds; -1 inherits.
    summon_max_alive = -1,           -- Living helper cap per owner; -1 inherits, 0 disables.
    summon_max_total = -1,           -- Successful helpers per life; -1 inherits, 0 unlimited.
    spike_offset = 0,               -- Nonnegative seconds into the spike cycle; desynchronizes placements.
    projectile_deflect = "inherit",
    attack_parryable = false,
    reflect_damage_mult = -1,
    aim_mount = "type_default",       -- Inherit the archetype arc; free, floor, ceiling, wall_left or wall_right.
    attack_pattern = "type_default",  -- Primary attack slot; inherits independently from movement
    attack_pattern2 = "type_default", -- Optional second attack; disabled removes the inherited attack in that slot
    behaviors = "ground_patrol,melee_attack",  -- Comma-separated behavior IDs
    behavior_preset = "basic_walker",           -- OR use a preset

    -- Available Behavior IDs:
    --   ground_patrol, fly_patrol, chase_player, melee_attack,
    --   ranged_attack, spread_attack, charge_attack, retreat_when_low,
    --   jump_attack, summon_minions, heal_allies, group_flank

    -- Available Presets:
    --   basic_walker, ranged_shooter, aggressive_charger,
    --   flying_chaser, pack_hunter, hit_and_run

    -- Movement/Combat
    facing = 1,                  -- Initial facing (1=right, -1=left)
    patrol_distance = 200,       -- Distance to patrol from spawn
    patrol_height = 48,          -- Vertical patrol height for hover/patrol_v
    patrol_speed = 50,           -- Patrol movement speed
    chase_range = 300,           -- Range to detect and chase player
    detection_range = -1,        -- Aggro radius; -1 grouped default (or legacy flat 0) inherits the selected type
    chase_speed = -1,            -- Base chase speed in pixels/second; -1 grouped default (or legacy flat 0) inherits
    chase_speed_mult = -1,       -- Positive multiplier applied to resolved chase speed; -1 grouped default inherits
    attack_range = -1,           -- Swipe/attack reach in pixels; -1 inherits the selected type

    -- Per-instance overrides
    difficulty = "none",        -- difficulty enum; none bakes as unset (uses the global/default profile)
    xp_value = -1, -- Nonnegative XP override; negative inherits configured XP.
    drops = "currency:5",       -- Inline CSV drops, used only when loot_table is empty
    loot_table = "",            -- Config loot table; takes precedence over drops when both are supplied

    -- Group Coordination
    group_id = "room_1_guards",  -- Join this coordination group
}

-- ============================================================================
-- ENEMY GROUP PROPERTIES
-- ============================================================================

M.ENEMY_GROUP = {
    -- Required
    type = "enemy_group",        -- Object type

    -- Group Configuration
    group_id = "patrol_squad",   -- Unique group identifier
    enemy_type = "guard",        -- Enemy type for all members
    count = 4,                   -- Number of enemies to spawn

    -- Formation
    formation = "line",          -- "line", "wedge", "circle", "box"
    spacing = 60,                -- Space between enemies (pixels)

    -- Coordination Behavior
    attack_mode = "coordinated", -- "individual", "coordinated", "wave", "limited"
    flank_style = "surround",    -- "surround", "pincer", "line", "arc"

    -- Shared Behaviors
    behaviors = "chase_player,melee_attack,group_flank",
}

-- ============================================================================
-- BOSS PROPERTIES
-- ============================================================================
-- Identity/linking: boss_id, boss_type, arena_id
-- Runtime: health, defense, damage scaling, attacks, transitions
-- Presentation/rewards: visual component, music, drops, unlock flags

M.BOSS = {
    status_immune = "", -- Damage affinities: adds to preset and global boss status immunities.
    -- Damage affinities: damage_type_flags CSV; blank inherits the boss preset.
    weak_to = "", resist_to = "", immune_to = "", vulnerable_to = "",
    -- Required
    type = "boss",               -- Object type

    -- Boss Configuration
    boss_id = "forest_boss", -- Unique boss identifier
    boss_type = "forest_boss",   -- Boss preset id
    arena_id = "forest_arena",   -- Link to boss_arena / arena objects
    boss_visual_type = "sprite", -- Explicit render path: "sprite" or "spine"
    visual_component = "sprite", -- Defold component id to render (sprite/spine based on boss_visual_type)
    max_health = 120,            -- Optional stat override
    defense = 2,                 -- Optional stat override
    damage_resistance = 0.9,     -- Multiplier applied to all incoming boss damage
    -- Combat: -1 inherits preset/defaults; threshold 0 switches stagger off.
    stagger_threshold = -1,     -- Accepted pressure needed to knock the boss down; scales with boss health.
    stagger_time = -1,          -- Seconds the stagger punish window lasts.
    stagger_damage_mult = -1,   -- Incoming damage multiplier during that window.
    parry_stagger = -1,         -- Pressure added by a successful player parry.
    stagger_decay_per_s = -1,   -- Pressure lost per second after the configured decay delay.
    attack_pattern_ids = "root_spike,poison_cloud", -- Fallback CSV if phases omit attacks or none are authored
    show_health_bar = true,      -- Show the boss HUD when this fight starts
    health_bar_position = "top", -- Boss HUD edge: "top" or "bottom"

    -- Boss template > Combat. -1 inherits; 0 disables that recoil axis/recovery.
    contact_knockback_x = -1,    -- Horizontal player recoil speed on body contact, away from the boss.
    contact_knockback_y = -1,    -- Vertical player recoil speed on body contact.
    contact_stun_t = -1,         -- Player recovery seconds on body contact; player feedback override wins.

    -- Boss hit feedback: enable the override to use this group's values.
    override_boss_feedback = false, -- False keeps combat_config/boss_defaults and preset audio.
    boss_hurt_sfx = "enemy_hurt", -- Sound-bank key; blank or none silences confirmed boss hits.
    boss_hitstop = 0.05,         -- Gameplay impact pause in seconds; 0 disables it.
    boss_flash_color = "#ffff4040", -- Tiled color picker; exports #AARRGGBB.
    boss_flash_duration = 0.2,   -- Flash fade duration in seconds; 0 disables it.
    boss_shake = 6,              -- Screen shake magnitude in pixels; 0 disables it.
    boss_rumble = 0.2,           -- Controller rumble strength, 0 to 1; 0 disables it.

    -- Player hit feedback applies only to damage from this boss, including
    -- contact, melee and projectiles. It does not change other enemies.
    override_player_feedback = false, -- False inherits the global player response and attack stun.
    player_hurt_sfx = "player_hurt", -- Sound-bank key; blank or none silences the hurt sound.
    player_hitstop = 0.06,       -- Gameplay impact pause in seconds; 0 disables it.
    player_flash_color = "#ffff4040", -- Tiled color picker; exports #AARRGGBB.
    player_flash_duration = 0.2, -- Flash fade duration in seconds; 0 disables it.
    player_shake = 5,           -- Screen shake magnitude in pixels; 0 disables it.
    player_rumble = 0.18,       -- Controller rumble strength, 0 to 1.
    player_stun_t = 0.2,        -- Recovery seconds; overrides attack/contact stun, 0 disables it.
    player_hurt_animation = "hurt", -- Logical player animation; blank or none skips the reaction clip.
    player_interrupt_attack = true, -- Cancel the current swing and its hitboxes on direct damage.
    player_hurt_decel = 5,      -- Recoil damping per second; lower retains more recoil, 0 keeps its speed.

    -- Audio / rewards
    music_track = "none",       -- boss_music_tracks enum; boss_arena battle_music is the fallback
    victory_music = "none",     -- boss_music_tracks enum; boss_arena victory_music is the fallback
    reward_xp = 0, -- Positive XP override; zero inherits configured XP.
    reward_currency_min = 150,
    reward_currency_max = 250,
    reward_drops = "health_large:1:1.0,gem_large:2:0.5",
    reward_loot_table = "rare",
    reward_unlock_flag = "forest_boss_defeated",
}

-- ============================================================================
-- BOSS ARENA PROPERTIES
-- ============================================================================

M.BOSS_ARENA = {
    -- Required
    type = "boss_arena",         -- Object type

    -- Arena Configuration
    arena_id = "forest_arena",   -- Unique arena identifier
    phases = 3,                  -- Number of boss phases
    camera_lock = false,         -- true locks to the arena center and auto-fits; false follows the player
    camera_priority = 10,        -- Priority over overlapping camera zones (higher wins)
    lock_on_enter = true,        -- Lock the room when the player enters
    unlock_on_clear = true,      -- Unlock after the boss encounter completes
    battle_music = "none",      -- Shared fallback if the boss object leaves music_track unset
    victory_music = "none",     -- Shared fallback if the boss object leaves victory_music unset

    shared_health = false,      -- Health bar: combine already-scaled member health; members keep their own stagger pressure.
    group_name = "",            -- Health bar: translated creator text for the shared bar; blank uses the lead boss name.

    -- Author hazards, boundaries, weak points, and add spawners as their own
    -- Tiled objects. boss_arena only defines the shared arena metadata.
}

-- ============================================================================
-- BOSS PHASE PROPERTIES
-- ============================================================================

M.BOSS_PHASE = {
    type = "boss_phase",         -- Object type

    phase_id = "forest_phase_2",
    boss_id = "forest_boss", -- Optional specific boss id
    boss_type = "forest_boss",   -- Optional preset fallback
    arena_id = "forest_arena",   -- Optional arena link

    phase = 2,
    partner_defeated = false,  -- Health thresholds: another group member starts this boss phase instead of health; health cannot undo it.
    health_min = 0.25,          -- Use -1 / -1 to auto-distribute
    health_max = 0.60,
    attacks = "root_spike,poison_cloud",
    attack_interval_min = 1.5,
    attack_interval_max = 3.0,
    behavior = "aggressive",     -- boss_behaviors enum: aggressive/cautious/defensive/etc.
    speed_multiplier = 1.2,
    damage_multiplier = 1.3,
    stagger_immune = false,     -- Attack sequence: prevents stagger for this boss phase; later boss phases reset it.

    transition_type = "rage",   -- boss_transition_types enum; aliases like power_up/final_form are accepted
    transition_duration = 1.5,
    transition_iframes = 1.2,
    transition_animation = "enrage",
    transition_camera_intensity = 12,
    transition_camera_duration = 0.8,
    transition_flash = true,
    transition_arena_darkness = false,
    transition_spawn_hazards = "spikes",
    transition_new_music = "none",
}

-- ============================================================================
-- BOSS PHASE TRIGGER PROPERTIES
-- ============================================================================

M.BOSS_PHASE_TRIGGER = {
    type = "boss_phase_trigger", -- Object type

    trigger_id = "phase_trigger_01",
    boss_id = "",               -- Preferred boss tag/id target
    boss_type = "",             -- Boss type fallback when boss_id is empty
    arena_id = "",              -- Optional arena id (defaults to active arena)

    phase = 2,                  -- Phase to force
    transition_time = 0,        -- Arena-only transition time; boss still uses its normal phase transition

    trigger_once = true,        -- Trigger once
    requires_flag = "",         -- Require flag to trigger
    set_flag = "",              -- Flag to set after trigger
    delay = 0,                  -- Delay before applying
}

-- ============================================================================
-- BOSS WEAK POINT PROPERTIES
-- ============================================================================

M.BOSS_WEAK_POINT = {
    type = "boss_weak_point",   -- Object type
    use_defold_sprite = true,

    point_id = "core",
    boss_id = "",
    boss_type = "",
    damage_mult = 2.0,
    health = 0,
    exposed_in_phase = 1,
    hidden_in_phase = 0,
    active_phases = "",
    vulnerable = true,
    destroy_flag = "",
    requires_flag = "",
    poll_interval = 0.2,
}

-- ============================================================================
-- ARENA BOUNDARY PROPERTIES
-- ============================================================================

M.ARENA_BOUNDARY = {
    type = "arena_boundary",    -- Object type

    boundary_id = "arena_wall_01",
    arena_ref = 0,              -- Pick a Boss Arena object, or set arena_id below.
    arena_id = "",
    active_phases = "",
    enabled_when_locked = true,
    start_enabled = true,
}

-- ============================================================================
-- BOSS ADD SPAWNER PROPERTIES
-- ============================================================================

M.BOSS_ADD_SPAWNER = {
    type = "boss_add_spawner",  -- Object type

    spawner_id = "boss_adds_01",
    boss_id = "",
    boss_type = "",
    arena_id = "",

    enemy_type = "default",
    spawn_interval = 4.0,
    spawn_count = 1,
    spawn_radius = 120.0,
    max_alive = 3,
    max_total = 0,
    active_phases = "2,3",
    start_delay = 0,
    start_active = true,
    despawn_on_defeat = true, -- Remove adds when the linked encounter ends.
    movement = "type_default", -- Inherit the enemy type unless overridden.
    attack_pattern = "type_default", -- First attack slot.
    attack_pattern2 = "type_default", -- Second attack slot.

    health_mult = 1.0,
    damage_mult = 1.0,
    speed_mult = 1.0,
}

-- ============================================================================
-- HAZARD PROPERTIES
-- ============================================================================
-- Identity/linking: hazard_type, arena_id, active_phases
-- Runtime: damage, damage_interval, pattern, and ability immunity requirements
-- Presentation: impact sound and phase-driven arena effects

M.HAZARD = {
    status_effect = "none", -- Status > Status effect: none inherits the preset.
    status_duration = -1, -- Seconds; -1 inherits status_effects.lua.
    status_chance = 1, -- Probability [0,1]; effective damage contacts only.
    damage_type = "none",        -- Elements > Damage type: authored text; none omits the override.
    level_mode = "none",          -- none, switch or rise; uses hazard_id as its channel.
    level_offset = 0,             -- Switched height offset in tiles; negative drains.
    level_speed = 96,             -- Switched pixels per second; 0 snaps.
    rise_speed = 48,              -- Rise pixels per second, after Rise delay.
    rise_limit = 4,               -- Tiles above the drawn top.
    rise_start = "signal",        -- signal or first room_enter; never replays saved channels.
    rise_delay = 0,               -- Seconds from the start until the surface moves.
    level_art_layer = "",         -- Decorative painted rows; separate from retract art.

    -- Required
    type = "hazard",             -- Object type

    -- Hazard Configuration
    hazard_type = "spikes",      -- Hazard type from developer/config/hazard_types.lua
    on_contact = "type_default", -- damage, safe_return or kill; inherit the type.
    return_damage = -1,          -- -1 inherits type / Game Settings.
    damage = 1,                    -- Damage per hit
    damage_interval = 0.5,         -- Seconds between damage ticks (alias: damage_cooldown)
    stun_t = -1,                  -- Player recovery seconds: -1 inherits hazard_types[type].stun_t, then combat_config.feedback.hurt.stun_t; 0 disables.
    knockback_force = 300,         -- Knockback strength on contact
    required_resistance = "none", -- Optional ability ID that grants immunity; none means no authored requirement
    instant_kill = false,          -- Bypass normal damage and kill on contact
    enabled = true,                -- Can be controlled by arena/trigger state
    sound_on_hit = "",            -- Optional SFX id played when hazard damages player
    retractable = false,           -- Retract/extend collision and sprite over time
    retract_time = 2.0,
    extend_time = 2.0,
    start_retracted = false,

    -- Path motion (separate from the retract/pattern Motion group)
    motion_type = "none",         -- none, line, path, orbit or slam.
    motion_path_ref = 0,          -- Visible unrotated polyline outside templates; Path starts at its first point.
    motion_pivot_ref = 0,         -- Optional visible point outside templates; Orbit uses this pivot.
    motion_distance_x = 0,        -- Line/Slam travel in pixels; positive is right.
    motion_distance_y = 0,        -- Line/Slam travel in pixels; positive is down.
    motion_radius = 128,          -- Orbit radius when no pivot is picked; centre is this far left.
    motion_speed = 200,           -- Line/Path pixels per second; Orbit degrees per second, negative clockwise.
    motion_offset = 0,            -- Timing offset in seconds at room load; reload resets the cycle.
    motion_wait = 0,              -- Seconds at both Line/Path ends (loop: seam); Slam waits at the top.
    motion_loop = "pingpong",     -- pingpong reverses, loop repeats (Path closes), once holds at the far end.
    slam_warn = -1,              -- Warning seconds; -1 inherits hazard_types.warn_time, then 0.5.
    slam_rest = -1,              -- Bottom hold seconds; -1 inherits crush_hold_time, then 1.
    slam_drop_speed = 1200,      -- Slam drop pixels per second.
    slam_rise_speed = 200,       -- Slam return pixels per second.

    -- Link to Arena (optional)
    arena_id = "",                -- arena.arena_id; blank means unlinked unless boss_id is set.
    boss_id = "",                 -- arena.boss_id; follows one named live boss, stops at its defeat.
    active_phases = "",           -- arena.active_phases; comma-separated boss indices; empty = whole fight.
    hide_when_inactive = true,    -- arena.hide_when_inactive; hides only for the arena gate.
    warn_time = 0,                -- arena.warn_time; harmless pause-aware blink before activation.
    boss_ref = 0,                -- Top-level Boss object link; resolves boss_id.
    arena_ref = 0,               -- Top-level Boss Arena object link; resolves arena_id.

    -- Pattern (for some hazard types)
    pattern = "none",             -- hazard_patterns: none/static stay enabled; wave/random animate activation
    pattern_speed = 1.0,          -- Pattern animation speed
}

-- ============================================================================
-- WATER VOLUME PROPERTIES
-- ============================================================================

M.WATER_VOLUME = {
    type = "water_volume",
    use_defold_sprite = false,
    level_mode = "none",           -- none, switch or rise; rise resets on return/death.
    level_offset = 0,              -- Tiles relative to drawn top; negative drains, positive raises.
    level_speed = 96,              -- Pixels per second; 0 snaps instantly.
    rise_speed = 48,              -- Rising flood speed, pixels per second.
    rise_limit = 4,               -- Rising flood limit, tiles above drawn top.
    rise_start = "signal",        -- signal or room_enter for rising floods.
    rise_delay = 0,               -- Seconds before a rising flood starts.
    level_art_layer = "",         -- Decorative painted layer; rows above the surface hide.
    water_id = "water_01",          -- Stable identifier
    water_type = "water",           -- water_types enum
    swim_enabled = true,
    swim_speed_mult = 0.7,
    damage = 0,
    damage_interval = 1.0,
    current_direction = "none",     -- water_directions enum
    current_strength = 0,
    buoyancy = 0.5,
    water_drag = 0.85,
    oxygen_drain = true,
    oxygen_drain_rate = 1.0,
    surface_y_offset = 0,
    splash_effect = true,
    tint_color = "",
}

M.AIR_POCKET = {
    type = "air_pocket",
    air_pocket_id = "",          -- Optional authored identity; blank uses the baked instance id.
    refill_rate = -1,            -- Oxygen per second; -1 inherits swim_settings.oxygen_refill_rate.
}

-- ============================================================================
-- SPAWN POINT PROPERTIES
-- ============================================================================
-- Identity: spawn_id, enemy_type
-- Runtime: max_count, respawn_delay, activation and despawn behavior
-- Placement: object position plus optional path/polyline references

M.SPAWN_POINT = {
    -- Required
    type = "spawn_point",        -- Object type

    -- Spawn Configuration
    spawn_id = "cave_bats",      -- Unique spawn point ID
    enemy_type = "bat",          -- Enemy type to spawn
    max_count = 3,               -- Max enemies from this point
    respawn_delay = 10.0,        -- Seconds before respawn

    -- Enemy Configuration (inherited by spawned enemies)
    behaviors = "fly_patrol,chase_player",
    template = "",               -- Template to apply
    patrol_distance = 150,
}

M.TELEPORTER = {
    type = "teleporter",
    use_defold_sprite = true,

    teleporter_id = "teleporter_a",            -- Unique teleporter id
    pair_id = "pair_1",                        -- Shared pair/group id
    target_id = "",                            -- Explicit destination teleporter id (optional)
    requires_flag = "",                        -- Flag required before this teleporter can activate
    hide_when_locked = false,                  -- Hide sprite while locked
    active_effect_id = "collectible_sparkle",  -- Looping effect while teleporter is active; blank disables
    unlock_effect_id = "",                     -- One-shot effect when the teleporter becomes available
    require_interact = false,                  -- Auto-teleport on enter when false
    cooldown = 0.5,                            -- Seconds before the same actor can teleport again
    transition_time = 0.0,                     -- Camera transition time
    preserve_velocity = false,                 -- Keep actor velocity after teleport
    facing = 0,                                -- Optional facing override after teleport
    label = "Teleport",                        -- Interaction prompt label
    fade_out = 0.5,                             -- Fade-to-black duration for cross-room travel
    fade_in = 0.5,                              -- Fade-from-black duration after arrival
    one_way = false,                            -- Receive-only teleporter when true
}

M.CAMERA_ZONE = {
    type = "camera_zone",
    zone_id = "camera_zone_01",
    camera_mode = "follow",
    zoom_level = 1.0,
    transition_speed = 1.0,
    bounds_padding = 0,
    lock_x = false,
    lock_y = false,
    focus_x = 0,
    focus_y = 0,
    parallax_override = "",
    smooth_follow = true,
    deadzone_width = 0,
    deadzone_height = 0,
    auto_fit = false,
}

M.COLLECTIBLE = {
    type = "collectible",
    use_defold_sprite = true,
    collectible_type = "currency", -- Required collectible_types id; never use none
    amount = 1,
    set_flag_on_collect = "",
    respawns = false,
}

M.ABILITY = {
    type = "ability",
    use_defold_sprite = true,
    ability_id = "double_jump",    -- optional_abilities enum; none is an authoring error
    show_popup = true,
    popup_title = "",
    popup_description = "",
}

M.CHEST = {
    type = "chest",
    use_defold_sprite = true,
    chest_id = "chest_01",
    chest_type = "wooden",
    contents = "currency:25",
    locked = false,
    requires_key = "none",         -- Optional keys id
    consume_key = true,            -- Use up key; false keeps it after Interact opens the chest
    single_use = true,
    -- Chests are editable baked gameobjects. Locked chests open with Interact;
    -- unlocked chests can also open on touch.
}

M.GATE = {
    type = "gate",
    use_defold_sprite = false,
    gate_id = "gate_01",
    gate_type = "key_gate",         -- gates enum / developer/config/gate_types.lua key
    required_key = "normal",
    required_item = "none",
    required_ability = "none",      -- optional_abilities enum
    required_abilities = "",         -- ability_flags ids, combined with required_ability; comma-separated, no sentinel
    requirement_logic = "all",       -- all needs every distinct ability; any needs one
    group_id = "",                  -- Persistent openings share gate_group_<id> across rooms
    required_action = "none",
    sequence_order = "",             -- comma-separated switch ids for sequence gates
    stage_flags = "",                -- comma-separated saved flags for staged_gate, in any order
    stages_required = -1,            -- -1 = preset; 0 = all listed flags; positive = count
    reset_on_wrong = true,           -- restart the sequence after a wrong switch
    starts_open = false,
    stays_open = true,
    persist_unlock = true,
    open_message = "",
}

M.LOCKED_DOOR = {
    type = "locked_door",
    door_id = "locked_door_01",
    require_ability = "none",       -- optional_abilities enum
    require_key = "none",            -- Optional keys id
    require_item = "none",           -- Optional collectibles id
    consume_key = true,
    unlock_message = "unlock",
    sound_locked = "none",
    sound_unlock = "none",
    starts_locked = true,
}

M.BREAKABLE_WALL = {
    type = "breakable_wall",
    use_defold_sprite = false,
    wall_id = "wall_01",
    wall_type = "cracked",
    health = 3,
    required_ability = "none",      -- optional_abilities enum
    required_damage_type = "none", -- Independent durability gate; exact type or family.
    drop_collectible = "none",      -- Optional collectibles id
    reveals_secret = "",             -- Free-form secret_id, not a sample-map enum
    particle_effect_name = "hit_impact",
    swap_tiles_on_break = true,
    wall_layer = "wall",
    broken_wall_layer = "broken_wall",
    swap_width = 0,
    swap_height = 0,
    sound_break = "wall_break",
}

-- ============================================================================
-- INTERACTION PROPERTIES
-- ============================================================================

M.SIGN = {
    type = "sign",
    use_defold_sprite = true,
    sign_id = "sign_01",
    label = "Read",
    range = 96,
    text = "Welcome to the ruins",
    title = "",
    display_mode = "toast", -- "toast", "dialogue", "tutorial"
    dialogue_id = "",
    duration = 2.5,
    trigger_once = false,
    set_flag = "",
    requires_flag = "",
    sound_id = "",
}

M.NPC = {
    type = "npc",
    use_defold_sprite = true,
    npc_id = "npc_01",
    npc_type = "villager_male",       -- NPC preset from developer/config/npc_types.lua
    npc_name = "NPC",
    npc_sprite = "",
    vendor_shop = "none", -- Vendor: shops.lua catalog; none uses the NPC preset, or disables trading without one.
    vendor_flag = "", -- Vendor: saved flag required to trade; blank allows trading immediately.
    buys_items = true, -- Buys eligible owned items; untick to hide Sell. Shop: Selling; NPC: Vendor.
    sell_share = -1, -- Sale share from 0 to 1; -1 uses Game Settings > Game > Shops > Sell price share.
    vendor_greeting = "first_visit", -- Vendor: first_visit greets once after unlocking; every_visit always greets; never opens directly.
    dialogue_id = "",
    dialogue_text = "",
    facing = 1,
    interaction_range = 48,
    despawn_flag = "",
    show_new_dialogue_marker = false, -- Behavior: show the npc_settings.lua marker while the NPC has unheard lines; talking clears it.
    face_player = false, -- Behavior: turn toward the player within interaction_range; art is assumed drawn facing right.
    barks = "", -- Behavior: short ambient lines separated by |; blank uses the npc_types.lua type's barks.
    bark_range = 96, -- Behavior: pixels from the NPC within which a line shows.
    bark_cooldown = 8, -- Behavior: seconds after a line hides before the next one.
    wander_width = 0, -- Behavior: pixels of floor to pace, centred on the NPC; 0 stands still. No physics: keep it flat.
    wander_speed = 30, -- Behavior: pacing speed in pixels a second.
}

M.LEVER = {
    type = "lever",
    use_defold_sprite = true,
    lever_id = "lever_01",
    target_id = "door_01",
    starts_on = false,
    toggle = true,
    message_on = "activate",
    call_landing = "", -- elevator_call: node_id of the destination floor
    message_off = "deactivate",
    label_on = "Switch On",
    label_off = "Switch Off",
    range = 96,
    cooldown = 0.2,
    set_flag_on = "",
    set_flag_off = "",
    requires_flag = "",
    sound_on = "lever_on",
    sound_off = "lever_off",
    on_animation = "",
    off_animation = "",
    reset_delay = 0,
}

M.STRIKE_SWITCH = {
    type = "strike_switch",
    switch_id = "switch_01", target_id = "door_01", starts_on = false,
    mode = "toggle", timer_seconds = 5, accepts = "any", accept_enemy_hits = false,
    solid = false, cooldown = -1, persist_state = false,
    message_on = "activate", message_off = "deactivate",
    call_landing = "", -- elevator_call: node_id of the destination floor
    set_flag_on = "", set_flag_off = "", requires_flag = "",
    sound_on = "", sound_off = "", sound_reject = "", tick_sound = "",
}

M.BREAKABLE_PROP = {
    type = "breakable_prop", prop_id = "", health = 1, required_ability = "none",
    break_on_interact = false, stays_broken = false, drop_collectible = "none",
    drop_count = 1, drop_chance = 1, set_flag = "", target_ref = 0, target_id = "",
    painted_layer = "", label = "Search", sound_break = "wall_break", art_item = "",
    consume_effect = "none", interact_effect = "none", effect_offset_x = 0, effect_offset_y = 0,
    effect_scale = 1, effect_cooldown = 0,
}

M.ZIP_LINE = {
    type = "zip_line", zip_id = "", path_ref = 0, speed = 800, exit_boost = 0,
    auto_start = false, label = "Ride", range = 96,
    progression_from = "", progression_to = "", progression_one_way = true,
}

M.WARP_STATUE = {
    type = "warp_statue", statue_id = "", label = "Return to checkpoint", range = 96,
    requires_flag = "", cost_currency = 0, cooldown = 1, fade_out = 0.5, fade_in = 0.5,
    sound_warp = "fast_travel", sound_fail = "gate_locked", show_toast = true,
    toast_success = "Returned to your checkpoint", toast_fail = "No checkpoint to return to",
    toast_cost = "", toast_blocked = "You cannot return right now", set_flag = "",
    art_item = "",
}

M.PRESSURE_PLATE = {
    type = "pressure_plate",
    use_defold_sprite = false,
    plate_id = "plate_01",
    target_id = "door_01",
    required_count = 1,
    allow_player = true,
    allow_world = true,
    allow_enemy = false,
    stays_pressed = false,
    message_on = "activate",
    message_off = "deactivate",
    set_flag = "",
    sound_on = "none",           -- Optional sound_effects id
    sound_off = "none",          -- Optional sound_effects id
    anim_tilemap = "",           -- Optional tilemap URL for a visual tile swap
    anim_layer = "",
    anim_offset_x = 0,
    anim_offset_y = 0,
    tile_on = 0,
    tile_off = 0,
}

M.HINT_STONE = {
    type = "hint_stone",
    use_defold_sprite = true,
    hint_id = "hint_01",
    label = "Inspect",
    range = 96,
    title = "Hint",
    body = "",
    position = "top",
    duration = 4.0,
    trigger_once = false,
    set_flag = "",
    requires_flag = "",
    sound_id = "",
    -- Goal hints group (G8-13b): optional; needs developer/config/goals.lua turned on.
    show_current_goal = false, -- Show the current goal's hint instead of body (body when none).
    reveal_goal_target = false, -- Also mark the goal's target on the world map (needs Hints reveal targets).
    goal_hint_cost = 0, -- Currency charged once per goal for its hint; 0 is free. Rereading is free.
}

-- ============================================================================
-- AUDIO/VISUAL PROPERTIES
-- ============================================================================

M.MUSIC_TRIGGER = {
    type = "music_trigger",
    trigger_id = "music_01",
    music_id = "none",
    -- Legacy aliases preserved for old maps only; current templates omit them.
    area_theme = "",
    fade_time = 0.5,
    stop_on_exit = true,
    exit_music = "none",
    exit_area = "",
    trigger_once = false,
}

M.AMBIENCE_ZONE = {
    type = "ambience_zone",
    zone_id = "ambience_01",
    ambience_id = "cave",
    gain = 1.0,
    positional = false, -- True mixes by distance instead of trigger overlap
    falloff_start = 0, -- Pixels beyond rectangle edge before fading
    falloff_end = 640, -- Pixels beyond rectangle edge at minimum volume
    min_volume = 0, -- Gain floor outside falloff_end (0 is silent)
    zone_width = 0, -- Baked from the authored rectangle width in pixels
    zone_height = 0, -- Baked from the authored rectangle height in pixels
    music_volume_percent = 100.0, -- Music volume while the player is in the zone
    stop_on_exit = true,
    trigger_once = false,
}

M.PARTICLE_EMITTER = {
    type = "particle_emitter",
    emitter_id = "emitter_01",
    effect_id = "ambient_sparkle",
    auto_play = true,
    loop = true,
    loop_interval = 0.5,
    start_delay = 0,
    run_duration = 0,
    debug_marker = false,
    debug_follow_player = false,
}

M.SCREEN_EFFECT_ZONE = {
    type = "screen_effect_zone",
    zone_id = "screenfx_01",
    effect_type = "tint", -- "underwater", "darkness", "tint", "shake"
    intensity = 0.5,
    tint_color = "#00000080",
    duration = 0.3,
    trigger_once = false,
    exit_darkness = 0,
    exit_tint = "",
    underwater_overlay = true,
}

-- ============================================================================
-- TRIGGER NOTE
-- ============================================================================
-- Generic authored trigger zones (type = "trigger") are deprecated.
-- Use specialized authored trigger types instead:
--   - cutscene
--   - dialogue_trigger

-- ============================================================================
-- PLAYER SPAWN PROPERTIES
-- ============================================================================

M.PLAYER_SPAWN = {
    type = "player_spawn",          -- Legacy runtime alias. Authoring template player_start.tx emits spawn_point with spawn_type = "player".

    spawn_id = "spawn_a",           -- Unique spawn identifier
    facing = 1,                     -- Initial facing (1=right, -1=left)
    is_default = false,             -- Is this the default spawn for the room?
    requires_flag = "",             -- Only spawn here if flag is set
}

-- ============================================================================
-- CHECKPOINT PROPERTIES
-- ============================================================================

M.CHECKPOINT = {
    type = "checkpoint",            -- Object type
    use_defold_sprite = true,

    checkpoint_id = "checkpoint_01", -- Unique checkpoint identifier
    respawn_facing = 1,             -- Reserved; has no effect on respawn facing yet
    trigger_once = false,           -- If true, only activates once per session
    room_id = "",                   -- Room ID for respawn tracking
    sound_id = "save_point",        -- Sound to play when activated
    particle_id = "ambient_sparkle", -- Particle effect when activated
    requires_flag = "",             -- Optional flag required before activation
    set_flag = "",                  -- Optional flag set on activation
}

M.SAVE_POINT = {
    type = "save_point",
    use_defold_sprite = true,
    save_id = "save_01",            -- Stable save identifier
    display_name = "Save Point",
    heal_on_save = true,
    restore_energy = true,
    is_fast_travel = false,
    show_on_map = true,
    requires_interact = true,
    sound_id = "none",              -- Optional sound_effects id
    particle_id = "none",           -- Optional particle_effects id
}

M.FAST_TRAVEL = {
    type = "fast_travel",
    use_defold_sprite = false,
    station_id = "",              -- Stable text id; required unless the object has a name
    station_name = "Fast Travel", -- Display name in the destination list
    station_description = "",    -- Optional destination description
    auto_unlock = false,         -- Register already unlocked, without an activation rest
    unlock_cost = 0,             -- Currency charged on first manual activation only
    show_on_map = true,           -- Register one bench marker when enabled
    facing = 1,                   -- Arrival facing, 1 or -1
    sound_id = "fast_travel",     -- Optional sound_effects id; none is silent
    label_locked = "Activate",    -- Interact label; a positive cost is appended
    label_unlocked = "Travel",    -- Interact label after activation
    art_item = "",                -- Named artwork, or link an Object Art object
}

M.ONE_WAY_PLATFORM = {
    type = "one_way_platform",
    use_defold_sprite = false,
    direction = "down",
}

M.TIMED_DOOR = {
    type = "timed_door",
    use_defold_sprite = false,
}

-- ============================================================================
-- MOVING PLATFORM PROPERTIES
-- ============================================================================

M.MOVING_PLATFORM = {
    type = "moving_platform",       -- Object type

    platform_id = "platform_01",    -- Unique platform identifier

    -- Path Configuration
    platform_type = "path",         -- "horizontal", "vertical", "path", or "circular"
    path_name = "platform_path",    -- Name of a polyline object in the room
    distance = 0,                    -- Linear travel distance for horizontal/vertical platforms
    speed = 100,                    -- Movement speed (pixels/second)

    -- Movement Modes
    -- "loop"     - Return to start after reaching end
    -- "pingpong" - Reverse direction at each end
    -- "once"     - Stop at final waypoint
    loop_mode = "pingpong",         -- Canonical name (legacy alias: mode)

    -- Timing
    wait = 1.0,                     -- Pause at each waypoint (seconds; legacy alias: wait_time)
    start_delay = 0,                -- Delay before first movement

    -- Player Interaction
    player_parent = true,           -- Player moves with platform

    -- Optional rideable vehicle. Empty/none retains all ordinary platform modes.
    vehicle_control = "",           -- "auto" boards to run; "throttle" projects held stick on track
    vehicle_max_speed = 400,         -- Maximum speed along the track, px/s
    vehicle_acceleration = 600,      -- Acceleration, px/s squared
    vehicle_brake = 1200,            -- Opposing input brakes to rest, px/s squared
    vehicle_drag = 0,                -- No-input drag, px/s squared; 0 coasts
    vehicle_end = "stop",            -- "stop", "return" empty after delay, or "fall_away"
    vehicle_return_delay = 2,        -- Seconds before empty return or hidden respawn
    vehicle_switch_id = "",          -- Text channel selecting the alternate at a forward junction
    vehicle_alt_path = "",           -- Named second polyline; first point on main track within 2 px
    vehicle_rider_walks = false,     -- Throttle rider cannot walk; Jump still leaves
    vehicle_float = false,           -- Ride a registered water surface; rest on the track when drained
    vehicle_float_offset = 16,       -- Pixels the raft's top sits above the surface
    progression_from = "",          -- Same-room analysis area at the start
    progression_to = "",            -- Same-room analysis area at the destination
    progression_one_way = true,      -- False adds an analysis-only reverse connector

    -- Activation
    trigger_id = "",                -- Start moving when triggered
    co_y_offset = 0,                -- Collision object vertical offset
    sensor_y_offset = 0,            -- Trigger sensor vertical offset
    collision_height = 0,           -- Optional collision-height override; 0 uses authored rectangle height
}

-- Cross-room elevators use one rectangle controller around painted cabin art
-- plus one point node in each participating room. Create Rooms extracts the
-- rectangle's environment tiles into a persistent cabin resource.
M.ELEVATOR = {
    type = "elevator",
    elevator_id = "shaft_a",       -- Shared globally unique id
    start_node_id = "shaft_a_bottom", -- Landing where the authored cabin starts

    speed = 96,
    acceleration = 384,
    deceleration = 384,
    endpoint_wait = 0.35,
    start_delay = 0,
    close_time = 0.25,
    open_time = 0.25,
    ready_timeout = 5,

    enabled = true,
    activation_mode = "on_board",
    destination_mode = "next", -- next floor onward, or hold Up/Down with direction
    trigger_id = "",
    require_interact = false,

    floor_offset = 32,              -- Origin-to-floor distance; normally match rectangle height
    co_y_offset = 0,
    sensor_y_offset = 0,
    carry_player = true,
    carry_enemies = false,
    carry_pushables = true,
    require_rider = true,
    shaft_clearance = 0,
    shaft_tolerance = 0.5,

    camera_follow = true,
    camera_lock_x = true,
    camera_look_ahead = 96,
    camera_blend_time = 0.2,
    camera_priority = 50,

    persist_landing = true,
    restore_to_last_landing = true,
    source_layer = "environment",  -- Tile layer containing the painted cabin art
    visual_z = 0.5,
}

M.ELEVATOR_NODE = {
    type = "elevator_node",
    elevator_id = "shaft_a",
    node_id = "shaft_a_bottom",    -- Unique within this elevator route
    landing_label = "",            -- Optional floor name, rendered through DisplayText
    node_kind = "landing",         -- "landing" or "pass_through"
    stop = "bottom",               -- landing: "bottom"/"top"/"middle"; pass-through: "none"
}

M.CRUMBLE_PLATFORM = {
    type = "crumble_platform",
    platform_id = "crumble_01",
    crumble_delay = 0.5,
    respawn_delay = 3.0,
    shake_before_crumble = true,
    one_way = true,
    clear_visual_layer_tiles = true,
    visual_layer = "environment",
    co_y_offset = 0,
    sensor_y_offset = 0,
    sound_crumble = "none",         -- Optional sound_effects id
    sound_respawn = "none",         -- Optional sound_effects id
}

-- ============================================================================
-- BOUNCE PAD PROPERTIES
-- ============================================================================

-- LAUNCH CANNON PROPERTIES (baked trigger; degrees anticlockwise from right).
M.LAUNCH_CANNON = {
    type = "launch_cannon", -- Object type.
    cannon_id = "", -- Blank generates a stable room/object identity.
    aim_mode = "fixed", -- fixed or sweep.
    angle = 45, -- Centre aim in degrees; 90 is up.
    sweep_range = 90, -- Total angle traversed around Angle.
    sweep_speed = 60, -- Degrees per second, ping-pong while loaded.
    fire_on = "jump", -- jump or auto.
    auto_delay = 1, -- Positive seconds loaded before auto fire.
    launch_speed = 2400, -- World pixels per second; leave room for the whole flight.
    control_lock_time = 0.35, -- Seconds without horizontal steering after firing.
    keep_momentum = true, -- Retain horizontal carry after the lock until landing; opposing input brakes.
    cooldown = 0.5, -- Seconds after firing before a new entry can load.
    breaks_action = "", -- Optional actions id accepted by an Action Barrier; no enemy damage.
    sound_id = "", -- Optional sound_effects id played once on firing.
}

M.BOUNCE_PAD = {
    type = "bounce_pad",            -- Object type
    use_defold_sprite = false,

    bounce_speed = 900,             -- Launch speed
    launch_angle = 90,              -- Degrees anticlockwise from right; vertical keeps legacy bounce
    control_lock_time = 0,          -- Seconds without horizontal steering on an angled launch
    keep_momentum = true,           -- Preserve angled launch speed until landing; opposing input brakes
    cooldown = 0.2,                 -- Cooldown between activations
    require_interact = false,       -- Require interact input instead of auto-bounce
    label = "Bounce",               -- Interaction label when require_interact is true
    sound_id = "",                  -- Optional bounce sound id
    range = 80,                     -- Interaction range in pixels
}

-- ============================================================================
-- CONVEYOR PROPERTIES
-- ============================================================================

M.CONVEYOR = {
    type = "conveyor",              -- Object type
    use_defold_sprite = false,

    conveyor_id = "conveyor_01",    -- Stable identifier
    direction = "right",            -- "left", "right", "up", or "down"
    speed = 100,                    -- Push speed in pixels/second
    affects_enemies = true,         -- Push enemy bodies too
    affects_items = false,          -- Push item / collectible bodies too
    enabled = true,                 -- Start enabled
    animation_speed = 1.0,          -- Visual animation multiplier
}

-- ============================================================================
-- LADDER PROPERTIES
-- ============================================================================

M.LADDER = {
    type = "ladder",                -- Object type

    ladder_id = "ladder_01",        -- Stable identifier
    ladder_type = "ladder",         -- ladder, vine, rope, chain, hang_bar or climb_mesh; unknown stays vertical
    climb_speed = 80,               -- Climb speed override
    hang_speed = 260,               -- Pixels/second along a hang_bar; unused on other types
    drop_on_down = true,            -- Down lets go of a hang_bar; unused on other types
    can_jump_off = true,            -- Jump dismounts; on a hang_bar it only lets go (no upward launch)
    snap_to_center = true,          -- Vertical types only; hang_bar and climb_mesh always ignore it
    climb_offset_x = 0,             -- Horizontal nudge for the climbing player: -left, +right, 0 = ladder center
    pass_through_top = true,        -- Allow entering through the top lip; hang_bar always ignores it
    grab_extend_down = 128,         -- Additional grab range below the ladder
    grab_extend_up = 128,           -- Additional grab range above the ladder
}

-- ============================================================================
-- SECRET PROPERTIES
-- ============================================================================

M.SECRET = {
    type = "secret",                -- Object type
    use_defold_sprite = true,

    secret_id = "secret_01",        -- Stable identifier used for persistence
    secret_type = "illusory_wall",  -- Secret type from developer/config/secret_types.lua
    reveals_on = "touch",           -- "touch", "attack", "ability", or "interact"
    required_ability = "none",     -- optional_abilities enum; none means no required reveal ability
    hide_tiles = true,              -- Clear overlapping tiles when revealed
    notification = true,            -- Show the discovery toast
    notification_text = "Secret Found!",
    reward_type = "",               -- Optional collectible reward type from developer/config/collectible_types.lua
    reward_amount = 0,              -- Optional reward amount
    map_reveal = true,              -- Reveal the secret on the map/minimap
}

M.QUEST_TRIGGER = {
    type = "quest_trigger",
    quest_id = "",                 -- Quest id in developer/config/quests.lua.
    trigger_id = "",               -- Blank uses the stable room/object registration id.
    quest = {
        action = "advance",        -- Start, advance, complete or fail the selected quest.
        step_id = "",              -- Blank advances the current step; otherwise it must match.
    },
    playback = { auto_play = true }, -- Otherwise interact while inside the rectangle.
    lifecycle = {
        trigger_once = true,       -- Fire once per loaded trigger after a successful action.
        persist_once = true,       -- Keep the once flag across room reloads and saves.
        once_flag = "",            -- Blank uses an independent generated flag.
        consume_on_fire = true,    -- Disable after a successful action.
    },
    conditions_and_outcomes = {
        requires_quest = "",       -- Optional quest whose state is checked.
        requires_quest_state = "any", -- Any, blank or none skips the state check.
        requires_flag = "",        -- Required flag before the action can fire.
        skip_if_flag = "",         -- Block while this flag is set.
        set_flag = "",             -- Set only after the quest action changes state.
    },
}

M.COUNTDOWN_ZONE = {
    type = "countdown_zone",
    countdown_id = "sample_course", -- Countdown id in developer/config/countdowns.lua.
    role = "start",                -- start begins the countdown; finish ends it with a result; cancel ends it without one.
}

M.DIALOGUE_TRIGGER = {
    type = "dialogue_trigger",
    trigger_id = "dialogue_01",
    dialogue_id = "",
    trigger_once = true,
    persist_once = true,
    once_flag = "",
    consume_on_fire = true,
    auto_play = true,
    delay = 0,
    npc_id = "",
    requires_flag = "",
    skip_if_flag = "",
    set_flag = "",
}

M.CUTSCENE = {
    type = "cutscene",
    cutscene_id = "",             -- Blank: unique tiled_cutscene_<room>_<object id>.
    trigger_id = "",              -- Blank: stable baked registration id.
    content = {
        cutscene_dialogue_id = "", -- Dialogue config id; only used during preparation.
        video_id = "",             -- Video config id; only used during preparation.
        video_play_sound = false,  -- Include the video's audio.
        video_timeout = 12,        -- Video failsafe in seconds.
        cutscene_use_fade = true,  -- Fade to black, wait, then fade back.
        cutscene_wait = 0.2,       -- Seconds between fades.
    },
    playback = { auto_play = true }, -- Otherwise interact while inside the rectangle.
    lifecycle = {
        trigger_once = true,      -- Fire once per loaded trigger.
        persist_once = true,      -- Save the once state across room reloads.
        once_flag = "",           -- Blank uses an independent generated flag.
        consume_on_fire = true,   -- Disable the zone after firing.
    },
    conditions_and_outcomes = {
        requires_flag = "",       -- Must be set before playing.
        skip_if_flag = "",        -- Suppress the scene while this is set.
        set_flag = "",            -- Set when the scene fires.
    },
}


-- ============================================================================
-- HEALTH STATION PROPERTIES
-- ============================================================================

M.SHOP = {
    type = "shop",
    shop_id = "town_vendor",       -- Catalog in developer/config/shops.lua
    buys_items = true, sell_share = -1, -- See the shared selling fields in NPC above.
    prompt_text = "Shop",
    menu_title = "",
    range = 96,
    show_on_map = true,
    requires_flag = "",
    locked_text = "",              -- Creator explanation when access is locked
    art_item = "",
    consume_effect = "none", interact_effect = "none",
    effect_offset_x = 0, effect_offset_y = 0, effect_scale = 1, effect_cooldown = 0,
}

M.UPGRADE_STATION = {
    type = "upgrade_station",
    upgrade_catalog = "forge",       -- Catalog in developer/config/shops.lua
    prompt_text = "Upgrade",
    menu_title = "",
    range = 96,
    show_on_map = true,
    requires_flag = "",
    locked_text = "",              -- Creator explanation when access is locked
    art_item = "",
    consume_effect = "none", interact_effect = "none",
    effect_offset_x = 0, effect_offset_y = 0, effect_scale = 1, effect_cooldown = 0,
}

M.BANK = {
    type = "bank",
    bank_id = "",                 -- Stable identity; blank uses the baked object id
    bank_mode = "both",           -- Deposit, withdraw or both; no purchase catalog
    prompt_text = "Bank",
    menu_title = "",
    range = 96,
    show_on_map = true,
    requires_flag = "",
    locked_text = "",
    art_item = "",
    consume_effect = "none", interact_effect = "none",
    effect_offset_x = 0, effect_offset_y = 0, effect_scale = 1, effect_cooldown = 0,
}

M.OFFERING_ALTAR = {
    type = "offering_altar",
    altar_id = "",                -- Stable saved identity; blank uses the baked object id
    cost_currency = 0,
    cost_item = "",
    cost_item_count = 1,
    reward = "",
    reward_text = "",
    prompt_text = "Offer",
    menu_title = "",
    range = 96,
    show_on_map = true,
    remove_after_use = false,
    requires_flag = "",
    locked_text = "",
    set_flag = "",
    art_item = "",
    consume_effect = "none", interact_effect = "none",
    effect_offset_x = 0, effect_offset_y = 0, effect_scale = 1, effect_cooldown = 0,
}

M.SKILL_TRAINER = {
    type = "skill_trainer",
    trainer_catalog = "training_hall",       -- Catalog in developer/config/shops.lua
    prompt_text = "Train",
    menu_title = "",
    range = 96,
    show_on_map = true,
    requires_flag = "",
    locked_text = "",              -- Creator explanation when access is locked
    leave_when_done = false,       -- Remove the trainer and art after every catalog ability is learned
    art_item = "",
    consume_effect = "none", interact_effect = "none",
    effect_offset_x = 0, effect_offset_y = 0, effect_scale = 1, effect_cooldown = 0,
}

M.HEALTH_STATION = {
    type = "health_station",        -- Object type (or healing_fountain)
    use_defold_sprite = true,

    station_id = "health_01",       -- Unique station identifier
    label = "Heal",                 -- Interaction label
    range = 96,                     -- Interaction range in pixels

    -- Healing Configuration
    heal_amount = 0,                -- HP to restore (0 = full heal)
    heal_percent = 0.0,             -- Percent of max HP (0.0-1.0)
    uses = 0,                       -- Number of uses (0 = unlimited)
    recharge_time = 0,              -- Cooldown between uses (seconds)
    cost_currency = 0,              -- Currency cost to use (0 = free)
    require_interact = true,        -- Requires button press (false = auto trigger)
    requires_flag = "",             -- Flag required to use

    -- Feedback
    sound_id = "collect_health",    -- Sound when used
    particle_id = "collectible_sparkle", -- Particle effect when used
}

-- ============================================================================
-- ENERGY STATION PROPERTIES
-- ============================================================================

M.ENERGY_STATION = {
    type = "energy_station",        -- Object type (or mana_fountain)
    use_defold_sprite = true,

    station_id = "energy_01",       -- Unique station identifier
    prompt_text = "Restore Energy", -- Interaction label
    range = 96,                     -- Interaction range in pixels

    -- Restore Configuration
    restore_amount = 0,             -- Energy/mana to restore (0 = full)
    restore_percent = 0.0,          -- Percent of max energy (0.0-1.0)
    resource_type = "energy",       -- "energy" or "stamina"
    uses = 0,                       -- Number of uses (0 = unlimited)
    cooldown = 0,                   -- Cooldown between uses (seconds)
    cost = 0,                       -- Currency cost to use (0 = free)

    -- Interaction
    require_interact = true,        -- Requires button press

    -- Feedback
    sound_id = "none",              -- Optional sound_effects id
    particle_id = "none",           -- Optional particle_effects id
}

-- ============================================================================
-- MAP STATION PROPERTIES
-- ============================================================================

M.MAP_STATION = {
    type = "map_station",           -- Object type (or cartographer)
    use_defold_sprite = true,

    station_id = "map_01",          -- Unique station identifier
    prompt_text = "Reveal Map",     -- Interaction label
    range = 96,                     -- Interaction range in pixels

    -- Map Reveal Configuration
    reveal_area = "current",        -- Area to reveal ("current" = current room biome)
    reveal_full_biome = true,       -- Reveal all rooms in target biome
    reveal_radius = 320,            -- Fallback world radius if reveal_full_biome is false
    cost = 0,                       -- Currency cost to use (0 = free)
    trigger_once = true,            -- Only works once per save file

    -- Feedback
    sound_id = "collect_map",       -- Sound when used
    particle_id = "marker_placed",  -- Particle effect when used
}

-- ============================================================================
-- LORE ITEM PROPERTIES
-- ============================================================================

M.LORE_ITEM = {
    type = "lore_item",             -- Object type (or journal_entry, note)
    use_defold_sprite = true,

    lore_id = "lore_01",            -- Unique lore identifier (for save tracking)
    prompt_text = "Read",           -- Interaction label

    -- Content
    title = "Ancient Note",         -- Title shown in UI (can be localization key)
    text = "The text content...",   -- Main text (can be localization key)
    category = "notes",             -- Category: notes, journals, lore

    -- Behavior
    auto_pickup = false,            -- Collect on contact (vs require interact)
    destroyable = false,            -- Disappears after reading
    trigger_once = false,           -- Only show once per save
    requires_flag = "",             -- Flag required to read
    unlock_flag = "",               -- Flag to set when read

    -- Feedback
    sound_id = "none",              -- Optional sound_effects id
    particle_id = "none",           -- Optional particle_effects id
}

-- ============================================================================
-- WALL JUMP SURFACE PROPERTIES
-- ============================================================================

M.WALL_JUMP_SURFACE = {
    type = "wall_jump_surface",     -- Object type
    use_defold_sprite = false,

    -- Identity
    surface_id = "wall_surface_01", -- Stable identifier (optional; autogenerated if blank)

    -- Allowed Mechanics
    allow_slide = true,             -- Player can wall slide
    allow_jump = true,              -- Player can wall jump
    allow_climb = true,            -- Player can climb (requires wall_climb ability)

    -- Physics
    slide_speed = -1,              -- Slide-cap multiplier; -1 inherits preset, 0 holds still
    jump_force_x = -1,             -- Horizontal jump speed; -1 inherits, 0 is valid
    jump_force_y = -1,             -- Vertical jump speed; -1 inherits, 0 is valid

    -- Configuration
    facing = 0,                     -- Which direction wall faces (0=either, 1=right, -1=left)
    require_ability = "none",      -- optional_abilities enum; none means always usable
    surface_type = "stone",         -- Wall movement preset: stone, ice, wood, metal; floor ice uses player_settings.surfaces.
}

-- ============================================================================
-- SPIKE HAZARD PROPERTIES
-- ============================================================================

M.SPIKE_HAZARD = {
    type = "spike_hazard",          -- Object type (or spikes)

    hazard_id = "spikes_01",        -- Unique hazard identifier

    -- Damage Configuration
    damage = 1,                     -- Damage per hit
    damage_interval = 0.5,          -- Minimum time between damage ticks
    stun_t = -1,                   -- Player recovery seconds: -1 inherits hazard_types.spikes.stun_t, then combat_config.feedback.hurt.stun_t; 0 disables.
    knockback_force = 300,          -- Knockback force applied to player

    -- Status Effect (optional)
    sound_on_hit = "spike_hit",     -- SFX id on damage

    -- Behavior
    retractable = false,            -- Can retract/extend
    retract_time = 2.0,             -- Time spent retracted
    extend_time = 2.0,              -- Time spent extended
    start_retracted = false,        -- Start in retracted state
}

-- ============================================================================
-- LAVA HAZARD PROPERTIES
-- ============================================================================

M.LAVA_HAZARD = {
    type = "lava_hazard",           -- Object type (or lava)

    hazard_id = "lava_01",          -- Unique hazard identifier

    -- Damage Configuration
    damage = 2,                     -- Damage per tick
    damage_interval = 0.3,          -- Time between damage ticks
    knockback_force = 200,          -- Knockback force

    -- Sound feedback
    sound_on_hit = "burn_sizzle",   -- SFX id on damage

    -- Immunity
    required_resistance = "none",   -- Optional ability ID that grants immunity
}

-- ============================================================================
-- VOID HAZARD PROPERTIES
-- ============================================================================

-- Floor ice changes grounded movement only. Wall Jump Surface's ice preset
-- belongs to wall_surface_types.lua and does not configure slippery floors.
M.PENDULUM_HAZARD = {
    type = "pendulum_hazard",
    pendulum_id = "", -- Unique switch channel; blank uses the baked instance id.
    arc_degrees = 70, -- Total swing angle in degrees around the top-centre pivot.
    swing_seconds = 1.2, -- Seconds for one side-to-side pass; verify in game.
    start_delay = 0, -- Timing offset in seconds before starting the swing.
    start_from_right = false, -- Start at the right end of the arc.
    blade_width = 0, -- 0 uses the authored rectangle width.
    blade_height = 48, -- Blade trigger height in world pixels.
    damage = 1,
    damage_type = "none", -- Damage and knockback group; none sends slash.
    damage_cooldown = 0.5, -- One cooldown shared by all player body parts.
    stun_t = -1, -- -1 inherits the player's configured recovery.
    knockback_force = 300, -- Horizontal force along the swing.
    knockback_lift = 150, -- Upward knockback.
    on_contact = "type_default", -- damage, safe_return or kill; the type default is damage.
    return_damage = -1, -- -1 inherits Game Settings > Game > Hazard returns.
    enabled = true, -- Initial state, then the saved switch channel replays.
}

M.SOCKET = {
    type = "socket", socket_id = "", -- Blank uses the baked instance id.
    target_id = "", target_ref = 0, -- Text channel or same-map receiver object.
    accepts = "any", accepts_id = "", -- Kind filter and optional carry_id.
    message_on = "activate", message_off = "deactivate",
    persist_state = false, persist_key = "", -- Blank key uses room and Tiled id.
    set_flag_on = "", -- One-way ever-filled flag; taking never clears it.
}

M.CARRYABLE = {
    type = "carryable", carry_id = "", -- Blank uses the baked instance id.
    kind = "crate", label = "Pick up", -- Kind from carry_settings.kinds; label uses DisplayText.
    move_speed_mult = 0.8, -- [0.25,1], temporary PlayerStats source carry.
    blocks_jump = false, throw_speed = 900, -- Jump guard and world pixels/second.
    breaks_on_impact = false, break_speed = 1600, -- World pixels/second threshold.
    fuse_time = 3, -- Bomb seconds after first pickup; pause holds the fuse.
}

M.MOVEMENT_ZONE = {
    type = "movement_zone",
    movement_zone_id = "", -- Blank uses the baked instance id; switches target this channel.
    preset = "low_gravity", -- movement_zone_types.lua key: heavy, sticky, sinking also ship.
    gravity_mult = -1, -- -1 inherits; otherwise [0.1, 3].
    max_fall_mult = -1, -- -1 inherits; otherwise [0.01, 3], global terminal only.
    speed_mult = -1, -- -1 inherits; otherwise [0.25, 3].
    jump_mult = -1, -- -1 inherits; otherwise [0.25, 3], after High Jump.
    sink_speed = -1, -- -1 inherits; otherwise nonnegative downward world px/s.
    enabled = true, -- Initial state; switch channels replay on room load.
}

M.ICE_FLOOR = {
    type = "ice_floor",
    ice_id = "", -- Optional authored identifier; the baked zone owns its lease.
    preset = "ice", -- Key in player_settings.surfaces, not wall surface_types.
    accel_mult = -1, -- -1 inherits; otherwise unscaled 0..1 ground acceleration.
    decel_mult = -1, -- -1 inherits; smaller values coast farther.
    turn_brake_mult = -1, -- -1 inherits; smaller values skid farther on reversal.
}

M.WIND_CURRENT = {
    type = "wind_current",
    current_id = "", -- Blank uses this baked instance's id for switch links.
    direction = "right", -- left/right/up/down; use up or down for lift.
    wind_mode = "push", -- push is a velocity bias; lift counters effective gravity.
    push_speed = 300, -- Pixels per second in push mode.
    angle = 0, -- Nonzero degrees override direction for push only.
    lift_gravity_multiple = 1.6, -- Above 1 lifts against gravity in every jump state.
    max_rise_speed = 600, -- Upward lift cap; faster jumps are never reduced.
    on_seconds = 0, -- Both on/off must be positive to cycle; otherwise always on.
    off_seconds = 0, -- Gust off duration in seconds, after the on duration.
    start_delay = 0, -- Seconds before the first gust, frozen while paused.
    enabled = true, -- Initial state; levers and plates can switch it.
}

M.HAZARD_RETURN_ZONE = {
    type = "hazard_return_zone",
    return_zone_id = "", -- Blank generates an identity from room and object.
    return_facing = 0, -- 0 keeps facing, 1 right, -1 left.
    forget_return_point = false, -- Forget this room's challenge start on entry.
}

M.VOID_HAZARD = {
    type = "void_hazard",           -- Object type (or pit, void)

    hazard_id = "pit_01",           -- Unique hazard identifier

    -- Behavior
    instant_kill = true,            -- Instantly kills player
    on_contact = "safe_return",     -- Pit returns; kill ignores protection
    return_damage = -1,             -- Inherit the type or Game Settings

    -- If not instant kill:
    damage = 999,                   -- Damage if not instant kill
    knockback_force = 0,            -- No knockback for pits
}

-- ============================================================================
-- PRINT REFERENCE
-- ============================================================================

function M.print_reference()
    print("=== MVTK Tiled Properties Reference ===")
    print("")
    print("Object Types:")
    for _, obj_type in ipairs(M.OBJECT_TYPES) do
        print("  - " .. obj_type)
    end
    print("")
    print("See mvtk/tiled/tiled_properties_reference.lua for full documentation")
    print("==========================================")
end

-- ============================================================================
-- VALIDATION
-- ============================================================================

--- Validate object properties
-- @param obj Tiled object
-- @return is_valid, errors
function M.validate(obj)
    local errors = {}
    local obj_type = obj.type or (obj.properties and obj.properties.type)

    if not obj_type then
        table.insert(errors, "Missing 'type' property")
        return false, errors
    end

    local valid_types = {}
    for _, t in ipairs(M.OBJECT_TYPES) do
        valid_types[t] = true
    end

    if not valid_types[obj_type] then
        table.insert(errors, "Unknown type: " .. obj_type)
        return false, errors
    end

    -- Type-specific validation
    local props = obj.properties or {}

    if obj_type == "enemy" then
        if not props.enemy_type and not obj.name then
            table.insert(errors, "Enemy needs 'enemy_type' or object name")
        end
    elseif obj_type == "enemy_group" then
        if not props.enemy_type then
            table.insert(errors, "Enemy group needs 'enemy_type'")
        end
    elseif obj_type == "boss" then
        if not props.boss_type then
            table.insert(errors, "Boss needs 'boss_type'")
        end
    end

    return #errors == 0, errors
end

M.COMBAT_TRIAL = {
    type = "combat_trial",
    trial_id = "",           -- Stable saved identity; blank uses the baked object id.
    trial_name = "",         -- Source name for the trial.
    encounter_ref = 0,       -- Linked Encounter; blank chooses the smallest containing Encounter.
    label = "Begin trial",  -- Source interaction prompt.
    range = 96,             -- Interaction distance in world pixels.
    trial_goal = "clear",    -- Clear every wave, defeat a count, or survive until the limit.
    defeat_target = 10,      -- Linked enemies to defeat for defeat_count.
    time_limit = 0,          -- Seconds; zero means no limit. Survive needs a positive limit.
    no_damage = false,       -- Fail on the first accepted hit.
    rank_1 = -1,            -- First rank threshold; seconds, or hits for survive. -1 disables it.
    rank_2 = -1,            -- Second rank threshold; at or below earns this rank. -1 disables it.
    rank_3 = -1,            -- Third rank threshold; at or below earns this rank. -1 disables it.
    disabled_abilities = "", -- Ability-use limits; unlock-only abilities are reported by Prepare & Check.
    disabled_attacks = "",   -- Attack action tags to block; movement tags need ability limits instead.
    trial_reward = "",       -- First-clear grant text, such as currency:25; blank grants nothing.
    clear_flag = "",         -- Blank uses trial_cleared_<trial_id>.
    requires_flag = "",      -- Optional saved flag required before starting.
    art_item = "",           -- Catalog art or linked Object Art; blank leaves an invisible pedestal.
}

-- World state (G8-09). The 18 most common templates carry these three fields in
-- a "World state" group (npc, collectible, ability_pickup, key, chest,
-- lore_item, map_fragment, sign, hint_stone, map_marker, dialogue_trigger,
-- teleporter, save_point, gate, locked_door, breakable_wall, light_source and
-- torch). Any other baked object may carry them as plain custom properties.
-- A condition is a comma list that must all hold; each term is flag, !flag,
-- ability:<id> or item:<id>[:n], and | joins alternatives inside one term.
-- Blank or none means no condition. Create Rooms bakes a <id>__presence
-- companion beside every object with a condition.
M.WORLD_STATE = {
    appear_when = "",          -- Object exists only while this condition holds.
    remove_when = "",          -- Object is removed once this condition holds.
    presence_timing = "enter", -- enter: change shows when the room is next built; live: remove at once.
}

return M
