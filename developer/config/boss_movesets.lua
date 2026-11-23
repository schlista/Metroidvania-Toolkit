-- Named attack lists for boss phases.
-- Add a table here and select it under Attack sequence > Moveset on a Boss Phase
-- in Tiled, or set moveset = "its_name" on a phase in boss_types.lua.
-- The phase then uses that list in place of its individual attacks.
--
-- Choose how the boss works through its entries.
--   weighted picks among usable entries. Weight 4 has twice the chance of 2.
--   sequence uses entries in order, then loops. It waits up to sequence_wait
--     seconds for a blocked entry before advancing. Omit sequence_wait to use
--     boss_defaults.lua. Use 0 to skip a blocked entry immediately.
--   shuffle chooses randomly without repeating a usable entry until the
--     current round is used up, then start another round.
--   opener tries the opener list once, then chooses by weight.
--   Any mode can have an optional opener = {"attack_name", ...}. List names
--   from entries in the order you want them tried, before the regular mode.
--   A blocked opener is skipped when the boss has a choice to make.
--
-- Each entry in entries can set these fields.
--   attack names a pattern from the framework or attack_patterns.lua.
--   weight sets relative chance in weighted mode. Default 1, must be positive.
--   min_range and max_range set inclusive bounds in pixels. Omit a bound for no limit
--     on that side. Floor chasers measure horizontally. Other profiles use
--     the straight-line distance to the player.
--   when lists conditions. Every listed condition must be true.
--   max_repeat sets the number of consecutive picks before preferring another usable
--     attack. Default 2. If this is the only usable attack it can repeat once
--     ready. Sequence mode follows its own order.
--   once_per_phase = true lets the boss pick this entry once each phase.
--   cooldown sets the seconds between uses of this attack. Overrides the
--     pattern's cooldown, including one set in overrides below. 0 is valid.
--   gap_closer = true lets the boss pick this entry beyond its maximum range
--     when no entry is usable in range. It still needs to be ready and satisfy when.
--     Choose an attack that moves the boss toward the player.
--   overrides replaces pattern fields for this entry, such as damage or
--     telegraph_time. Pixel values here use world pixels. The phase's
--     telegraph_scale and cooldown_scale apply after the attack overrides.
--
-- Conditions for when = {"condition", ...}
--   player_above and player_below compare the characters' root heights outside
--     the height dead band in boss_defaults.lua.
--   player_in_front and player_behind use the boss's current facing.
--   player_grounded and player_airborne use the player's current floor contact.
--   near_wall holds near the left or right edge of the arena or room.
--   partner_alive holds while at least one other boss in the group is alive.
--   partner_defeated holds when at least one actual partner has been defeated.
--   last_survivor holds when a boss with partners is the only one still alive.
--   boss_health_below:0.5 and boss_health_above:0.5 compare remaining health as
--     a fraction from 0 to 1. The comparison excludes the exact threshold.
--   adds_below:2 holds with fewer than two living helpers summoned by this boss.
--   phase_time_above:3 holds after more than three fight seconds in this phase.
--   after:test_projectile holds if the most recent attack performed in this phase was
--     test_projectile. You can use any existing pattern name after the colon.
--
-- These movesets use the toolkit's own attacks at the 64-pixel reference
-- tile size. Adjust their distance bounds if you change the attack pixel
-- scale. Copy a set to keep a separate version for your encounter.
return {
    -- Step away from the close swing and sidestep the opening shot. At long
    -- range the boss walks in to put the sword back in play.
    close_and_ranged = {
        mode = "weighted",
        opener = {"test_projectile"},
        entries = {
            {attack = "test_melee", weight = 3, max_range = 72},
            {attack = "test_projectile", max_range = 660},
            {attack = "walk_in", min_range = 144, max_range = 640, gap_closer = true},
        },
    },

    -- Jump the charge, retreat from the advancing swing and dodge the shots.
    -- The boss gives a blocked charge or single shot half a second before
    -- moving on. A walk or the longer burst can follow either blocked entry.
    charge_and_shoot = {
        mode = "sequence",
        sequence_wait = 0.5,
        entries = {
            {attack = "dash_slash", min_range = 80, max_range = 200},
            {attack = "walk_in"},
            {attack = "test_projectile", max_range = 660, overrides = {damage = 2}},
            {attack = "sentinel_burst", max_range = 800},
        },
    },

    -- Step out of the sword box and jump the short floor wave or charge.
    -- Beyond the charge lane, watch for the Warden to leap toward you.
    warden_patrol = {
        mode = "weighted",
        entries = {
            {attack = "sword_combo", weight = 3, max_range = 120, max_repeat = 1},
            {attack = "dash_slash", weight = 3, min_range = 80, max_range = 200},
            {attack = "short_ground_wave", max_range = 160},
            {attack = "long_arc_slam", min_range = 160, max_range = 640, gap_closer = true},
        },
    },

    -- The Warden adds a slam circle and a floor wave to both sides. Give the
    -- slam room and jump the passing wave. Backing away still invites a leap.
    warden_last_stand = {
        mode = "shuffle",
        entries = {
            {attack = "sword_combo", max_range = 120},
            {attack = "ground_slam", max_range = 150},
            {attack = "dash_slash", min_range = 80, max_range = 200},
            {attack = "shock_wave_double", min_range = 120, max_range = 400},
            {attack = "long_arc_slam", min_range = 160, max_range = 640, gap_closer = true},
        },
    },

    -- Jump outside the short hop and floor slam. Farther out, pick a gap
    -- between the Colossus's needle spokes.
    needles_and_slams = {
        mode = "shuffle",
        entries = {
            {attack = "short_hop_slam", max_range = 128},
            {attack = "cactus_ground_slam", max_range = 340},
            -- Nine spokes keep one needle aimed at a player across the room.
            {attack = "cactus_needle_volley", max_range = 800,
                overrides = {projectiles = {count = 9, spread = 320}}},
        },
    },

    -- Expect a long charge at the start of the rage. Land clear of the boss
    -- after jumping it so you have space for the two-sided follow-up wave.
    colossus_rage = {
        mode = "opener",
        opener = {"cactus_charge"},
        entries = {
            {attack = "cactus_ground_slam", weight = 2, max_range = 340},
            {attack = "cactus_charge", weight = 3, min_range = 140, max_range = 800, max_repeat = 1},
            {attack = "cactus_needle_volley", max_range = 800,
                overrides = {projectiles = {count = 9, spread = 320}}},
            {attack = "shock_wave_double", weight = 3, max_range = 400, when = {"after:cactus_charge"}},
        },
    },

    -- The construct cycles through a swipe, a short sweeping beam and a
    -- burst. Stay beyond the beam's arc and move between the incoming shots.
    sentinel_watch = {
        mode = "sequence",
        sequence_wait = 0,
        entries = {
            {attack = "sentinel_swipe", max_range = 135},
            {attack = "close_beam_sweep", max_range = 176},
            {attack = "sentinel_burst", max_range = 800},
        },
    },

    -- The Sentinel calls slimes when you are nearby. Step out of the slam
    -- circle, jump the burning floor front and dodge the shots beyond it.
    sentinel_reinforcements = {
        mode = "opener",
        opener = {"sentinel_summon"},
        entries = {
            {attack = "sentinel_slam", weight = 3, max_range = 140},
            {attack = "sentinel_summon", max_range = 320, when = {"adds_below:2"}},
            {attack = "sentinel_burst", weight = 2, max_range = 800},
            {attack = "fire_wave", min_range = 140, max_range = 800},
        },
    },

    -- Leave the whip box up close and jump the low travelling floor front.
    -- Keep moving farther out so the fixed root trap forms behind you.
    whip_and_roots = {
        mode = "weighted",
        entries = {
            {attack = "vine_whip", weight = 4, max_range = 120},
            {attack = "short_ground_wave", weight = 2, max_range = 160},
            {attack = "root_spike", weight = 2, max_repeat = 1},
        },
    },

    -- The roots still punish standing still. Leave room to move around the
    -- crawlers the Guardian can now call next to itself.
    forest_guardian_grove = {
        mode = "shuffle",
        entries = {
            {attack = "vine_whip", max_range = 120},
            {attack = "short_ground_wave", max_range = 160},
            {attack = "root_spike"},
            {attack = "summon_thorns", max_range = 320, when = {"adds_below:2"}},
        },
    },

    -- The stronger whip protects the Guardian up close. Keep moving once
    -- the poison cloud marks your position.
    forest_guardian_poison = {
        mode = "opener",
        opener = {"poison_cloud"},
        entries = {
            {attack = "berserk_whip", weight = 3, max_range = 120},
            {attack = "root_spike", weight = 2, cooldown = 3},
            {attack = "summon_thorns", max_range = 320, when = {"adds_below:2"}},
            {attack = "poison_cloud", overrides = {zone = {damage = 3}}},
        },
    },

    -- The Golem guards its feet with a slam and scatters short spokes.
    -- Step between them or move off the line of the long crystal throw.
    crystal_guard = {
        mode = "weighted",
        entries = {
            {attack = "crystal_slam", weight = 3, max_range = 150},
            {attack = "short_spoke_ring", weight = 2, max_range = 240},
            {attack = "crystal_throw", max_range = 800},
        },
    },

    -- A beam joins the slam, short spokes and throw. Watch for the horizontal
    -- beam lane when approaching and dodge the thrown crystal across the room.
    crystal_refraction = {
        mode = "sequence",
        sequence_wait = 0,
        entries = {
            {attack = "crystal_slam", max_range = 150},
            {attack = "laser_sweep", min_range = 120, max_range = 400},
            {attack = "short_spoke_ring", max_range = 240},
            {attack = "crystal_throw", max_range = 800},
        },
    },

    -- The Golem fans out a barrage and calls spiked shells. Leave their
    -- spawn circles clear and keep a path out of the beam or the slam circle.
    crystal_shatter = {
        mode = "shuffle",
        entries = {
            {attack = "ground_slam", max_range = 150},
            {attack = "crystal_barrage", max_range = 800},
            {attack = "crystal_throw", max_range = 800},
            {attack = "laser_sweep", min_range = 120, max_range = 400},
            {attack = "summon_crystals", max_range = 320, when = {"adds_below:2"}},
        },
    },

    -- The swordsman protects its feet with a slash, charges at middle range
    -- and throws a fan of dark bolts across the room. Cross through a gap.
    dark_swordsman = {
        mode = "weighted",
        entries = {
            {attack = "sword_combo", weight = 3, max_range = 120, max_repeat = 1},
            {attack = "dash_slash", weight = 2, min_range = 80, max_range = 200},
            {attack = "dark_wave", max_range = 800},
        },
    },

    -- The knight opens with ghosts when you are nearby. Leave the spawn
    -- circles and make space to jump the charge and dodge the fan of bolts.
    sanctum_call = {
        mode = "opener",
        opener = {"summon_shadows"},
        entries = {
            {attack = "sword_combo", weight = 3, max_range = 120},
            {attack = "dash_slash", weight = 2, min_range = 80, max_range = 200},
            {attack = "dark_wave", max_range = 800},
            {attack = "summon_shadows", max_range = 420, when = {"adds_below:2"}},
        },
    },

    -- The knight can dash, slash and slam in one turn. Dodge all three cues
    -- and watch its flanks when more ghosts appear.
    sanctum_clones = {
        mode = "shuffle",
        entries = {
            {attack = "berserk_combo", max_range = 150},
            {attack = "dark_wave", max_range = 800},
            {attack = "shadow_clones", max_range = 420, when = {"adds_below:2"}},
            {attack = "summon_shadows", max_range = 420, when = {"adds_below:2"}},
        },
    },

    -- Back away from the ring of blades and move between its spokes. The
    -- knight can still send its bolt fan, bring in ghosts or rush you up close.
    sanctum_blades = {
        mode = "opener",
        opener = {"blade_storm"},
        entries = {
            {attack = "berserk_combo", weight = 3, max_range = 150},
            {attack = "dark_wave", max_range = 800},
            {attack = "shadow_clones", max_range = 420, when = {"adds_below:2"}},
            {attack = "blade_storm", weight = 4, max_range = 800, once_per_phase = true},
        },
    },

    -- This machine alternates charges and beam lanes with longer bursts.
    -- Jump the charge, then find cover or dodge through the gaps in the shots.
    factory_patrol_fire = {
        mode = "sequence",
        sequence_wait = 0,
        entries = {
            {attack = "dash_slash", min_range = 80, max_range = 200},
            {attack = "laser_shot", max_range = 400},
            {attack = "long_beam_sweep", min_range = 220, max_range = 640},
            {attack = "sentinel_burst", max_range = 800},
        },
    },

    -- Stay low when the beam tilts up to catch a jump. Clear the overload
    -- circle and give the machine room when it plants a mine by a wall.
    factory_unstable = {
        mode = "shuffle",
        entries = {
            {attack = "dash_slash", min_range = 80, max_range = 200},
            {attack = "laser_sweep", max_range = 400},
            {attack = "rising_beam_sweep", max_range = 304, when = {"player_above"}},
            {attack = "overload", max_range = 200, when = {"boss_health_below:0.35"}, once_per_phase = true,
                cooldown = 0},
            {attack = "plant_mine", max_range = 56, when = {"near_wall"}},
            {attack = "sentinel_burst", max_range = 800},
        },
    },

    -- Leave the front swing box and dodge long bolts. Watch behind you for
    -- the mark of the boss's blink and move before its follow-up swing.
    shadow_ambush = {
        mode = "shuffle",
        entries = {
            {attack = "sword_combo", max_range = 120},
            {attack = "shadow_bolt", max_range = 800},
            {attack = "teleport_strike", min_range = 120},
        },
    },

    -- Ghosts join the blink strikes and bolts. Move away from the marked
    -- spot when the boss plants a mine at your position.
    ruins_shadow_host = {
        mode = "weighted",
        entries = {
            {attack = "sword_combo", weight = 3, max_range = 120},
            {attack = "shadow_bolt", weight = 2, max_range = 800},
            {attack = "teleport_strike", min_range = 120},
            {attack = "summon_shadows", max_range = 420, when = {"adds_below:2"}},
            {attack = "shadow_trap", max_range = 220},
        },
    },

    -- The Dark Lord mixes its dash-swing-slam combo and blink with a heavy
    -- beam and a spread of bolts. Move out of the lane before the beam fires.
    ruins_dark_beam = {
        mode = "sequence",
        sequence_wait = 0,
        entries = {
            {attack = "berserk_combo", max_range = 150},
            {attack = "dark_beam", min_range = 130, max_range = 400},
            {attack = "teleport_strike", min_range = 120},
            {attack = "summon_shadows", max_range = 420, when = {"adds_below:2"}},
            {attack = "shadow_barrage", max_range = 800},
        },
    },

    -- Find the safe strip when debris falls. Up close, the new combo follows
    -- a blink with bolts, a charge and a beam. Keep a way clear of the ghosts.
    ruins_last_ritual = {
        mode = "opener",
        opener = {"ceiling_collapse"},
        entries = {
            {attack = "ultimate_combo", weight = 4, max_range = 150},
            {attack = "dark_beam", weight = 2, min_range = 120, max_range = 400},
            {attack = "summon_shadows", max_range = 420, when = {"adds_below:2"}},
            {attack = "shadow_barrage", weight = 2, max_range = 800},
            {attack = "ceiling_collapse", once_per_phase = true},
        },
    },

    -- Wait for the landing disc to stop tracking, then dodge sideways.
    -- For a flying boss, uncomment this example and set the phase's
    -- Movement profile to hover or flying_patrol before selecting it.
    --[[
    hovering_diver = {
        mode = "weighted",
        entries = {
            {attack = "quick_tracking_dive", weight = 3, max_repeat = 1},
            {attack = "short_spoke_ring", max_range = 240},
            {attack = "sentinel_burst", max_range = 800},
        },
    },
    ]]
}
