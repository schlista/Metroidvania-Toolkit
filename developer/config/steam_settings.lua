-- Optional Steam settings. The add-on ships off; this file alone
-- does not enable Steam or add an extension dependency to game.project.
return {
    -- Your game's Steamworks app id; 0 means not set. This documents the id for
    -- authoring checks; steam.init() has no app-id parameter. Steam supplies it
    -- when launching the game, or reads steam_appid.txt for local testing.
    -- Each creator needs their own Steamworks account and app id.
    app_id = 0,
    -- Stable achievements.lua ids mapped to published Steamworks API Names.
    -- An unmapped id is sent as itself. API Names are identifiers, not player
    -- text: author names, descriptions, icons and translations in Steamworks.
    achievement_names = {
        -- hunter = "ACH_HUNTER",
    },
    -- Text your Steam friends can see. Translate these source phrases with
    -- your game's translation tables before uploading the Steamworks file.
    rich_presence = {
        -- Show title, playing or region status to Steam friends; ships off.
        enabled = false,
        -- Status while the player is at the title screen.
        title = "At the title screen",
        -- Status during play in a room with no named region.
        playing = "Playing",
        -- Use {region} exactly once for the name from biomes.lua; no other
        -- braces or percent signs are allowed in this phrase.
        region = "Exploring {region}",
    },
    -- Steam Auto-Cloud setup for your published game, not editor test runs.
    cloud_saves = {
        -- Have Prepare & Check write your Steam Auto-Cloud settings; ships off.
        enabled = false,
        -- Also sync mvtk_settings: volume, language and display preferences.
        include_preferences = false,
        -- Also sync mvtk_bindings_v2: the player's remapped keys and buttons.
        include_controls = false,
    },
    -- Extra game language code -> Steam API language code mappings, overriding
    -- the built-in map; for example ["pt-BR"] = "brazilian". Empty uses defaults.
    steam_languages = {},
}
