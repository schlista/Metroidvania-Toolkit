--- Boss Attack Patterns
-- Defines reusable attack patterns for bosses
-- Patterns can be mixed and matched across different bosses
--
-- Legacy fields in your own attack_patterns.lua still work:
-- * special.teleport_attack blinks behind the player. Set special["then"] to
--   a pattern name, or leave it off for the built-in slash. For that slash,
--   attack_range (or radius) sets its reach, width/height set its hitbox
--   half-extents, damage (or attack_damage) sets its hit, knockback sets push,
--   and delay sets the swing warning time. With a named follow-up, delay
--   instead extends the blink warning and the named attack keeps its own fields.
-- * special.blade_storm takes count (or projectile_count), speed, lifetime,
--   damage and knockback for the shots. Without lifetime, radius (or width
--   or height) is the travel distance. Delay extends the warning.
-- * special.explosion sets the boss-centred circle with radius (or width or
--   height), delay after the initial warning, damage, and knockback.
-- * special.clone uses summon as authored. If omitted in summon, count and
--   radius (or width or height) set the number and distance from the boss.
--   Delay extends the warning. Helpers use their own damage and movement.
-- * hazard.poison_cloud and hazard.spike_trap accept position = "boss" or
--   "player" (default). Radius sets a circle, or count sizes the circle if
--   radius is absent. Width or height selects a box using full dimensions.
--   Delay runs after the warning. Damage is per tick; damage_per_second
--   converts to damage per tick. Knockback sets the push on each hit.
--   Lifetime or active_duration controls how long the zone remains.
-- * hazard.fire_wave uses width (or range or radius) for travel distance,
--   height for jump clearance, and speed, damage and knockback for the front.
--   Delay extends the warning. Each front can hit once and apply Burn.
-- * A legacy block's telegraph_duration sets the initial warning time.
--   On a single-hit legacy attack, damage_per_second can supply damage if
--   no hit damage is set. A hazard without hazard.type still does one area
--   hit at the player, with telegraph_duration or delay as its old hit delay.
--   A special.callback still runs as authored.
--
-- The avoid field supplies the catalogue's player hint. Combat ignores it.
-- @module attack_patterns

local M = {}

-- Minimal asset-free patterns used by default_boss and the shipped Tiled
-- fixture. Keep these ids stable: they are the safe first-run boss contract.
M.test_melee = {
    avoid = "Leave the swing box in front of the boss.",
    type = "melee",
    telegraph_time = 0.35,
    duration = 0.35,
    cooldown = 1.5,
    damage = 1,
    range = 72,
    width = 56,
    height = 64,
    knockback = 120,
    animation = "attack",
}

M.test_projectile = {
    avoid = "Step out of the shot's line.",
    type = "projectile",
    telegraph_time = 0.45,
    duration = 0.3,
    cooldown = 2.0,
    damage = 1,
    projectiles = {
        count = 1,
        speed = 220,
        damage = 1,
        lifetime = 3.0,
    },
    animation = "ranged_attack",
}

--[[============================================================================
    STARTER PATTERNS (Atlas-friendly)
    These align with animations in /developer/assets/atlas/boss.atlas
==============================================================================]]

M.sentinel_swipe = {
    avoid = "Back away from the front swing box.",
    type = "melee",
    telegraph_time = 0.4,
    duration = 0.6,
    cooldown = 2.5,

    damage = 3,
    range = 90,
    width = 90,
    height = 80,
    animation = "attack",
}

M.sentinel_burst = {
    avoid = "Move between the three shots.",
    type = "projectile",
    telegraph_time = 0.5,
    duration = 0.4,
    cooldown = 3.0,

    damage = 2,
    projectiles = {
        count = 3,
        spread = 20,
        speed = 260,
        lifetime = 4.0,
    },

    animation = "ranged_attack",
}

M.sentinel_slam = {
    avoid = "Leave the circle around the boss.",
    type = "aoe",
    telegraph_time = 0.7,
    duration = 0.6,
    cooldown = 4.5,

    damage = 4,
    aoe = {
        radius = 140,
        delay = 0.3,
        knockback = 220,
    },

    animation = "slam",
}

M.sentinel_summon = {
    avoid = "Leave the spawn circles and avoid touching the slimes.",
    type = "summon", telegraph_time = 0.8, duration = 0.5, cooldown = 6,
    telegraph_shape = "circle", telegraph_size = {x = 64, y = 64},
    summon = {count = 2, enemy_type = "slime", spawn_radius = 120},
    animation = "summon",
}

--[[============================================================================
    CACTUS COLOSSUS PATTERNS
    These map directly to the three clips in cactus_boss.atlas.
==============================================================================]]

