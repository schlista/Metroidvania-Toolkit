-- Damage type vocabulary, neutral defaults and optional elemental rules.
-- Multipliers: 1 = unchanged, 0 = immune, 0.5 = half, 2 = double damage.
return {
    -- Affinity flags use these values unless an actor supplies damage_taken.
    weak_multiplier = 2.0,
    resist_multiplier = 0.5,

    -- Stable ids are saved/authored as text; labels are translatable source text.
    -- color is RGB in [0,1], with no vmath dependency (also read by the editor).
    -- outgoing scales hits ON enemies/bosses only, never hits on the player.
    -- A subtype falls back to its family only when no exact rule is present.
    -- Optional status={id, chance [0,1]} supplies enemy/boss defaults; players
    -- accept explicit attack statuses only. Hazards own their status presets.
    types = {
        physical   = { label = "Physical",   color = {1, 1, 1},       outgoing = 1.0 },
        slash      = { label = "Slash",      color = {1, 1, 1},       outgoing = 1.0, family = "physical" },
        projectile = { label = "Projectile", color = {1, 0.9, 0.6},   outgoing = 1.0, family = "physical" },
        impact     = { label = "Impact",     color = {1, 1, 1},       outgoing = 1.0, family = "physical" },
        fire       = { label = "Fire",       color = {1, 0.35, 0.1},  outgoing = 1.0, status = {id="burn", chance=0.25} },
        ice        = { label = "Ice",        color = {0.4, 0.8, 1},   outgoing = 1.0, status = {id="freeze", chance=0.15} },
        lightning  = { label = "Lightning",  color = {1, 0.95, 0.3},  outgoing = 1.0 },
        poison     = { label = "Poison",     color = {0.5, 0.9, 0.2}, outgoing = 1.0, status = {id="poison", chance=0.5} },
    },

    -- Incoming player factors [0,10], outside PlayerStats. Lethal hits bypass
    -- these factors. Remove a subtype entry to inherit its physical family.
    player_taken = { physical = 1.0, slash = 1.0, projectile = 1.0, impact = 1.0,
        fire = 1.0, ice = 1.0, lightning = 1.0, poison = 1.0 },

    -- Optional unlocked-ability resistances, multiplied per type and clamped
    -- together to [0.1,10] for their one PlayerStats source. Range [0.1,10]
    -- follows the PlayerStats floor: immunity belongs in player_taken instead.
    -- Hazard/gate protections remain separate. This real ability id is only an
    -- example; no elemental resistance is enabled in the empty toolkit.
    ability_taken = {
        -- heat_resistance = { fire = 0.5 },
    },

    -- Optional target tags -> per-type factors (exact, then family, then 1).
    -- No shipped enemy archetype has tags; creators can opt in, for example:
    tag_multipliers = {
        -- armored = { lightning = 1.2 },
    },

    -- Category defaults when an attack omits damage_type. Infusions override
    -- per-attack types, and leave unspecified categories unchanged.
    player_attacks = { melee = "slash", ranged = "projectile", movement = "impact" },
    -- Ordered {ability, melee?, ranged?} entries; the first unlocked entry wins.
    -- No infusion ships enabled. Example using an existing ability id:
    player_attack_infusions = {
        -- { ability = "heat_resistance", melee = "fire" },
    },
    -- Water preset -> damage type, sent to both players and enemies.
    water_types = { lava = "fire", acid = "poison", poison = "poison" },

    feedback = {
        tint_numbers = true,          -- Use the hit type's RGB for damage numbers.
        weak_as_critical = true,       -- Weak hits request the critical number style.
        immune_label = "IMMUNE",      -- Translatable creator source text, never an id.
        immune_color = {0.7, 0.7, 0.7}, -- RGB for immune-hit labels.
        immune_sfx = "parry_miss",     -- sound_bank.lua sfx id (actor integration).
        weak_color = {1, 0.9, 0.2},  -- RGB for the weak-hit actor flash.
        weak_flash = 0.15,             -- Weak-hit actor flash duration in seconds.
        immune_flash = 0.1,            -- Actor flash duration in seconds.
    },
}
