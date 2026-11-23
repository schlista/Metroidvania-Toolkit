-- Weapon attack sets may define up_light and up_heavy in grounded and aerial
-- buckets; missing up attacks fall back to the normal attack.
-- developer/config/combat_config.lua
-- ============================================================================
-- MV Toolkit Combat Configuration
-- ============================================================================
-- This is the live combat schema used by the player combat executor.
-- Every player attack is authored as data here so new move sets can be created
-- without editing player controller code.
--
-- Authoring notes:
-- - An attack may set energy_cost (Max energy units; omitted or 0 is free).
--   Max energy 0 waives attack costs. Otherwise it pays once when starting,
--   including combo links; insufficient energy refuses without starting.
--   Optional sfx.refuse is a sound_bank.lua id played once for a refused press.
--   The Dev Menu's Infinite energy waiver keeps costed attacks free.
-- - Game Settings > Attacks publishes numeric tuning as creator_settings.lua
--   overrides; this file remains the baseline. label and settings_order name
--   and order each attack in that window. Optional projectile kx/ky and
--   dir_x/dir_y get numeric controls when authored; omission keeps dynamic aim.
-- - Durations are in seconds. Timeline recovery is the wait after the last
--   active window, or after startup if there are no windows.
-- - Hitbox `width`/`height` values are full box sizes in pixels.
-- - `sprite_offset` is used by sprite characters.
-- - `spine_bone` + `spine_offset` is used by Spine characters. Bone names
--   below target the bundled BeardyBuck rig and are contract-tested against
--   its checked-in skeleton JSON.
-- - `damage_type` is a damage_types.lua id; an unlocked infusion can override it.
-- - `action_tag` is forwarded as `attack_type` so gates/breakables can still
--   require specific actions.
-- - `shape` is "box" (default) or "circle". Circle hitboxes use the
--   melee_hitbox_circle factory; sphere collision shape scaled by `radius`.
-- - `radius` is in pixels (circle only). Defaults to `width * 0.5` when
--   omitted, so a circle attack inherits the same reach as a box of the
--   same width.
-- ============================================================================

