-- Optional Inventory recipes. Enable Crafting in Game Settings > Equipment.
-- One shared material funds gear here and permanent stats at upgrade stations.
return {
    enabled = false, -- Off hides the tab and refuses every craft without spending.
    -- Ordered recipes; keep ids stable. name/description are translatable source text.
    -- costs uses currency:<whole amount> and item:<id>:<whole count>, comma-separated.
    -- Any item may be a cost: adding another material requires no framework code.
    -- gives accepts weapon_tier:<weapon>:<tier> or item:charm_<id> only.
    -- Weapon tiers require ownership and exactly the preceding tier; owned outputs
    -- cannot be bought twice. Optional requires_flag hides a recipe until it is set.
    recipes = {
        {id = "maul_2", name = "Heavy Maul tier 2", description = "Temper the maul for stronger hits.",
            costs = "item:upgrade_material:2, currency:100", gives = "weapon_tier:heavy_maul:2"},
        {id = "maul_3", name = "Heavy Maul tier 3", description = "Finish the maul with masterwork damage.",
            costs = "item:upgrade_material:3, currency:200", gives = "weapon_tier:heavy_maul:3"},
        {id = "ember", name = "Ember Charm", description = "Make a charm that increases attack damage.",
            costs = "item:upgrade_material:2", gives = "item:charm_ember"},
        -- Consuming an equipped base charm unequips it. Equip the new charm in Charms.
        {id = "ember_plus", name = "Ember Charm+", description = "Trade the base charm for stronger damage.",
            costs = "item:charm_ember:1, item:upgrade_material:3", gives = "item:charm_ember_plus"},
    },
}