M.cactus_ground_slam = {
    avoid = "Jump above the marked ground band or move outside it.",
    type = "aoe",
    telegraph_time = 0.55,
    duration = 0.5,
    cooldown = 3.8,

    damage = 3,
    aoe = {
        -- Match (and slightly exceed) the 320px attack commitment range so
        -- the cactus cannot choose a guaranteed-miss slam at max range.
        radius = 340,
        ground_only = true,
        vertical_clearance = 96.5, -- Player feet above the floor needed to clear the slam.
        -- attack_1 runs at 8 FPS; frame three lands 0.25 seconds in.
        delay = 0.25,
        knockback = 300,
        knockback_y = 140,
        effect_duration = 0.5,
    },

    animation = "attack_1",
}

M.cactus_needle_volley = {
    avoid = "Dodge between the needle spokes.",
    type = "projectile",
    telegraph_time = 0.6,
    duration = 0.5,
    cooldown = 3.8,

    damage = 1,
    projectiles = {
        count = 8,
        -- Eight evenly spaced needles form a full radial burst.
        spread = 315,
        speed = 380,
        lifetime = 4.0,
    },

    animation = "attack_2",
}

M.cactus_charge = {
    avoid = "Jump above the marked charge lane.",
    type = "charge",
    telegraph_time = 0.6,
    duration = 0.8,
    cooldown = 5.5,

    -- Cross most of the arena quickly after a readable wind-up. The low
    -- vertical lane makes a committed jump the intended counter.
    dash_speed = 1650,
    dash_distance = 900,
    hitbox_half_width = 78,
    hitbox_half_height = 105,
    recovery = 0.18,
    edge_padding = 80,
    damage = 2,
    knockback = 340,
    knockback_y = 130,
    animation = "attack_3",
}

--[[============================================================================
    MELEE PATTERNS
==============================================================================]]

M.sword_combo = {
    avoid = "Step behind the boss or stay past the marked boxes until the third swing.",
    type = "melee",
    telegraph_time = 0.5,
    duration = 1.25, -- A recovery window after the third swing closes.
    cooldown = 3.0,
    warn_in_combo = true, -- Keep the opening tell when another attack calls this one.
    damage = 2, active_time = 0.14, animation = "slash_1",
    -- Delays are measured from the first hit, including the next swing's warning.
    followup_strikes = {
        {delay = 0.4, telegraph_time = 0.25, active_time = 0.14, damage = 2, animation = "slash_2"},
        {delay = 0.8, telegraph_time = 0.25, active_time = 0.14, damage = 3, animation = "thrust"},
    },
}

M.vine_whip = {
    avoid = "Back away from the marked swing box.",
    type = "melee",
    telegraph_time = 0.3,
    duration = 0.8,
    cooldown = 2.5,

}

M.berserk_whip = {
    avoid = "Get behind the boss or out of range until the fourth, longer whip.",
    type = "melee",
    telegraph_time = 0.45,
    duration = 1.6, -- A recovery window after the fourth whip closes.
    cooldown = 2.0,
    warn_in_combo = true, -- Keep the opening tell when another attack calls this one.
    damage = 3, range = 100, width = 70, active_time = 0.12, animation = "vine_attack", -- Reaches 120 px.
    followup_strikes = {
        {delay = 0.35, telegraph_time = 0.21, active_time = 0.12, damage = 3, animation = "vine_fury_2"},
        {delay = 0.7, telegraph_time = 0.21, active_time = 0.12, damage = 3, animation = "vine_fury_3"},
        {delay = 1.05, telegraph_time = 0.23, active_time = 0.14, damage = 4, range = 120, animation = "vine_fury_4"},
    },
}

M.ground_slam = {
    avoid = "Get outside the marked circle around the boss.",
    type = "aoe",
    telegraph_time = 1.0,
    duration = 1.5, -- After the delayed slam, leave one second to punish it.
    cooldown = 6.0,
}

M.crystal_slam = {
    avoid = "Clear the marked circle around the boss.",
    type = "aoe",
    telegraph_time = 1.2,
    duration = 1.5, -- After the delayed slam, leave one second to punish it.
    cooldown = 5.0,
}

M.dash_slash = {
    avoid = "Jump the charge or move behind the boss.",
    type = "charge",
    telegraph_time = 0.8,
    duration = 0.6,
    cooldown = 4.0,

    dash_speed = 500,
    dash_distance = 200,
    damage = 3,
    knockback = 250,
    animation = "dash_attack",
}

--[[============================================================================
    PROJECTILE PATTERNS
==============================================================================]]

M.crystal_throw = {
    avoid = "Step out of the incoming shot's line.",
    type = "projectile",
    telegraph_time = 0.6,
    duration = 0.4,
    cooldown = 3.5,

    projectiles = {
        count = 1,
        speed = 300,
        damage = 3,
        lifetime = 5.0,
    },

    animation = "throw",
}

M.crystal_barrage = {
    avoid = "Move between the crystals in the fan.",
    type = "projectile",
    telegraph_time = 1.0,
    duration = 0.55, -- The volley leaves together. Recover while it travels.
    cooldown = 7.0,

    projectiles = {
        count = 12,
        spread = 66, -- Total angle of the simultaneous fan.
        speed = 350,
        damage = 2,
        lifetime = 6.0,
    },

    animation = "barrage",
}

