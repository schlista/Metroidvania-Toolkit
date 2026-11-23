-- mvtk/core/build_deps.lua
-- BUILD DEPENDENCY MANIFEST
--
-- This module tells the Defold build system (bob) about all developer config
-- files that the mvtk framework loads via pcall(require, ...) at runtime.
--
-- Problem: Defold's bob builder uses static text analysis to find require()
-- calls and determine which .lua files to include in the game archive.
-- pcall(require, "module") is NOT detected as a dependency, so those
-- modules get silently excluded from the bundle.
--
-- Solution: This file contains explicit require() statements inside an
-- unreachable code block. The build system's scanner finds them and
-- includes the files, but they never execute at runtime. The actual
-- loading is done safely via pcall in the framework scripts.
--
-- IMPORTANT: When adding new developer config files that are loaded via
-- pcall(require, ...) in any mvtk/ script, add them here too.

-- Never executes, but build system scans for require("...") patterns
if false then
    require("mvtk.core.localization")
    -- settings.lua names it in a variable (require cycle) and runs in the boot
    -- world, before audio_controller.script's literal require loads it.
    require("mvtk.audio.volume_groups")
    require("developer.config.ui_text")
    require("developer.config.translations.manifest_generated")
    ---------------------------------------------------------
    -- Core configs (non-optional, game won't start without these)
    ---------------------------------------------------------
    require("developer.config.resolved_config")
    require("developer.config.game_completion")
    require("developer.config.player_settings")
    require("developer.config.player_actions")
    require("developer.config.default_bindings")
    require("developer.config.debug_config")
    require("developer.config.tile_settings")
    require("developer.config.collectible_types")
    require("developer.config.fragments")
    require("developer.config.run_stats")
    require("developer.config.leveling")
    require("developer.config.bestiary")
    require("developer.config.achievements")
    require("developer.config.quests")
    require("developer.config.goals")
    require("developer.config.countdowns")
    require("developer.config.npc_settings")
    require("developer.config.random_drops")
    require("developer.config.performance_budgets")
    require("developer.config.powerups")
    require("developer.config.weapons")
    require("developer.config.charms")
    require("developer.config.crafting")
    require("developer.config.completion_tracking")
    require("developer.config.trial_settings")
    require("developer.config.new_game_plus")
    require("developer.config.extras")
    require("developer.config.extras_gallery_generated")
    require("mvtk.game.trial_limits")
    require("developer.config.steam_settings")
    require("developer.config.items")
    require("developer.config.shops")
    require("developer.config.upgrades")
    require("developer.config.reward_text")
    require("developer.config.narrative.cutscenes")
    require("developer.config.narrative.cutscene_settings")
    require("developer.config.narrative.dialogues")
require("developer.config.narrative.dialogues_authored")
    require("developer.config.narrative.cutscenes_generated")
    require("developer.config.narrative.videos")

    ---------------------------------------------------------
    -- Gameplay configs
    ---------------------------------------------------------
    require("developer.config.abilities")
    require("developer.config.combat_config")
    require("developer.config.difficulty_settings")
    require("developer.config.gameplay_constants")
    require("developer.config.hazard_types")
    require("developer.config.damage_types")
    require("developer.config.status_effects")
    require("developer.config.wall_surface_types")
    require("developer.config.movement_zone_types")
    require("developer.config.carry_settings")
    require("developer.config.interaction")
    require("developer.config.loot_tables")
    require("developer.config.loot_tables_authored")

    ---------------------------------------------------------
    -- Player & input
    ---------------------------------------------------------
    require("developer.config.runtime_settings")
    require("developer.config.settings_defaults")
    require("developer.config.accessibility")
    require("developer.config.swim_settings")

    ---------------------------------------------------------
    -- Enemy & NPC configs
    ---------------------------------------------------------
    require("developer.config.enemy_settings")
    require("developer.config.encounter_settings")
    require("developer.config.enemy_types")
    require("developer.config.boss_types")
    require("developer.config.boss_animations")
    require("developer.config.boss_arenas")
    require("developer.config.boss_behaviors")
    require("developer.config.boss_movesets")
    require("developer.config.boss_ui")
    require("developer.config.npc_types")
    require("developer.config.room_enemies")
    require("developer.config.tiled_enemy_overrides")

    ---------------------------------------------------------
    -- World & room configs
    ---------------------------------------------------------
    require("developer.config.biomes")
    require("developer.config.camera_zones")
    require("developer.config.gate_types")
    require("developer.config.gates")
    require("developer.config.switches")
    require("developer.config.layer_settings")
    require("developer.config.map_markers")
    require("developer.config.rooms_config")
    require("developer.config.room_tilemap_layers_generated")
    require("developer.config.tilemap_animations")
    require("developer.config.tilemap_animations_generated")
    require("mvtk.rooms.tilemap_layers")
    require("developer.config.elevators_generated")
    require("developer.config.world_census_generated")
    require("developer.config.world_census")
    require("developer.config.map_icons")
    require("mvtk.map.map_tracking")
    require("developer.config.stream_settings")
    require("developer.config.tiled_object_config")
    require("developer.config.water_zones")

    ---------------------------------------------------------
    -- Collectibles & objects
    ---------------------------------------------------------
    require("developer.config.chest_inline_contents")
    require("developer.config.locked_door_settings")
    require("developer.config.secret_settings")
    require("developer.config.secret_types")

    ---------------------------------------------------------
    -- Audio
    ---------------------------------------------------------
    require("developer.config.sound_bank")
    require("developer.config.music_tracks_generated")
    require("developer.config.ambient_sounds")
    require("developer.config.positional_audio")
    require("developer.config.ambient_zones")

    ---------------------------------------------------------
    -- UI & visual
    ---------------------------------------------------------
    require("developer.config.lighting")
    require("mvtk.world.lantern_light") -- Lazy optional require in the light manager.
    require("developer.config.hud_layout")
    require("developer.config.localization")
    require("developer.config.minimap_settings")
    require("developer.config.particle_effects")
    require("developer.config.screenshot_marker_settings")
    require("developer.config.tutorial_popups")
    require("developer.config.ui_theme")

    ---------------------------------------------------------
    -- Editor & tools (only needed in dev builds)
    ---------------------------------------------------------
    require("mvtk.tiled.catalog_enums")
    require("mvtk.editor.room_catalogs")
    require("mvtk.editor.room_catalogs.cutscenes")
    require("mvtk.editor.room_catalogs.world_census")
    require("developer.config.layout_editor_settings")
    require("developer.tools.setup_wizard")
    require("developer.tools.dev_helpers")
    -- Validated on the boot screen (mvtk/boot/config_gate.lua), before the game collection loads.
    require("developer.config.combat_music")
    require("developer.config.healing")
    require("developer.config.menu_settings")
    require("developer.config.display_settings")
    require("developer.config.creator_settings")
    require("developer.config.player_art")
    require("developer.config.movement_test")
    require("developer.config.persistence_settings")
    require("developer.config.save_migrations")
    require("developer.config.combat_overrides")
    require("developer.config.ability_defaults")
    require("developer.config.enemy_defaults")
    require("developer.config.secret_rooms")
    require("developer.config.world_lint")
    require("developer.config.ambience_tracks")
    require("developer.config.game_config")
    -- mvtk/combat/multipliers.lua loads this by name, because its sources require multipliers.
    require("mvtk.combat.multiplier_sources")
end

return true
