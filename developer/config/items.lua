-- Inventory item definitions, keyed by stable item id.
-- id: authored item id, matching the table key.
-- name: translatable display name; desc: translatable short description.
-- price: optional integer currency buying and selling base >= 0. Catalog offers
-- set their own buy prices; selling uses floor(price * the store's sell share).
-- sellable: optional boolean; false prevents selling (default true for priced
-- items). Keys and items owned by other Inventory tabs never sell. Zero sale
-- values hide the item. Charm Slot cannot sell because it increases capacity.
-- unique: true limits grants to one owned copy; omitted is stackable.
-- quick_use: true lists owned items in Quick Use (default false).
-- heal: health restored by one use; use_time: seconds (0 is instant,
-- positive values use the drink cancellation rules).
-- reveal_radius: world-pixel radius used by a map reveal item.

local M = {
  -- quick_use lists owned items in Quick Use; use_time 0 is instant, above 0 uses drink cancellation rules.
  potion_small = { id = "potion_small", name = "Small Potion", price = 25, desc = "Heals a small amount.", heal = 1, quick_use = true, use_time = 0 },
  potion_large = { id = "potion_large", name = "Large Potion", price = 75, desc = "Heals a large amount.", heal = 3, quick_use = true, use_time = 0 },
  map_fragment = { id = "map_fragment", name = "Map Fragment", price = 50, desc = "Reveals nearby rooms.", reveal_radius = 1600 },
  charm_slot   = { id = "charm_slot", name = "Charm Slot", price = 120, sellable = false, desc = "Adds a charm slot." },
  upgrade_material = { id = "upgrade_material", name = "Upgrade Material", price = 40, desc = "Used for crafting and upgrades." },
}

return M