M.dark_wave = {
    avoid = "Dodge between the incoming bolts.",
    type = "projectile",
    telegraph_time = 0.7,
    duration = 0.5,
    cooldown = 4.0,

    projectiles = {
        count = 5,
        spread = 60,  -- Total spread in degrees
        speed = 250,
        damage = 3,
        lifetime = 5.0,
    },

    animation = "cast_dark",
}

M.shadow_bolt = {
    avoid = "Move off the bolt's path.",
    type = "projectile",
    telegraph_time = 0.4,
    duration = 0.3,
    cooldown = 2.5,

    projectiles = {
        count = 1,
        speed = 400,
        damage = 2,
        lifetime = 4.0,
    },

    animation = "shadow_cast",
}

M.shadow_barrage = {
    avoid = "Move between the incoming bolts.",
    type = "projectile",
    telegraph_time = 1.0,
    duration = 0.55, -- The volley leaves together. Recover while it travels.
    cooldown = 6.0,

    projectiles = {
        count = 9,
        spread = 320, -- Nine bolts at 40-degree intervals, with one aimed at the player.
        speed = 300,
        damage = 3,
        lifetime = 5.0,
    },

    animation = "shadow_burst",
}

M.laser_shot = {
    avoid = "Leave the horizontal beam lane.",
    type = "beam",
    telegraph_time = 1.0,
    duration = 0.5,
    cooldown = 4.0,

    damage = 4,

    animation = "laser_charge",
}

M.laser_sweep = {
    avoid = "Get behind the boss or past the beam's tip before it sweeps down.",
    type = "sweep",
    telegraph_time = 1.5,
    duration = 2.6, -- Sweep wind-up, travel and recovery after the warning.
    cooldown = 8.0,
    damage = 3,
    -- Sweep from directly above to directly below, across the facing side.
    sweep = {from_angle = 90, to_angle = -90, angular_speed = 90, windup = 0.25, length = 500, width = 15},

    animation = "laser_sweep",
}

--[[============================================================================
    SUMMON PATTERNS
==============================================================================]]

M.summon_thorns = {
    avoid = "Leave the spawn circles and avoid the ground crawlers.",
    type = "summon", telegraph_time = 1, duration = 1, cooldown = 12,
    telegraph_shape = "circle", telegraph_size = {x = 64, y = 64},
    -- Ground crawlers patrol and chase. The cap is shared with other summons.
    summon = {enemy_type = "crawler", count = 2, spawn_radius = 100, max_active = 3},
    animation = "summon",
}

M.summon_shadows = {
    avoid = "Leave the spawn circles and dodge the ghosts and their shots.",
    type = "summon", telegraph_time = 1.2, duration = 0.55, cooldown = 15,
    telegraph_shape = "circle", telegraph_size = {x = 64, y = 64},
    -- Ghosts float and shoot. One summon can fill the boss's three-helper cap.
    summon = {enemy_type = "ghost", count = 3, spawn_radius = 100, max_active = 3},
    animation = "summon_dark",
}

M.summon_crystals = {
    avoid = "Give the spawn circles and cycling Spike Shells room.",
    type = "summon", telegraph_time = 0.8, duration = 1, cooldown = 10,
    telegraph_shape = "circle", telegraph_size = {x = 64, y = 64},
    -- Stationary Spike Shells alternate exposed and spiked states.
    summon = {enemy_type = "spike_shell", count = 2, spawn_radius = 100, max_active = 3},
    animation = "crystal_summon",
}

--[[============================================================================
    AOE / HAZARD PATTERNS
==============================================================================]]

M.poison_cloud = {
    avoid = "Leave the fixed circle before its first poison tick.",
    type = "zone", telegraph_time = 0.8, duration = 0.5, cooldown = 8,
    -- Freeze the cloud at the player's warning-start position.
    zone = {target = "player", shape = "circle", radius = 100, delay = 0,
        duration = 8, tick = 1, damage = 2, status = "poison", knockback = 0},
    animation = "poison_cast",
}

M.fire_wave = {
    avoid = "Jump above the low front as it passes.",
    type = "ground_wave", telegraph_time = 1, duration = 1, cooldown = 6, damage = 4,
    ground_wave = {distance = 800, speed = 800, width = 40, height = 40, status = "burn"},
    animation = "fire_cast",
}

M.root_spike = {
    avoid = "Leave the fixed circle before the spikes hit.",
    type = "zone", telegraph_time = 0.7, duration = 0.8, cooldown = 3.5, persist = false,
    -- Freeze the trap at the player's warning-start position, with one damage tick.
    zone = {target = "player", shape = "circle", radius = 90, delay = 0.25,
        duration = 0.25, tick = 0.25, damage = 3},
    animation = "root_attack",
}

