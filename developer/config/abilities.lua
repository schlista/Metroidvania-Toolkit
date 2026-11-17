-- developer/config/abilities.lua
-- Centralised ability metadata consumed by mvtk.abilities.ability_manager
-- Entries here become the Tiled optional_abilities dropdown after Project > Prepare & Check.
-- Fields on each ability:
-- name and description supply the displayed label and help text.
-- category groups it as movement, combat, defensive or utility.
-- starts_unlocked must stay false: true force-unlocks it again on every save load.
-- Choose starting unlocks in ability_defaults.lua or Game Settings > Abilities instead.
-- enabled defaults to true; false disables use even after the ability is unlocked.
-- cooldown is the delay between uses in seconds.
-- stamina_cost draws from the single stamina pool; new abilities ship with 0.
-- Optional HUD metadata on each ability:
-- show_on_hud defaults to true; false hides its label even when unlocked.
-- hud_short overrides the compact label; by default it uses the initials of name.

local AbilityConfig = {
    stamina = {
        max = 100, -- Ignored: the maximum is Project > Game Settings... > Player > Max stamina.
        regen_per_sec = 25, -- Stamina points restored per second while below the live maximum.
    },
    abilities = {
        -- Passive carried light; no button or ability-use event is needed.
        lantern = {
            name = "Lantern", -- DisplayText resolves the pickup and ability label.
            description = "Lights the area around you in dark places", -- Displayed ability help.
            category = "utility", -- Game Settings > Abilities > Utility.
            starts_unlocked = false, -- Grant through a pickup or a starting unlock.
            enabled = true, -- Available after unlocking.
            cooldown = 0, -- Passive: no activation delay.
            stamina_cost = 0, -- Carried light spends no stamina.
        },
        -- Passive discovery; no input or ability-use event is needed.
        reveal_lens = {
            name = "Reveal Lens", -- DisplayText resolves the pickup and ability label.
            description = "Reveal hidden secrets near you", -- Displayed ability help.
            category = "utility", -- Game Settings > Abilities > Utility.
            starts_unlocked = false, -- Grant through a pickup or Game Settings starting unlock.
            enabled = true, -- Available to the ability system after unlocking.
            cooldown = 0, -- Passive: no activation delay.
            stamina_cost = 0, -- Passive discovery spends no stamina.
        },
        -- Placed with Down + Ranged Attack; owns no separate input binding.
        bomb = {
            name = "Bomb", -- DisplayText resolves the pickup and ability label.
            description = "Place a timed bomb to break bomb walls and reveal bomb secrets", -- Displayed help.
            category = "utility", -- Game Settings > Abilities > Utility.
            starts_unlocked = false, -- Place a Bomb pickup or choose a starting unlock.
            enabled = true, -- Allows use after unlocking.
            cooldown = 0.4, -- Seconds between placements.
            stamina_cost = 0, -- Bomb placement spends no stamina by default.
        },
        -- Movement
        compact_form = {
            name = "Compact Form", -- DisplayText resolves pickup, ability and HUD labels.
            description = "Hold Down and press Slide on the ground to crawl through low tunnels", -- Displayed help.
            category = "movement", -- Game Settings > Abilities > Movement.
            starts_unlocked = false, -- Grant through a pickup or a starting unlock.
            enabled = true, -- Available after unlocking.
            cooldown = 0, -- Standing and crawling have no activation delay.
            stamina_cost = 0, -- Entering spends no stamina by default.
        },
        super_jump = {
            name = "Super Jump", -- DisplayText resolves pickup, ability and HUD labels (SJ).
            description = "Hold Down while standing still to charge, then Jump straight up", -- Displayed help.
            category = "movement", -- Game Settings > Abilities > Movement.
            starts_unlocked = false, -- Grant through a pickup or the starting unlock.
            enabled = true, -- Available after unlocking.
            cooldown = 0.5, -- Seconds between successful launches.
            stamina_cost = 0, -- Charged launches spend no stamina by default.
        },
        blink = {
            name = "Blink", -- DisplayText resolves the pickup and ability label.
            hud_short = "Bl", -- Keep the compact HUD label distinct from Bomb's B.
            description = "Press Dash again while dashing or sliding to blink a short distance", -- Displayed help.
            category = "movement", -- Game Settings > Abilities > Movement.
            starts_unlocked = false, -- Grant through a pickup or a starting unlock.
            enabled = true, -- Available after unlocking.
            cooldown = 0.6, -- Seconds between successful teleports.
            stamina_cost = 0, -- No stamina cost by default.
            prerequisites = { any = { "air_dash", "slide" } }, -- Progression needs either movement ability too.
        },
        intangible_dash = {
            name = "Intangible Dash", -- DisplayText resolves the displayed label.
            description = "Air dashes pass through intangible barriers and enemy attacks", -- Displayed help.
            category = "movement", -- Game Settings > Abilities > Movement.
            starts_unlocked = false, -- Grant through a pickup or a starting unlock.
            enabled = true, -- Available after unlocking.
            cooldown = 0, -- Passive upgrade: no separate activation delay.
            stamina_cost = 0, -- The underlying dash keeps its own stamina cost.
        },
        double_jump = {
        name = "Double Jump",
        description = "Jump again while in the air",
        category = "movement",
        starts_unlocked = false,  -- Must be picked up
        enabled = true,
        cooldown = 0,
        stamina_cost = 0,
    },
        air_dash = {
        name = "Air Dash",
        description = "Dash through the air in any direction",
        category = "movement",
        starts_unlocked = false,  -- Must be picked up
        enabled = true,
        cooldown = 1.0,
        stamina_cost = 10,
    },
        -- Passive charge upgrade; the Air Dash ability still controls dash use.
        extra_air_dash = {
        name = "Extra Air Dash", -- DisplayText resolves the displayed label.
        description = "One more air dash before landing", -- Pickup and ability help text.
        category = "movement", -- Appears under Abilities > Movement.
        starts_unlocked = false, -- Grant through Game Settings or a matching pickup.
        enabled = true, -- Apply the configured charge bonus when unlocked.
        cooldown = 0, -- Passive: no separate activation delay.
        stamina_cost = 0, -- Passive: no extra stamina cost.
    },
        wall_climb = {
        name = "Wall Climb",
        description = "Cling to and climb walls",
        category = "movement",
        starts_unlocked = false,  -- Must be picked up
        enabled = true,
        cooldown = 0,
        stamina_cost = 5,
    },
        slide = {
        name = "Slide",
        description = "Slide along the ground at high speed",
        category = "movement",
        starts_unlocked = false,  -- Must be picked up
        enabled = true,
        cooldown = 0.5,
        stamina_cost = 5,
    },
        -- Passive height upgrade; no input, cooldown or stamina is required.
        high_jump = {
        name = "High Jump",
        description = "Jump higher from the ground",
        category = "movement",
        starts_unlocked = false, -- Choose a starting unlock in Game Settings or place a pickup.
        enabled = true, -- Use the upgrade whenever it is unlocked.
        cooldown = 0, -- Passive: every ground jump benefits.
        stamina_cost = 0, -- Passive: jumping does not spend stamina.
    },
        extended_jump = {
        name = "Extended Jump",
        description = "Hold jump for extra height and hang time",
        category = "movement",
        enabled = true,
        cooldown = 0,
        stamina_cost = 0,
    },

        grapple = {
        name = "Grapple",
        hud_short = "Gr", -- Distinguish Grapple from Glide in the compact HUD line.
        description = "Hold to catch any ceiling; steer to swing and release to leap",
        category = "movement",
        enabled = true,
        -- Must be picked up: Lanternfall grants it at the Rite of the Hook.
        -- true here would force-unlock it on every save load, overriding
        -- ability_defaults.lua (see ability_manager.load_save_data).
        starts_unlocked = false,
        cooldown = 0, -- Continuous ceiling chains never wait on ability cooldown.
        stamina_cost = 0, -- Exploration grapples do not consume a limited resource.
    },


        -- Combat
        charge_attack = {
        name = "Charge Attack",
        description = "Hold attack to charge up a powerful strike",
        category = "combat",
        enabled = true,
        starts_unlocked = false,  -- Must be picked up
        cooldown = 2.0,
        stamina_cost = 20,
    },
        down_strike = {
        name = "Down Strike",
        description = "Strike downward while in the air",
        category = "combat",
        enabled = true,
        starts_unlocked = false,  -- Must be picked up
        cooldown = 1.5,
        stamina_cost = 15,
    },
        ranged_attack = {
        name = "Ranged Attack",
        description = "Launch projectiles at enemies",
        category = "combat",
        enabled = true,
        starts_unlocked = false,  -- Must be picked up
        cooldown = 0.8,
        stamina_cost = 10,
    },

        dash = {
        name = "Dash",
        description = "Hold Slide after a ground slide to run at Run Speed",
        category = "movement",
        enabled = true,
        cooldown = 0.5,
        stamina_cost = 5,
    },

        glide = {
        name = "Glide",
        description = "Hold JUMP while falling to glide",
        category = "movement",
        enabled = true,
        cooldown = 0,
        stamina_cost = 2,
    },

        ground_pound = {
        name = "Ground Pound",
        description = "Press DOWN while airborne to slam downward",
        category = "combat",
        enabled = true,
        cooldown = 1.0,
        stamina_cost = 10,
    },

        swim = {
        name = "Swim",
        hud_short = "Sw", -- Distinguish Swim from Slide in the compact HUD line.
        description = "Move through water",
        category = "movement",
        enabled = true,
        cooldown = 0,
        stamina_cost = 0,
    },

        wall_jump = {
        name = "Wall Jump",
        description = "Jump off walls",
        category = "movement",
        enabled = true,
        cooldown = 0,
        stamina_cost = 0,
    },

        -- Defensive / utility
        -- Passive hazard protection. Starting ownership is chosen in Game Settings.
        heat_resistance = {
          name = "Heat Resistance",
          description = "Ignore lava and flame jet hazards",
          category = "defensive",
          starts_unlocked = false, -- Unlock through a pickup or Game Settings > Abilities.
          enabled = true, -- Allow protection once unlocked.
          cooldown = 0, -- Passive protection has no reuse delay.
          stamina_cost = 0, -- Passive protection never spends stamina.
        },
        acid_resistance = {
          name = "Acid Resistance",
          description = "Ignore acid and poison gas hazards",
          category = "defensive",
          starts_unlocked = false, -- Unlock through a pickup or Game Settings > Abilities.
          enabled = true, -- Allow protection once unlocked.
          cooldown = 0, -- Passive protection has no reuse delay.
          stamina_cost = 0, -- Passive protection never spends stamina.
        },
        cold_resistance = {
          name = "Cold Resistance",
          description = "Ignore freezing water hazards",
          category = "defensive",
          starts_unlocked = false, -- Unlock through a pickup or Game Settings > Abilities.
          enabled = true, -- Allow protection once unlocked.
          cooldown = 0, -- Passive protection has no reuse delay.
          stamina_cost = 0, -- Passive protection never spends stamina.
        },
        -- Built-in flask only; potions remain usable without this ability.
        healing = {
          name = "Healing",
          show_on_hud = false, -- The quick-item block already displays Healing.
          description = "Heal with the Heal / Item button",
          category = "defensive",
          starts_unlocked = false, -- Starting ownership comes from ability_defaults.lua.
          enabled = true,
          cooldown = 0, -- Drinks have their own use time.
          stamina_cost = 0, -- Healing spends flask charges, never stamina.
        },
        slide_iframes = {
        name = "Slide Invincibility",
        show_on_hud = false, -- Keep this passive upgrade out of the ability line.
        description = "Become invulnerable during slide",
        category = "defensive",
        enabled = true,
        cooldown = 0,
        stamina_cost = 0,
        },
        air_dash_iframes = {
        name = "Dash Invincibility",
        show_on_hud = false, -- Keep this passive upgrade out of the ability line.
        description = "Become invulnerable during air dash",
        category = "defensive",
        enabled = true,
        cooldown = 0,
        stamina_cost = 0,
    },
    }
}

return AbilityConfig
