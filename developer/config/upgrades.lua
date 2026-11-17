-- Permanent upgrade definitions; no level rewards or temporary effects.
-- upgrades: map of stable ids referenced by upgrade:<id> grant text.
-- name / description: translatable creator text displayed for this upgrade.
-- max_health / max_energy / max_stamina: added capacity (omitted means 0).
-- damage_mult: outgoing damage factor (omitted means 1); factors multiply.
-- These are the only four supported permanent-ledger effect keys.
-- A max_stamina boost enables stamina even when the base Max stamina is 0.
-- Stations sell permanent stats; Inventory crafting uses materials for weapon
-- tiers and charms. Both spend the shared upgrade_material item through costs.
-- requires: optional list of upgrade ids that must already be applied; no cycles.
-- random_drop: false on an entry excludes it from random equipment drops.
-- count_in_census: false excludes placed pickups of this upgrade from completion totals.
-- icon_animation / collect_sound: optional pickup animation and collect audio overrides
-- (collect_sound defaults to the one-shot "/sound#gem_collect"; it must not loop).
return {
    upgrades = {
        health_boost_1 = { name = "Health Boost I", description = "Adds one health capacity.", max_health = 1 },
        health_boost_2 = { name = "Health Boost II", description = "Adds two health capacity.", max_health = 2, requires = { "health_boost_1" } },
        energy_boost_1 = { name = "Energy Boost I", description = "Adds one energy capacity.", max_energy = 1 },
        stamina_boost_1 = { name = "Stamina Boost I", description = "Adds ten stamina capacity.", max_stamina = 10 },
        damage_boost_small = { name = "Damage Boost", description = "Increases outgoing damage by five percent.", damage_mult = 1.05, requires = { "health_boost_1" } },
    },
}
