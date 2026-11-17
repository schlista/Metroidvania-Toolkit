-- Purchase catalogs. Every station using a catalog shares its saved stock.
-- settings.autosave_after_purchase: save the completed exchange once; abilities
-- may still autosave when false. Suspended saves keep only in-memory progress.
-- settings.sell_share: project sale price share, from 0 to 1 (default 0.5).
-- Game Settings > Game > Shops overrides it; stores may override it individually.
-- Sales use floor(items.lua price * share). Values above 1 are refused so buying
-- and reselling at the same base price never earns currency. Keep catalog buy
-- prices at least as high as the sale value when discounting an offer.
-- settings.bank.steps: ordered positive whole currency amounts for bank menu rows.
-- settings.bank.autosave: save each completed deposit or withdrawal (default true).
-- Banked currency is separate from carried currency and is safe from death fees.
-- Suspended saves keep transfers in memory until the session ends or saving resumes.
-- settings.sounds.buy / fail: sound_bank.lua sfx ids for purchase feedback.
-- catalogs: map of stable catalog ids; name is translatable creator text.
-- entries: ordered offers; an empty list is allowed.
-- Entry fields (optional unless stated):
-- id: required stable id, unique within this catalog; keep it after release.
-- gives: required grant text or list (item, collectible, upgrade, ability,
-- currency, flag or fast_travel); collectible grants use the station position.
-- price: required integer currency cost >= 0; 0 is free.
-- cost_items: additional item-id to positive integer count map.
-- The Forge spends the shared upgrade_material on permanent stats; crafting
-- spends that same material on weapon tiers and charms. Health Boost II costs
-- 200 currency plus one material, after Health Boost I.
-- stock: positive integer total sold across all stations; omitted is unlimited.
-- A container without stock grants a new permanent bonus on every purchase.
-- requires_flag: hide until this flag is true, unless show_locked is true.
-- show_locked: show an unavailable offer instead of hiding it (default false).
-- locked_text: optional translatable explanation for a missing flag.
-- set_flag: set this flag on success. Upgrade prerequisites belong in upgrades.lua.
-- name / description: optional translatable offer text overriding reward text.
-- confirm: ask before purchasing (default false).
return {
    settings = {
        autosave_after_purchase = true,
        sell_share = 0.5,
        bank = { steps = { 10, 100 }, autosave = true },
        sounds = { buy = "ui_confirm", fail = "ui_back" },
    },
    catalogs = {
        town_vendor = { name = "Town Vendor", entries = {
            { id = "potion_small", gives = "item:potion_small", price = 25 },
            { id = "potion_large", gives = "item:potion_large", price = 75 },
            { id = "map_fragment", gives = "collectible:map_fragment", price = 50, stock = 1 },
        } },
        apothecary = { name = "Apothecary", entries = {
            { id = "potion_small", gives = "item:potion_small", price = 25 },
            { id = "potion_large", gives = "item:potion_large", price = 75 },
        } },
        forge = { name = "Forge", entries = {
            { id = "health_boost_1", gives = "upgrade:health_boost_1", price = 100 },
            { id = "health_boost_2", gives = "upgrade:health_boost_2", price = 200, cost_items = { upgrade_material = 1 } },
            { id = "energy_boost_1", gives = "upgrade:energy_boost_1", price = 100 },
            { id = "stamina_boost_1", gives = "upgrade:stamina_boost_1", price = 120 },
            { id = "damage_boost_small", gives = "upgrade:damage_boost_small", price = 180 },
        } },
        training_hall = { name = "Training Hall", entries = {
            { id = "wall_jump", gives = "ability:wall_jump", price = 200 },
            { id = "double_jump", gives = "ability:double_jump", price = 200 },
        } },
    },
}
