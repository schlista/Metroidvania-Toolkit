--- Collectible Type Definitions
-- Defines all collectible types available in the game
-- Each type specifies behavior, visuals, audio, and rewards
-- currency_type is display-only: all currency pickups add to one balance.
--
-- Generated entries are supplied by mvtk/collectibles/generated_types.lua.
-- Ability pickups come from abilities.lua; weapons.lua, charms.lua and
-- powerups.lua supply their families when supported.
-- Authored ids win collisions; Prepare & Check reports the conflicting source.
--
-- @module collectible_types
-- Entries here become the Tiled collectibles dropdown after Project > Prepare & Check.
-- Optional count_in_census=false excludes a type from world completion totals.
-- Category and respawns defaults are read live; changing them needs no room bake.

local collectible_types = {
    -- Permanent capacity pickup; its placed collectible ID makes the grant idempotent.
    heal_charge_upgrade = {
        category = "upgrade", name = "Flask Upgrade", animation = "health_upgrade", -- Placeholder art.
        on_collect = "add_heal_charge", value = 1, -- Extra flask capacity and a filled charge.
        respawns = false, notification = "Healing Flask +1 charge", -- Milestone notice.
    },
    -- Potions use the existing collectible template and inventory delivery.
    potion_small = {
        category = "consumable", name = "Small Potion", on_collect = "add_to_inventory",
        item_id = "potion_small", respawns = false, -- One owned quick-use item; supply tile art.
    },
    potion_large = {
        category = "consumable", name = "Large Potion", on_collect = "add_to_inventory",
        item_id = "potion_large", respawns = false, -- One owned quick-use item; supply tile art.
    },
    --[[========================================================================
        CONSUMABLES (Health/Energy Pickups)
    ========================================================================]]

    health_small = {
        category = "consumable",
        name = "Small Health",
        description = "Restores a small amount of health",

        animation = "health_small",
        glow = false,

        audio = {
            collect = "/sound#health_pickup",
        },

        on_collect = "restore_health",
        value = 5,

        notification = nil,  -- No notification for small pickups
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,  -- Respawns
        respawn_time = 60,
    },

    health_medium = {
        category = "consumable",
        name = "Medium Health",
        description = "Restores a moderate amount of health",

        animation = "health_medium",
        glow = true,
        glow_color = {r = 1.0, g = 0.4, b = 0.4, a = 1.0},

        audio = {
            collect = "/sound#health_pickup",
        },

        on_collect = "restore_health",
        value = 10,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,
        respawn_time = 90,
    },

    health_large = {
        category = "consumable",
        name = "Large Health",
        description = "Restores a large amount of health",

        animation = "health_large",
        glow = true,
        glow_color = {r = 1.0, g = 0.3, b = 0.3, a = 1.0},

        audio = {
            collect = "/sound#health_pickup",
        },

        on_collect = "restore_health",
        value = 20,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,
        respawn_time = 120,
    },

    energy_small = {
        category = "consumable",
        name = "Small Energy",
        description = "Restores a small amount of energy",

        animation = "energy_small",
        glow = false,

        audio = {
            collect = "/sound#energy_pickup",
        },

        on_collect = "restore_energy",
        value = 5,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,
        respawn_time = 60,
    },

    energy_large = {
        category = "consumable",
        name = "Large Energy",
        description = "Restores a large amount of energy",

        animation = "energy_large",
        glow = true,
        glow_color = {r = 0.3, g = 0.5, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#energy_pickup",
        },

        on_collect = "restore_energy",
        value = 20,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,
        respawn_time = 120,
    },

    --[[========================================================================
        CURRENCY
    ========================================================================]]

    currency = {
        category = "currency",
        name = "Coin",
        description = "Currency used to buy items",

        animation = "currency",
        glow = false,

        audio = {
            collect = "/sound#coin_pickup",
        },

        on_collect = "add_currency",
        currency_type = "gold",
        value = 1,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,  -- Coins respawn
        respawn_time = 300,
    },

    currency_large = {
        category = "currency",
        name = "Large Coin",
        description = "A valuable pile of currency",

        animation = "currency_large",
        glow = true,
        glow_color = {r = 1.0, g = 0.85, b = 0.2, a = 1.0},

        audio = {
            collect = "/sound#coin_pickup",
        },

        on_collect = "add_currency",
        currency_type = "gold",
        value = 50,

        notification = "Currency +50",
        popup_duration = 1.5,
        show_in_collection = false,

        respawns = true,
        respawn_time = 300,
    },

    --[[========================================================================
        GEMS (Valuable Currency)
    ========================================================================]]

    gem_red = {
        category = "currency",
        name = "Red Gem",
        description = "A valuable red gemstone",

        animation = "gem_red",
        glow = true,
        glow_color = {r = 1.0, g = 0.2, b = 0.2, a = 1.0},

        audio = {
            collect = "/sound#gem_collect",
        },

        on_collect = "add_currency",
        currency_type = "gems",
        value = 25,

        notification = "Gem +25",
        popup_duration = 1.5,
        show_in_collection = false,

        minimap_icon = "gem",
        minimap_color = {r = 1.0, g = 0.2, b = 0.2},
    },

    gem_green = {
        category = "currency",
        name = "Green Gem",
        description = "A valuable green gemstone",

        animation = "gem_green",
        glow = true,
        glow_color = {r = 0.2, g = 1.0, b = 0.2, a = 1.0},

        audio = {
            collect = "/sound#gem_collect",
        },

        on_collect = "add_currency",
        currency_type = "gems",
        value = 100,

        notification = "Gem +100",
        popup_duration = 1.5,
        show_in_collection = false,

        minimap_icon = "gem",
        minimap_color = {r = 0.2, g = 1.0, b = 0.2},
    },

    gem_blue = {
        category = "currency",
        name = "Blue Gem",
        description = "A valuable blue gemstone",

        animation = "gem_blue",
        glow = true,
        glow_color = {r = 0.2, g = 0.5, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#gem_collect",
        },

        on_collect = "add_currency",
        currency_type = "gems",
        value = 50,

        notification = "Gem +50",
        popup_duration = 1.5,
        show_in_collection = false,

        minimap_icon = "gem",
        minimap_color = {r = 0.2, g = 0.5, b = 1.0},
    },

    --[[========================================================================
        KEYS (Generic)
    ========================================================================]]

    key = {
        category = "key",
        name = "Key",
        description = "Opens locked doors and chests",

        animation = "key",
        glow = true,
        glow_color = {r = 1.0, g = 0.8, b = 0.0, a = 1.0},

        audio = {
            collect = "/sound#key_found",
        },

        on_collect = "add_to_inventory",
        item_id = "key",

        notification = "Key obtained!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "key",
        minimap_color = {r = 1.0, g = 0.8, b = 0.0},
    },

    --[[========================================================================
        PERMANENT UPGRADES
    ========================================================================]]

    health_container = {
        category = "upgrade",
        name = "Health Container",
        description = "Increases maximum health by 1",

        -- Visual
        animation = "health_container",
        glow = true,  -- Add glowing particle effect
        glow_color = {r = 1.0, g = 0.2, b = 0.2, a = 1.0},  -- Red glow

        -- Audio
        audio = {
            collect = "/sound#health_upgrade",
            ambient = "/sound#item_hum",  -- Looping ambient sound
        },

        -- Behavior
        on_collect = "increase_max_health",
        value = 1,  -- Amount to increase

        -- UI
        notification = "Max Health +1!",
        popup_duration = 3.0,
        show_in_collection = false,  -- Don't show in collection menu

        -- Minimap
        minimap_icon = "health_container",
        minimap_color = {r = 1.0, g = 0.2, b = 0.2},
    },

    energy_container = {
        category = "upgrade",
        name = "Energy Container",
        description = "Increases maximum energy by 10",

        animation = "energy_container",
        glow = true,
        glow_color = {r = 0.2, g = 0.5, b = 1.0, a = 1.0},  -- Blue glow

        audio = {
            collect = "/sound#energy_upgrade",
            ambient = "/sound#item_hum",
        },

        on_collect = "increase_max_energy",
        value = 10,

        notification = "Max Energy +10!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "energy_container",
        minimap_color = {r = 0.2, g = 0.5, b = 1.0},
    },

    -- A permanent piece; progress feedback comes from its fragment set templates.
    health_fragment = {
        category = "upgrade", -- Counts as an upgrade in the world census.
        name = "Health fragment", -- Translatable pickup name.
        description = "A piece of a permanent health upgrade", -- Translatable description.
        animation = "health_fragment", -- Reuses the container image until creator art is supplied.
        audio = {collect = "/sound#health_upgrade", ambient = "/sound#item_hum"}, -- Container audio.
        on_collect = "add_fragment", -- The fragment service owns its notice.
        fragment_set = "health", -- Stable key in fragments.lua.
        show_in_collection = false, -- Progress is in Journal > Records instead.
        minimap_icon = "health_container", -- Same map icon as the full container.
        minimap_color = {r = 1.0, g = 0.2, b = 0.2}, -- Same map colour as the full container.
    },

    -- A permanent piece; progress feedback comes from its fragment set templates.
    energy_fragment = {
        category = "upgrade", -- Counts as an upgrade in the world census.
        name = "Energy fragment", -- Translatable pickup name.
        description = "A piece of a permanent energy upgrade", -- Translatable description.
        animation = "energy_fragment", -- Reuses the container image until creator art is supplied.
        audio = {collect = "/sound#energy_upgrade", ambient = "/sound#item_hum"}, -- Container audio.
        on_collect = "add_fragment", -- The fragment service owns its notice.
        fragment_set = "energy", -- Stable key in fragments.lua.
        show_in_collection = false, -- Progress is in Journal > Records instead.
        minimap_icon = "energy_container", -- Same map icon as the full container.
        minimap_color = {r = 0.2, g = 0.5, b = 1.0}, -- Same map colour as the full container.
    },

    stamina_vessel = {
        category = "upgrade",
        name = "Stamina Vessel",
        description = "Increases maximum stamina by 10",

        animation = "stamina_vessel",
        glow = true,
        glow_color = {r = 0.2, g = 1.0, b = 0.2, a = 1.0},  -- Green glow

        audio = {
            collect = "/sound#stamina_upgrade",
            ambient = "/sound#item_hum",
        },

        on_collect = "increase_max_stamina",
        value = 10,

        notification = "Max Stamina +10!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "stamina_vessel",
        minimap_color = {r = 0.2, g = 1.0, b = 0.2},
    },

    health_upgrade = {
        category = "upgrade",
        name = "Health Upgrade",
        description = "Increases maximum health",

        animation = "health_upgrade",
        glow = true,
        glow_color = {r = 1.0, g = 0.3, b = 0.3, a = 1.0},

        audio = {
            collect = "/sound#health_upgrade",
            ambient = "/sound#item_hum",
        },

        on_collect = "increase_max_health",
        value = 1,

        notification = "Max Health +1!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "health_container",
        minimap_color = {r = 1.0, g = 0.2, b = 0.2},
    },

    charm_slot = {
        category = "upgrade",
        name = "Charm Slot",
        description = "Adds a charm slot",

        animation = "charm_slot",
        glow = true,
        glow_color = {r = 0.9, g = 0.8, b = 0.3, a = 1.0},

        audio = {
            collect = "/sound#relic_found",  -- One-shot; item_hum loops and never stops.
        },

        on_collect = "add_to_inventory",
        item_id = "charm_slot",

        notification = "Charm Slot +1",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "relic",
        minimap_color = {r = 0.9, g = 0.8, b = 0.3},
    },

    --[[========================================================================
        MAP & PROGRESSION ITEMS
    ========================================================================]]

    map_piece_forest = {
        category = "progression",
        name = "Forest Map",
        description = "Reveals the Ancient Forest on your map",

        animation = "map_piece_forest",
        glow = true,
        glow_color = {r = 1.0, g = 1.0, b = 0.5, a = 1.0},  -- Yellow glow

        audio = {
            collect = "/sound#map_found",
        },

        on_collect = "reveal_map_area",
        area_id = "forest",
        area_name = "Ancient Forest",

        notification = "Map Updated: Ancient Forest",
        popup_duration = 4.0,
        show_in_collection = false,

        minimap_icon = "map_piece",
        minimap_color = {r = 1.0, g = 1.0, b = 0.5},
    },

    map_piece_caves = {
        category = "progression",
        name = "Cave Map",
        description = "Reveals the Cave System on your map",

        animation = "map_piece_caves",
        glow = true,
        glow_color = {r = 0.6, g = 0.4, b = 0.2, a = 1.0},

        audio = {
            collect = "/sound#map_found",
        },

        on_collect = "reveal_map_area",
        area_id = "caves",
        area_name = "Crystal Caves",

        notification = "Map Updated: Crystal Caves",
        popup_duration = 4.0,
        show_in_collection = false,

        minimap_icon = "map_piece",
        minimap_color = {r = 0.6, g = 0.4, b = 0.2},
    },

    map_piece_castle = {
        category = "progression",
        name = "Castle Map",
        description = "Reveals the Dark Castle on your map",

        animation = "map_piece_castle",
        glow = true,
        glow_color = {r = 0.5, g = 0.0, b = 0.8, a = 1.0},

        audio = {
            collect = "/sound#map_found",
        },

        on_collect = "reveal_map_area",
        area_id = "castle",
        area_name = "Dark Castle",

        notification = "Map Updated: Dark Castle",
        popup_duration = 4.0,
        show_in_collection = false,

        minimap_icon = "map_piece",
        minimap_color = {r = 0.5, g = 0.0, b = 0.8},
    },

    map_fragment = {
        category = "progression",
        name = "Map Fragment",
        description = "Reveals nearby rooms on the map",

        animation = "map_fragment",
        glow = true,
        glow_color = {r = 1.0, g = 1.0, b = 0.6, a = 1.0},

        audio = {
            collect = "/sound#map_found",
        },

        on_collect = "reveal_nearby",
        reveal_radius = 1600,

        notification = "Map Updated",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "map_piece",
        minimap_color = {r = 1.0, g = 1.0, b = 0.5},
    },

    --[[========================================================================
        KEYS & STORY ITEMS
    ========================================================================]]

    key_red = {
        category = "key",
        name = "Red Key",
        description = "Opens red doors",

        animation = "key_red",
        glow = true,
        glow_color = {r = 1.0, g = 0.0, b = 0.0, a = 1.0},

        audio = {
            collect = "/sound#key_found",
        },

        on_collect = "add_to_inventory",
        item_id = "key_red",

        notification = "Red Key obtained!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "key",
        minimap_color = {r = 1.0, g = 0.0, b = 0.0},
    },

    key_blue = {
        category = "key",
        name = "Blue Key",
        description = "Opens blue doors",

        animation = "key_blue",
        glow = true,
        glow_color = {r = 0.0, g = 0.5, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#key_found",
        },

        on_collect = "add_to_inventory",
        item_id = "key_blue",

        notification = "Blue Key obtained!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "key",
        minimap_color = {r = 0.0, g = 0.5, b = 1.0},
    },

    key_gold = {
        category = "key",
        name = "Gold Key",
        description = "Opens ornate gold doors",

        sprite = "/developer/assets/atlas/collectibles/keys.atlas",
        animation = "gold",
        glow = true,
        glow_color = {r = 1.0, g = 0.75, b = 0.1, a = 1.0},

        audio = {
            collect = "/sound#key_found",
        },

        on_collect = "add_to_inventory",
        item_id = "key_gold",

        notification = "Gold Key obtained!",
        popup_duration = 3.0,
        show_in_collection = false,

        minimap_icon = "key",
        minimap_color = {r = 1.0, g = 0.75, b = 0.1},
    },

    key_boss = {
        category = "key",
        name = "Boss Key",
        description = "Opens the door to the final boss",

        animation = "key_boss",
        glow = true,
        glow_color = {r = 1.0, g = 0.8, b = 0.0, a = 1.0},

        audio = {
            collect = "/sound#boss_key_found",
        },

        on_collect = "add_to_inventory",
        item_id = "key_boss",

        notification = "Boss Key obtained!",
        popup_duration = 4.0,
        show_in_collection = false,

        minimap_icon = "key_boss",
        minimap_color = {r = 1.0, g = 0.8, b = 0.0},
    },

    upgrade_material = {
        category = "material",
        name = "Upgrade Material",
        description = "A crafting material for upgrades",

        animation = "upgrade_material",
        glow = true,
        glow_color = {r = 0.8, g = 0.9, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#coin_pickup",
        },

        on_collect = "add_to_inventory",
        item_id = "upgrade_material",

        notification = "Material Acquired",
        popup_duration = 2.0,
        show_in_collection = false,

        minimap_icon = "relic",
        minimap_color = {r = 0.6, g = 0.8, b = 1.0},
    },

    --[[========================================================================
        RELICS & COLLECTIBLES (100% Completion)
    ========================================================================]]
    --
    -- HOW TO RECORD A RELIC PICKUP WITH A FLAG:
    --
    -- Use a custom on_collect function to call Flags.set("relic_found", true).
    -- Dialogue and gates can check this flag to react to the collected relic.
    -- In Tiled, place a collectible template and select the custom type here.
    --

    relic = {
        category = "relic",
        name = "Relic",
        description = "A mysterious relic from a forgotten age",

        animation = "relic",
        glow = true,
        glow_color = {r = 0.9, g = 0.8, b = 0.5, a = 1.0},

        audio = {
            collect = "/sound#relic_found",
        },

        on_collect = "add_to_collection",
        relic_id = "relic_generic",

        notification = "Relic Found",
        popup_duration = 4.0,
        show_in_collection = true,
        collection_number = 0,

        minimap_icon = "relic",
        minimap_color = {r = 0.9, g = 0.8, b = 0.5},
    },

    relic_ancient_sword = {
        category = "relic",
        name = "Ancient Sword",
        description = "A legendary blade from the Old Kingdom. Its edge still gleams despite centuries of slumber.",

        animation = "relic_ancient_sword",
        glow = true,
        glow_color = {r = 0.8, g = 0.8, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#relic_found",
        },

        on_collect = "add_to_collection",
        relic_id = "ancient_sword",

        notification = "Relic Found: Ancient Sword",
        popup_duration = 5.0,
        show_in_collection = true,
        collection_number = 1,

        minimap_icon = "relic",
        minimap_color = {r = 1.0, g = 0.8, b = 0.0},
    },

    relic_crystal_shard = {
        category = "relic",
        name = "Crystal Shard",
        description = "A fragment of pure crystal energy. It pulses with an otherworldly light.",

        animation = "relic_crystal_shard",
        glow = true,
        glow_color = {r = 0.5, g = 0.8, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#relic_found",
        },

        on_collect = "add_to_collection",
        relic_id = "crystal_shard",

        notification = "Relic Found: Crystal Shard",
        popup_duration = 5.0,
        show_in_collection = true,
        collection_number = 2,

        minimap_icon = "relic",
        minimap_color = {r = 0.5, g = 0.8, b = 1.0},
    },

    relic_golden_chalice = {
        category = "relic",
        name = "Golden Chalice",
        description = "An ornate chalice once used in royal ceremonies. Still bears ancient inscriptions.",

        animation = "relic_golden_chalice",
        glow = true,
        glow_color = {r = 1.0, g = 0.8, b = 0.0, a = 1.0},

        audio = {
            collect = "/sound#relic_found",
        },

        on_collect = "add_to_collection",
        relic_id = "golden_chalice",

        notification = "Relic Found: Golden Chalice",
        popup_duration = 5.0,
        show_in_collection = true,
        collection_number = 3,

        minimap_icon = "relic",
        minimap_color = {r = 1.0, g = 0.8, b = 0.0},
    },

    -- -------------------------------------------------------------------------
    -- STORY RELIC EXAMPLE: Hermit Medal
    --
    -- This keepsake records the Desert Hermit's lost medal in the collection.
    -- It uses the same pickup feedback and collection display as other relics.
    --
    -- To use in Tiled:
    --   - Place a collectible template on the top-level templates layer
    --   - Set collectible_type = relic_hermit
    --   - Picking it up adds the Hermit Medal to the player's collection
    -- -------------------------------------------------------------------------
    relic_hermit = {
        category = "relic",
        name = "Hermit Medal",
        description = "The weathered medal the Desert Hermit lost in the ruined spires above the dunes.",

        sprite = "/developer/assets/atlas/collectibles/relics.atlas",
        animation = "sword",
        glow = true,
        glow_color = {r = 0.9, g = 0.8, b = 0.5, a = 1.0},

        audio = {
            collect = "/sound#relic_found",
        },

        on_collect = "add_to_collection",
        relic_id = "hermit",

        notification = "Relic Found: Hermit Medal",
        popup_duration = 4.0,
        show_in_collection = true,
        collection_number = 4,

        minimap_icon = "relic",
        minimap_color = {r = 0.9, g = 0.8, b = 0.5},
    },

    relic_coyote = {
        category = "relic",
        name = "Coyote Heart",
        description = "A talisman cherished by the Desert Coyote, lost somewhere in the old sandstone ruins.",

        sprite = "/developer/assets/atlas/collectibles/relics.atlas",
        animation = "sword",
        glow = true,
        glow_color = {r = 1.0, g = 0.55, b = 0.45, a = 1.0},

        audio = {
            collect = "/sound#relic_found",
        },

        on_collect = "add_to_collection",
        relic_id = "coyote",

        notification = "Relic Found: Coyote Heart",
        popup_duration = 4.0,
        show_in_collection = true,
        collection_number = 5,

        minimap_icon = "relic",
        minimap_color = {r = 1.0, g = 0.55, b = 0.45},
    },

    --[[========================================================================
        LORE TABLETS
    ========================================================================]]

    lore_item = {
        category = "lore",
        name = "Lore Item",
        description = "Unlocks a lore entry",

        animation = "lore_item",
        glow = false,

        audio = {
            collect = "/sound#lore_found",
        },

        on_collect = "unlock_lore_entry",
        lore_id = "lore_entry",
        lore_text = "An ancient inscription awaits discovery...",

        notification = "Lore Entry Unlocked!",
        popup_duration = 2.5,
        show_in_collection = false,

        minimap_icon = "lore",
        minimap_color = {r = 0.8, g = 0.8, b = 0.8},
    },

    lore_tablet_origins = {
        category = "lore",
        name = "Tablet of Origins",
        description = "An ancient stone tablet inscribed with the history of this land.",

        animation = "lore_tablet_origins",
        glow = true,
        glow_color = {r = 0.6, g = 0.6, b = 0.6, a = 1.0},

        audio = {
            collect = "/sound#lore_found",
        },

        on_collect = "unlock_lore_entry",
        lore_id = "origins",
        lore_text = "In the beginning, the land was forged by the Ancient Ones...",

        notification = "Lore Discovered: Origins",
        popup_duration = 4.0,
        show_in_collection = true,

        minimap_icon = "lore",
        minimap_color = {r = 0.8, g = 0.8, b = 0.8},
    },

    --[[========================================================================
        GEMS (Size Variants for Loot Tables)
    ========================================================================]]

    gem_small = {
        category = "currency",
        name = "Small Gem",
        description = "A small valuable gemstone",

        animation = "gem_small",
        glow = false,

        audio = {
            collect = "/sound#gem_collect",
        },

        on_collect = "add_currency",
        currency_type = "gems",
        value = 5,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,
    },

    gem_medium = {
        category = "currency",
        name = "Medium Gem",
        description = "A medium-sized valuable gemstone",

        animation = "gem_medium",
        glow = true,
        glow_color = {r = 0.6, g = 0.3, b = 0.9, a = 1.0},

        audio = {
            collect = "/sound#gem_collect",
        },

        on_collect = "add_currency",
        currency_type = "gems",
        value = 15,

        notification = nil,
        popup_duration = 0,
        show_in_collection = false,

        respawns = true,
    },

    gem_large = {
        category = "currency",
        name = "Large Gem",
        description = "A valuable gemstone",

        animation = "gem_large",
        glow = true,
        glow_color = {r = 0.5, g = 0.0, b = 1.0, a = 1.0},

        audio = {
            collect = "/sound#gem_collect",
        },

        on_collect = "add_currency",
        currency_type = "gems",
        value = 50,

        notification = "Gem +50",
        popup_duration = 1.5,
        show_in_collection = false,

        minimap_icon = "gem",
        minimap_color = {r = 0.5, g = 0.0, b = 1.0},
    },
}

-- Optional catalogs use the bundled loader in game and fresh nested loads in
-- Prepare & Check. New catalog families join here when their support ships.
local ok, abilities = pcall(require, "developer.config.abilities")
local powerups_ok, powerups = pcall(require, "developer.config.powerups")
local weapons_ok, weapons = pcall(require, "developer.config.weapons")
local charms_ok, charms = pcall(require, "developer.config.charms")
return require("mvtk.collectibles.generated_types").append(collectible_types, {
    abilities = ok and abilities or nil,
    powerups = powerups_ok and powerups or nil,
    weapons = weapons_ok and weapons or nil,
    charms = charms_ok and charms or nil,
    upgrades = require "developer.config.upgrades",
})
