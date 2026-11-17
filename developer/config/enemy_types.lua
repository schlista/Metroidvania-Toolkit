-- Optional xp sets archetype defeat XP; Rewards > XP value >= 0 overrides it.
-- Omit xp to use Game Settings > Progression > Leveling > Enemy XP (and elite multiplier).
-- status_immune={"poison"} (or CSV text) adds immunities to the placed list.
-- status_on_hit={id="poison",chance=0.5} applies on contact, melee and projectiles.
-- Placed Elements > Status on hit overrides the id; none inherits. Status chance
-- -1 inherits the archetype probability; 0 disables application, 1 always applies.
-- Optional element affinities (damage_types.lua ids): weak_to, resist_to,
-- immune_to and vulnerable_to are comma-separated text, e.g. weak_to="physical".
-- Blank placed fields inherit these preset values. vulnerable_to makes all
-- other types immune. damage_taken={fire=0.5,physical=2} supplies exact numeric
-- factors (exact type, then family); tags={"armored"} uses tag_multipliers.
-- damage_type="fire" changes outgoing contact, melee and projectile hits;
-- omit it for physical contact/melee and projectile shots.
-- developer/config/enemy_types.lua
-- Optional projectile_deflect="reflect" opts an archetype's shots into returns;
-- "none" prevents cuts and returns; omitted inherits enemy_defaults (destroy).
-- reflect_damage_mult=-1 inherits combat_config.projectiles, or use a
-- nonnegative damage multiplier. Both counterplay features ship off.
-- attack_parryable=true allows melee_swipe parries; false is the shipped
-- preset default. Enemy > Tuning > Attack parryable can also opt a placement in.
-- Unticked inherits; this boolean never changes contact hits or projectile rules.
-- Starter enemy pack wired to existing behaviors/FX.
--
-- Each top-level key appears in the Tiled Enemy Archetype dropdown after
-- Prepare & Check; reopen the Tiled project to refresh it. Archetype chooses
-- stats and behaviour independently of enemy_type (synced art) and linked art.
-- Archetype=none keeps matching-preset behaviour, or enemy_defaults.lua's
-- default_archetype for art without a matching preset. Duplicate a commented
-- entry, rename it, and tune its fields for a custom archetype.
--
-- Tuning ranges (the slime entry below is the baseline archetype):
--   respawn            optional always, room_reload, save or never; an instance's
--                      On defeat > Respawn wins. Omit to use enemy_defaults.
--   health             1-50 hits-to-kill at base damage; pair with damage_dealt_mult.
--   damage             1-30 damage to player per contact/attack.
--   speed              30-200 px/s for ground; 100-400 for fliers.
--   detection_range    80-400 px. >400 reads as "always sees you".
--   chase_speed        usually 1.2-2.0x `speed`.
--   patrol_distance    60-400 px back-and-forth distance.
--   ledge_behavior     stop, fall or fall_when_chasing for ground movers;
--                      omit or use type_default to inherit enemy_defaults.lua.
--   behavior           fallback behavior if a Tiled object omits movement/attack_pattern.
--   scale              0.5-2.0 body/art scale, multiplied by Tiled Size and elite scale.
--                      Keep 1.0 when the art is drawn at
--                      its in-game size (as the shipped skins are).
--   color              vmath.vector4(r, g, b, a). Used only when tint_skinned is enabled.
--   skin               optional default custom art skin id from Sync Enemy Art.
--                      Leave unset to use the shipped `default` enemy skin.
--   audio              optional combat SFX ids from the audio controller, e.g.
--                      audio = { hurt = "enemy_hurt", death = "enemy_death" }
--                      Set either value to false to silence that enemy sound.

local vmath = _G.vmath or { vector4 = function(...) return {...} end }