--[[============================================================================
    SPECIAL / UNIQUE PATTERNS
==============================================================================]]

M.shadow_clones = {
    avoid = "Leave the spawn circles and avoid the two ghosts.",
    type = "summon", telegraph_time = 1.5, duration = 0.55, cooldown = 20,
    telegraph_shape = "circle", telegraph_size = {x = 64, y = 64},
    -- Two ghosts appear at opposite points. They share Summon Shadows' cap.
    summon = {enemy_type = "ghost", count = 2, spawn_radius = 100, max_active = 3},
    animation = "split",
}

M.blade_storm = {
    avoid = "Back away and move between the outward-firing blades.",
    -- All blades launch together. The boss can move again while they travel.
    type = "ring", telegraph_time = 2, duration = 0.65, cooldown = 15, damage = 3,
    telegraph_size = {x = 160, y = 160},
    ring = {count = 30, volleys = 1, speed = 300, lifetime = 3},
    animation = "blade_storm",
}

M.teleport_strike = {
    avoid = "Move away from the destination, then dodge the swing box.",
    type = "reposition", telegraph_time = 0.6, duration = 0.4, cooldown = 5,
    telegraph_shape = "circle", telegraph_size = {x = 72, y = 72},
    warn_in_combo = true,
    reposition = {anchor = "behind_player", style = "blink", ["then"] = "teleport_slash",
        warn_follow_up = true},
    animation = "teleport",
}

M.dark_beam = {
    avoid = "Move away from the marked line as soon as it stops following you.",
    type = "beam",
    telegraph_time = 0, -- The same tracking warning plays in a combo or as a standalone cast.
    duration = 3.2, -- Tracking, locked warning, active beam, then recovery.
    cooldown = 10.0,
    damage = 3,
    -- Track at up to 45 degrees per second, then hold the warning on its final lane.
    -- Lock time inherits default_tracking_beam_lock_time unless specified here.
    beam = {length = 600, width = 30, track_time = 1.5, tracking_speed = 45, duration = 0.8},
    animation = "dark_beam",
}

M.overload = {
    avoid = "Leave the blast circle around the boss before it fires.",
    type = "aoe", telegraph_time = 1.5, duration = 0.5, cooldown = 999, damage = 3,
    aoe = {target = "boss", radius = 200, delay = 0.8, knockback = 150},
    animation = "overload",
}

--[[============================================================================
    COMBO / SEQUENCE PATTERNS
==============================================================================]]

M.berserk_combo = {
    avoid = "Dodge the dash and swing, then clear the slam circle.",
    type = "combo",
    telegraph_time = 0.4,
    duration = 2.5,
    cooldown = 5.0,

    combo = {
        {pattern = "dash_slash", delay = 0.0},
        {pattern = "sword_combo", delay = 0.8},
        {pattern = "ground_slam", delay = 1.8},
    },

    animation = "berserk_start",
}

M.ultimate_combo = {
    avoid = "Dodge the blink swing, shots and dash, then leave the beam lane.",
    type = "combo",
    telegraph_time = 1.0,
    duration = 5.0,
    cooldown = 12.0,

    combo = {
        {pattern = "teleport_strike", delay = 0.0},
        {pattern = "shadow_barrage", delay = 1.0},
        {pattern = "dash_slash", delay = 2.5},
        {pattern = "dark_beam", delay = 3.5},
    },

    animation = "ultimate",
}

--[[============================================================================
    GRAB / THROW PATTERNS
    These pin the player on contact, hold them for `duration`, then release
    with a throw knockback. Requires grab_start/grab_hold/grab_throw
    animation keys on the boss rig.
==============================================================================]]

M.grab_and_throw = {
    avoid = "Stay outside the grab box.",
    type = "grab",
    telegraph_time = 0.6,
    duration = 1.8,  -- total pattern duration (includes hold + throw)
    cooldown = 7.0,

    grab = {
        reach = 110,
        width = 110,
        height = 90,
        damage = 4,
        duration = 1.0,           -- how long the player is held
        throw_knockback = 420,
        throw_knockback_y = 240,
    },

    animation = "grab_start",
}

M.titan_grab_slam = {
    avoid = "Back away from the grab box.",
    -- Grab then immediately slam: held duration is short, throw knockback
    -- is mostly vertical so the player is smashed into the ground.
    type = "grab",
    telegraph_time = 0.8,
    duration = 2.2,
    cooldown = 10.0,

    grab = {
        reach = 140,
        width = 140,
        height = 120,
        damage = 6,
        duration = 0.6,
        throw_knockback = 120,
        throw_knockback_y = -600,
    },

    animation = "grab_start",
}

--[[============================================================================
    HEAL PATTERNS
==============================================================================]]

M.boss_self_heal = {
    avoid = "Interrupt the heal to stop its remaining ticks.",
    type = "heal",
    telegraph_time = 1.2,
    duration = 2.5,
    cooldown = 18.0,

    heal = {
        amount = 8,
        ticks = 5,
        interval = 0.4,
    },

    animation = "heal",
}

