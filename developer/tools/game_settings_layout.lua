-- Display order for Project > Game Settings. Field titles, values, types,
-- choices, ranges and help belong to creator_settings_model, not this layout.
local Model = require "mvtk.core.creator_settings_model"
local M = {}

local function ability_sections()
    local sections, by_category = {}, {}
    local titles = { movement = "Movement", combat = "Combat", defensive = "Defensive", other = "Other" }
    for _, field in ipairs(Model.toggle_fields("ability")) do
        local category = field.category or "other"
        if not by_category[category] then
            local title = titles[category] or (category:gsub("_", " "):gsub("^%l", string.upper))
            by_category[category] = { title = title, fields = {} }
            sections[#sections + 1] = by_category[category]
        end
        local fields = by_category[category].fields
        fields[#fields + 1] = field.key
    end
    return sections
end

local function control_sections()
    local sections, groups = {}, {}
    for _, group in ipairs({
        { "Movement", { "jump", "dash", "backdash", "ground_pound", "morph", "grapple" } },
        { "Combat", { "attack", "special", "ranged", "parry", "loadout_cycle" } },
        { "Items and interaction", { "interact", "quick_use", "potion" } },
        { "Map and menus", { "map", "world_map", "marker", "inventory", "settings", "pause" } },
    }) do
        local section = { title=group[1], fields={} }
        sections[#sections + 1] = section
        for _, id in ipairs(group[2]) do groups[id] = section end
    end
    local timing, other = { title="Button timing", fields={} }, { title="Other actions", fields={} }
    for _, key in ipairs(Model.binding_fields) do
        local binding = Model.fields[key].binding
        local section = binding.slot == "hold_seconds" and timing or groups[binding.id] or other
        section.fields[#section.fields + 1] = key
    end
    timing.fields[#timing.fields + 1] = "quick_use_step_repeat"
    sections[#sections + 1] = timing
    if #other.fields > 0 then sections[#sections + 1] = other end
    return sections
end

M.tabs = {
    { title = "Player", sections = {
        { title = "Size", fields = { "player_scale", "scale_movement" } },
        { title = "Health and resources", fields = { "max_health", "max_energy", "max_stamina", "health_fragment_pieces", "energy_fragment_pieces" } },
        { title = "Healing", fields = { "healing_model", "heal_charges", "heal_amount",
            "heal_channel_amount", "heal_cost", "heal_channel_time" } },
    } },
    { title = "Movement feel", sections = {
        { title = "Ground", fields = { "walk_speed", "run_speed", "ground_accel", "run_accel", "ground_decel", "turn_brake" } },
        { title = "Jump", fields = { "jump_height", "speed_jump_bonus", "gravity", "jump_release_mode", "jump_release_gravity_mult",
            "jump_cut_speed_mult", "jump_min_hold_time",
            "coyote_time", "jump_buffer", "corner_correction", "air_jumps" } },
        { title = "In the air", fields = { "air_accel_mult", "air_decel_mult", "apex_threshold", "apex_gravity_mult" } },
        { title = "Falling", fields = { "fall_gravity_mult", "fast_fall_mult", "fast_fall_max_mult", "max_fall_speed" } },
        { title = "Walls", fields = { "wall_slide_speed", "wall_jump_grace", "wall_jump_push", "steer_lock",
            "wall_climb_speed", "wall_cling_fall_speed" } },
        { title = "Dash and slide", fields = { "air_dash_speed", "air_dash_duration", "air_dash_cooldown", "air_dash_count",
            "air_dash_directions", "air_dash_suspend_gravity", "air_dash_end_lift", "extra_air_dash_bonus", "slide_speed", "slide_duration" } },
        { title = "Glide", fields = { "glide_gravity_mult", "glide_fall_speed" } },
    } },
    { title = "Player art", sections = {
        { title = "Source and frames", fields = { "art_source", "art_mode", "art_frame_width", "art_frame_height",
            "art_animations", "art_mappings", "art_fps", "art_once", "art_required", "art_fallback" } },
        { title = "Size and body", fields = { "art_width", "art_height", "art_origin_x", "art_origin_y",
            "art_body_width", "art_body_height" } },
    } },
    { title = "Abilities", sections = ability_sections() },
    { title = "Advanced", sections = {
        { title = "High Jump", fields = { "high_jump_height_mult" } },
        { title = "Super Jump", fields = { "super_jump_charge_time", "super_jump_height_mult" } },
        { title = "Blink", fields = { "blink_distance", "blink_chain_grace" } },
        { title = "Ice", fields = { "ice_accel", "ice_decel", "ice_turn" } },
        { title = "Zip line", fields = { "zip_hang_offset", "zip_release_on_jump" } },
        { title = "Hang bar", fields = { "hang_bar_offset" } },
        { title = "Lantern", fields = { "lantern_radius", "lantern_intensity", "lantern_flicker", "lantern_min_darkness" } },
    } },
    { title = "Combat", sections = {
        { title = "Light attack", fields = { "melee_light_damage", "melee_light_cooldown",
            "light_hitbox_width", "light_hitbox_height" } },
        { title = "Heavy attack", fields = { "melee_heavy_damage", "heavy_hitbox_width", "heavy_hitbox_height" } },
        { title = "Up attack", fields = { "melee_up_damage" } },
        { title = "Ranged attack", fields = { "ranged_damage", "ranged_projectile_speed" } },
        { title = "Parry", fields = { "parry_window", "parry_push", "perfect_parry_push" } },
        { title = "Invincibility", fields = { "damage_iframes", "slide_iframe_seconds",
            "air_dash_iframe_seconds", "parry_iframes" } },
        { title = "Resource gain", fields = { "energy_from_combat", "energy_on_hit", "energy_on_parry",
            "energy_on_perfect_parry", "energy_on_defeat" } },
    } },
    { title = "Attacks", sections = Model.attack_sections },
    { title = "Combat features", sections = {
        { title = "Combo attacks", fields = { "combo_chaining", "mixed_finishers", "attack_cancels" } },
        { title = "Parry", fields = { "parry", "perfect_parry", "parry_counter", "parry_reflects", "parry_tells" } },
        { title = "Aerial attacks", fields = { "aerial_attacks", "aerial_juggle" } },
        { title = "Directional attacks", fields = { "up_attacks", "ranged_aim", "aim_stance" } },
        { title = "Projectiles", fields = { "cut_projectiles" } },
    } },
    { title = "Enemies and elements", sections = {
        { title = "Enemies", fields = { "enemy_default_archetype", "enemy_cap_per_room", "enemy_ledge_behavior", "enemy_fall_gravity", "enemy_respawn_policy", "enemy_autosave_on_permanent_defeat" } },
        { title = "Elements", fields = Model.element_fields },
        { title = "Status effects", fields = Model.status_effect_fields },
        { title = "Encounters", fields = {"encounter_wave_delay", "encounter_max_alive",
            "encounter_wave_messages", "encounter_autosave"} },
        { title = "Champions", fields = {"champion_health_mult", "champion_damage_mult", "champion_engage_range"} },
    } },
    { title = "Grapple", sections = {
        { title = "Hook", fields = { "grapple_style", "grapple_targets", "grapple_stay_hooked", "grapple_pull_hang", "grapple_reel",
            "grapple_break_on_impact", "grapple_walls" } },
        { title = "Swing and rope", fields = { "grapple_range", "grapple_hook_speed", "grapple_swing_strength", "grapple_swing_speed",
            "grapple_swing_fade", "grapple_pump_with_swing", "grapple_pump_start_speed", "grapple_counter_brake",
            "grapple_reel_speed", "grapple_pull_speed" } },
        { title = "Letting go", fields = { "grapple_momentum", "grapple_release_carry", "grapple_release_float",
            "grapple_release_boost", "grapple_release_lift", "grapple_rehook_window" } },
    } },
    { title = "Game", sections = {
        { title = "Game", fields = { "project_name", "game_id" } },
        { title = "Options", fields = { "camera_shake", "damage_numbers", "icon_theme" } },
        { title = "When the game loses focus", fields = { "pause_on_focus_loss", "pause_on_controller_disconnect", "mute_when_unfocused" } },
        { title = "Death drop", fields = { "death_drop_enabled", "death_currency_fraction", "death_minimum" } },
        { title = "Shops", fields = { "shop_sell_share" } },
        { title = "NPCs", fields = { "npc_markers_enabled", "npc_barks_enabled", "npc_bark_seconds" } },
        { title = "Cutscenes", fields = { "cutscene_opening", "cutscene_allow_skip", "cutscene_skip_hold" } },
        { title = "Combat music", fields = { "combat_music_enabled", "combat_music_track", "combat_music_line_of_sight", "combat_music_release" } },
        { title = "Hazard returns", fields = { "hazard_return_enabled", "hazard_return_damage", "hazard_return_fade_time", "hazard_return_grace_time" } },
        { title = "Difficulty", fields = { "difficulty_selection", "difficulty_default" } },
        { title = "Large worlds", fields = { "prewarm_scope", "prewarm_adjacent_regions", "actor_sleep",
            "max_live_projectiles", "max_live_damage_numbers" } },
    } },
    { title = "Ending", sections = {
        { title = "Ending settings", fields = { "ending_enabled", "ending_id", "ending_condition", "ending_flag",
            "ending_boss_id", "ending_continue_policy", "ending_return_room", "ending_return_x", "ending_return_y",
            "ending_title", "ending_body", "ending_credits", "ending_music", "ending_artwork", "ending_reward_flag" } },
        { title = "Other endings", fields = { "ending_others" } },
        { title = "Extras", fields = { "extras_enabled", "extras_notify", "extras_show_locked",
            "extras_jukebox", "extras_gallery", "extras_credits" } },
    } },
    { title = "Progression", sections = {
        { title = "Leveling", fields = { "leveling_enabled", "leveling_max_level", "leveling_first_level_xp", "leveling_xp_growth",
            "leveling_enemy_xp", "leveling_boss_xp", "leveling_health_per_level", "leveling_full_heal" } },
        { title = "Achievements", fields = { "achievements_enabled", "achievements_notify", "achievements_show_hidden_count" } },
        { title = "Quests", fields = { "quests_enabled", "quests_notify" } },
        { title = "Goals", fields = { "goals_enabled", "goals_hint_reveals_target" } },
        { title = "Completion", fields = { "completion_enabled", "completion_show_on_ending", "completion_show_in_journal" } },
        { title = "Records", fields = { "records_statistics", "records_on_ending" } },
        { title = "Bestiary", fields = { "bestiary_enabled" } },
        { title = "People", fields = { "people_enabled", "people_show_unmet" } },
        { title = "Trials", fields = { "trial_countdown", "trial_restore_health", "trial_autosave" } },
        { title = "Countdowns", fields = { "countdown_autosave", "countdown_tenths_below" } },
        { title = "New Game+", fields = { "ng_plus_enabled", "ng_plus_enemy_health_mult", "ng_plus_damage_taken_mult",
            "ng_plus_carry_level", "ng_plus_carry_equipment", "ng_plus_carry_currency" } },
    } },
    { title = "Equipment", sections = {
        { title = "Weapons", fields = { "weapons_enabled", "weapons_quick_switch", "weapons_starting" } },
        { title = "Charms", fields = { "charms_enabled", "charms_base_slots", "charms_max_slots" } },
        { title = "Crafting", fields = { "crafting_enabled" } },
        { title = "Power-ups", fields = { "powerups_enabled" } },
        { title = "Random drops", fields = { "random_drops_enabled", "random_drops_chance", "random_drops_weapons", "random_drops_charms", "random_drops_upgrades" } },
    } },
    { title = "Camera", sections = {
        { title = "View", fields = { "camera_zoom", "camera_pixel_snap" } },
        { title = "Following the player", fields = { "camera_follow_x", "camera_follow_y", "camera_deadzone_x",
            "camera_deadzone_y", "camera_lookahead", "camera_offset_x", "camera_offset_y", "camera_vertical_look" } },
        { title = "Respawning", fields = { "camera_respawn_snap", "camera_respawn_time" } },
    } },
    { title = "Display", sections = {
        { title = "Screen shape", fields = { "display_view_mode", "display_player_choice",
            "display_min_aspect", "display_max_aspect", "display_bar_red", "display_bar_green", "display_bar_blue" } },
        { title = "Framing", fields = { "display_mask_outside_room", "display_hud_frame",
            "startup_cover_red", "startup_cover_green", "startup_cover_blue", "startup_cover_fade" } },
        { title = "Pixel scaling", fields = { "display_scale_rule" } },
        { title = "Picture tone", fields = { "display_post_brightness", "display_post_gamma", "display_post_saturation",
            "display_post_tint_red", "display_post_tint_green", "display_post_tint_blue", "display_post_tint_strength",
            "display_post_player_brightness" } },
        { title = "Retro screen", fields = { "display_post_scanlines", "display_post_curvature", "display_post_vignette" } },
        { title = "Lighting", fields = { "lighting_mode", "lighting_shadow_red", "lighting_shadow_green", "lighting_shadow_blue",
            "lighting_light_red", "lighting_light_green", "lighting_light_blue", "lighting_falloff" } },
    } },
    { title = "HUD and prompts", sections = {
        { title = "Layout", fields = { "hud_preset", "hud_scale", "hud_theme", "hud_health_anchor" } },
        { title = "Show on screen", fields = { "hud_health_bar", "hud_energy_bar", "hud_stamina_bar",
            "hud_currency", "hud_currency_format", "hud_abilities", "hud_mode_label", "hud_quick_item", "hud_interact_hint", "hud_area_title", "hud_notices", "hud_status_chips", "hud_level_xp", "hud_weapon", "hud_powerups", "hud_goal", "hud_countdown", "hud_play_timer", "hud_trial" } },
        { title = "Area titles", fields = { "area_titles", "area_title_seconds" } },
        { title = "Toasts and prompts", fields = { "toast_anchor", "toast_y", "toast_text_scale",
            "prompt_anchor", "prompt_x", "prompt_y", "prompt_opacity", "prompt_text_scale" } },
        { title = "Message backing", fields = { "message_plate_r", "message_plate_g", "message_plate_b", "message_plate_a" } },
        { title = "Health bar color", fields = { "hud_health_red", "hud_health_green", "hud_health_blue" } },
    } },
    { title = "Controls", sections = control_sections() },
    { title = "Map", sections = {
        { title = "Discovery", fields = { "map_fog", "map_discovery_mode", "map_reveal_radius", "map_softness" } },
        { title = "Visibility", fields = { "map_visible", "minimap_visible" } },
        { title = "Player markers", fields = { "map_marker_limit", "map_marker_size", "map_stamps_enabled", "map_stamps_max" } },
        { title = "World map", fields = { "map_max_zoom", "map_pan_speed", "map_show_legend" } },
        { title = "Item tracking", fields = { "map_item_icons", "map_item_rule", "map_item_flag", "map_room_complete_tint" } },
        { title = "Fast travel", fields = { "fast_travel_from", "fast_travel_cost", "fast_travel_fade", "fast_travel_block_boss" } },
    } },
    { title = "Saves and checkpoints", sections = {
        { title = "Save slots", fields = { "save_slots", "save_slot_summary", "save_slot_copy" } },
        { title = "Autosave", fields = { "save_autosave", "save_interval", "save_room_change", "save_pickup" } },
    } },
    { title = "Accessibility", sections = {
        { title = "Player defaults", fields = { "accessibility_text_size", "accessibility_shake", "accessibility_flashes", "accessibility_freeze_frames" } },
        { title = "Options players see", fields = { "accessibility_show_text_size", "accessibility_show_shake", "accessibility_show_flashes",
            "accessibility_show_freeze_frames", "accessibility_show_vibration", "accessibility_show_toggles" } },
        { title = "Assist", fields = { "assist_allowed", "assist_pit_damage", "assist_record_use", "assist_block_achievements" } },
        { title = "Captions", fields = { "captions_default", "caption_background", "captions_player_choice" } },
    } },
    { title = "Languages", sections = {
        { title = "Language choice", fields = { "default_language", "show_language_choice" } },
        { title = "Font", fields = { "ui_font_file", "ui_text_rendering", "ui_glyph_generation" } },
    } },
    { title = "Movement test", sections = {
        { title = "Course", fields = { "test_floor_tiles", "test_step_tiles", "test_gap_tiles" } },
    } },
}

M.deferred = {}

return M
