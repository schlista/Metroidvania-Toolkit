-- developer/config/sound_bank.lua
-- ============================================================================
-- MV Toolkit . Sound Bank Configuration (data-only)
-- Map all SFX and BGM here so developers can wire their audio without code.
-- Other configs reference sounds by key (e.g., "attack_light").
-- ============================================================================
-- Entries here become the Tiled sound_effects dropdown after Project > Prepare & Check.
--
-- Each sfx entry:
--   path           The audio file this sound was made from (for reference).
--   volume         0..1 loudness; also written as the gain of the id's own
--                  component when the toolkit adds one.
--   pitch_variance Random pitch range (reference; not applied by playback).
--   loop           Marks a looping recording (reference). Sound effects play
--                  once; use an Ambience Zone for loops.
--   caption        Optional translatable source text, e.g. "Jump". Shown only
--                  for sound_bank ids when player Captions and captions.sound
--                  in accessibility.lua are on; component-URL sounds are excluded.
--   component      Optional. The sound component on
--                  developer/game/audio/audio_controller.go that plays this id.
--                  Leave it out to use "sfx_<id>". Set it to another sfx_
--                  component to reuse that sound, e.g. component = "sfx_ui_click".
-- Every id here must reach a sound component; test/sfx_id_resolution_tests.lua
-- checks it. To give an id its own audio, add an sfx_<id> sound component to
-- audio_controller.go in the Defold editor and remove the component field.

