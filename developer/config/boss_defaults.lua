-- developer/config/boss_defaults.lua
-- Centralized defaults for boss behaviour.
--
-- These values are used whenever an individual boss (in developer/config/boss_types.lua)
-- or an attack pattern (in mvtk/bosses/patterns/attack_patterns.lua) does not provide
-- its own value. Tuning these affects *every* boss that relies on defaults.
--
-- All distances are in pixels. All times are in seconds.

return {
    -- Pressure gauge defaults. Presets override individual values with stagger
    -- tables; placed nonnegative stagger fields override the preset in turn.
    stagger = {
        threshold = 0,          -- Damage units to trigger; 0 disables stagger.
        decay_per_s = 5,        -- Pressure lost per second after decay_delay.
        decay_delay = 2,        -- Seconds without pressure before decay starts.
        stun_time = 2,          -- Seconds of knockdown when the gauge fills.
        damage_mult = 1.5,      -- Health damage multiplier during knockdown.
        parry_amount = 15,      -- Pressure from a successful player parry; no HP damage.
        weak_point_mult = 2,    -- Accepted weak-point damage contributes this much pressure.
        shield_break_amount = 15, -- Pressure added when an absorb shield breaks.
    },

    -- -------------------------------------------------------------------------
    -- MOVEMENT
    -- -------------------------------------------------------------------------

    -- How fast a boss chases the player in its MOVING state (pixels / sec).
    chase_speed = 120,

    -- Where the boss stops chasing, in pixels from the player. It comes
    -- closer if none of its attacks can reach from here. A boss with a swing
    -- and a shot can stop here to shoot and swing when the player comes closer.
    -- Lower the phase's attack_range to make that boss close in.
    attack_range = 150,

    -- When the boss must come closer, it stops this many pixels inside attack
    -- reach so a small step back by the player does not put them out of range.
    approach_margin = 8,

    -- How close the player must come, in pixels, before a boss with no Boss Arena
    -- of its own starts attacking. Such a boss wakes when its room is entered,
    -- so without this it would act from across the room. A boss placed with a
    -- Boss Arena attacks anywhere inside the arena and ignores this value.
    -- Per-boss override: engage_range in developer/config/boss_types.lua.
    engage_range = 800,

    -- Boss will not intentionally close the gap below this distance
    -- (prevents the boss from clipping into the player).
    min_chase_distance = 80,

    -- Pixels past the player, on the side away from the boss, for behind_player.
    behind_player_distance = 56,

    -- -------------------------------------------------------------------------
    -- ATTACKS & TELEGRAPHS
    -- -------------------------------------------------------------------------

    -- How long a telegraph/wind-up plays before the attack fires.
    -- Override per-attack via `telegraph_time` in the attack pattern.
    telegraph_time = 0.5,

    -- How boss danger areas read on the floor and in the air.
    indicator = {
        warning_color = {0.81, 0.28, 0.03, 0.96}, -- Red, green, blue, opacity before a hit. An attack's own colour or parry tell can take precedence.
        active_color = {0.90, 0.16, 0.46, 1}, -- Red, green, blue, opacity while the shape can hurt.
        neutral_color = {0.19, 0.47, 0.79, 1}, -- Steady blue outline for destinations, summons and shot launches.
        box_rim_pixels = 4, -- Whole-pixel box outline at world scale. Regenerate the textures with tools/generate_boss_indicators.py after editing.
        disc_rim_texels = 32, -- Outline on the 1280-pixel disc used by circular danger areas. The texture generator reads this value.
        ring_rim_texels = 88, -- Outline on the 704-pixel hollow ring used by waves and round location markers. The texture generator reads this value.
        fill = 0.20, -- Opacity of the inside of a circle or box, as a fraction of its colour's opacity.
        rim = 1, -- Opacity of the outline, as a fraction of its colour's opacity.
        pulse_speed = 2, -- Gentle warning pulses per second. Players using Reduced or Off see a steady warning.
        pulse_min = 0.86, -- Dimmest warning as a fraction of its colour's opacity.
        pulse_max = 1, -- Brightest warning, also used for a steady warning.
        spent_fraction = 0.33, -- Starting opacity of a fading shape after it can no longer hurt, as a fraction of its active colour.
        minimum_active_time = 0.12, -- Seconds to show a single-hit impact before it fades. This changes the picture only.
    },

    -- How long an attack's "active" portion lasts after the telegraph.
    -- Override per-attack via `duration` in the attack pattern.
    attack_duration = 1.0,

    -- Default range for melee boss attacks when a pattern omits `range`.
    melee_range = 120,

    -- Maximum living summons per boss across all its summon attacks.
    -- A pattern's summon.max_active replaces this limit.
    summon_max_active = 4,

    -- Allow summons to use their enemy type's drops. False prevents farming.
    -- A pattern's summon.drops boolean overrides this default.
    summon_drops = false,

    -- -------------------------------------------------------------------------
    -- INVULNERABILITY / I-FRAMES
    -- -------------------------------------------------------------------------

    -- After the boss takes damage, how long it is immune to further hits.
    -- Prevents multi-hit moves from stunlocking or deleting health.
    iframes_on_hit = 0.20,

    -- Fallback protection in seconds for a transition with no duration at all.
    -- Otherwise the whole transition is protected unless the phase sets its own i-frames.
    iframes_on_phase_transition = 1.5,

    -- Stop big hits at the next health phase so the player sees each phase change.
    -- Set phase_damage_gate = false on a boss preset or placed boss to let hits skip phases.
    phase_damage_gate = true,

    -- How often the invulnerability flash toggles the sprite tint.
    iframe_flash_period = 0.08,

    -- Phase change cues. Flash colors are red, green, blue, and opacity (0 to 1).
    -- Set shake_enabled or flash_enabled to false to turn off the default cues.
    -- Positive Tiled Camera intensity/duration and a checked Flash box still apply.
    transition_feedback = {
        phase_duration = 2.0, -- Seconds before the boss resumes acting when no duration is authored.
        shake_enabled = true, -- Default camera shake for phase changes.
        flash_enabled = true, -- Default full-screen flashes for phase changes.
        telegraph = { -- Opening cue for all phase changes with a transition.
            shake_duration = 0.4, shake_intensity = 1.4,
            flash_duration = 0.2, flash_color = {1, 0.8, 0.2, 0.5},
        },
        authored_camera = { -- Fallback when Tiled specifies only one camera field.
            intensity = 8, duration = 0.5,
        },
        cutscene = { -- Camera and flash cues requested by a cutscene phase, plus its music fade.
            shake_duration = 0.5, shake_intensity = 1.2,
            flash_duration = 0.25, flash_color = {1, 1, 1, 0.45}, music_fade = 0.3,
        },
        teleport = { -- Seconds to shrink away and grow back during the teleport.
            shrink_duration = 0.3, grow_duration = 0.3,
        },
        transform = { -- Transform cues, arena flash length, and music fade.
            shake_duration = 0.6, shake_intensity = 1.5,
            flash_duration = 0.35, flash_color = {0.8, 0.4, 1, 0.7},
            arena_flash_duration = 0.2, music_fade = 0.4,
        },
        rage = { -- Rage and desperation phase cues and music fade.
            shake_duration = 0.8, shake_intensity = 1.8,
            flash_duration = 0.3, flash_color = {1, 0.2, 0.2, 0.7}, music_fade = 0.3,
        },
        shield = { -- Shield phase cues, arena flash length, and music fade.
            shake_duration = 0.4, shake_intensity = 1.0,
            flash_duration = 0.25, flash_color = {0.4, 0.8, 1, 0.55},
            arena_flash_duration = 0.15, music_fade = 0.3,
        },
        dramatic = { -- Cues and timings for scripted dramatic transitions.
            effects_delay = 0.1, -- Wait before applying the boss and arena effects.
            scale_duration = 0.3, -- Time for the scale pulse and shrink/grow animation.
            reappear_delay = 0.5, -- Wait to reappear if a preset omits its own delay.
            pause_duration = 1.0, -- Protection time for a summon without its own pause length.
            music_fade = 0.5, -- Music crossfade in seconds.
            presets = {
                -- Freeze durations are seconds, rounded to the nearest 60 Hz step.
                -- Standard flash, shake and short hold.
                standard = {
                    hitstop_duration = 0.133333333, shake_intensity = "heavy",
                    flash_color = {1, 1, 1, 0.5}, flash_duration = 0.2, pause_duration = 0.5,
                },
                -- Red flash and scale pulse for an enraging boss.
                rage = {
                    hitstop_duration = 0.183333333, shake_intensity = "critical",
                    flash_color = {1, 0.2, 0.2, 0.8}, flash_duration = 0.3, pause_duration = 1.0,
                    boss_scale_pulse = 1.2, spawn_particles = "rage_aura",
                },
                -- Green flash and scale pulse for a recovering boss.
                heal = {
                    hitstop_duration = 0.083333333, shake_intensity = "medium",
                    flash_color = {0.3, 1, 0.3, 0.6}, flash_duration = 0.3, pause_duration = 0.7,
                    boss_scale_pulse = 1.1, spawn_particles = "heal_effect",
                },
                -- Purple flash before a new form appears and the music changes.
                transform = {
                    hitstop_duration = 0.233333333, shake_intensity = "critical",
                    flash_color = {0.8, 0.4, 1, 0.9}, flash_duration = 0.5, pause_duration = 1.5,
                    boss_disappear = true, boss_reappear_delay = 1.0,
                    spawn_particles = "transformation", music_change = true,
                },
                -- Blue flash and a short disappearance for a teleport.
                teleport = {
                    hitstop_duration = 0.083333333, shake_intensity = "light",
                    flash_color = {0.5, 0.5, 1, 0.4}, flash_duration = 0.15, pause_duration = 0.3,
                    boss_disappear = true, boss_reappear_delay = 0.5,
                    spawn_particles = "teleport_out", teleport_destination = true,
                },
                -- Flash and pause while adding enemies to the fight.
                summon = {
                    hitstop_duration = 0.133333333, shake_intensity = "medium",
                    flash_color = {0.7, 0.3, 0.9, 0.6}, flash_duration = 0.25, pause_duration = 0.8,
                    boss_invulnerable = true, spawn_adds = true, spawn_particles = "summon_circle",
                },
                -- Orange flash and shake as the arena changes.
                environmental = {
                    hitstop_duration = 0.183333333, shake_intensity = "critical",
                    flash_color = {1, 0.5, 0, 0.7}, flash_duration = 0.3, pause_duration = 1.0,
                    activate_hazards = true, spawn_particles = "arena_activation",
                },
            },
        },
    },

    -- -------------------------------------------------------------------------
    -- DEFEAT / CLEANUP
    -- -------------------------------------------------------------------------

    -- Delay between the "defeat started" cinematic and full cleanup.
    -- Gives cutscene / loot / fade time to play.
    defeat_cleanup_delay = 2.0,

    -- -------------------------------------------------------------------------
    -- CONTACT DAMAGE (boss body -> player collision)
    -- -------------------------------------------------------------------------

    -- Damage applied when the player's hitbox overlaps the boss body.
    -- Per-boss override: boss_types[type].contact_damage in developer/config/boss_types.lua.
    contact_damage = 2,

    -- Seconds between hits from the same boss while touching its body.
    contact_damage_interval = 0.5,

    -- Horizontal knockback magnitude applied to the player on contact.
    -- Directed away from the boss, regardless of its current facing.
    contact_knockback_x = 120,

    -- Vertical knockback magnitude applied to the player on contact.
    contact_knockback_y = 80,

    -- Player recovery lock after boss contact or an attack without stun_t.
    -- Seconds; an individual attack may set stun_t = 0 to disable the lock.
    default_hit_stun = 0.20,

    -- -------------------------------------------------------------------------
    -- ATTACK DEFAULTS (used when an attack pattern omits the value)
    -- Pattern-level fields always win; these are the last-resort fallback.
    -- -------------------------------------------------------------------------

    default_melee_damage      = 2,
    default_melee_width       = 60,   -- hitbox half-width  (pixels)
    default_melee_height      = 80,   -- hitbox half-height (pixels)
    default_melee_active_time = 0.14, -- Seconds a boss swing can hit after it starts (0 checks only at the start).
    default_melee_knockback_x = 200,
    default_melee_knockback_y = 100,

    default_projectile_damage = 1,
    default_projectile_speed  = 300,  -- pixels / second
    default_projectile_life   = 3.0,  -- seconds before despawn

    default_aoe_damage        = 3,
    default_aoe_radius        = 150,
    default_aoe_delay         = 0.5,
    default_aoe_active_time   = 0,     -- Seconds an area attack can hit after its delay. 0 checks once.
    default_aoe_knockback     = 150,
    default_rehit_interval   = 0,     -- Seconds between hits from the same attack. 0 allows one hit.

    default_beam_damage       = 2,
    default_beam_length       = 400,
    default_beam_width        = 40,
    default_beam_duration     = 1.5,
    default_beam_windup       = 0.5,
    -- Seconds a tracking beam holds its warning still before it can hurt.
    -- Half a second gives the player time to dodge across the locked lane.
    default_tracking_beam_lock_time = 0.5,

    -- Attack and phase transition pulses use these times unless they specify their own.
    default_hazard_pulse = {
        warn_time = 0.6, -- Seconds the placed hazards blink harmlessly before turning on. 0 skips the blink.
        duration = 2, -- Seconds the placed hazards are dangerous after the blink.
    },

    -- Lingering zones. Dimensions, radius and knockback are in world pixels.
    default_zone = {
        shape = "circle", -- circle or box
        radius = 96, -- Circle radius.
        width = 160, -- Full box width.
        height = 80, -- Full box height.
        target = "boss", -- boss, player, or anchor, sampled when the warning starts.
        -- Set anchor to a confinement anchor name when target is "anchor".
        delay = 0.25, -- Seconds from the end of the warning to placement.
        duration = 3, -- Seconds the placed zone stays active.
        tick = 1, -- Seconds between hits, including the wait for the first hit.
        damage = 2, -- Damage each tick offers.
        status_duration = 0, -- Seconds. 0 uses the status effect's own duration.
        knockback = 0, -- Push away from the zone centre. 0 disables the push.
        -- Set status to an id from status_effects.lua to apply it on accepted hits.
    },

    -- Travelling ground waves.
    default_ground_wave = {
        speed = 320, -- Pixels per second.
        distance = 320, -- Pixels each front travels.
        height = 64, -- Jump clearance in pixels, measured at the player root.
        width = 40, -- Full horizontal thickness of the front in pixels.
        both_sides = false, -- Send a front to both sides instead of just the facing side.
        damage = 2, -- Damage offered by each front.
        knockback = 150, -- Horizontal push in the direction of travel.
    },

    -- Turning beams. Angles in degrees from the boss's facing direction.
    default_sweep = {
        from_angle = 0, -- Starting angle.
        to_angle = 45, -- Ending angle.
        duration = 1, -- Seconds it takes the active beam to turn.
        windup = 0.25, -- Additional seconds after the warning before the beam fires.
        length = 400, -- Beam reach in pixels.
        width = 40, -- Full beam thickness in pixels.
        damage = 2, -- Damage per accepted beam hit.
        knockback = 100, -- Push along the beam.
    },

    -- Falling shots across the confinement rectangle.
    default_rain = {
        count = 8, -- Number of shots.
        gap_width = 128, -- Safe strip width in pixels.
        gap_at = "player", -- player, random, or away on the far side.
        stagger = 0, -- Seconds between drops. 0 drops them together.
        speed = 280, -- Pixels per second.
        lifetime = 4, -- Seconds a shot can travel.
        damage = 2, -- Damage per shot.
    },

    -- Equally spaced shots in a full circle.
    default_ring = {
        count = 8, -- Shots per volley.
        volleys = 1, -- Number of volleys.
        volley_delay = 0.25, -- Seconds between volleys.
        rotate_per_volley = 0, -- Degrees to rotate successive volleys.
        speed = 240, -- Pixels per second.
        lifetime = 3, -- Seconds a shot can travel.
        damage = 2, -- Damage per shot.
    },

    -- Moving attacks. Per-pattern values override each setting. A landing
    -- uses land.damage, then the pattern's damage, then the landing default.
    -- A ground-only slam hits through this many pixels above its floor when
    -- the attack's aoe or land block omits vertical_clearance.
    default_slam_dodge_height = 96,
    -- Contact tolerance below the floor in world pixels. The standing
    -- hurtbox can dip slightly into its support at rest.
    floor_attack_contact_slop = 3,

    -- Optional land settings override the default AOE radius, damage,
    -- knockback, and floor-relative dodge height.
    default_leap = {
        target = "player", -- Player at launch, or a named confinement anchor.
        height = 112, -- Peak rise in pixels when there is room for it.
        time = 0.75, -- Seconds from launch to landing.
        max_distance = 360, -- Maximum horizontal travel when targeting the player.
    },
    default_dive = {
        rise = 96, -- Pixels the boss climbs before tracking and dropping.
        rise_time = 0.25, -- Seconds to climb.
        track_time = 0.45, -- Seconds to follow the player's x before committing.
        track_speed = 480, -- Maximum rise and tracking speed in pixels per second; a player can outrun the dive.
        speed = 640, -- Drop speed in pixels per second.
        recover_time = 0.4, -- Seconds to return to the starting height.
    },
    default_reposition = {
        anchor = "centre", -- Confinement anchor. Top anchors require blink.
        style = "walk", -- walk uses chase speed. blink uses teleport transition timings.
        timeout = 1.5, -- Walk gives up here and runs its follow-up at its current position.
        -- Set ["then"] to a pattern name for an optional follow-up.
    },

    -- Absorb shield HP pool and its pause-aware lifetime in seconds.
    default_shield_hp = 25,
    default_shield_duration = 6.0,
    -- Seconds that a counter stance waits for an incoming direct hit.
    default_parry_window = 0.5,

    -- Health restored per tick when a heal attack omits its amount.
    default_heal_amount = 10,

    -- Fallback attack interval when a boss phase omits attack_interval.
    -- State machine uses (min, max) to jitter the gap between attacks.
    attack_interval_min = 2.0,
    attack_interval_max = 4.0,

    -- Seconds spent idle without starting an attack before a warning appears in
    -- the console. Paused time does not count. Set to 0 to turn warnings off.
    idle_deadman_seconds = 8.0,

    -- Default time a sequence waits for its next attack to become usable
    -- before skipping it. A moveset can set its own sequence_wait. 0 skips at once.
    sequence_wait = 1,

    -- How close the boss's centre must be to a left or right arena edge for
    -- the near_wall moveset condition. Uses the room edge if there is no arena.
    near_wall_distance = 64,

    -- The player's root must be more than this many pixels higher or lower
    -- than the boss's root to count as above or below.
    player_height_dead_band = 24,

    -- -------------------------------------------------------------------------
    -- VISUALS
    -- -------------------------------------------------------------------------

    -- Source-art size the boss sprite was authored at. Used to compute runtime
    -- scale when a boss_types entry specifies a target size.
    default_sprite_size = 64,

    -- Gravity for bosses with Ground motion on, as a multiplier of enemy gravity.
    ground_gravity_multiplier = 1,
    -- How many tiles below a boss's centre to search for a floor on spawn.
    spawn_settle_depth_tiles = 8,
    -- Use "stop" to hold at a ledge or "fall" to walk down to a lower floor.
    ledge_behavior = "stop",
    -- Jump Attack's height in pixels when the phase leaves Jump height at zero.
    jump_height = 96,
    -- Seconds on the ground between Jump Attack arcs.
    jump_recovery = 0.4,
    -- Skip a jump if a ledge or wall leaves less than this much horizontal travel, in pixels.
    jump_min_travel = 4,
    -- Seconds of warning before a burrowing boss can be hit or attack again.
    burrow_warning_time = 0.25,
    -- Grounded movement starts off unless the boss type or the placed Boss turns it on.
    ground_motion = false,
    -- Distance in pixels from the boss centre to its feet if the placement and type leave it unset.
    -- Leave this at 0 to measure the floor from the boss's placed position.
    feet_offset = 0,
    -- Seconds between idle blinks when neither the phase nor the boss type sets an interval.
    teleport_interval = 3,
    -- Blink near the player to fight, then away to make space. Anchors cycle
    -- in this order when neither the phase nor the boss type lists any.
    teleport_anchors = {"near_player", "far_from_player"},

    -- Smallest size during a teleport, as a fraction of the boss's normal size.
    -- Use a value greater than 0 and at most 1.
    teleport_min_scale = 0.02,

    -- Tint color flashed over the sprite on hit (vmath.vector4 table form).
    hurt_flash_color = { 1.0, 0.25, 0.25, 1.0 },

    -- How long the hurt flash holds before reverting to white.
    hurt_flash_duration = 0.20,

    -- -------------------------------------------------------------------------
    -- UI
    -- -------------------------------------------------------------------------

    -- Whether the boss health bar is shown by default.
    show_health_bar = true,
}