-- Tiled Enemy > Defense overrides guard, guard_break, guard_hits, guard_open_time,
-- armor_hits, armor_requires and rear_damage_mult for one placement. type_default,
-- blank tag lists and -1 numbers inherit this defense table, then enemy_defaults.
-- random_drop_chance: optional 0 to 1 per type, overriding the project chance.
-- 0 prevents random equipment drops; bosses and summoned minions never roll.
return {
    -- Splits once into smaller floor-settled children; Death effects overrides a placement.
    splitter = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,                       -- Base health before instance scaling.
        damage = 1,                       -- Contact damage.
        speed = 50,                       -- Ground speed in pixels per second.
        behavior = "ground_patrol_chase", -- Ordinary ground movement until defeated.
        grounded_movement = true,         -- Children use the shared ground settle service too.
        death_behavior = "split",        -- Combat damage only; none on an instance cancels it.
    },
    -- Fires one ring of shots before the death animation takes over the attack clip.
    burster = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 2,                       -- Base health before instance scaling.
        damage = 1,                       -- Contact damage and base projectile damage.
        speed = 50,                       -- Ground speed in pixels per second.
        behavior = "ground_patrol_chase", -- Ordinary ground movement until defeated.
        grounded_movement = true,         -- Uses normal ground and ledge rules.
        death_behavior = "burst",        -- Combat damage only; no burst on developer or pit kills.
        death_burst_count = 8,             -- Evenly spaced radial projectiles.
    },

    -- Share Stats > Group id across placements; encounters group each wave.
    swarmling = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 2,                       -- Base health before instance scaling.
        damage = 1,                       -- Contact damage.
        speed = 100,                      -- Ring steering speed in pixels per second.
        behavior = "swarm",              -- Followers surround the current group leader.
        grounded_movement = false,        -- Free movement in both axes.
        swarm_leader_movement = "chase_flying", -- Inner movement pattern for the leader.
        swarm_ring_radius = 32,           -- Follower ring radius in pixels; overrides the project default.
        detection_range = 240,            -- Leader chase detection radius in pixels.
    },
    -- Confined to a live Water Volume; chases only a player in that same volume.
    swimmer = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,                 -- Base health before instance scaling.
        damage = 1,                 -- Contact damage.
        speed = 80,                 -- Base speed in pixels per second.
        behavior = "swim",         -- Water movement; dry placements idle.
        grounded_movement = false,  -- The water rectangle owns vertical motion.
        swim_speed = 80,            -- Pixels per second inside the water.
        detection_range = 240,      -- Player detection radius in pixels.
    },
    -- Reuses ordinary ground falling and landing after every explicit launch.
    hopper = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,                 -- Base health before instance scaling.
        damage = 1,                 -- Contact damage.
        speed = 80,                 -- Horizontal hop speed in pixels per second.
        behavior = "hop",          -- Idle, prepare, arc, land.
        grounded_movement = true,   -- Uses terrain rays for the shared hop arc.
        ledge_behavior = "fall",   -- Follows the ground between hops.
        hop_height = 96,            -- Pixels above take-off with current fall gravity.
        hop_interval = 1.2,         -- Seconds waiting after a landing pause.
        detection_range = 240,      -- Aim toward the player inside this radius.
        patrol_distance = 96,       -- Otherwise hop back and forth near the post.
    },
    -- Circles nearby terrain; Special movement can choose one initial surface.
    wall_crawler = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,                  -- Base health before difficulty and instance scaling.
        damage = 1,                  -- Contact damage while crawling.
        speed = 60,                  -- Baseline movement speed in pixels per second.
        behavior = "surface_crawl", -- Uses the ordinary movement-pattern host.
        grounded_movement = true,    -- May use ground physics after losing its surface.
        cling_side = "free",        -- Attach to the nearest of the four surfaces.
    },
    -- Hidden in its baked collection until proximity or a switch releases it.
    lurker = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,                  -- Base health before difficulty and instance scaling.
        damage = 1,                  -- Contact damage after release only.
        speed = 80,                  -- Chase speed in pixels per second.
        behavior = "ambush",        -- Suppresses other patterns while hidden.
        grounded_movement = true,    -- Drops through shared ground physics.
        ambush_style = "drop",      -- Falls when released; rise and disguise are alternatives.
        ambush_then = "chase_ground", -- Pattern name used after release.
    },
    -- Always guards the facing side; a rear attack deals extra damage.
    shield_bearer = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 6,                     -- Base health before instance/profile scaling.
        damage = 1,                     -- Contact damage.
        speed = 50,                     -- Ground speed in pixels per second.
        behavior = "ground_patrol",    -- Patrol and turn with the facing direction.
        defense = {
            guard = "front",           -- Blocks attacks from the facing side only.
            guard_break = {"heavy_attack", "charge_attack", "parry"}, -- Accepted breaking tags.
            rear_damage_mult = 1.5,     -- Rear direct-hit damage multiplier.
        },
    },
    -- Armor rejects light hits; the third accepted blow breaks it and deals damage.
    armored = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 8,                     -- Base health before instance/profile scaling.
        damage = 2,                     -- Contact damage.
        speed = 40,                     -- Ground speed in pixels per second.
        behavior = "ground_patrol",    -- Ordinary ground movement beneath the armor.
        defense = {
            armor_hits = 3,             -- Accepted hits needed to remove armor for this life.
            armor_requires = {"heavy_attack", "ground_pound", "down_strike"}, -- Allowed tags.
        },
    },
    -- Enemy nests use the same real summon pattern as summoners. Place an Enemy
    -- with Archetype nest; Stats > Required action can restrict accepted hits.
    -- On defeat > Respawn overrides this preset, and Defeat flag names its save.
    nest = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 6,                    -- Health before instance/profile scaling.
        damage = 0,                    -- No base contact damage.
        contact_damage = 0,            -- Touching the nest does not hurt the player.
        knockback_force = 0,           -- Zero-damage contact must not push the player.
        knockback_resistance = 1,      -- Hits cannot displace this stationary nest.
        poise_threshold = 999,         -- Avoid interrupting charges with ordinary hits.
        speed = 0,                     -- Idle movement keeps the authored position.
        behavior = "idle,summon_minion", -- Charge, then spawn real helpers.
        detection_range = 360,         -- Player distance in pixels that starts charging.
        respawn = "never",             -- Permanent defeat through the existing saved Flags.
        summon = {
            enemy_type = "none",       -- Use the minion archetype's art, or default.
            archetype = "slime",       -- Helpers' stats and behaviour.
            count = 1,                 -- Attempts per charge.
            interval = 3,              -- Cooldown seconds between completed attempts.
            max_alive = 3,             -- Maximum living helpers owned by this nest.
            max_total = 0,             -- Unlimited successful helpers over this life.
            radius = 48,               -- Horizontal spawn radius in pixels.
            telegraph_time = 0.5,      -- Charge duration in seconds.
            despawn_with_summoner = true, -- Remove helpers when the nest is defeated.
            drops = false,             -- Helpers do not drop loot unless enabled.
            effect = "",              -- Optional fx_types.lua effect at each spawn point.
        },
        drops = {},                    -- No nest loot; add normal drop entries to opt in.
    },
    -- Stationary summoner. The six Tiled Summon fields override these values;
    -- additional options stay in this table (see enemy_defaults.lua for units).
    summoner = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 6,                    -- Health before instance/profile scaling.
        damage = 1,                    -- Contact damage.
        speed = 0,                     -- Idle movement holds the summoning position.
        behavior = "idle,summon_minion", -- Charge, then call floor-settled helpers.
        detection_range = 360,         -- Player must enter this pixel radius to start charging.
        summon = {
            enemy_type = "none",       -- Art from the minion archetype, or default.
            archetype = "slime",       -- Helpers use this archetype's stats and behaviour.
            count = 2,                 -- Attempts per charge.
            interval = 5,              -- Seconds between completed attempts.
            max_alive = 4,             -- Maximum living helpers for this summoner.
            max_total = 0,             -- 0 means unlimited successful helpers per life.
            radius = 48,               -- Horizontal radius, kept on the supporting platform.
            telegraph_time = 0.5,      -- Charge duration in seconds.
            despawn_with_summoner = true, -- Remove helpers when this summoner is defeated.
            drops = false,             -- Set true to allow the helpers' normal loot.
            effect = "",              -- Optional fx_types.lua effect id at each spawn point.
        },
    },
    -- Stationary shell. Any synced art can use this archetype independently.
    spike_shell = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 6,                    -- Base health before instance/profile scaling.
        damage = 1,                    -- Base contact damage, before the armed factor.
        speed = 0,                     -- Idle movement keeps the placed shell stationary.
        behavior = "idle,spike_cycle",  -- Exposed, warning, then armed, repeating.
        spike_exposed_time = 2,         -- Seconds with the guard down; must be positive.
        spike_warn_time = 0.5,          -- Warning seconds; 0 skips the warning.
        spike_armored_time = 2,         -- Guard-up seconds; must be positive.
        spike_contact_multiplier = 2,   -- Armed contact factor; 0 disables armed damage.
        spike_start_phase = "exposed", -- exposed, warn or armored before per-instance offset.
    },

    -- Stationary mounted shooter. Use any synced art; aim_mount on the placed
    -- Enemy overrides this preset. Degrees/seconds and lead tuning are explained
    -- in enemy_defaults.lua. No ground settle: ceiling and wall mounts stay put.
    turret = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 6,                     -- Base health before instance/profile scaling.
        damage = 1,                     -- Contact and projectile damage fallback.
        speed = 0,                      -- Stationary; idle owns movement.
        behavior = "idle,aimed_shot",    -- Track and shoot within the selected arc.
        detection_range = 480,          -- Maximum target distance in pixels.
        shoot_cooldown = 1.5,           -- Seconds between bursts.
        projectile_speed = 260,         -- Pixels per second.
        aim_mount = "floor",            -- Upper half-circle; instance may override.
        aim_turn_speed = 120,           -- Degrees per second.
        aim_tolerance = 5,              -- Degrees of allowed firing error.
        aim_lead = 1,                   -- 0 disables velocity prediction.
        aim_line_of_sight = true,       -- Hold fire behind terrain.
        aim_rotates_body = false,       -- Opt-in; also rotates the collision body.
        burst_count = 1,                -- Shots per burst.
        burst_interval = 0.15,          -- Seconds between shots in a burst.
    },

    -- Slime (basic ground enemy)
    slime = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        ledge_behavior = "type_default", -- Inherit the project's ground motion rule.
        health = 2,
        damage = 1,
        speed = 50,

        behavior = "ground_patrol_chase",
        detection_range = 140,
        chase_speed = 80,
        patrol_distance = 180,
        scale = 0.9,
        color = vmath.vector4(0.3, 0.8, 0.3, 1.0),  -- Green slime
        animation_idle = "idle",
        animation_walk = "walk",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 180,
        knockback_resistance = 0.2,
        invincibility_time = 0.4,

        drops = { currency = { min = 1, max = 5, chance = 0.9 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Tumbleweed (rolling contact charger)
    -- Uses the matching developer/assets/enemies/tumbleweed_enemy art folder.
    tumbleweed_enemy = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 5,
        damage = 2,
        speed = 85,

        behavior = "chase_player,dash_attack",
        grounded_movement = true,
        detection_range = 360,
        chase_speed = 135,
        charge_speed = 240,
        charge_distance = 96,   -- Pixels traveled during each rolling charge.
        charge_cooldown = 2.0,  -- Seconds between charge starts.
        scale = 1.0,
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "walk",
        animation_attack = "charge",
        animation_charge = "charge",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 2,
        contact_damage_cooldown = 0.8,
        knockback_force = 280,
        knockback_resistance = 0.35,
        invincibility_time = 0.35,

        drops = { currency = { min = 4, max = 9, chance = 1.0 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Cactus (stationary radial needle shooter)
    -- `projectile_visual` selects the needle art without changing other enemy shots.
    cactus_enemy = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 6,
        damage = 1,
        speed = 0,

        behavior = "idle,shoot_circle",
        detection_range = 480,
        shoot_cooldown = 2.4,
        projectile_damage = 1,
        projectile_speed = 260,
        projectile_visual = "needle_projectile",
        scale = 1.0,
        animation_idle = "idle",
        animation_attack = "ranged_attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        contact_damage_cooldown = 0.8,
        knockback_force = 180,
        knockback_resistance = 0.5,
        invincibility_time = 0.4,

        drops = { currency = { min = 5, max = 12, chance = 1.0 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Bat enemy (ceiling ambush flyer)
    -- Place it at the ceiling height you want it to hang from. It stays in its
    -- hanging `idle` animation until the player enters detection_range, then
    -- swoops once and keeps darting left/right for the rest of the encounter.
    bat_enemy = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,
        damage = 1,
        speed = 150,

        behavior = "swoop_attack",
        ignores_terrain = true,
        detection_range = 320,
        swoop_speed = 300,       -- Initial diagonal dive speed in pixels/second.
        swoop_duration = 0.55,   -- Time spent on the first dive toward the player.
        dart_speed = 230,        -- Horizontal speed after the opening swoop.
        dart_interval = 0.85,    -- Seconds before reversing its dart direction.
        dart_vertical_speed = 95, -- How quickly later darts track the player's height.
        scale = 1.0,             -- Frames are drawn at in-game size (136 x 109).
        animation_idle = "idle",
        animation_walk = "fly",
        animation_run = "fly",
        animation_attack = "attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        contact_damage_cooldown = 0.65,
        knockback_force = 220,
        knockback_resistance = 0.1,
        invincibility_time = 0.35,

        drops = { currency = { min = 2, max = 6, chance = 0.9 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Ghost enemy (slow aerial follower with a proximity rise)
    -- The ghost begins with a gentle hover, follows once detected, and climbs
    -- above nearby players instead of firing a projectile attack.
    ghost_enemy = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,
        damage = 1,
        speed = 62,

        behavior = "ghost_float",
        ignores_terrain = true,
        detection_range = 280,
        chase_speed = 76,
        chase_speed_mult = 1.15,
        rise_range = 104,        -- Player distance that triggers the upward evade.
        rise_height = 88,        -- Desired height above a nearby player.
        rise_speed = 115,        -- Maximum upward evade speed in pixels/second.
        patrol_distance = 128,
        scale = 1.0,             -- Frames are drawn at in-game size (144 x 173).
        animation_idle = "fly_idle",
        animation_walk = "fly",
        animation_run = "fly",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        contact_damage_cooldown = 0.9,
        knockback_force = 170,
        knockback_resistance = 0.15,
        invincibility_time = 0.45,

        drops = { currency = { min = 3, max = 7, chance = 0.9 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Mummy enemy (slow ground pursuer with a timed arm swipe)
    -- The swipe uses the normal enemy damage payload after its short wind-up;
    -- attack_range/attack_height define the simple rectangular reach check.
    mummy_enemy = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 7,
        damage = 2,
        speed = 38,

        behavior = "chase_player,melee_swipe",
        grounded_movement = true,
        detection_range = 260,
        chase_speed = 46,
        attack_range = 76,
        attack_height = 58,
        attack_windup = 0.28,
        attack_cooldown = 1.45,
        scale = 1.0,             -- Frames are drawn at in-game size (152 x 182).
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "walk",
        animation_attack = "attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 2,
        contact_damage_cooldown = 1.0,
        knockback_force = 250,
        knockback_resistance = 0.55,
        invincibility_time = 0.4,

        drops = { currency = { min = 5, max = 11, chance = 1.0 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- ------------------------------------------------------------------
    -- Inkreach hand-drawn enemies. Their art lives in
    -- developer/assets/enemies/ink_* (drawn by
    -- developer/tools/tiled/inkreach_enemies.py). Each reuses a proven
    -- behavior above; only stats and art differ.
    -- ------------------------------------------------------------------

    -- Lantern moth (Whisperwood flyer): the bat's swoop-and-dart pattern.
    

    -- Ember imp (Cinder Works flyer): a faster, tougher moth.
    

    -- Drowned wisp (Sanctum and Catacombs ghost): the ghost's float and rise.
    

    -- Thorn crawler (Whisperwood walker): the mummy's chase and swipe, quicker
    -- and lighter.
    

    -- Slagling (Cinder Works walker): a heavier, glowing crawler.
    

    -- Bone walker (Catacombs walker): the mummy's chase and arm swipe.
    

    -- ===================== Lanternfall (pixel-art glow creatures) =====================
    -- Skins drawn by developer/tools/tiled/lanternfall_enemies.py at 160 x 128.
    
    
    
    
    
    

    -- Ground patrol
    crawler = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,
        damage = 1,
        speed = 60,

        behavior = "ground_patrol_chase",
        detection_range = 160,
        chase_speed = 90,
        patrol_distance = 220,
        scale = 1.0,
        color = vmath.vector4(0.2, 0.8, 0.3, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 200,
        knockback_resistance = 0.3,
        invincibility_time = 0.4,

        drops = { currency = { min = 3, max = 8, chance = 1.0 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Flyer (chase)
    screecher = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 2,
        damage = 1,
        speed = 110,

        behavior = "flying_chase",
        detection_range = 220,
        chase_speed = 140,
        hover_height = 60,
        scale = 0.9,
        color = vmath.vector4(0.4, 0.3, 0.6, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "run",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 240,
        knockback_resistance = 0.15,
        invincibility_time = 0.5,

        drops = { currency = { min = 2, max = 6, chance = 0.9 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Charger (rush attack)
    charger = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 5,
        damage = 2,
        speed = 40,

        behavior = "charger",
        detection_range = 260,
        charge_speed = 220,
        charge_distance = 360,
        charge_cooldown = 2.6,
        scale = 1.1,
        color = vmath.vector4(0.8, 0.4, 0.2, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "run",
        animation_attack = "charge",
        animation_charge = "charge",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 2,
        knockback_force = 320,
        knockback_resistance = 0.5,
        invincibility_time = 0.35,

        drops = { currency = { min = 8, max = 16, chance = 1.0 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
        aggro_sound = "ui_click",
    },

    -- Ranged skirmisher (projectile)
    marksman = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 4,
        damage = 1,
        speed = 70,

        behavior = "flying_patrol",
        detection_range = 260,
        chase_speed = 0, -- stays near patrol points
        patrol_points = {}, -- optional list of waypoints
        hover_height = 90,
        scale = 1.0,
        color = vmath.vector4(0.5, 0.7, 0.8, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_attack = "ranged_attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 180,
        knockback_resistance = 0.25,
        invincibility_time = 0.35,

        shoots_projectiles = true,
        shoot_cooldown = 1.8,
        projectile_damage = 1,
        projectile_speed = 240,

        drops = { currency = { min = 5, max = 12, chance = 1.0 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Heavy bruiser (high knockback resist)
    bruiser = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 8,
        damage = 3,
        speed = 55,

        behavior = "ground_patrol_chase",
        detection_range = 220,
        chase_speed = 90,
        patrol_distance = 200,
        scale = 1.2,
        color = vmath.vector4(0.9, 0.7, 0.3, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 3,
        knockback_force = 260,
        knockback_resistance = 0.8,
        invincibility_time = 0.25,

        drops = { currency = { min = 10, max = 20, chance = 1.0 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Bat (fast flyer)
    bat = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 2,
        damage = 1,
        speed = 140,

        behavior = "chase",
        detection_range = 220,
        scale = 0.8,
        color = vmath.vector4(0.55, 0.35, 0.75, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "run",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 200,
        knockback_resistance = 0.1,
        invincibility_time = 0.35,

        drops = { currency = { min = 2, max = 5, chance = 0.9 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Bomber (spread shot patrol)
    bomber = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,
        damage = 1,
        speed = 70,

        behavior = "bomber",
        detection_range = 240,
        scale = 1.0,
        color = vmath.vector4(0.9, 0.4, 0.2, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_attack = "ranged_attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 220,
        knockback_resistance = 0.2,
        invincibility_time = 0.35,

        drops = { currency = { min = 4, max = 9, chance = 0.9 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Ghost (floats through platforms, patrols + chases player)
    ghost = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,
        damage = 1,
        speed = 90,

        behavior = "ghost_float,shoot_random",
        detection_range = 240,
        chase_speed_mult = 1.2,     -- speed multiplier when chasing vs patrol
        ignores_terrain = true,     -- phases through platforms and ground tiles
        scale = 0.95,
        color = vmath.vector4(0.7, 0.9, 1.0, 0.75),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_attack = "ranged_attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 180,
        knockback_resistance = 0.15,
        invincibility_time = 0.45,

        drops = { currency = { min = 3, max = 7, chance = 0.9 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Goblin (quick melee dasher)
    goblin = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 4,
        damage = 1,
        speed = 110,

        behavior = "patrol,dash",
        detection_range = 200,
        scale = 0.95,
        color = vmath.vector4(0.2, 0.7, 0.2, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "run",
        animation_attack = "charge",
        animation_charge = "charge",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 220,
        knockback_resistance = 0.25,
        invincibility_time = 0.35,

        drops = { currency = { min = 3, max = 7, chance = 0.9 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Skeleton (ranged patrol)
    skeleton = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 4,
        damage = 1,
        speed = 70,

        behavior = "ranged_patrol",
        detection_range = 240,
        scale = 1.0,
        color = vmath.vector4(0.9, 0.9, 0.8, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_attack = "ranged_attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 200,
        knockback_resistance = 0.2,
        invincibility_time = 0.35,

        drops = { currency = { min = 4, max = 8, chance = 0.9 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Knight (heavy guard with shield + dash)
    knight = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        defense = {guard = "front"},    -- Shield blocks from the facing side only while raised.
        health = 7,
        damage = 2,
        speed = 60,

        behavior = "guardian,dash",
        detection_range = 220,
        scale = 1.2,
        color = vmath.vector4(0.4, 0.5, 0.8, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_run = "run",
        animation_attack = "charge",
        animation_charge = "charge",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 2,
        knockback_force = 260,
        knockback_resistance = 0.6,
        invincibility_time = 0.3,

        drops = { currency = { min = 7, max = 14, chance = 1.0 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Spider (ground skirmisher)
    spider = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 3,
        damage = 1,
        speed = 70,

        behavior = "patrol",
        detection_range = 200,
        scale = 0.95,
        color = vmath.vector4(0.45, 0.35, 0.25, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 200,
        knockback_resistance = 0.2,
        invincibility_time = 0.4,

        drops = { currency = { min = 3, max = 7, chance = 0.9 } },
        hit_sound = "hit_melee",
        death_sound = "hit_melee",
    },

    -- Wizard (ranged caster)
    wizard = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 4,
        damage = 1,
        speed = 60,

        behavior = "ranged_patrol",
        detection_range = 260,
        scale = 1.0,
        color = vmath.vector4(0.6, 0.45, 0.9, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_attack = "ranged_attack",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 180,
        knockback_resistance = 0.2,
        invincibility_time = 0.4,

        drops = { currency = { min = 6, max = 14, chance = 1.0 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },

    -- Flying patrol (hovering scout)
    flying_patrol = {
        attack_parryable = false, -- Melee swipes cannot be parried unless explicitly enabled.
        health = 2,
        damage = 1,
        speed = 90,

        behavior = "hover",
        detection_range = 220,
        hover_height = 48,
        scale = 0.9,
        color = vmath.vector4(0.45, 0.6, 0.9, 1.0),
        animation_idle = "idle",
        animation_walk = "walk",
        animation_hit = "hurt",
        animation_death = "death",

        contact_damage = 1,
        knockback_force = 220,
        knockback_resistance = 0.15,
        invincibility_time = 0.45,

        drops = { currency = { min = 2, max = 6, chance = 0.9 } },
        hit_sound = "hit_projectile",
        death_sound = "hit_projectile",
    },
}