--[[============================================================================
    BUFF PATTERNS
    Temporary multipliers applied to the boss itself — no damage to player.
==============================================================================]]

M.enrage_buff = {
    avoid = "Give the boss room while it is powered up.",
    type = "buff",
    telegraph_time = 0.6,
    duration = 1.2,
    cooldown = 15.0,

    buff = {
        duration = 6.0,
        damage_multiplier = 1.5,
        speed_multiplier = 1.3,
    },

    animation = "enrage",
}

M.defensive_stance = {
    avoid = "Wait for the defensive stance to expire.",
    type = "buff",
    telegraph_time = 0.4,
    duration = 1.0,
    cooldown = 12.0,

    buff = {
        duration = 5.0,
        defense_bonus = 2,
        speed_multiplier = 0.8,
    },

    animation = "shield_up",
}

--[[============================================================================
    SHIELD PATTERNS
    Absorbs incoming damage until HP pool is depleted or duration expires.
==============================================================================]]

M.absorb_shield = {
    avoid = "Break the shield or wait for it to expire.",
    type = "shield",
    telegraph_time = 0.5,
    duration = 1.0,
    cooldown = 14.0,

    shield = {
        hp = 30,
        duration = 6.0,
    },

    animation = "shield_up",
}

--[[============================================================================
    PARRY WINDOW PATTERNS
    Opens a counter-attack window; if struck during the window, the boss
    fires `counter_pattern` at the attacker.
==============================================================================]]

M.counter_stance = {
    avoid = "Wait for the counter window to close before attacking.",
    type = "parry_window",
    telegraph_time = 0.3,
    duration = 0.8,
    cooldown = 6.0,

    parry_window = {
        window = 0.5,
        counter_pattern = "dash_slash",
    },

    animation = "parry",
}

--[[============================================================================
    ENVIRONMENTAL PATTERNS
    Play live arena effects. Screen shake and flash play once. The other
    effects in these patterns hold for environmental.duration seconds.
==============================================================================]]

M.ceiling_collapse = {
    avoid = "Stand in the unmarked gap while debris falls.",
    -- Nine drops take one second to launch. Recovery starts after the last drop.
    type = "rain", telegraph_time = 1.5, duration = 1.5, cooldown = 20, damage = 2,
    rain = {count = 9, gap_width = 160, gap_at = "player", stagger = 0.125,
        speed = 300, lifetime = 4, shake = "heavy"},
    animation = "roar",
}

M.arena_pulse = {
    avoid = "Give yourself space to move while the arena slows.",
    type = "environmental",
    telegraph_time = 0.6,
    duration = 1.5,
    cooldown = 10.0,

    environmental = {
        effect_ids = {"screen_shake", "flash", "slow_motion"},
        shake = {intensity = "medium"},
        duration = 1.5,
    },

    animation = "taunt",
}

--[[============================================================================
    MINE / TRAP PATTERNS
    Deploy stationary hitboxes that trigger on player contact.
==============================================================================]]

M.plant_mine = {
    avoid = "Stay outside the planted mine's circle.",
    type = "mine",
    telegraph_time = 0.4,
    duration = 0.5,
    cooldown = 5.0,

    mine = {
        radius = 56,
        damage = 3,
        lifetime = 8.0,
        arm_delay = 0.6,
        position = "boss",   -- or "player" to plant at player feet
        knockback = 280,
    },

    animation = "cast_start",
}

M.shadow_trap = {
    avoid = "Leave the marked spot before the mine arms.",
    type = "mine",
    telegraph_time = 0.3,
    duration = 0.4,
    cooldown = 4.0,

    mine = {
        radius = 40,
        damage = 2,
        lifetime = 12.0,
        arm_delay = 0.3,
        position = "player",
    },

    animation = "summon",
}

--[[============================================================================
    WAVE PATTERNS
    Expanding ring AOEs — players caught inside any active ring take damage.
==============================================================================]]

M.shockwave = {
    avoid = "Move out of each expanding band before it reaches you.",
    type = "wave",
    telegraph_time = 0.8,
    duration = 1.6,
    cooldown = 9.0,

    wave = {
        rings = 3,
        ring_delay = 0.35,
        radius_step = 90,
        thickness = 44,
        damage = 3,
        knockback = 260,
    },

    animation = "slam",
}

M.pulse_nova = {
    avoid = "Step between the expanding damage bands.",
    type = "wave",
    telegraph_time = 1.0,
    duration = 2.5,
    cooldown = 12.0,

    wave = {
        rings = 5,
        ring_delay = 0.3,
        radius_step = 70,
        thickness = 36,
        damage = 2,
    },

    animation = "cast_loop",
}