return {
    -- Pixel-unit generation for automatic conversion to the project's player
    -- baseline; unitless version, safe 1 or 2 (2 uses Player Size 1.00).
    units_version = 2,
    default_attack_set = "default",

    feedback = {
        -- Positive player hits on enemies, champions and bosses: fx_types.lua
        -- id at the hit point, or target centre when no point is supplied.
        -- Empty disables particles. Blocks/immune hits and quiet DoT ticks keep
        -- their own feedback; a guard-break spark replaces this effect.
        -- A boss type's existing boss_hit_feedback.hit_effect overrides this
        -- id (including empty); regular enemy types use this shared default.
        hit_effect = "hit_impact",
        -- Optional parry cues: RGBA cyan differs from white guards and amber
        -- spike warnings. Duration is seconds; sfx is a sound_bank.lua id or
        -- empty for silence. anim.flash returns to white, losing preset tints.
        parry_tell = { color = {0.2, 0.85, 1, 1}, duration = 0.15, sfx = "" },
        -- Optional red cue for explicitly non-parryable windups; disabled
        -- independently. Shots only use the parry cue, never this warning.
        unblockable_tell = { enabled = false, color = {1, 0.2, 0.2, 1}, duration = 0.15 },
        -- Quiet poison/burn and drowning ticks; no shake, hitstop or rumble.
        damage_over_time = {shake=0, hitstop=0, rumble=0, screen_shake=false},
        melee = { shake = 6, hitstop = 0.02, rumble = 0.20 },
        projectile = { shake = 4, hitstop = 0.015, rumble = 0.16 },
        -- Player damage: sound-bank key, impact pause, recovery lock, and tint.
        -- Explicit attack/hazard stun_t overrides stun_t here; zero disables
        -- recovery. Tiled hazards use -1 to inherit their type/default config.
        hurt = {
            shake = 5, hitstop = 0.06, rumble = 0.18,
            sfx = "player_hurt", stun_t = 0.20,
            flash_color = { 1, 0.25, 0.25, 1 }, flash_duration = 0.20,
            animation = "hurt", -- Logical player animation; missing art uses the controller fallback.
            interrupt_attack = true, -- Cancel the swing and its hitboxes on direct damage.
        },
        -- Confirmed boss damage, including weak points. Preset audio.hurt wins
        -- over this default; enabled Tiled feedback overrides win over both.
        -- Freeze for 33 ms on a boss hit. Seconds round to the nearest 60 Hz step.
        boss_hurt = { shake = 6, hitstop = 0.033333333, rumble = 0.20, sfx = "enemy_hurt" },
        parry = { shake = 7, hitstop = 0.03, rumble = 0.24 },
        perfect_parry = { shake = 9, hitstop = 0.05, rumble = 0.30 },
        -- Camera shake for boss phase changes, boss telegraphs and the arena
        -- screen_shake effect. Shake pixels = intensity x pixels_per_intensity;
        -- 0 turns this shake off. duration (seconds) is used only when the
        -- caller gives none. max_intensity caps a number given by the caller,
        -- such as a boss_types.lua phase camera_shake intensity. presets name
        -- the intensity of light/medium/heavy/critical arena shakes. Game
        -- Settings camera shake off still stops it.
        screen_shake = {
            pixels_per_intensity = 8, duration = 0.3, max_intensity = 2.2,
            presets = { light = 0.5, medium = 1.0, heavy = 1.5, critical = 2.2 },
        },
    },

    -- ========================================================================
    -- Combo settings
    -- ========================================================================
    -- mixed_combos: when true, heavy input during a light chain triggers
    --   a special finisher (L+H, L-L+H). When false, heavy is independent.
    --   To fully disable, also remove the "heavy" entries from the
    --   combo_links tables in light_1 / light_2 below.
    combo = {
        -- Master toggle: when false, all combo chaining is disabled (each attack is standalone).
        enabled = true,
        -- When true, pressing heavy during a light chain triggers a special finisher.
        -- When false, only light→light chains work; heavy is always independent.
        mixed_combos = true,
        -- Combo timing and chain length are controlled per-attack via combo_links
        -- and combo_window in each attack definition below.
    },

    -- ========================================================================
    -- Combat feature switches
    -- ========================================================================
    -- These are the setup-wizard friendly combat toggles. Use them to enable
    -- or disable entire combat systems without editing attack definitions.
    features = {
        combo_chaining = true,   -- allow chained attacks during combo windows
        mixed_finishers = true,  -- allow L+H / L-L+H mixed combo finishers
        attack_cancels = true,   -- allow cancel windows to unlock dash/parry/jump outs
        parry = true,            -- enable parry input and parry resolution
        perfect_parry = true,    -- reward early parries with perfect-parry behavior
        parry_counter = true,    -- enable the boosted counter-attack follow-up window
        cut_projectiles = false, -- Player melee swings cut enemy shots; each attack may opt out with cuts_projectiles=false.
        parry_reflects = false,  -- Perfect parries return shots whose enemy or boss pattern opts into reflect.
        parry_tells = false,     -- Flash parryable windups and tint parryable enemy shots; opt in to change their art.
        aerial_attacks = true,   -- use dedicated air attack mappings instead of ground fallbacks
        aerial_juggle = true,    -- allow launchers / pogo-style aerial combo extensions
        up_attacks = true,       -- Up + attack selects an authored upward attack when available
    },

    directional = {
        up_threshold = 0.6, -- Minimum upward stick/keyboard value for an up attack (0..1).
    },
    aim = {
        mode = "eight", -- "eight" follows the stick; "four" snaps cardinally; "facing" restores straight shots.
        deadzone = 0.5, -- Radial stick threshold; neutral input shoots in the facing direction.
        allow_down_grounded = false, -- Downward shots require being airborne unless enabled here.
        stance = false, -- Hold Ranged on the ground to stop walking and aim; release to fire. Down + Ranged still places a usable bomb.
    },

    -- Projectile counterplay feedback and returned-shot tuning. Speeds are
    -- multipliers; lifetime counts unpaused seconds. Both features ship off.
    projectiles = {
        cut_fx = "hit_impact",      -- fx_types.lua effect id.
        cut_sfx = "hit_projectile", -- sound_bank.lua sound id.
        reflect_speed_mult = 1.2,   -- Multiply the incoming shot speed.
        reflect_damage_mult = 1.0, -- Used when an enemy's multiplier is -1.
        reflect_lifetime = 1.5,    -- Returned shot lifetime in seconds.
    },

    parry = {
        window = 0.18,              -- total parry window in seconds
        cooldown = 0.15,            -- cooldown after parry attempt
        perfect_window = 0.08,      -- first N seconds count as perfect parry
        -- Game Settings > Combat > Invincibility: seconds after a successful
        -- parry during which hits do no damage, lethal hits included; damage
        -- over time keeps ticking. 0 turns it off.
        iframes = 0.30,
        counter_window = 0.50,      -- time to input a boosted counter-attack
        stun_duration = 0.60,       -- how long the attacker is stunned
        counter_damage_mult = 2.0,  -- counter-attack damage multiplier
        animation = "attack_alt",   -- animation played when parry stance starts
        success_sfx = "parry_success",   -- sound on successful parry
        miss_sfx = "parry_miss",         -- sound when parry window expires (whiff)
        perfect_feedback = "perfect_parry",
        success_feedback = "parry",
        -- Perfect parry time-slow: brief slow-motion on perfect parry for emphasis.
        -- Uses global set_time_step so everything slows. Keep duration short.
        perfect_time_slow_duration = 0.15,  -- seconds of slow-motion
        perfect_time_slow_factor = 0.3,     -- time scale (0.3 = 30% speed)
        -- Game Settings > Combat > Parry: a parried enemy slides this many
        -- pixels straight away from the player, slowing to a stop, during its
        -- stun. Its knockback resistance shortens the slide and walls stop it.
        -- Bosses never move, and a parried shot never pushes its shooter.
        -- 0 turns that push off.
        knockback_px = 32,          -- ordinary parry (Q pressed a little early)
        perfect_knockback_px = 128, -- perfect parry
        knockback_time = 0.25,      -- seconds the slide lasts
    },

    default_inputs = {
        light = "light_1",
        heavy = "heavy_1",
        ranged = "ranged_shot",
    },

    attack_sets = {
        default = {
            grounded = {
                light = "light_1",
                up_light = "up_light", -- Up + Light on the ground.
                heavy = "heavy_1",
                ranged = "ranged_shot",
                charged = "charged_slash",
            },
            aerial = {
                light = "air_light_1",
                up_light = "air_up_light", -- Up + Light in the air.
                heavy = "air_launcher",
                ranged = "ranged_shot",
                down_strike = "down_strike",
            },
            parry = {
                counter = "counter_attack",
            },
        },
    },

    attacks = {
        -- Up attacks use base pixels at units_version 2, like light_2 and air attacks.
        -- They do not receive the light_1/heavy_1 player-scale geometry multiplier.
        -- Game Settings Up attack damage overrides the first hitbox of both ids.
        up_light = {
            label = "Up light", -- Short name in Game Settings; does not change the attack id.
            settings_order = 60, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "up_light", input = "light", weapon_class = "melee", state = "ground",
            action_tag = "light_attack", -- Existing tag for switches and breakables.
            animation = "weapon_attack", -- Use "attack_up" only after adding that clip to player_art.lua required.
            cooldown = 0.18, -- Seconds between completed attacks; no combo links.
            timeline = {
                startup = 0.05, recovery = 0.04, -- Seconds before the hit and after the last hit window.
                active_windows = { { start = 0.05, duration = 0.10, hitboxes = { {
                    width = 128, height = 108, damage = 1, -- Full box size in base pixels and hit damage.
                    knockback = 60, ky = 120, stun_t = 0.12, -- Horizontal/upward impulse and stun seconds.
                    reaction_type = "light", parryable = false, -- Existing light hit reaction.
                    anchor = { spine_bone = "item_near", sprite_offset = { x = 0, y = 120 },
                        spine_offset = { x = 0, y = 48 } }, -- Above the sprite head / rig's near item.
                } } } },
            },
            sfx = { start = "attack_light" }, -- sound_bank.lua id.
        },

        air_up_light = {
            label = "Air up light", -- Short name in Game Settings; does not change the attack id.
            settings_order = 70, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "air_up_light", input = "light", weapon_class = "melee", state = "air",
            action_tag = "light_attack", -- Existing tag for switches and breakables.
            animation = "weapon_attack", -- Use "attack_up" only after adding that clip to player_art.lua required.
            cooldown = 0.18, -- Seconds between completed attacks; no combo links.
            timeline = {
                startup = 0.05, recovery = 0.04, -- Seconds before the hit and after the last hit window.
                active_windows = { { start = 0.05, duration = 0.10, hitboxes = { {
                    width = 128, height = 108, damage = 1, -- Full box size in base pixels and hit damage.
                    knockback = 60, ky = 120, stun_t = 0.12, -- Horizontal/upward impulse and stun seconds.
                    reaction_type = "light", parryable = false, -- Existing light hit reaction.
                    anchor = { spine_bone = "item_near", sprite_offset = { x = 0, y = 120 },
                        spine_offset = { x = 0, y = 48 } }, -- Above the sprite head / rig's near item.
                } } } },
            },
            sfx = { start = "attack_light" }, -- sound_bank.lua id.
        },

        -- Optional heavy example: uncomment and add up_heavy = "up_heavy" to the
        -- desired attack_sets bucket. Otherwise Up + Heavy keeps its normal attack.
        -- Shares the up-attack anchor, timing and pixel conventions explained above.
        -- up_heavy = {
        --     label = "Up heavy", -- Short name in Game Settings.
        --     settings_order = 75, -- After upward light attacks, before other air attacks.
        --     energy_cost = 0, -- Max energy units; 0 is free.
        --     damage_type = "slash", attack_id = "up_heavy", input = "heavy",
        --     weapon_class = "melee", state = "ground", action_tag = "heavy_attack",
        --     animation = "weapon_attack", cooldown = 0.3,
        --     timeline = { startup = 0.08, recovery = 0.05, active_windows = {
        --         { start = 0.08, duration = 0.15, hitboxes = {
        --             { width = 128, height = 108, damage = 2, knockback = 60, ky = 150,
        --               stun_t = 0.15, reaction_type = "heavy", parryable = false,
        --               anchor = { spine_bone = "item_near", sprite_offset = { x = 0, y = 120 },
        --                   spine_offset = { x = 0, y = 48 } } },
        --         } },
        --     } },
        --     sfx = { start = "attack_heavy" },
        -- },

        light_1 = {
            label = "Light combo 1", -- Short name in Game Settings; does not change the attack id.
            settings_order = 10, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "light_1",
            input = "light",
            weapon_class = "melee",
            state = "ground",
            action_tag = "light_attack",
            animation = "punch",
            cooldown = 0.18,
            timeline = {
                startup = 0.05,
                active_windows = {
                    {
                        start = 0.05,
                        duration = 0.10,
                        hitboxes = {
                            {
                                width = 210,
                                height = 175,
                                damage = 1,
                                knockback = 90,
                                stun_t = 0.12,
                                reaction_type = "light",
                                parryable = false,
                                anchor = {
                                    spine_bone = "hand_far",
                                    sprite_offset = { x = 52, y = 12 },
                                    spine_offset = { x = 0, y = 0 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.04, -- Seconds after the last hit window closes.
            },
            combo_window = { start = 0.12, duration = 0.28 },
            combo_links = {
                light = "light_2",
                heavy = "mixed_finisher_1",  -- L+H finisher (only queued during combo window)
            },
            cancel_windows = {
                { start = 0.13, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true, jump = true } },
            },
            sfx = { start = "attack_light" },
        },

        light_2 = {
            label = "Light combo 2", -- Short name in Game Settings; does not change the attack id.
            settings_order = 20, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "light_2",
            input = "light",
            weapon_class = "melee",
            state = "ground",
            action_tag = "light_attack",
            animation = "attack",
            cooldown = 0.18,
            timeline = {
                startup = 0.06,
                active_windows = {
                    {
                        start = 0.06,
                        duration = 0.10,
                        hitboxes = {
                            {
                                width = 130,
                                height = 104,
                                damage = 1.25,
                                knockback = 105,
                                stun_t = 0.14,
                                reaction_type = "medium",
                                parryable = false,
                                anchor = {
                                    spine_bone = "hand_far",
                                    sprite_offset = { x = 58, y = 12 },
                                    spine_offset = { x = 2, y = 0 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.05, -- Seconds after the last hit window closes.
            },
            combo_window = { start = 0.14, duration = 0.30 },
            combo_links = {
                light = "light_3",
                heavy = "mixed_finisher_2",  -- L-L+H launcher finisher
            },
            cancel_windows = {
                { start = 0.15, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true, jump = true } },
            },
            sfx = { start = "attack_light" },
        },

        light_3 = {
            label = "Light combo 3", -- Short name in Game Settings; does not change the attack id.
            settings_order = 30, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "light_3",
            input = "light",
            weapon_class = "melee",
            state = "ground",
            action_tag = "light_attack",
            animation = "weapon_attack",
            cooldown = 0.20,
            timeline = {
                startup = 0.08,
                active_windows = {
                    {
                        start = 0.08,
                        duration = 0.12,
                        hitboxes = {
                            {
                                width = 144,
                                height = 110,
                                damage = 1.75,
                                knockback = 165,
                                stun_t = 0.18,
                                reaction_type = "heavy",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_near",
                                    sprite_offset = { x = 64, y = 18 },
                                    spine_offset = { x = 8, y = 4 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.06, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.20, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true } },
            },
            sfx = { start = "attack_heavy" },
        },

        heavy_1 = {
            label = "Heavy", -- Short name in Game Settings; does not change the attack id.
            settings_order = 40, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "heavy_1",
            input = "heavy",
            weapon_class = "melee",
            state = "ground",
            action_tag = "heavy_attack",
            animation = "weapon_attack",
            cooldown = 0.40,
            timeline = {
                startup = 0.11,
                active_windows = {
                    {
                        start = 0.11,
                        duration = 0.14,
                        hitboxes = {
                            {
                                width = 269.5,
                                height = 203,
                                damage = 2,
                                knockback = 180,
                                stun_t = 0.22,
                                reaction_type = "heavy",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 68, y = 20 },
                                    spine_offset = { x = 10, y = 5 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.10, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.24, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true } },
            },
            sfx = { start = "attack_heavy" },
        },

        charged_slash = {
            label = "Charged slash", -- Short name in Game Settings; does not change the attack id.
            settings_order = 50, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "charged_slash",
            input = "light",
            weapon_class = "melee",
            state = "ground",
            action_tag = "charge_attack",
            animation = "weapon_attack",
            cooldown = 0.55,
            timeline = {
                startup = 0.12,
                active_windows = {
                    {
                        start = 0.12,
                        duration = 0.14,
                        hitboxes = {
                            {
                                width = 168,
                                height = 124,
                                damage = 2.5,
                                knockback = 260,
                                stun_t = 0.28,
                                reaction_type = "heavy",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 72, y = 24 },
                                    spine_offset = { x = 12, y = 8 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.08, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.24, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true } },
            },
            sfx = { start = "attack_heavy" },
        },

        air_light_1 = {
            label = "Air light", -- Short name in Game Settings; does not change the attack id.
            settings_order = 80, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "air_light_1",
            input = "light",
            weapon_class = "melee",
            state = "air",
            action_tag = "light_attack",
            animation = "air_spin",
            cooldown = 0.18,
            movement = {
                hold_vy_min = -120,
            },
            timeline = {
                startup = 0.04,
                active_windows = {
                    {
                        start = 0.04,
                        duration = 0.12,
                        hitboxes = {
                            {
                                width = 128,
                                height = 108,
                                damage = 1.1,
                                knockback = 110,
                                ky = 35,
                                stun_t = 0.12,
                                reaction_type = "light",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 50, y = 10 },
                                    spine_offset = { x = 0, y = 0 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.00, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.12, actions = { dash = true, backdash = true, blink = true, parry = true, jump = true } },
            },
            sfx = { start = "attack_light" },
        },

        air_launcher = {
            label = "Air launcher", -- Short name in Game Settings; does not change the attack id.
            settings_order = 90, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "air_launcher",
            input = "heavy",
            weapon_class = "melee",
            state = "air",
            action_tag = "heavy_attack",
            animation = "weapon_attack",
            cooldown = 0.42,
            movement = {
                hold_vy_min = -80,
            },
            timeline = {
                startup = 0.08,
                active_windows = {
                    {
                        start = 0.08,
                        duration = 0.12,
                        hitboxes = {
                            {
                                width = 146,
                                height = 120,
                                damage = 1.75,
                                knockback = 120,
                                ky = 220,
                                stun_t = 0.18,
                                reaction_type = "launch",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_near",
                                    sprite_offset = { x = 60, y = 18 },
                                    spine_offset = { x = 8, y = 6 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.04, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.16, actions = { dash = true, backdash = true, blink = true, parry = true } },
            },
            sfx = { start = "attack_heavy" },
        },

        down_strike = {
            label = "Down strike", -- Short name in Game Settings; does not change the attack id.
            settings_order = 100, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "down_strike",
            input = "light",
            weapon_class = "melee",
            state = "down_strike",
            action_tag = "down_strike",
            animation = "weapon_attack",
            cooldown = 0.22,
            movement = {
                hold_vy_max = -260,
            },
            timeline = {
                startup = 0.03,
                active_windows = {
                    {
                        start = 0.03,
                        duration = 0.18,
                        hitboxes = {
                            {
                                width = 112,
                                height = 104,
                                damage = 1.5,
                                knockback = 0,
                                ky = -80,
                                stun_t = 0.15,
                                reaction_type = "medium",
                                parryable = false,
                                on_hit_msg = "mvtk_pogo",
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 0, y = -32 },
                                    spine_offset = { x = 0, y = -12 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.00, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.16, actions = { dash = true, backdash = true, blink = true } },
            },
            sfx = { start = "attack_light" },
        },

        ranged_shot = {
            label = "Ranged shot", -- Short name in Game Settings; does not change the attack id.
            settings_order = 110, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "projectile", -- Base type before ability infusions.
            attack_id = "ranged_shot",
            input = "ranged",
            weapon_class = "ranged",
            state = "ground",
            action_tag = "ranged_attack",
            animation = "shoot",
            -- Optional logical clips; blank retains shoot. Missing clips use the existing controller fallback.
            animation_aim = { up = "", diagonal_up = "", down = "", diagonal_down = "" },
            cooldown = 0.35,
            timeline = {
                startup = 0.06,
                active_windows = {
                    {
                        start = 0.06,
                        duration = 0.04,
                        projectile = {
                            damage = 1,
                            speed = 2100,
                            lifetime = 1.5,
                            stun_t = 0.08,
                            reaction_type = "light",
                            parryable = true,
                            offset = { x = 24, y = 18 }, -- Reach along aim and muzzle height, in base pixels.
                            aim = true, -- false keeps this projectile facing-only; explicit dir_x/dir_y also opt out.
                            -- Optional kx/ky override directional knockback (default 60*sign(dx), 60*dy).
                        },
                    },
                },
                recovery = 0.08, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.10, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true, jump = true } },
            },
            sfx = { start = "projectile_fire" },
        },

        -- ====================================================================
        -- Mixed combo finishers (L+H and L-L+H)
        -- These are reached via combo_links when pressing heavy during a
        -- light combo. Disable by removing the heavy entries from
        -- light_1/light_2 combo_links above, or set combo.mixed_combos = false.
        -- ====================================================================

        -- L+H finisher — strong overhead slash after one light hit
        mixed_finisher_1 = {
            label = "Mixed finisher 1", -- Short name in Game Settings; does not change the attack id.
            settings_order = 120, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "mixed_finisher_1",
            input = "heavy",
            weapon_class = "melee",
            state = "ground",
            action_tag = "heavy_attack",
            animation = "sword_stab",
            cooldown = 0.35,
            timeline = {
                startup = 0.08,
                active_windows = {
                    {
                        start = 0.08,
                        duration = 0.14,
                        hitboxes = {
                            {
                                width = 148,
                                height = 112,
                                damage = 2.0,
                                knockback = 200,
                                stun_t = 0.20,
                                reaction_type = "heavy",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 64, y = 16 },
                                    spine_offset = { x = 8, y = 4 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.06, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.22, actions = { dash = true, slide = true, backdash = true, blink = true, parry = true } },
            },
            sfx = { start = "attack_heavy" },
        },

        -- L-L+H launcher finisher — powerful upward strike after two lights
        mixed_finisher_2 = {
            label = "Mixed finisher 2", -- Short name in Game Settings; does not change the attack id.
            settings_order = 130, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "mixed_finisher_2",
            input = "heavy",
            weapon_class = "melee",
            state = "ground",
            action_tag = "heavy_attack",
            animation = "sword_attack",
            cooldown = 0.40,
            timeline = {
                startup = 0.09,
                active_windows = {
                    {
                        start = 0.09,
                        duration = 0.14,
                        hitboxes = {
                            {
                                width = 156,
                                height = 120,
                                damage = 2.5,
                                knockback = 160,
                                ky = 250,           -- strong upward launch
                                stun_t = 0.24,
                                reaction_type = "launch",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 68, y = 22 },
                                    spine_offset = { x = 10, y = 6 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.08, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.24, actions = { dash = true, backdash = true, blink = true, parry = true } },
            },
            sfx = { start = "attack_heavy" },
        },

        counter_attack = {
            label = "Counter attack", -- Short name in Game Settings; does not change the attack id.
            settings_order = 140, -- Position in the Attacks picker; new attacks may omit this to sort by id last.
            energy_cost = 0, -- Max energy units paid once per attack; 0 is free.
            damage_type = "slash", -- Base type before ability infusions.
            attack_id = "counter_attack",
            input = "light",
            weapon_class = "melee",
            state = "counter",
            action_tag = "parry_counter",
            animation = "weapon_attack",
            cooldown = 0.25,
            timeline = {
                startup = 0.04,
                active_windows = {
                    {
                        start = 0.04,
                        duration = 0.12,
                        hitboxes = {
                            {
                                width = 164,
                                height = 126,
                                damage = 2.5,
                                knockback = 240,
                                ky = 80,
                                stun_t = 0.24,
                                reaction_type = "stun",
                                parryable = false,
                                anchor = {
                                    spine_bone = "item_part_near",
                                    sprite_offset = { x = 72, y = 20 },
                                    spine_offset = { x = 12, y = 6 },
                                },
                            },
                        },
                    },
                },
                recovery = 0.04, -- Seconds after the last hit window closes.
            },
            cancel_windows = {
                { start = 0.16, actions = { dash = true, backdash = true, blink = true } },
            },
            sfx = { start = "attack_heavy" },
        },
    },
}
