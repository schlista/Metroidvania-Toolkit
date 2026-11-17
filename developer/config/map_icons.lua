-- Map item tracking: which placed objects the world map and minimap mark, and how.
-- Game Settings > Map > Item tracking edits item_tracking and room_complete.
-- Every object comes from the prepared world census, so icons also show for rooms
-- that are not loaded. Run Project > Prepare & Check after changing this file.
--
-- Colours are {r, g, b, a} tables from 0 to 1. The editor also loads this file,
-- so it holds plain data only. An item uses its type's minimap_color from
-- collectible_types.lua first; otherwise the icon's color, then the row's color,
-- then the row's color_from.
--
-- Visibility rules ("rule"):
--   "always"       shown from the start, even in rooms the player never entered.
--   "visited"      shown once the player has entered the object's room.
--   "seen"         shown once the object's spot has been on screen, or its room was
--                  visited and the spot is uncovered. A Map Station's reveal alone
--                  does not count, so items in unvisited rooms stay hidden.
--   "mapped"       "seen", or the room's layout was revealed (for example by a Map Station).
--   "ability:<id>" shown once the player has that ability.
--   "flag:<name>"  shown once that save flag is set.
--   "never"        never shown.
-- Collected styles ("collected"), used after an item is taken, a chest opened, a
-- barrier opened, a boss defeated or an altar used:
--   "hide" removes the icon, "dim" fades it (see dim_alpha), "outline" draws only its edge.
-- Shapes ("shape"): "square", "diamond", "circle" or "ring".
--
-- Tiled: any object can set map_icon ("auto", "hide" or an icon id from icons below)
-- and hide_on_map (true removes its icon). An object that the census does not list
-- appears only when map_icon names an icon.
return {
    -- Icons for items, chests, lore and secrets. Stations, barriers and placed Map
    -- Markers do not use this switch, so turning it off never removes a station.
    item_tracking = {
        enabled = true, -- Show item, chest, lore and secret icons on the map.
        rule = "seen", -- Rule for those kinds: "seen", "visited", "mapped" or "always".
        require_flag = "", -- A save flag that must be set first (for example a map upgrade); "" for none.
    },

    -- Rooms where every counted item is found get this tint on the world map.
    room_complete = {
        enabled = true, -- Tint visited rooms whose counted items are all found.
        color = { r = 0.35, g = 0.85, b = 0.45, a = 0.35 }, -- Tint colour and strength.
    },

    -- Minimap icons for the current room and its direct neighbours.
    minimap = {
        show = true, -- Draw item and station icons on the minimap.
        max_icons = 32, -- Most icons drawn at once on the minimap.
    },

    dim_alpha = 0.4, -- Opacity multiplier of a "dim" icon, from 0 (invisible) to 1 (unchanged).

    -- One row per census kind or object type. An object type row (for example
    -- save_point) wins over its kind row (travel). Fields:
    --   shape, color, rule, collected: as described above. A tracked kind (item,
    --     chest, lore, secret) without a rule uses item_tracking.rule.
    --   color_from: a colour name in world_map_settings.lua colors, used when no colour is set.
    --   label: the legend name, shown to players (translated through Project > Translations...).
    --   hidden_until_found: true keeps the icon away until the object is found.
    kinds = {
        item = { shape = "square", color = { r = 1.0, g = 0.85, b = 0.3, a = 1.0 }, collected = "dim", label = "Item" },
        chest = { shape = "square", color = { r = 0.85, g = 0.6, b = 0.25, a = 1.0 }, collected = "dim", label = "Chest" },
        lore = { shape = "circle", color = { r = 0.7, g = 0.8, b = 1.0, a = 1.0 }, collected = "dim", label = "Lore" },
        secret = { shape = "diamond", color = { r = 0.9, g = 0.5, b = 1.0, a = 1.0 }, collected = "dim",
            hidden_until_found = true, label = "Secret" }, -- Never give an unfound secret away.
        boss = { shape = "diamond", color_from = "icon_boss", rule = "seen", collected = "dim", label = "Boss" },
        trial = { shape = "ring", color = { r = 1.0, g = 0.6, b = 0.2, a = 1.0 }, rule = "seen", collected = "dim", label = "Trial" },
        barrier = { shape = "square", color = { r = 0.9, g = 0.3, b = 0.3, a = 1.0 }, rule = "seen", collected = "hide", label = "Locked" },
        timed_door = { rule = "never", label = "Timed door" }, -- A timed door has no saved lock state.
        travel = { shape = "circle", color_from = "icon_bench", rule = "seen", label = "Rest point" },
        save_point = { shape = "circle", color_from = "icon_bench", rule = "seen", label = "Save point" },
        fast_travel = { shape = "circle", color_from = "icon_bench", rule = "seen", label = "Fast travel" },
        player_start = { rule = "never", label = "Start" }, -- Start and respawn points.
        map_station = { shape = "square", color = { r = 0.4, g = 0.8, b = 1.0, a = 1.0 }, rule = "seen", label = "Map station" },
        health_station = { shape = "circle", color = { r = 0.95, g = 0.35, b = 0.4, a = 1.0 }, rule = "seen", label = "Health station" },
        energy_station = { shape = "circle", color = { r = 0.35, g = 0.6, b = 1.0, a = 1.0 }, rule = "seen", label = "Energy station" },
        teleporter = { shape = "ring", color = { r = 0.6, g = 0.9, b = 1.0, a = 1.0 }, rule = "seen", label = "Teleporter" },
        shop = { shape = "square", color_from = "icon_shop", rule = "seen", label = "Shop" },
        upgrade_station = { shape = "square", color_from = "icon_shop", rule = "seen", label = "Upgrades" },
        bank = { shape = "square", color_from = "icon_shop", rule = "seen", label = "Bank" },
        skill_trainer = { shape = "square", color_from = "icon_shop", rule = "seen", label = "Trainer" },
        offering_altar = { shape = "diamond", color_from = "icon_shop", rule = "seen", collected = "dim", label = "Altar" },
        npc = { shape = "circle", color_from = "icon_shop", rule = "seen", label = "Vendor" }, -- Vendors and NPCs with a map_icon.
        map_marker = { shape = "diamond", color_from = "icon_custom", label = "Marker" }, -- Uses its own Visible from start and Discovery radius.
        poi = { shape = "circle", color_from = "icon_custom", rule = "seen", label = "Point of interest" }, -- Other objects with a map_icon.
        enemy = { rule = "never", label = "Enemy" },
        objective = { rule = "never", label = "Objective" }, -- Progression objectives without a kind of their own.
        -- The current goal's target once a Hint Stone with Reveal goal target marked it
        -- (developer/config/goals.lua). Shown at every zoom, even with item icons off;
        -- rule and collected do not apply. Without a label the legend says "Goal".
        goal_target = { shape = "ring", color = { r = 1.0, g = 0.95, b = 0.35, a = 1.0 } },
    },

    -- Icon ids for Tiled map_icon and for minimap_icon in collectible_types.lua.
    -- An item uses its type's minimap_icon; a type without one uses its kind row.
    icons = {
        gem = { shape = "diamond", label = "Gem" },
        key = { shape = "square", label = "Key" },
        key_boss = { shape = "diamond", label = "Boss key" },
        health_container = { shape = "circle", label = "Health upgrade" },
        energy_container = { shape = "circle", label = "Energy upgrade" },
        stamina_vessel = { shape = "circle", label = "Stamina upgrade" },
        relic = { shape = "diamond", label = "Relic" },
        map_piece = { shape = "square", label = "Map piece" },
        lore = { shape = "circle", label = "Lore" },
        ability = { shape = "ring", label = "Ability" },
    },
}