-- Lingering zones. The cast ends independently of the fixed, ticking area.
M.poison_pool = {
    avoid = "Leave the marked circle before its first poison tick.",
    type = "zone", telegraph_time = 0.75, duration = 0.25, cooldown = 7,
    damage_type = "poison",
    zone = {
        shape = "circle", target = "player", radius = 104, delay = 0.25,
        duration = 3, tick = 1, damage = 2, status = "poison", status_duration = 3, knockback = 0,
    },
    animation = "cast_start",
}

M.lingering_box = {
    avoid = "Leave the box or knock the boss down to clear it.",
    type = "zone", telegraph_time = 0.5, duration = 0.25, cooldown = 6, persist = false,
    zone = {
        shape = "box", target = "boss", width = 360, height = 96, delay = 0.25,
        duration = 2, tick = 1, damage = 3, knockback = 90,
    },
    animation = "slam",
}

-- A moving front on each warned floor lane. Jump above its marked height.
M.shock_wave = {
    avoid = "Jump above the moving front or move behind it.",
    type = "ground_wave", telegraph_time = 0.5, duration = 0.5, cooldown = 4, damage = 2,
    ground_wave = {speed = 320, distance = 320, width = 48, height = 64, knockback = 160},
    animation = "slam",
}

M.shock_wave_double = {
    avoid = "Jump above either moving front.",
    type = "ground_wave", telegraph_time = 0.75, duration = 0.5, cooldown = 6, damage = 3,
    ground_wave = {speed = 400, distance = 400, width = 56, height = 72, both_sides = true, knockback = 200},
    animation = "slam",
}

-- The warning rays mark the start and end of the turn.
M.beam_sweep_low = {
    avoid = "Stay outside the marked arc or beyond the beam.",
    type = "sweep", telegraph_time = 0.75, duration = 0.5, cooldown = 5, damage = 2,
    sweep = {from_angle = -25, to_angle = 25, duration = 1, windup = 0.25, length = 400, width = 36},
    animation = "cast_loop",
}

M.beam_sweep_high = {
    avoid = "Stay below or beyond the marked arc.",
    type = "sweep", telegraph_time = 0.75, duration = 0.5, cooldown = 6, damage = 2,
    rehit_interval = 1,
    sweep = {from_angle = 80, to_angle = 10, duration = 1.5, windup = 0.25, length = 470, width = 40},
    animation = "cast_loop",
}

-- Two marked bands frame a safe strip chosen once at the warning.
M.rain_volley_gap = {
    avoid = "Stay in the centre of the open strip.",
    type = "rain", telegraph_time = 0.875, duration = 0.5, cooldown = 7, damage = 2,
    rain = {count = 7, gap_width = 152, gap_at = "player", stagger = 0.125, speed = 335, lifetime = 4},
    animation = "ranged_attack",
}

M.rain_away_gap = {
    avoid = "Cross to the open strip at the far side during the warning.",
    type = "rain", telegraph_time = 1, duration = 0, cooldown = 7, damage = 3,
    rain = {count = 9, gap_width = 176, gap_at = "away", stagger = 0, speed = 280, lifetime = 4},
    animation = "ranged_attack",
}

M.rain_random_gap = {
    avoid = "Find the open strip on each cast and stay inside it.",
    type = "rain", telegraph_time = 1, duration = 0.5, cooldown = 8, damage = 2,
    rain = {count = 9, gap_width = 160, gap_at = "random", stagger = 0.125, speed = 300, lifetime = 4},
    animation = "ranged_attack",
}

-- A glow at the boss signals shots in every direction.
M.radial_burst = {
    avoid = "Dodge between the evenly spaced spokes.",
    type = "ring", telegraph_time = 0.5, duration = 0, cooldown = 5, damage = 2,
    telegraph_size = {x = 128, y = 128},
    ring = {count = 8, volleys = 1, volley_delay = 0.25, rotate_per_volley = 0, speed = 265, lifetime = 3},
    animation = "cast_start",
}

M.spiral_ring = {
    avoid = "Shift between spokes as each volley rotates.",
    type = "ring", telegraph_time = 0.75, duration = 0.5, cooldown = 7, damage = 2,
    telegraph_size = {x = 160, y = 160},
    ring = {count = 8, volleys = 3, volley_delay = 0.25, rotate_per_volley = 15, speed = 250, lifetime = 3},
    animation = "cast_loop",
}

-- Closes a gap to the player. In a named moveset, try min_range = 160
-- so the leap does not replace the boss's close attacks.
M.leap_slam = {
    avoid = "Leave the landing band after launch or jump above it.",
    type = "leap", telegraph_time = 0.7, duration = 0.5, cooldown = 5, damage = 3,
    leap = {target = "player", height = 128, time = 0.8, max_distance = 384,
        land = {radius = 96, knockback = 170, ground_only = true, vertical_clearance = 90}},
    animation = "slam",
}

-- Leaps to the side farthest from the player and strikes that landing.
M.far_side_leap = {
    avoid = "Clear the indicated landing disc.",
    type = "leap", telegraph_time = 0.8, duration = 0.75, cooldown = 7, damage = 4,
    leap = {target = "far_from_player", height = 160, time = 1,
        land = {radius = 120, knockback = 190}},
    animation = "slam",
}