return {
    -- =========================================================================
    -- SOUND EFFECTS (SFX)
    -- =========================================================================
    sfx = {
        -- =====================================================================
        -- PLAYER COMBAT
        -- =====================================================================
        attack_light = {
            path = "/developer/assets/generated_audio/attack_light.wav",
            volume = 0.8,
            pitch_variance = 0.1,  -- random pitch variation
        },
        attack_heavy = {
            path = "/developer/assets/generated_audio/attack_heavy.wav",
            volume = 0.9,
            pitch_variance = 0.05,
        },
        attack_down = {
            path = "/developer/assets/generated_audio/attack_down.wav",
            volume = 0.85,
        },
        attack_counter = {
            path = "/developer/assets/generated_audio/counter.wav",
            volume = 1.0,
        },
        charge_loop = {
            path = "/developer/assets/generated_audio/charge_loop.wav",
            volume = 0.6,
            loop = true,
        },
        
        -- =====================================================================
        -- PROJECTILES
        -- =====================================================================
        projectile_fire = {
            path = "/developer/assets/generated_audio/projectile_fire.wav",
            volume = 0.7,
        },
        projectile_charged = {
            path = "/developer/assets/generated_audio/projectile_charged.wav",
            volume = 0.85,
        },
        projectile_hit = {
            path = "/developer/assets/generated_audio/projectile_hit.wav",
            component = "sfx_hit_projectile",
            volume = 0.6,
        },
        
        -- =====================================================================
        -- HIT/DAMAGE
        -- =====================================================================
        hit_melee = {
            path = "/developer/game/audio/combat_impact_light.sound",
            volume = 0.8,
            pitch_variance = 0.1,
        },
        hit_projectile = {
            path = "/developer/game/audio/combat_impact_heavy.sound",
            volume = 0.85,
        },
        parry_success = {
            path = "/developer/game/audio/parry_ring.sound",
            component = "sfx_parry_ring",
            volume = 0.9,
        },
        parry_miss = {
            -- Subtle whiff sound when parry window expires without catching a hit.
            -- Replace with a dedicated parry-miss audio file when available.
            path = "/developer/game/audio/air_dash.sound",
            component = "sfx_air_dash",
            volume = 0.35,
            pitch_variance = 0.15,
        },
        player_hurt = {
            path = "/developer/assets/generated_audio/player_hurt.wav",
            component = "sfx_hit_melee",
            volume = 1.0,
        },
        player_death = {
            path = "/developer/game/audio/death_blast.sound",
            component = "sfx_hit_projectile",
            volume = 1.0,
        },
        
        -- =====================================================================
        -- PLAYER MOVEMENT
        -- =====================================================================
        jump = {
            path = "/developer/game/audio/jump.sound",
            volume = 0.5,
            pitch_variance = 0.1,
        },
        double_jump = {
            path = "/developer/assets/generated_audio/double_jump.wav",
            volume = 0.55,
        },
        land = {
            path = "/developer/game/audio/land.sound",
            volume = 0.4,
        },
        land_heavy = {
            path = "/developer/assets/generated_audio/land_heavy.wav",
            volume = 0.6,
        },
        slide = {
            path = "/developer/game/audio/slide.sound",
            volume = 0.5,
        },
        air_dash = {
            path = "/developer/game/audio/air_dash.sound",
            volume = 0.6,
        },
        wall_slide = {
            path = "/developer/assets/generated_audio/wall_slide.wav",
            volume = 0.35,
            loop = true,
        },
        wall_jump = {
            path = "/developer/assets/generated_audio/wall_jump.wav",
            volume = 0.55,
        },
        footstep = {
            path = "/developer/game/audio/footstep_default.sound",
            component = "sfx_footstep_default",
            volume = 0.25,
            pitch_variance = 0.2,
        },
        
        -- =====================================================================
        -- COLLECTIBLES
        -- =====================================================================
        collect_gem = {
            path = "/developer/game/audio/collectible_sparkle.sound",
            component = "sfx_collectible_sparkle",
            volume = 0.6,
            pitch_variance = 0.15,
        },
        collect_gem_large = {
            path = "/developer/assets/generated_audio/gem_collect.wav",
            volume = 0.75,
        },
        collect_health = {
            path = "/developer/assets/generated_audio/health_upgrade.wav",
            volume = 0.7,
        },
        collect_energy = {
            path = "/developer/assets/generated_audio/energy_upgrade.wav",
            volume = 0.7,
        },
        collect_key = {
            path = "/developer/assets/generated_audio/key_found.wav",
            volume = 0.85,
        },
        collect_ability = {
            path = "/developer/assets/generated_audio/ability_found.wav",
            volume = 1.0,
        },
        collect_map = {
            path = "/developer/assets/generated_audio/map_found.wav",
            volume = 0.8,
        },

        -- =====================================================================
        -- UI / UX
        -- =====================================================================
        ui_click = {
            path = "/developer/game/audio/ui_click.sound",
            volume = 0.6,
        },
        ui_confirm = {
            path = "/developer/game/audio/ui_confirm.sound",
            volume = 0.7,
        },
        ui_back = {
            path = "/developer/game/audio/ui_back.sound",
            volume = 0.7,
        },
        ui_move = {
            path = "/developer/game/audio/ui_move.sound",
            volume = 0.55,
        },
        
        -- =====================================================================
        -- GATES & DOORS
        -- =====================================================================
        gate_locked = {
            path = "/developer/assets/generated_audio/gate_locked.wav",
            volume = 0.7,
        },
        gate_unlock = {
            path = "/developer/assets/generated_audio/gate_unlock.wav",
            volume = 0.85,
        },
        gate_unlock_energy = {
            path = "/developer/assets/generated_audio/gate_unlock_energy.wav",
            volume = 0.9,
        },
        gate_open = {
            path = "/developer/assets/sfx/door_open.wav",
            component = "sfx_door_open",
            volume = 0.8,
        },
        door_open = {
            path = "/developer/assets/sfx/door_open.wav",
            volume = 0.7,
        },
        door_close = {
            path = "/developer/assets/sfx/door_close.wav",
            volume = 0.65,
        },
        lever_on = {
            path = "/developer/assets/sfx/lever_on.wav",
            volume = 0.7,
        },
        lever_off = {
            path = "/developer/assets/sfx/lever_off.wav",
            volume = 0.65,
        },
        
        -- =====================================================================
        -- CHESTS & CONTAINERS
        -- =====================================================================
        chest_open = {
            path = "/developer/assets/generated_audio/chest_open.wav",
            volume = 0.8,
        },
        chest_locked = {
            path = "/developer/assets/generated_audio/chest_locked.wav",
            volume = 0.6,
        },
        
        -- =====================================================================
        -- HAZARDS
        -- =====================================================================
        hazard_hit = {
            path = "/developer/assets/generated_audio/hazard_hit.wav",
            volume = 0.7,
        },
        spike_hit = {
            path = "/developer/assets/generated_audio/spike_hit.wav",
            volume = 0.75,
        },
        burn_sizzle = {
            path = "/developer/assets/sfx/lava_sizzle.wav",
            volume = 0.6,
        },
        cough = {
            path = "/developer/assets/sfx/poison_cough.wav",
            volume = 0.55,
        },
        acid_burn = {
            path = "/developer/assets/generated_audio/acid_burn.wav",
            volume = 0.65,
        },
        electric_shock = {
            path = "/developer/assets/generated_audio/electric_shock.wav",
            volume = 0.8,
        },
        fall_scream = {
            path = "/developer/assets/generated_audio/fall_scream.wav",
            volume = 0.9,
        },
        crusher_warn = {
            path = "/developer/assets/generated_audio/crusher_warn.wav",
            volume = 0.7,
        },
        crusher_impact = {
            path = "/developer/assets/generated_audio/crusher_impact.wav",
            volume = 0.95,
        },

        -- =====================================================================
        -- BOSSES / SPECIAL EVENTS
        -- =====================================================================
        boss_phase = {
            path = "/developer/game/audio/boss_phase.sound",
            volume = 0.9,
        },
        death_explosion = {
            path = "/developer/game/audio/death_blast.sound",
            component = "sfx_death_blast",
            volume = 1.0,
        },
        
        -- =====================================================================
        -- AMBIENT LOOPS
        -- =====================================================================
        lava_loop = {
            path = "/developer/assets/generated_audio/lava_loop.wav",
            volume = 0.4,
            loop = true,
            spatial = true,
        },
        acid_loop = {
            path = "/developer/assets/generated_audio/acid_loop.wav",
            volume = 0.35,
            loop = true,
            spatial = true,
        },
        electric_hum = {
            path = "/developer/assets/generated_audio/electric_hum.wav",
            volume = 0.3,
            loop = true,
            spatial = true,
        },
        water_flow = {
            path = "/developer/assets/sfx/water_cc0.ogg",
            component = "sfx_water",
            volume = 0.4,
            loop = true,
            spatial = true,
        },
        wind_howl = {
            path = "/developer/assets/generated_audio/wind_howl.wav",
            volume = 0.35,
            loop = true,
            spatial = true,
        },
        
        -- =====================================================================
        -- WATER
        -- =====================================================================
        water_splash = {
            path = "/developer/assets/generated_audio/water_splash.wav",
            volume = 0.7,
        },
        water_swim = {
            path = "/developer/assets/generated_audio/water_swim.wav",
            volume = 0.4,
            loop = true,
        },
        
        -- =====================================================================
        -- BREAKABLES
        -- =====================================================================
        wall_crack = {
            path = "/developer/assets/sfx/wall_hit.wav",
            component = "sfx_wall_hit",
            volume = 0.6,
        },
        wall_break = {
            path = "/developer/assets/sfx/wall_break.wav",
            volume = 0.85,
        },
        secret_reveal = {
            path = "/developer/assets/generated_audio/secret_reveal.wav",
            volume = 0.9,
        },
        
        -- =====================================================================
        -- UI
        -- =====================================================================
        menu_move = {
            path = "/developer/game/audio/ui_move.sound",
            component = "sfx_ui_move",
            volume = 0.5,
        },
        menu_select = {
            path = "/developer/game/audio/ui_confirm.sound",
            component = "sfx_ui_confirm",
            volume = 0.6,
        },
        menu_back = {
            path = "/developer/game/audio/ui_back.sound",
            component = "sfx_ui_back",
            volume = 0.5,
        },
        pause = {
            path = "/developer/assets/generated_audio/pause.wav",
            volume = 0.7,
        },
        save_point = {
            path = "/developer/assets/generated_audio/save_point.wav",
            volume = 0.8,
        },
        fast_travel = {
            path = "/developer/assets/generated_audio/fast_travel.wav",
            volume = 0.9,
        },
        
        -- =====================================================================
        -- ADDITIONAL WORLD CUES
        -- =====================================================================
        ignite = {
            path = "/developer/assets/generated_audio/ignite.wav",
            volume = 0.65,
        },
        freeze = {
            path = "/developer/assets/generated_audio/freeze.wav",
            volume = 0.7,
        },
        poison_apply = {
            path = "/developer/assets/generated_audio/poison_apply.wav",
            volume = 0.6,
        },
        shock = {
            path = "/developer/assets/generated_audio/shock.wav",
            volume = 0.75,
        },
        
        -- =====================================================================
        -- ENEMIES
        -- =====================================================================
        enemy_alert = {
            path = "/developer/assets/generated_audio/enemy_alert.wav",
            volume = 0.6,
        },
        enemy_hurt = {
            path = "/developer/assets/generated_audio/enemy_hurt.wav",
            volume = 0.55,
            pitch_variance = 0.2,
        },
        enemy_death = {
            path = "/developer/assets/generated_audio/enemy_death.wav",
            volume = 0.7,
        },
        boss_intro = {
            path = "/developer/assets/generated_audio/boss_intro.wav",
            volume = 1.0,
        },
        boss_death = {
            path = "/developer/assets/generated_audio/boss_death.wav",
            volume = 1.0,
        },
        
        -- =====================================================================
        -- NPC / DIALOGUE
        -- =====================================================================
        npc_talk = {
            path = "/developer/assets/generated_audio/npc_talk.wav",
            volume = 0.5,
            pitch_variance = 0.1,
        },

        -- =====================================================================
        -- SHARED CUES (ids the toolkit's own code and older configs play)
        -- =====================================================================
        collectible_sparkle = {
            path = "/developer/assets/sfx/collectible_sparkle.wav",
            volume = 0.6,
        },
        collectible_pick = {
            path = "/developer/assets/sfx/collectible_sparkle.wav",
            volume = 0.6,
            component = "sfx_collectible_sparkle",
        },
        combat_impact_light = {
            path = "/developer/assets/sfx/combat_impact_light.wav",
            volume = 0.8,
        },
        combat_impact_heavy = {
            path = "/developer/assets/sfx/combat_impact_heavy.wav",
            volume = 0.85,
        },
        death_blast = {
            path = "/developer/assets/sfx/death_blast.wav",
            volume = 1.0,
        },
        footstep_default = {
            path = "/developer/assets/sfx/footstep_default.wav",
            volume = 0.25,
        },
        footstep_grass = {
            path = "/developer/assets/sfx/footstep_grass.wav",
            volume = 0.25,
        },
        footstep_metal = {
            path = "/developer/assets/sfx/footstep_metal.wav",
            volume = 0.25,
        },
        footstep_stone = {
            path = "/developer/assets/sfx/footstep_stone.wav",
            volume = 0.25,
        },
        parry_ring = {
            path = "/developer/assets/sfx/parry_ring.wav",
            volume = 0.9,
        },
        platform_crumble = {
            path = "/developer/assets/sfx/footstep_landing.wav",
            volume = 0.6,
            component = "sfx_land",
        },
        platform_respawn = {
            path = "/developer/assets/sfx/ui_click.wav",
            volume = 0.5,
            component = "sfx_ui_click",
        },
        wall_hit = {
            path = "/developer/assets/sfx/wall_hit.wav",
            volume = 0.6,
        },
        water = {
            path = "/developer/assets/sfx/water_cc0.ogg",
            volume = 0.4,
        },
        grapple_attach = {
            -- The grapple hook catching a surface.
            path = "/developer/assets/sfx/wall_hit.wav",
            volume = 0.6,
            component = "sfx_wall_hit",
        },
        error = {
            -- A refused action, such as interacting without the required item.
            path = "/developer/assets/generated_audio/gate_locked.wav",
            volume = 0.7,
            component = "sfx_gate_locked",
        },
        paper_pickup = {
            -- Lore Item pickup (the script default).
            path = "/developer/assets/generated_audio/lore_found.wav",
            volume = 0.7,
        },
        energy_restore = {
            -- Energy Station refill (the script default).
            path = "/developer/assets/generated_audio/energy_upgrade.wav",
            volume = 0.7,
            component = "sfx_collect_energy",
        },
        insufficient_funds = {
            -- A station or shop the player cannot afford.
            path = "/developer/assets/generated_audio/gate_locked.wav",
            volume = 0.7,
            component = "sfx_gate_locked",
        },

        -- =====================================================================
        -- CONFIG CUES (ids used by gate_types, hazard_types, secret_types and
        -- screenshot settings; each reuses the closest existing sound)
        -- =====================================================================
        door_locked = {
            -- Locked key door.
            path = "/developer/assets/generated_audio/gate_locked.wav",
            volume = 0.7,
            component = "sfx_gate_locked",
        },
        door_unlock = {
            -- Key door opening.
            path = "/developer/assets/generated_audio/gate_unlock.wav",
            volume = 0.7,
            component = "sfx_gate_unlock",
        },
        door_unlock_special = {
            -- Special key door opening.
            path = "/developer/assets/generated_audio/gate_unlock_energy.wav",
            volume = 0.7,
            component = "sfx_gate_unlock_energy",
        },
        boss_door_locked = {
            -- Locked boss door.
            path = "/developer/assets/generated_audio/gate_locked.wav",
            volume = 0.7,
            component = "sfx_gate_locked",
        },
        boss_door_unlock = {
            -- Boss door opening.
            path = "/developer/assets/generated_audio/gate_unlock_energy.wav",
            volume = 0.7,
            component = "sfx_gate_unlock_energy",
        },
        timer_tick = {
            -- Timed gate countdown tick.
            path = "/developer/assets/sfx/ui_move.wav",
            volume = 0.7,
            component = "sfx_ui_move",
        },
        timer_success = {
            -- Timed gate opened in time.
            path = "/developer/assets/generated_audio/gate_unlock.wav",
            volume = 0.7,
            component = "sfx_gate_unlock",
        },
        floor_crack = {
            -- Breakable floor taking a hit.
            path = "/developer/assets/sfx/wall_hit.wav",
            volume = 0.7,
            component = "sfx_wall_hit",
        },
        floor_shatter = {
            -- Breakable floor breaking.
            path = "/developer/assets/sfx/wall_break.wav",
            volume = 0.7,
            component = "sfx_wall_break",
        },
        coins_paid = {
            -- Toll paid.
            path = "/developer/assets/sfx/collectible_sparkle.wav",
            volume = 0.7,
            component = "sfx_collectible_sparkle",
        },
        wall_scrape = {
            -- Climbable wall refusing the player.
            path = "/developer/assets/sfx/slide.wav",
            volume = 0.7,
            component = "sfx_slide",
        },
        barrier_bump = {
            -- One-way barrier bump.
            path = "/developer/assets/sfx/wall_hit.wav",
            volume = 0.7,
            component = "sfx_wall_hit",
        },
        lava_sizzle = {
            -- Lava contact.
            path = "/developer/assets/sfx/lava_sizzle.wav",
            volume = 0.7,
            component = "sfx_burn_sizzle",
        },
        acid_hiss = {
            -- Acid contact.
            path = "/developer/assets/generated_audio/acid_burn.wav",
            volume = 0.7,
            component = "sfx_acid_burn",
        },
        cold_wind = {
            -- Cold zone.
            path = "/developer/assets/generated_audio/wind_howl.wav",
            volume = 0.7,
            component = "sfx_wind_howl",
        },
        insufficient_energy = {
            -- Energy gate without enough energy.
            path = "/developer/assets/generated_audio/gate_locked.wav",
            volume = 0.7,
            component = "sfx_gate_locked",
        },
        energy_gate_pass = {
            -- Energy gate opening.
            path = "/developer/assets/generated_audio/gate_unlock_energy.wav",
            volume = 0.7,
            component = "sfx_gate_unlock_energy",
        },
        flame_start = {
            -- Flame jet igniting.
            path = "/developer/assets/generated_audio/ignite.wav",
            volume = 0.7,
            component = "sfx_ignite",
        },
        flame_whoosh = {
            -- Flame jet burning.
            path = "/developer/assets/sfx/lava_sizzle.wav",
            volume = 0.7,
            component = "sfx_burn_sizzle",
        },
        gas_hiss = {
            -- Poison gas.
            path = "/developer/assets/generated_audio/acid_burn.wav",
            volume = 0.7,
            component = "sfx_acid_burn",
        },
        saw_cut = {
            -- Saw blade hit.
            path = "/developer/assets/generated_audio/hazard_hit.wav",
            volume = 0.7,
            component = "sfx_hazard_hit",
        },
        saw_spin = {
            -- Saw blade spinning.
            path = "/developer/assets/generated_audio/electric_hum.wav",
            volume = 0.7,
            component = "sfx_electric_hum",
        },
        freeze_crack = {
            -- Cold hazard hit.
            path = "/developer/assets/generated_audio/freeze.wav",
            volume = 0.7,
            component = "sfx_freeze",
        },
        ui_screenshot = {
            -- Screenshot captured.
            path = "/developer/assets/sfx/ui_confirm.wav",
            volume = 0.7,
            component = "sfx_ui_confirm",
        },
        phase_whoosh = {
            -- One-way secret passage.
            path = "/developer/assets/sfx/air_dash.wav",
            volume = 0.7,
            component = "sfx_air_dash",
        },
        dig_treasure = {
            -- Buried treasure revealed.
            path = "/developer/assets/generated_audio/secret_reveal.wav",
            volume = 0.7,
            component = "sfx_secret_reveal",
        },
        explosion = {
            -- Bomb wall exploding.
            path = "/developer/assets/sfx/death_blast.wav",
            volume = 0.7,
            component = "sfx_death_blast",
        },
    },
    
    -- =========================================================================
    -- BACKGROUND MUSIC (BGM)
    -- =========================================================================
    bgm = {
        -- =====================================================================
        -- AREA THEMES
        -- =====================================================================
        forest = {
            path = "/developer/examples/forest/audio/music/forest_ambient.wav",
            volume = 0.6,
            loop = true,
            fade_in = 1.0,
            fade_out = 1.0,
        },
        caves = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.55,
            loop = true,
            fade_in = 1.5,
            fade_out = 1.0,
        },
        ruins = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.6,
            loop = true,
            fade_in = 1.0,
            fade_out = 1.0,
        },
        graveyard = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.5,
            loop = true,
            fade_in = 2.0,
            fade_out = 1.5,
        },
        castle = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.6,
            loop = true,
            fade_in = 1.0,
            fade_out = 1.0,
        },
        lava_zone = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.65,
            loop = true,
            fade_in = 1.0,
            fade_out = 1.0,
        },
        water_temple = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.55,
            loop = true,
            fade_in = 1.5,
            fade_out = 1.5,
        },
        
        -- =====================================================================
        -- BOSS THEMES
        -- =====================================================================
        boss_generic = {
            path = "/developer/assets/music/Sample_Music1.ogg",
            volume = 0.75,
            loop = true,
            fade_in = 0.5,
            fade_out = 2.0,
        },
        boss_final = {
            path = "/developer/assets/music/Sample_Music1.ogg",
            volume = 0.8,
            loop = true,
            fade_in = 0.5,
            fade_out = 2.0,
        },
        miniboss = {
            path = "/developer/examples/forest/audio/music/forest_boss.wav",
            volume = 0.7,
            loop = true,
            fade_in = 0.3,
            fade_out = 1.5,
        },
        
        -- =====================================================================
        -- SPECIAL
        -- =====================================================================
        title = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.7,
            loop = true,
            fade_in = 0.5,
            fade_out = 1.0,
        },
        credits = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.65,
            loop = false,
            fade_in = 1.0,
            fade_out = 2.0,
        },
        game_over = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.6,
            loop = false,
            fade_in = 0.5,
            fade_out = 0.0,
        },
        victory = {
            path = "/developer/assets/music/graveyard_1.ogg",
            volume = 0.75,
            loop = false,
            fade_in = 0.0,
            fade_out = 2.0,
        },
        safe_room = {
            path = "/developer/examples/forest/audio/music/forest_ambient.wav",
            volume = 0.45,
            loop = true,
            fade_in = 1.0,
            fade_out = 1.0,
        },
    },
    
    -- =========================================================================
    -- AUDIO SETTINGS
    -- =========================================================================
    settings = {
        master_volume = 1.0,
        sfx_volume = 1.0,
        bgm_volume = 0.7,
        ambient_volume = 0.5,
        
        -- Spatial audio
        spatial_max_distance = 800,
        spatial_ref_distance = 100,
        spatial_rolloff = 1.0,
        
        -- Ducking (lower music volume during important sounds)
        ducking_enabled = true,
        ducking_amount = 0.3,
        ducking_fade_time = 0.2,
    },
}
