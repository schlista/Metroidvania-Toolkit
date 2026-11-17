-- Optional random equipment drops. Enable in Game Settings > Equipment > Random drops.
-- Defeated enemies can leave one extra unowned weapon, charm or permanent upgrade.
-- A pickup left behind is not saved. Protect story or gate items with random_drop = false.
return {
    enabled = false, -- Ships off: enemies do not roll extra equipment drops.
    chance = 0.02, -- Chance per defeat, from 0 (never) to 1 (always if eligible).
    weapons = true, -- Include eligible weapons when Equipment > Weapons is on.
    charms = true, -- Include eligible charms when Equipment > Charms is on.
    upgrades = true, -- Include unapplied permanent upgrades with their prerequisites met.
    duplicate_currency = 50, -- Paid if an upgrade was already applied before collection.
}
