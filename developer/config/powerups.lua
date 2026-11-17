-- Temporary world pickups. Enable them in Game Settings > Equipment > Power-ups.
-- Effects end on death or a new player session; they are never saved or stored.
return {
    enabled = false, -- Off leaves world pickups in place and preparation warns.
    stacking = "refresh", -- refresh restarts the timer; extend adds remaining time.
    powerups = {
        invincibility = {
            name = "Invincibility", -- Source wording, collected for translations.
            duration = 10, -- Active play seconds, from 0.5 to 600; pause holds it.
            -- Blocks ordinary enemy/projectile/contact and non-lethal hazard hits.
            -- Hazard returns cause no damage while enabled. Kill hazards, lethal
            -- hits, drowning and damage over time still apply.
            effects = { invulnerable = true }, -- Temporary StatKeys effects only.
            icon_animation = "powerup_invincibility", -- gameplay_visuals animation.
            collect_sound = "/sound#powerup_invincibility", -- Collectible sound component.
        },
        speed = {
            name = "Speed Boost", -- Source wording, collected for translations.
            duration = 15, -- Active play seconds; refresh/extend uses this amount.
            effects = { speed_mult = 1.5 }, -- Walk/run speed only, not swim/climb.
            icon_animation = "powerup_speed", -- gameplay_visuals animation.
            collect_sound = "/sound#powerup_speed", -- Collectible sound component.
        },
    },
}
