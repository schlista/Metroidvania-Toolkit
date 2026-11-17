-- Optional owned weapons. Enable Weapons in Game Settings > Equipment > Weapons.
-- Ownership is one weapon_<id> Inventory item; the starter is virtual, never granted.
-- random_drop: optional boolean on each entry; false excludes it from random equipment drops.
-- Protect gate and story items; requires_ability must be learned before a random drop.
return {
    enabled = false, -- Disabled world pickups stay in place; combat is unchanged.
    quick_switch = true, -- Allow the Loadout cycle button when switching is available.
    starting_weapon = "training_blade", -- An id below, or blank for the unarmed moveset.
    duplicate_currency = 50, -- Whole currency paid for an already-owned world pickup.
    -- Ordered list: this order is also the weapon cycle order. Keep ids stable in saves.
    -- Each attack_set names combat_config.lua attack_sets; omitted means "default".
    -- Sets may define up_light/up_heavy in grounded/aerial buckets. Missing up attacks
    -- fall back to the normal attack, without a weapon-specific input handler.
    -- scale defaults to 1: damage, hitbox reach, cooldown and knockback are unitless.
    -- cooldown changes only time between attacks, never startup/active/recovery timing.
    -- Optional ranged overrides: damage, speed (pixels/second), lifetime (seconds),
    -- energy_cost (Max energy units, 0 is free), for attacks with weapon_class="ranged".
    -- Optional damage_type names damage_types.lua; an unlocked infusion overrides it.
    -- Optional requires_ability names an ability that must be unlocked to equip/cycle.
    -- icon_animation must exist in gameplay_visuals.atlas (default "prop_base").
    -- collect_sound is a one-shot collectible sound component (default "/sound#relic_found").
    -- count_in_census=false opts a pickup type out of the weapon completion category.
    -- Optional tiers is an ordered list: tiers[1] is tier 2, tiers[2] is tier 3.
    -- Each has an optional translated name, scale multipliers on the base weapon,
    -- and optional ranged overrides (same units as above). Tier scales are absolute
    -- relative to the base, not cumulative; saved tiers live with weapon equipment.
    -- Names and descriptions are creator source text collected for translations.
    weapons = {
        {
            id = "training_blade", name = "Training Blade",
            description = "A balanced practice blade.",
            attack_set = "default", icon_animation = "prop_base",
            scale = {damage = 1, reach = 1, cooldown = 1, knockback = 1},
        },
        {
            id = "heavy_maul", name = "Heavy Maul",
            description = "A heavy weapon with longer reach and stronger knockback.",
            attack_set = "default", icon_animation = "prop_base",
            scale = {damage = 1.6, reach = 1.2, cooldown = 1.35, knockback = 1.5},
            tiers = {
                {name = "Tempered Maul", scale = {damage = 1.15}},
                {name = "Masterwork Maul", scale = {damage = 1.3}},
            },
        },
        {
            id = "ember_caster", name = "Ember Caster",
            description = "A caster that strengthens the ranged shot and deals fire damage.",
            attack_set = "default", icon_animation = "prop_base",
            damage_type = "fire",
            ranged = {damage = 2, speed = 1400, lifetime = 1.8, energy_cost = 1},
        },
    },
}