-- Hover/flying patrol. Brief tracking before a quick drop and recovery.
M.dive_bomb = {
    avoid = "Dodge sideways once the landing disc stops tracking.",
    type = "dive", telegraph_time = 0.6, duration = 0.5, cooldown = 5, damage = 3,
    dive = {rise = 96, rise_time = 0.25, track_time = 0.5, track_speed = 480, speed = 640, recover_time = 0.5,
        land = {radius = 88, knockback = 160}},
    animation = "slam",
}

-- Hover/flying patrol. A longer climb and track lead to a wider impact.
M.high_dive_bomb = {
    avoid = "Wait for the lock, then clear the impact circle.",
    type = "dive", telegraph_time = 0.8, duration = 0.75, cooldown = 7, damage = 4,
    dive = {rise = 160, rise_time = 0.5, track_time = 0.75, track_speed = 440, speed = 800, recover_time = 0.75,
        land = {radius = 120, knockback = 200}},
    animation = "slam",
}

-- Closes distance on foot. In a named moveset, try min_range = 144.
M.walk_in = {
    avoid = "Back away from the boss's approach and its swing.",
    type = "reposition", telegraph_time = 0.35, duration = 0, cooldown = 4,
    telegraph_shape = "circle", telegraph_size = {x = 72, y = 72},
    reposition = {anchor = "near_player", style = "walk", timeout = 2, ["then"] = "test_melee"},
    animation = "walk",
}

-- Closes distance by blinking past the player. In a named moveset, try
-- min_range = 128 to reserve it for targets outside ordinary melee reach.
M.blink_strike = {
    avoid = "Move clear of the marked destination before the boss swings.",
    type = "reposition", telegraph_time = 0.65, duration = 0, cooldown = 6,
    telegraph_shape = "circle", telegraph_size = {x = 72, y = 72},
    reposition = {anchor = "behind_player", style = "blink", ["then"] = "test_melee"},
}

-- Pulse all hazards linked to this fight's arena. The placed hazards blink
-- for warn_time before becoming dangerous for duration. They use this warning
-- even if their Tiled Warn time is blank or different. Tiled Warn time still
-- applies to phase activation. With Active phases set to "none", a hazard
-- can turn on through a pulse attack or a rage-family phase change whose
-- Transition effects > Spawn hazards matches its type.
M.pulse_arena_hazards = {
    avoid = "Get clear of the blinking arena hazards.",
    type = "hazard_pulse", telegraph_time = 0.5, duration = 0, cooldown = 6,
    -- Omitted hazard_ids means the whole arena. Times inherit boss_defaults.
    hazard_pulse = {},
}

-- To name particular hazards in your own pattern, replace these example
-- strings with the Hazard IDs of the objects you placed in this boss's arena:
-- hazard_pulse = {hazard_ids = {"left_spikes", "right_spikes"}, warn_time = 0.6, duration = 2}

-- Leave the short floor band, or jump over the front once it reaches you.
M.short_ground_wave = {
    avoid = "Jump over the short floor front or step behind it.",
    type = "ground_wave", telegraph_time = 0.45, duration = 0.35, cooldown = 4, damage = 2,
    ground_wave = {distance = 160, speed = 320, width = 40, height = 48},
    animation = "slam",
}

-- Step outside the small disc before its first pulse.
M.close_pulse_zone = {
    avoid = "Leave the small disc before its first pulse.",
    type = "zone", telegraph_time = 0.5, duration = 0.5, cooldown = 4, persist = false,
    zone = {target = "boss", shape = "circle", radius = 80, delay = 0, duration = 1, tick = 0.5, damage = 2},
    animation = "cast_start",
}

-- Jump or retreat beyond the ground-level box before its first pulse.
M.wide_pulse_zone = {
    avoid = "Jump or retreat out of the low box before its first pulse.",
    type = "zone", telegraph_time = 0.9, duration = 0.6, cooldown = 8,
    zone = {target = "boss", shape = "box", width = 576, height = 72, delay = 0, duration = 2, tick = 1, damage = 2},
    animation = "slam",
}

-- Back away from the short beam or get behind the boss.
M.close_beam_sweep = {
    avoid = "Back away from the short arc or get behind the boss.",
    type = "sweep", telegraph_time = 0.5, duration = 0.45, cooldown = 4, damage = 2,
    sweep = {from_angle = -40, to_angle = 40, duration = 0.6, windup = 0, length = 176, width = 28},
    animation = "cast_loop",
}

-- Stay below or beyond the beam's rising arc.
M.rising_beam_sweep = {
    avoid = "Stay below or beyond the beam's rising arc.",
    type = "sweep", telegraph_time = 0.75, duration = 0.5, cooldown = 6, damage = 2,
    sweep = {from_angle = 0, to_angle = 65, duration = 1, windup = 0.15, length = 304, width = 28},
    animation = "cast_loop",
}

