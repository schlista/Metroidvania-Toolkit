-- developer/config/enemy_defaults.lua
-- Centralized defaults for regular (non-boss) enemy behaviour.
--
-- Used as fallbacks whenever a specific enemy in developer/config/enemy_types.lua
-- (or a per-instance Tiled override) does not specify a value. Bosses have their
-- own defaults in boss_defaults.lua.
--
-- Distances are in pixels, except keys ending in _tiles: those count tiles of
-- the project's tile size (developer/config/tile_settings.lua, written by
-- Import Assets), so they keep working when the tile size changes.
-- All times are in seconds.

return {
    -- Enemy tuning inherits the archetype, then these defaults. Features must
    -- be enabled in Game Settings before either mode affects enemy shots.
    projectile_deflect = "destroy", -- none ignores cuts; destroy breaks shots; reflect returns them.
    reflect_damage_mult = -1,       -- -1 uses combat_config.projectiles; nonnegative overrides it.
    -- Champion factors stack with Elite and Size once. Tiled Rank enables a
    -- champion; its optional range/threshold fields use -1 to inherit here.
    -- Each champion's own Tiled Champion seal and Champion bar checkboxes
    -- decide whether it seals the room and shows a bar; neither inherits here.
    champion = {
        health_mult = 3,          -- Positive health factor before difficulty scaling.
        damage_mult = 1.5,        -- Positive contact damage factor.
        scale_mult = 1.2,         -- Positive body/art scale, multiplied by Size and Elite.
        engage_range = 0,         -- World pixels; 0 engages anywhere in the current room.
        enrage_below = 0,         -- Health fraction [0,1]; 0 disables the extra attack.
        enrage_sfx = "",         -- Optional sound_bank.lua id; blank is silent.
    },
    -- Combat deaths only: instance Death effects fields override archetype fields,
    -- then these defaults. Developer kills, pit deaths and unloading run none.
    death_behavior = "none",       -- none, burst, split or hazard.
    death_burst_count = 8,          -- Evenly spaced shots per combat death; 0 disables.
    death_burst_speed = 180,        -- Shot speed in pixels per second, independent of aimed bursts.
    split_type = "default",        -- Synced child art id from enemy_skins_generated.lua.
    split_archetype = "slime",     -- Child stats and behaviour from enemy_types.lua.
    split_count = 2,                -- Child attempts; rejected spawns are not retried.
    split_max_depth = 1,            -- Maximum generations; 1 lets the parent split once.
    split_size = 0.5,               -- Child creation scale relative to the parent's body scale.
    split_spacing_px = 24,          -- Horizontal distance in pixels between adjacent child centres.
    death_hazard_type = "spikes",  -- hazard_types.lua id; contact uses damage semantics.
    death_hazard_time = 3,          -- Positive unpaused seconds before the hazard disappears.
    death_hazard_width = 64,        -- Hazard width in world pixels (not multiplied by enemy Size).
    death_hazard_height = 32,       -- Hazard height in world pixels; the zone is centred on death.

    -- Surface crawling: instance Special movement values override the archetype,
    -- then these defaults. Probe depth is in tiles; speed and clearance are pixels.
    crawl_speed = 60,               -- Pixels per second along the supporting surface.
    cling_side = "floor",          -- floor, ceiling, wall_left, wall_right or free (nearest).
    crawl_skin_px = 1,              -- Clearance from terrain, without scaling.
    crawl_half_height_px = 40,      -- Enemy collision box half-height before body scaling.
    crawl_probe_tiles = 4,          -- Maximum initial attachment search, in tile heights.
    ambush_style = "drop",         -- drop falls, rise plays emerge, disguise keeps its art.
    ambush_range = 160,             -- Reveal distance in pixels; terrain must not block sight.
    ambush_trigger_id = "",         -- Optional additional release channel; blank uses proximity.

    -- Swarm followers form a sorted ring around the current group leader.
    swarm_ring_radius = 48,        -- Ring radius in pixels around the leader centre.
    swarm_separation = 24,         -- Neighbours closer than this many pixels repel.
    swarm_cohesion = 0.6,          -- Weight of averaged neighbour separation steering.
    -- Swim stays inside a live Water Volume; a drained swimmer idles in place.
    swim_speed = 80,                -- Swim speed in pixels per second; instance -1 inherits.
    swim_margin_px = 16,            -- Centre clearance from water edges, in pixels.
    hop_height = 96,                -- Arc height in pixels, using Enemy fall gravity.
    hop_interval = 1.2,             -- Idle seconds between landing and preparing another hop.
    hop_prepare_time = 0.15,        -- Grounded windup before launching, in seconds.
    hop_land_time = 0.12,           -- Landing pause before the next idle interval, in seconds.
    leash_distance = 0,             -- World-space radius in pixels; 0 disables returning home.
    leash_time = 1,                 -- Continuous chasing seconds outside the radius before return.
    leash_cooldown = 1.5,           -- Seconds ignoring detection/attacks after arriving home.

    -- Defense defaults. Archetype defense tables override these values.
    -- Tiled Enemy > Defense overrides seven fields per placement: Guard uses
    -- type_default, tag lists use blank, and numbers use -1 to inherit.
    -- Tag checkbox lists export as one comma-separated string in enum order.
    -- Guard tests use the attacker's previous-frame world position, including shots.
    defense = {
        guard = "none",                -- none, front (facing side), top or all.
        guard_break = "",              -- CSV or list of tags; empty means unbreakable.
        guard_hits = 1,                 -- Accepted breaking hits needed per opening.
        guard_open_time = 1,            -- Seconds open and stunned after breaking.
        armor_hits = 0,                 -- Required hits before armor breaks for this life; 0 disables.
        armor_requires = "",           -- CSV or list; empty accepts any damaging hit, not a parry stun.
        rear_damage_mult = 1,           -- Direct-hit factor when attacker is behind the facing side.
        guard_top_margin_px = 16,       -- Top guard also covers attackers this far above the centre.
        guard_recoil_px_s = 160,        -- Initial horizontal player speed away from a blocked melee hit.
        shield_up_time = 2,             -- Positive seconds raised per Shield cycle.
        shield_down_time = 2,           -- Positive seconds lowered per Shield cycle.
        blocked_sfx = "parry_miss",     -- sound_bank.lua id for a block.
        armor_sfx = "parry_miss",       -- sound_bank.lua id for an armor deflection.
        guard_break_sfx = "parry_success", -- sound_bank.lua id for opening a guard.
        guard_spark = "crit_hit",       -- fx_types.lua id for guard and armor impacts; blank disables.
    },
    -- Summon-pattern fallbacks. Instance Summon fields override the archetype's
    -- summon table; all other options are configured here or in enemy_types.lua.
    summon = {
        enemy_type = "none",           -- Synced minion art; none uses archetype skin, then default.
        archetype = "slime",           -- Stats and behaviour, independent of the chosen art.
        count = 2,                     -- Attempts per charged summon; 0 disables spawning.
        interval = 5,                  -- Positive seconds after each attempt, successful or not.
        max_alive = 4,                 -- Living helpers owned by this summoner at once; 0 disables.
        max_total = 0,                 -- Successful spawns per life; 0 means unlimited.
        radius = 48,                   -- Horizontal spawn radius in world pixels.
        telegraph_time = 0.5,          -- Seconds of charge before helpers appear; 0 skips waiting.
        despawn_with_summoner = true,   -- Remove helpers on defeat; false keeps them until room cleanup.
        drops = false,                 -- Helpers drop no loot unless true.
        effect = "",                  -- Optional fx_types.lua id played at each spawn point.
    },
    -- When a defeated placed enemy comes back: always (each time its room is
    -- entered), room_reload (when its room is rebuilt), save (after resting at a
    -- Save Point) or never (stays defeated, saved as a flag). An enemy's Tiled
    -- On defeat > Respawn wins, then its archetype's respawn in enemy_types.lua.
    -- save enemies also return after death or load. Checkpoints save progress
    -- without counting as rest. Only the current room revives immediately;
    -- other rooms revive on entry. Runtime-spawned enemies use room_reload.
    respawn_policy = "room_reload",

    -- true saves the game as soon as a "never" enemy is defeated, together with
    -- the flags that defeat set. false waits for the next normal save; dying
    -- before then undoes the defeat.
    autosave_on_permanent_defeat = false,

    -- enemy_types.lua key supplying stats/behaviour for synced art without a
    -- matching preset or a Tiled Archetype. Keeps the starter ground behaviour.
    default_archetype = "slime",

    -- Mount arcs use world-space degrees: 0 right, 90 up, 180 left.
    -- centre is the resting aim; half_width limits either side of it.
    -- free covers the full circle. Wall names identify the supporting wall.
    aim_mounts = {
        free = { centre = 0, half_width = 180 },
        floor = { centre = 90, half_width = 90 },
        ceiling = { centre = -90, half_width = 90 },
        wall_left = { centre = 0, half_width = 90 },
        wall_right = { centre = 180, half_width = 90 },
    },
    -- Used when the instance and archetype do not select a mount.
    default_aim_mount = "free",
    -- Turning speed in degrees per second and allowed firing error in degrees.
    aim_turn_speed = 120,
    aim_tolerance = 5,
    -- Velocity prediction multiplier; 0 disables lead, 1 predicts travel time.
    aim_lead = 1,
    -- Terrain blocks firing. Body rotation is opt-in because it rotates collision.
    aim_line_of_sight = true,
    aim_rotates_body = false,
    -- Shots in each burst, and seconds between them; shoot_cooldown separates bursts.
    burst_count = 1,
    burst_interval = 0.15,

    -- Seconds between white tells while the Shield guard is raised.
    shield_tell_period = 0.5,

    -- Spike-cycle fallbacks for archetypes that only select the attack pattern.
    spike_exposed_time = 2,       -- Seconds with the guard down.
    spike_warn_time = 0.5,        -- Seconds of warning before arming (0 skips it).
    spike_armored_time = 2,       -- Seconds with the guard up.
    spike_contact_multiplier = 2, -- Contact damage factor only while armed.
    spike_start_phase = "exposed", -- exposed, warn or armored; offset advances from here.
    spike_warn_color = {1, 0.8, 0.2}, -- RGB warning tint when charge art is absent.

    -- Default aggro/chase speed when an enemy does not define its own.
    chase_speed = 80,

    -- Ground-moving enemies stop at drops instead of walking onto air.
    -- Patrollers turn back at the edge. Enemy types can override this switch.
    stop_at_ledges = true,

    -- Ground motion: stop keeps the existing ledge guard; fall follows slopes,
    -- steps and drops; fall_when_chasing drops only while chasing a target.
    -- Game Settings > Enemies and elements > Enemies publishes this default;
    -- an archetype's ledge_behavior overrides it, then Tiled Stats > Ledge behaviour.
    ledge_behavior = "stop",
    -- Enemy fall gravity in Game Settings publishes fall_gravity_tiles.
    -- Downward acceleration and terminal speed, in tiles of tile height.
    fall_gravity_tiles = 20,       -- Tiles per second squared; positive.
    max_fall_speed_tiles = 16,     -- Maximum downward tiles per second; positive.
    -- Largest climbable step and floor-following drop, in tiles of tile height.
    step_up_tiles = 0.125,
    step_down_tiles = 0.25,
    -- Defeat falling enemies below the room bottom when no floor is in reach.
    -- No loot drops; the enemy's normal respawn policy still applies.
    fall_out_kills = true,

    -- Distance between the enemy's centre and the edge where it stops, in
    -- tiles (of tile width). 0.25 is a quarter tile: 16 pixels on 64-pixel
    -- tiles, 4 pixels on 16-pixel tiles. Raise it if your enemies are wide
    -- for your tiles and hang over edges. An enemy type can set its own
    -- distance in pixels with ledge_margin in enemy_types.lua, for one
    -- unusually wide or narrow enemy.
    ledge_margin_tiles = 0.25,

    -- How far below the enemy's centre to look for the ground it stands on,
    -- in tiles (of tile height). It must reach past the enemy's feet: 4 tiles
    -- covers enemies up to about 8 tiles tall. If it is too short for an
    -- enemy, the check turns itself off for that enemy and it can walk onto
    -- air again.
    ledge_probe_depth_tiles = 4,

    -- How far below a runtime ground spawn to search for its floor, in tiles
    -- of tile height. A miss leaves the authored spawn position unchanged.
    spawn_settle_depth_tiles = 8,

    -- Gap above the floor after spawn settling, in world pixels. Feet offsets
    -- scale with the enemy's body; this small clearance does not scale.
    ground_skin_px = 1,

    -- Largest step down that still counts as the same floor, in tiles (of
    -- tile height). 0.125 is an eighth of a tile: 8 pixels on 64-pixel tiles.
    -- Ground movers never move down to follow the floor, so an accepted step
    -- leaves them this far above the lower floor; larger drops stop them.
    ledge_step_tolerance_tiles = 0.125,

    -- How long an enemy is invulnerable after taking a hit.
    -- Keeps fast multi-hit weapons from deleting enemies in one swing.
    iframes_on_hit = 0.15,

    -- How often the invulnerability flash toggles the sprite tint.
    iframe_flash_period = 0.06,

    -- Default telegraph time for enemy attacks that don't specify one.
    telegraph_time = 0.3,

    -- Default active duration for enemy attacks that don't specify one.
    attack_duration = 0.6,

    -- Seconds before the enemy's corpse / game object is removed after death.
    cleanup_delay = 0.8,
}
