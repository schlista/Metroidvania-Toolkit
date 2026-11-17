-- developer/config/hazard_types.lua
-- ============================================================================
-- Hazard Type Definitions (data-only)
-- All hazard zones configurable here - spikes, lava, acid, electricity, etc.
-- Each Hazard can have immunity granted by either an unlocked ability or owned item.
-- immunity_ability: use an id declared in developer/config/abilities.lua, or nil.
-- immunity_item: use an inventory id from developer/config/items.lua, a collectible's
-- item_id, or a key id; nil means no item protection. Prepare & Check warns on
-- undefined ids. A placed Hazard's Required resistance replaces both immunity defaults.
-- Lava, acid and cold Water Volumes use these immunities for the player too.
-- ============================================================================
-- Entries here become the Tiled hazards dropdown after Project > Prepare & Check.
-- on_contact: damage (hurt/knock back), safe_return (cost health then return),
-- or kill. Omitted inherits damage, or kill for an instant_kill type.
-- return_damage: optional nonnegative health cost; omitted uses Game Settings.

return {
    -- =========================================================================
    -- INSTANT DAMAGE HAZARDS
    -- =========================================================================
    
    spikes = {
        damage_type = "physical", -- Type id; an instance can override it in Elements.
        on_contact = "safe_return", -- Return to safe ground by default.
        name = "Spikes",
        damage = 1,
        damage_interval = 0.0,  -- 0 = single hit on contact
        knockback = 300,
        knockback_direction = "up",  -- "up", "away", "none"
        -- Player recovery seconds. A Tiled hazard's stun_t overrides this;
        -- -1 inherits combat_config.feedback.hurt.stun_t, 0 disables recovery.
        stun_t = -1,
        instant_kill = false,
        
        -- Immunity
        immunity_ability = nil,  -- no ability grants immunity
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        -- Visuals
        sprite = "hazard_spikes",
        particle_on_hit = "blood_splat",
        sound_on_hit = "spike_hit",
        
    },
    
    -- =========================================================================
    -- DAMAGE-OVER-TIME HAZARDS
    -- =========================================================================
    
    lava = {
        status_effect = "burn", -- Applied to the player only in effective damage mode.
        damage_type = "fire", -- Type id; an instance can override it in Elements.
        name = "Lava",
        damage = 2,
        damage_interval = 0.5,  -- damage every 0.5 seconds
        knockback = 400,
        knockback_direction = "up",
        instant_kill = false,
        
        
        -- Immunity
        immunity_ability = "heat_resistance",  -- was nil; unlocked ability grants protection
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        -- Visuals
        sprite = "hazard_lava",
        particle_ambient = "lava_bubbles",
        particle_on_hit = "burn",
        sound_ambient = "lava_loop",
        sound_on_hit = "burn_sizzle",
        
    },
    
    acid = {
        status_effect = "poison", -- Applied to the player only in effective damage mode.
        damage_type = "poison", -- Type id; an instance can override it in Elements.
        name = "Acid",
        damage = 1,
        damage_interval = 0.3,
        knockback = 200,
        knockback_direction = "up",
        instant_kill = false,
        
        
        -- Walking slow [0.25,1], leased only while inside in damage mode.
        -- Shares group zone with Movement Zones: only the stronger slow wins.
        slow_multiplier = 0.5,
        
        immunity_ability = "acid_resistance",  -- was nil; unlocked ability grants protection
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        sprite = "hazard_acid",
        particle_ambient = "acid_bubbles",
        particle_on_hit = "acid_splash",
        sound_ambient = "acid_loop",
        sound_on_hit = "acid_burn",
        
    },
    
    cold = {
        status_effect = "freeze", -- Applied to the player only in effective damage mode.
        damage_type = "ice", -- Type id; an instance can override it in Elements.
        name = "Freezing Water",
        damage = 1,
        damage_interval = 1.0,
        knockback = 0,
        knockback_direction = "none",
        instant_kill = false,
        
        
        -- Walking slow [0.25,1]; strongest hazard/Movement Zone slow wins.
        slow_multiplier = 0.3,
        
        immunity_ability = "cold_resistance",  -- was nil; unlocked ability grants protection
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        sprite = "hazard_cold_water",
        particle_ambient = "frost_mist",
        particle_on_hit = "ice_crystals",
        sound_ambient = "cold_wind",
        sound_on_hit = "freeze_crack",
        
    },
    
    electricity = {
        damage_type = "lightning", -- Type id; an instance can override it in Elements.
        name = "Electricity",
        damage = 2,
        damage_interval = 0.0,  -- single burst
        knockback = 500,
        knockback_direction = "away",
        instant_kill = false,
        
        
        -- May arc to player from distance
        arc_range = 64,
        arc_chance = 0.3,
        
        immunity_ability = nil,  -- set an abilities.lua id to grant protection
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        sprite = "hazard_electric",
        particle_ambient = "sparks",
        particle_on_hit = "lightning_flash",
        sound_ambient = "electric_hum",
        sound_on_hit = "electric_shock",
        
    },
    
    -- =========================================================================
    -- INSTANT KILL HAZARDS
    -- =========================================================================
    
    void = {
        damage_type = "physical", -- Type id; an instance can override it in Elements.
        on_contact = "safe_return", -- Lethal pit; protection never strands a fall.
        name = "Void / Pit",
        damage = 999,
        damage_interval = 0.0,
        knockback = 0,
        knockback_direction = "none",
        instant_kill = true,
        
        -- No ability protection for this instant-kill hazard by default
        immunity_ability = nil,  -- set an abilities.lua id to grant protection
        
        sprite = nil,  -- usually invisible / off-screen
        particle_on_death = "void_fade",
        sound_on_death = "fall_scream",
        
    },
    
    -- =========================================================================
    -- MOVING/MECHANICAL HAZARDS
    -- =========================================================================
    
    crusher = {
        damage_type = "physical", -- Type id; an instance can override it in Elements.
        name = "Crusher",
        damage = 5,
        damage_interval = 0.0,
        knockback = 0,
        knockback_direction = "none",
        instant_kill = false,  -- set to true for instant death crushers
        
        -- Slam motion timing (Path motion on the Hazard template)
        warn_time = 0.5,  -- Slam warning seconds when Slam warn inherits (-1)
        crush_hold_time = 1.0,  -- Slam bottom hold seconds when Slam rest inherits (-1)
        
        immunity_ability = nil,  -- no immunity, must avoid
        
        sprite = "hazard_crusher",
        particle_on_crush = "dust_cloud", -- FX effect played at each Slam impact
        sound_warn = "crusher_warn", -- Audio SFX played when Slam warning starts
        sound_crush = "crusher_impact", -- Audio SFX played at each Slam impact
        
    },
    
    saw_blade = {
        damage_type = "physical", -- Type id; an instance can override it in Elements.
        name = "Saw Blade",
        damage = 2,
        damage_interval = 0.2,  -- rapid damage if touching
        knockback = 400,
        knockback_direction = "away",
        instant_kill = false,
        
        
        immunity_ability = nil,
        
        sprite = "hazard_saw",
        particle_on_hit = "sparks",
        sound_ambient = "saw_spin",
        sound_on_hit = "saw_cut",
        
    },
    
    -- =========================================================================
    -- TIMED/PERIODIC HAZARDS
    -- =========================================================================
    
    flame_jet = {
        status_effect = "burn", -- Applied to the player only in effective damage mode.
        damage_type = "fire", -- Type id; an instance can override it in Elements.
        name = "Flame Jet",
        damage = 2,
        damage_interval = 0.3,
        knockback = 200,
        knockback_direction = "away",
        instant_kill = false,
        
        
        -- Timing
        on_duration = 2.0,
        off_duration = 3.0,
        
        immunity_ability = "heat_resistance",  -- was nil; unlocked ability grants protection
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        sprite = "hazard_flame_jet",
        particle_active = "fire_jet",
        sound_active = "flame_whoosh",
        sound_ignite = "flame_start",
        
    },
    
    poison_gas = {
        status_effect = "poison", -- Applied to the player only in effective damage mode.
        damage_type = "poison", -- Type id; an instance can override it in Elements.
        name = "Poison Gas",
        damage = 1,
        damage_interval = 0.5,
        knockback = 0,
        knockback_direction = "none",
        instant_kill = false,
        
        
        -- Visual obstruction
        visibility_reduction = 0.5,  -- 50% visibility in gas
        
        immunity_ability = "acid_resistance",  -- was nil; unlocked ability grants protection
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        sprite = "hazard_gas",
        particle_ambient = "gas_cloud",
        sound_ambient = "gas_hiss",
        sound_on_hit = "cough",
        
    },
    
    -- =========================================================================
    -- WATER/LIQUID HAZARDS
    -- =========================================================================
    
    deep_water = {
        damage_type = "physical", -- Type id; an instance can override it in Elements.
        name = "Deep Water",
        damage = 0,  -- no direct damage
        damage_interval = 0.0,
        knockback = 0,
        knockback_direction = "none",
        instant_kill = false,
        
        -- Drowning mechanic
        enable_drowning = true,
        oxygen_drain_rate = 20,  -- units per second
        drowning_damage = 1,
        drowning_interval = 1.0,
        
        -- Movement in water
        swim_enabled = true,
        swim_speed_mult = 0.6,
        gravity_mult = 0.3,
        
        immunity_ability = "swim",
        immunity_item = nil,  -- set an items.lua inventory id to grant protection
        
        sprite = nil,  -- uses water shader
        particle_ambient = "bubbles",
        particle_surface = "water_ripples",
        sound_enter = "water_splash",
        sound_swim = "water_swim",
        
    },
    
    -- =========================================================================
    -- GLOBAL HAZARD SETTINGS
    -- =========================================================================
    settings = {
        -- Seconds between arena warning blink edges (0.01-2); coarse tile writes.
        -- Hazard Arena links select a live fight; active_phases uses boss phase indices.
        -- hide_when_inactive affects arena inactivity only; warn_time is harmless.
        arena_warn_blink_period = 0.1,
        -- Universal iframes after hazard damage
        hazard_iframes = 0.5,
        
        -- Flash color when damaged
        damage_flash_color = { 1.0, 0.3, 0.3, 1.0 },
        damage_flash_duration = 0.1,
        
        -- Screen shake on hazard damage
        screen_shake_enabled = true,
        screen_shake_intensity = 5,
        
        -- Audio
        default_hit_sound = "hazard_hit",
    },
}