-- Get behind the boss or outside the long beam's arc.
M.long_beam_sweep = {
    avoid = "Get behind the boss or outside the long beam's arc.",
    type = "sweep", telegraph_time = 1.1, duration = 0.6, cooldown = 8, damage = 3,
    sweep = {from_angle = 35, to_angle = -30, duration = 1.25, windup = 0.2, length = 640, width = 36},
    animation = "cast_loop",
}

-- Get to the middle of the open strip and stay there through the drops.
M.staggered_gap_rain = {
    avoid = "Stand in the centre of the open strip until the last drop.",
    type = "rain", telegraph_time = 1.1, duration = 0.6, cooldown = 8, damage = 2,
    rain = {count = 12, gap_at = "player", gap_width = 192, stagger = 0.16, speed = 280, lifetime = 4},
    animation = "ranged_attack",
}

-- Step between the six spokes or wait past their short travel distance.
M.short_spoke_ring = {
    avoid = "Step between the six spokes or wait beyond their reach.",
    type = "ring", telegraph_time = 0.45, duration = 0.3, cooldown = 4, damage = 2,
    telegraph_size = {x = 112, y = 112},
    ring = {count = 6, volleys = 1, speed = 200, lifetime = 1.2},
    animation = "cast_start",
}

-- Find a gap again when the second volley turns between the first spokes.
M.offset_double_ring = {
    avoid = "Find another gap when the second volley turns between the first spokes.",
    type = "ring", telegraph_time = 0.7, duration = 0.5, cooldown = 7, damage = 2,
    telegraph_size = {x = 144, y = 144},
    ring = {count = 8, volleys = 2, volley_delay = 0.35, rotate_per_volley = 22.5, speed = 260, lifetime = 2},
    animation = "cast_loop",
}

-- Step aside once the low hop commits to the marked landing.
M.short_hop_slam = {
    avoid = "Step aside once the hop commits to the landing band.",
    type = "leap", telegraph_time = 0.4, duration = 0.4, cooldown = 4, damage = 2,
    leap = {target = "player", height = 56, time = 0.45, max_distance = 128,
        land = {radius = 64, knockback = 120, ground_only = true, vertical_clearance = 34.5}},
    animation = "slam",
}

-- Wait for the long leap to launch, then leave its landing disc.
M.long_arc_slam = {
    avoid = "Wait for the leap to launch, then leave its landing disc.",
    type = "leap", telegraph_time = 0.9, duration = 0.6, cooldown = 7, damage = 3,
    leap = {target = "player", height = 176, time = 1.15, max_distance = 640,
        land = {radius = 120, knockback = 210}},
    animation = "slam",
}

-- Dodge sideways once the small tracking disc stops following you.
M.quick_tracking_dive = {
    avoid = "Dodge sideways once the small landing disc stops tracking.",
    type = "dive", telegraph_time = 0.5, duration = 0.45, cooldown = 5, damage = 2,
    dive = {rise = 80, rise_time = 0.25, track_time = 0.35, track_speed = 560, speed = 750, recover_time = 0.4,
        land = {radius = 64, knockback = 125}},
    animation = "slam",
}

-- Save your dodge until the boss stops tracking, then clear the wide disc.
M.wide_tracking_dive = {
    avoid = "Save your dodge until the boss stops tracking, then clear the wide disc.",
    type = "dive", telegraph_time = 1, duration = 0.7, cooldown = 8, damage = 4,
    dive = {rise = 144, rise_time = 0.4, track_time = 0.85, track_speed = 420, speed = 700, recover_time = 0.65,
        land = {radius = 152, knockback = 220}},
    animation = "slam",
}

-- Watch the upper corner to keep track of where the boss will reappear.
M.blink_to_ceiling_corner = {
    avoid = "Watch the marked upper corner for the boss's reappearance.",
    type = "reposition", telegraph_time = 0.65, duration = 0, cooldown = 5,
    telegraph_shape = "circle", telegraph_size = {x = 72, y = 72},
    reposition = {anchor = "top_right", style = "blink"},
}

-- Give the boss room to retreat to the far side of the arena.
M.walk_to_far_edge = {
    avoid = "Keep clear of the boss's retreat path.",
    type = "reposition", telegraph_time = 0.55, duration = 0, cooldown = 5,
    telegraph_shape = "circle", telegraph_size = {x = 72, y = 72},
    reposition = {anchor = "far_from_player", style = "walk", timeout = 2.5},
    animation = "walk",
}

-- Step out of the box that lights up in front of the boss after the blink.
M.teleport_slash = {
    avoid = "Step out of the swing box in front of the boss.",
    type = "melee", telegraph_time = 0.2, duration = 0.25, cooldown = 3,
    damage = 3, range = 60, width = 30, height = 80, knockback = 150,
    animation = "attack",
}

return M
