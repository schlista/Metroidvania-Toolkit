-- Optional charms use limited equipment slots. Enable Charms in Game Settings > Equipment.
-- Ownership is one charm_<id> Inventory item. Keep ids stable in saved games.
-- random_drop: optional boolean on each entry; false excludes it from random equipment drops.
-- Protect gate and story items; requires_ability must be learned before a random drop.
return {
    enabled = false, -- Disabled world pickups stay in place and equipped effects are inert.
    base_slots = 3, -- Whole starting capacity; change charms anywhere in the Inventory.
    max_slots = 9, -- Whole capacity cap, including slot pickups.
    slot_item = "charm_slot", -- Inventory item whose count adds capacity, capped above.
    duplicate_currency = 50, -- Whole payout for an owned world pickup, never currency-multiplied.
    -- Ordered examples; id "slot" is reserved for the existing Charm Slot pickup.
    -- name/description are creator source text collected for translations.
    -- cost is a whole slot cost, at least 1. icon_animation defaults to "prop_base"
    -- in gameplay_visuals.atlas; collect_sound defaults to the one-shot "/sound#relic_found".
    -- count_in_census=false opts a type out of the charm completion category.
    -- Effects use the equipment layer: additive keys sum; multiplier keys multiply.
    -- Supported keys follow stat_keys.lua, including max_health/max_energy/max_stamina,
    -- speed_mult, damage_mult, damage_taken_mult and damage_taken_mult:<damage type>.
    -- invulnerable is forbidden. A health-capacity bonus never refills current health.
    -- xp_mult does nothing while Leveling is off. currency_mult affects currency
    -- pickups (including dropped coins) only, with nearest-integer rounding and a
    -- minimum of 1 for pickups worth at least 1; it never boosts gear duplicates.
    charms = {
        {id = "vitality", name = "Vitality Charm", description = "Adds one health capacity without healing.",
            cost = 1, icon_animation = "prop_base", effects = {max_health = 1}},
        {id = "fleetfoot", name = "Fleetfoot Charm", description = "Increases walking and running speed.",
            cost = 1, icon_animation = "prop_base", effects = {speed_mult = 1.15}},
        {id = "ember_ward", name = "Ember Ward", description = "Reduces fire damage taken.",
            cost = 2, icon_animation = "prop_base", effects = {["damage_taken_mult:fire"] = 0.75}},
        {id = "scholar", name = "Scholar Charm", description = "Increases XP while Leveling is enabled.",
            cost = 1, icon_animation = "prop_base", effects = {xp_mult = 1.25}},
        {id = "prosperity", name = "Prosperity Charm", description = "Increases currency collected from pickups.",
            cost = 2, icon_animation = "prop_base", effects = {currency_mult = 1.5}},
        -- Crafting examples: the improved charm consumes the base, never stacks it.
        {id = "ember", name = "Ember Charm", description = "Increases attack damage.",
            cost = 1, icon_animation = "prop_base", effects = {damage_mult = 1.1}},
        {id = "ember_plus", name = "Ember Charm+", description = "Further increases attack damage.",
            cost = 2, icon_animation = "prop_base", effects = {damage_mult = 1.2}},
    },
}
