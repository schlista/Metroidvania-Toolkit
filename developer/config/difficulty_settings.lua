-- developer/config/difficulty_settings.lua
-- Starting difficulty and named profiles for combat and defeat currency.
--
-- Every multiplier accepts 0.1-10; 1.0 preserves the authored baseline.
-- damage_taken_mult: every hit the player takes, including hazards and drowning,
--   except instant kills, which skip scaling.
-- damage_dealt_mult: every hit enemies and bosses take.
-- enemy_health_mult: enemy health when it spawns.
-- boss_health_mult: boss health when it spawns; omitted values fall back to
--   enemy_health_mult. Boss phase thresholds keep the same health fractions.
-- loot_mult: currency from defeated enemies and bosses, rounded per drop;
--   other pickups and item counts are unchanged.
-- A per-enemy Tiled Difficulty Override stacks underneath the chosen profile:
--   a hard enemy on Hard has 1.25 x 1.25 health. Health applies at spawn time.
-- Entries here become the Enemy difficulty dropdown after Project > Prepare & Check;
-- reopen the project in Tiled to see added profiles.

return {
    selection = "new_game", -- fixed: creator chooses; new_game: ask once; anytime: also allow pause changes.
    current = "normal", -- Default profile; Game Settings can override this key.
    order = { "easy", "normal", "hard", "nightmare" }, -- Player choice and pause-cycle order; use profile keys.
    profiles = { -- Named tuning presets; each follows the key descriptions above.
        easy = {
            label = "Easy", -- Player-visible name, also used by the pause row.
            description = "Take less damage and face weaker foes.", -- New-game picker detail.
            damage_taken_mult = 0.8,
            damage_dealt_mult = 1.1,
            enemy_health_mult = 0.9,
            boss_health_mult = 0.9,
            loot_mult = 1.1,
        },
        normal = {
            label = "Normal", -- Player-visible name.
            description = "The authored combat balance.", -- New-game picker detail.
            damage_taken_mult = 1.0,
            damage_dealt_mult = 1.0,
            enemy_health_mult = 1.0,
            boss_health_mult = 1.0,
            loot_mult = 1.0,
        },
        hard = {
            label = "Hard", -- Player-visible name.
            description = "Take more damage and face tougher foes.", -- New-game picker detail.
            damage_taken_mult = 1.2,
            damage_dealt_mult = 0.95,
            enemy_health_mult = 1.25,
            boss_health_mult = 1.25,
            loot_mult = 1.0,
        },
        nightmare = {
            label = "Nightmare", -- Player-visible name.
            description = "The strongest foes and highest incoming damage.", -- New-game picker detail.
            damage_taken_mult = 1.4,
            damage_dealt_mult = 0.9,
            enemy_health_mult = 1.4,
            boss_health_mult = 1.4,
            loot_mult = 1.2,
        },
    }
}
