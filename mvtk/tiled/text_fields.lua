-- Player-visible Tiled text, classified against the authored .tx templates.
-- Paths retain class names for the census; exports flatten their leaf names.
-- ids includes message names, persistence keys and asset references; enums are ids
-- chosen from dropdowns. Never infer translatable text from a field's spelling.
local M = {}
M.templates = {
    ["combat_trial"] = {type="combat_trial", text={"trial_name", "label"}, ids={"trial_id", "art_item", "rewards.trial_reward", "rewards.clear_flag", "access.requires_flag"}, enums={"goal.trial_goal", "limits.disabled_abilities", "limits.disabled_attacks"}},
    ["encounter"] = {type="encounter", text={}, ids={"encounter_id", "start.requires_flag", "rewards.clear_flag", "rewards.clear_message"}, enums={"start.encounter_start", "music.battle_music", "music.victory_music", "rewards.reward_collectible"}},
    ["encounter_spawn"] = {type="encounter_spawn", text={}, ids={}, enums={"enemy.enemy_type", "enemy.archetype", "timing.telegraph_effect"}},
    ["ability_pickup"] = { type="ability", text={"popup.popup_description", "popup.popup_title"}, ids={"art_item", "collectible_id", "world_state.appear_when", "world_state.remove_when"}, enums={"ability_id", "art_feedback.consume_effect", "art_feedback.interact_effect", "world_state.presence_timing"} },
    ["ambience_zone"] = { type="ambience_zone", text={}, ids={"zone_id"}, enums={"ambience_id"} },
    ["music_trigger"] = { type="music_trigger", text={}, ids={"trigger_id"}, enums={"music_id", "transition.exit_music"} },
    ["particle_emitter"] = { type="particle_emitter", text={}, ids={"emitter_id"}, enums={"effect_id"} },
    ["sound_source"] = { type="ambience_zone", text={}, ids={"zone_id"}, enums={"ambience_id"} },
    ["arena_boundary"] = { type="arena_boundary", text={}, ids={"activation.active_phases", "boundary_id", "links.arena_id"}, enums={} },
    ["boss"] = { type="boss", text={"arena_and_ui.bar_name"}, ids={"arena_id", "boss_id", "combat.attack_pattern_ids", "player_hit_feedback.player_hurt_animation", "presentation.defeat_cutscene", "presentation.intro_cutscene", "rewards_and_persistence.defeat_flag", "rewards_and_persistence.reward_drops", "rewards_and_persistence.reward_loot_table", "rewards_and_persistence.reward_unlock_fast_travel", "rewards_and_persistence.reward_unlock_flag", "visuals.visual_component"}, enums={"damage_affinities.status_immune", "damage_affinities.weak_to", "damage_affinities.resist_to", "damage_affinities.immune_to", "damage_affinities.vulnerable_to", "arena_and_ui.health_bar_position", "boss_hit_feedback.boss_hurt_sfx", "boss_type", "movement.ground_motion", "player_hit_feedback.player_hurt_sfx", "presentation.music_track", "presentation.victory_music", "visuals.boss_visual_type", "visuals.intro_animation"} },
    ["boss_add_spawner"] = { type="boss_add_spawner", text={}, ids={"links.arena_id", "links.boss_id", "spawner_id", "spawning.active_phases"}, enums={"enemy_type", "movement_and_attacks.attack_pattern", "movement_and_attacks.attack_pattern2", "movement_and_attacks.movement"} },
    ["boss_arena"] = { type="boss_arena", text={"health_bar.group_name"}, ids={"arena_id", "boss_id"}, enums={"boss_type", "music.battle_music", "music.victory_music"} },
    ["boss_phase"] = { type="boss_phase", text={}, ids={"attack_sequence.attacks", "links.arena_id", "links.boss_id", "phase_id", "transition.transition_teleport_to"}, enums={"attack_sequence.moveset", "boss_type", "movement.behavior", "movement.movement_profile", "movement.teleport_anchors", "transition.transition_animation", "transition.transition_type", "transition_effects.transition_new_music", "transition_effects.transition_spawn_hazards"} },
    ["boss_phase_trigger"] = { type="boss_phase_trigger", text={}, ids={"boss_type", "links.arena_id", "links.boss_id", "outcome.set_flag", "trigger_id", "triggering.requires_flag"}, enums={} },
    ["boss_weak_point"] = { type="boss_weak_point", text={}, ids={"availability.active_phases", "availability.requires_flag", "boss_id", "boss_type", "outcome.destroy_flag", "point_id"}, enums={} },
    ["chest"] = { type="chest", text={}, ids={"art_item", "chest_id", "rewards.contents", "world_state.appear_when", "world_state.remove_when"}, enums={"access.requires_key", "art_feedback.consume_effect", "art_feedback.interact_effect", "chest_type", "world_state.presence_timing"} },
    ["collectible"] = { type="collectible", text={}, ids={"art_item", "collectible_id", "persistence.set_flag_on_collect", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "collectible_type", "world_state.presence_timing"} },
    ["key"] = { type="collectible", text={}, ids={"art_item", "collectible_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "collectible_type", "key_id", "world_state.presence_timing"} },
    ["lore_item"] = { type="lore_item", text={"content.text", "content.title", "interaction.prompt_text"}, ids={"art_item", "conditions_and_persistence.requires_flag", "conditions_and_persistence.unlock_flag", "lore_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "category", "feedback_and_visuals.sound_id", "world_state.presence_timing"} },
    ["map_fragment"] = { type="collectible", text={"reveal.area_name"}, ids={"area_id", "art_item", "collectible_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "collectible_type", "world_state.presence_timing"} },
    ["enemy"] = { type="enemy", text={"rank.champion_name"}, ids={"rank.champion_reward", "special_movement.ambush_trigger_id", "on_defeat.defeat_flag", "on_defeat.species", "movement_and_attacks.patrol_route", "rewards.drops", "rewards.loot_table", "stats.faction", "stats.group_id"}, enums={"tuning.projectile_deflect", "rank.champion_music", "rank.champion_enrage_pattern", "death_effects.death_behavior", "death_effects.split_type", "death_effects.split_archetype", "death_effects.death_hazard_type", "special_movement.cling_side", "special_movement.ambush_style", "defense.guard", "defense.guard_break", "defense.armor_requires", "stats.ledge_behavior", "stats.required_action", "summon.summon_enemy_type", "summon.summon_archetype", "on_defeat.respawn", "movement_and_attacks.aim_mount", "elements.status_immune", "elements.status_on_hit", "elements.weak_to", "elements.resist_to", "elements.immune_to", "elements.vulnerable_to", "elements.damage_type", "archetype", "enemy_type", "movement_and_attacks.attack_pattern", "movement_and_attacks.attack_pattern2", "movement_and_attacks.movement", "stats.difficulty"} },
    ["air_pocket"] = { type="air_pocket", text={}, ids={"air_pocket_id"}, enums={} },
    ["breakable_prop"] = { type="breakable_prop", text={"feedback.label"}, ids={"art_item", "prop_id", "rewards.set_flag", "target_id", "tiles.painted_layer"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "durability.required_ability", "feedback.sound_break", "rewards.drop_collectible"} },
    ["camera_zone"] = { type="camera_zone", text={}, ids={"framing.parallax_override", "zone_id"}, enums={"camera_mode"} },
    ["hazard"] = { type="hazard", text={}, ids={"arena.active_phases", "arena.arena_id", "arena.boss_id", "hazard_id", "level.level_art_layer", "motion.retract_visual_layer"}, enums={"status.status_effect", "elements.damage_type", "activation_and_feedback.sound_on_hit", "damage_and_knockback.on_contact", "damage_and_knockback.required_resistance", "hazard_type", "level.level_mode", "level.rise_start", "motion.pattern", "path_motion.motion_loop", "path_motion.motion_type"} },
    ["light_source"] = { type="light_source", text={}, ids={"light_id", "world_state.appear_when", "world_state.remove_when"}, enums={"world_state.presence_timing"} },
    ["locked_door"] = { type="locked_door", text={}, ids={"door_id", "feedback.unlock_message", "world_state.appear_when", "world_state.remove_when"}, enums={"feedback.sound_locked", "feedback.sound_unlock", "locking.require_ability", "locking.require_item", "locking.require_key", "world_state.presence_timing"} },
    ["map_marker"] = { type="map_marker", text={"presentation.marker_label"}, ids={"marker_id", "presentation.marker_icon", "world_state.appear_when", "world_state.remove_when"}, enums={"marker_type", "world_state.presence_timing"} },
    ["movement_zone"] = { type="movement_zone", text={}, ids={"movement_zone_id"}, enums={"preset"} },
    ["one_way_platform"] = { type="one_way_platform", text={}, ids={}, enums={"direction"} },
    ["pendulum_hazard"] = { type="pendulum_hazard", text={}, ids={"pendulum_id"}, enums={"damage_and_knockback.damage_type", "damage_and_knockback.on_contact"} },
    ["screen_effect_zone"] = { type="screen_effect_zone", text={}, ids={"effect.tint_color", "lifecycle.exit_tint", "zone_id"}, enums={"effect_type"} },
    ["secret"] = { type="secret", text={"feedback.notification_text"}, ids={"art_item", "secret_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "discovery.required_ability", "discovery.reveals_on", "reward.reward_type", "secret_type"} },
    ["timed_door"] = { type="timed_door", text={}, ids={"art_item", "door_id", "feedback.message_off", "feedback.message_on"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_close", "feedback.sound_open"} },
    ["water_volume"] = { type="water_volume", text={}, ids={"level.level_art_layer", "presentation.tint_color", "water_id"}, enums={"level.level_mode", "level.rise_start", "swimming_and_current.current_direction", "water_type"} },
    ["breakable_wall"] = { type="breakable_wall", text={}, ids={"art_item", "rewards_and_secrets.reveals_secret", "tile_swap.broken_wall_layer", "tile_swap.wall_layer", "wall_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "durability.break_from", "durability.required_damage_type", "feedback.particle_effect_name", "feedback.sound_break", "required_ability", "rewards_and_secrets.drop_collectible", "wall_type", "world_state.presence_timing"} },
    ["cutscene"] = { type="cutscene", text={}, ids={"conditions_and_outcomes.requires_flag", "conditions_and_outcomes.set_flag", "conditions_and_outcomes.skip_if_flag", "content.cutscene_dialogue_id", "content.video_id", "cutscene_id", "lifecycle.once_flag", "trigger_id"}, enums={} },
    ["countdown_zone"] = { type="countdown_zone", text={}, ids={}, enums={"countdown_id", "role"} },
    ["quest_trigger"] = { type="quest_trigger", text={}, ids={"quest_id", "trigger_id", "quest.step_id", "lifecycle.once_flag", "conditions_and_outcomes.requires_quest", "conditions_and_outcomes.requires_flag", "conditions_and_outcomes.skip_if_flag", "conditions_and_outcomes.set_flag"}, enums={"quest.action", "conditions_and_outcomes.requires_quest_state"} },
    ["dialogue_trigger"] = { type="dialogue_trigger", text={}, ids={"conditions_and_outcomes.requires_flag", "conditions_and_outcomes.set_flag", "conditions_and_outcomes.skip_if_flag", "dialogue_id", "lifecycle.once_flag", "npc_id", "trigger_id", "world_state.appear_when", "world_state.remove_when"}, enums={"world_state.presence_timing"} },
    ["energy_station"] = { type="energy_station", text={"prompt_text"}, ids={"art_item", "station_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_id", "resource_type"} },
    ["gate"] = { type="gate", text={"messaging.open_message"}, ids={"art_item", "gate_id", "sequence.sequence_order", "stages.stage_flags", "state_and_persistence.group_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "gate_type", "requirements.required_abilities", "requirements.required_ability", "requirements.required_action", "requirements.required_item", "requirements.required_key", "requirements.requirement_logic", "world_state.presence_timing"} },
    ["health_station"] = { type="health_station", text={"prompt_text"}, ids={"art_item", "availability.requires_flag", "station_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_id"} },
    ["hint_stone"] = { type="hint_stone", text={"body", "interaction.label", "title"}, ids={"art_item", "conditions_and_persistence.requires_flag", "conditions_and_persistence.set_flag", "hint_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "display.position", "feedback.sound_id", "world_state.presence_timing"} },
    ["lever"] = { type="lever", text={"interaction.label_off", "interaction.label_on"}, ids={"art_item", "conditions_and_flags.requires_flag", "conditions_and_flags.set_flag_off", "conditions_and_flags.set_flag_on", "feedback.off_animation", "feedback.on_animation", "lever_id", "messages.call_landing", "messages.message_off", "messages.message_on", "target_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_off", "feedback.sound_on"} },
    ["map_station"] = { type="map_station", text={"prompt_text"}, ids={"art_item", "station_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_id", "reveal_area"} },
    ["npc"] = { type="npc", text={"behavior.barks", "dialogue.dialogue_text", "npc_name"}, ids={"art_item", "dialogue.dialogue_id", "lifecycle.despawn_flag", "npc_id", "vendor.vendor_flag", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "npc_type", "vendor.vendor_shop", "vendor.vendor_greeting", "world_state.presence_timing"} },
    ["pressure_plate"] = { type="pressure_plate", text={}, ids={"art_item", "plate_id", "response.message_off", "response.message_on", "response.set_flag", "target_id", "tile_animation.anim_layer", "tile_animation.anim_tilemap"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_off", "feedback.sound_on"} },
    ["sign"] = { type="sign", text={"interaction.label", "text", "title"}, ids={"art_item", "conditions_and_persistence.requires_flag", "conditions_and_persistence.set_flag", "content_link.dialogue_id", "sign_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_id", "presentation.display_mode", "world_state.presence_timing"} },
    ["upgrade_station"] = { type="upgrade_station", text={"access.locked_text", "presentation.prompt_text", "presentation.menu_title"}, ids={"access.requires_flag", "art_item"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "upgrade_catalog"} },
    ["bank"] = { type="bank", text={"access.locked_text", "presentation.prompt_text", "presentation.menu_title"}, ids={"access.requires_flag", "art_item", "bank_id"}, enums={"access.bank_mode", "art_feedback.consume_effect", "art_feedback.interact_effect"} },
    ["offering_altar"] = { type="offering_altar", text={"lifecycle.locked_text", "payout.reward_text", "presentation.prompt_text", "presentation.menu_title"}, ids={"altar_id", "art_item", "lifecycle.requires_flag", "lifecycle.set_flag", "offer.cost_item", "payout.reward"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect"} },
    ["skill_trainer"] = { type="skill_trainer", text={"access.locked_text", "presentation.prompt_text", "presentation.menu_title"}, ids={"access.requires_flag", "art_item"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "trainer_catalog"} },
    ["shop"] = { type="shop", text={"presentation.prompt_text", "presentation.menu_title", "access.locked_text"}, ids={"art_item", "access.requires_flag"}, enums={"shop_id", "art_feedback.consume_effect", "art_feedback.interact_effect"} },
    ["socket"] = { type="socket", text={}, ids={"acceptance.accepts_id", "response.message_off", "response.message_on", "response.persist_key", "response.set_flag_on", "socket_id", "target_id"}, enums={"acceptance.accepts"} },
    ["strike_switch"] = { type="strike_switch", text={}, ids={"art_item", "conditions.requires_flag", "conditions.set_flag_off", "conditions.set_flag_on", "messages.call_landing", "messages.message_off", "messages.message_on", "switch_id", "target_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "behavior.accepts", "behavior.mode", "feedback.sound_off", "feedback.sound_on", "feedback.sound_reject", "feedback.tick_sound"} },
    ["torch"] = { type="torch_holder", text={"feedback.label", "feedback.label_lit"}, ids={"ignition.set_flag", "torch_id", "world_state.appear_when", "world_state.remove_when"}, enums={"feedback.sound_off", "feedback.sound_on", "world_state.presence_timing"} },
    ["warp_statue"] = { type="warp_statue", text={"feedback.toast_blocked", "feedback.toast_cost", "feedback.toast_fail", "feedback.toast_success", "label"}, ids={"access.requires_flag", "art_item", "feedback.set_flag", "statue_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback.sound_fail", "feedback.sound_warp"} },
    ["end_game"] = { type="end_game", text={}, ids={"ending.completion_id", "progression_area"}, enums={} },
    ["bounce_pad"] = { type="bounce_pad", text={"feedback_and_visuals.label"}, ids={}, enums={"feedback_and_visuals.sound_id"} },
    ["checkpoint"] = { type="checkpoint", text={}, ids={"activation.requires_flag", "activation.set_flag", "art_item", "checkpoint_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback_and_visuals.sound_id"} },
    ["conveyor"] = { type="conveyor", text={}, ids={"conveyor_id"}, enums={"direction"} },
    ["crumble_platform"] = { type="crumble_platform", text={}, ids={"platform_id", "tile_visuals.visual_layer"}, enums={"feedback.sound_crumble", "feedback.sound_respawn"} },
    ["elevator"] = { type="elevator", text={}, ids={"activation.trigger_id", "elevator_id", "start_node_id", "visuals.source_layer"}, enums={"activation.activation_mode", "activation.destination_mode", "route_axis"} },
    ["elevator_node"] = { type="elevator_node", text={"landing_label"}, ids={"elevator_id", "node_id"}, enums={"node_kind", "stop"} },
    ["fast_travel"] = { type="fast_travel", text={"presentation.label_locked", "presentation.label_unlocked", "presentation.station_description", "station_name"}, ids={"art_item", "station_id"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "presentation.sound_id"} },
    ["grapple_point"] = { type="grapple_point", text={}, ids={}, enums={} },
    ["grapple_surface"] = { type="grapple_surface", text={}, ids={}, enums={} },
    ["hazard_return_zone"] = { type="hazard_return_zone", text={}, ids={"return_zone_id"}, enums={} },
    ["ice_floor"] = { type="ice_floor", text={}, ids={"ice_id", "preset"}, enums={} },
    ["ladder"] = { type="ladder", text={}, ids={"ladder_id"}, enums={"ladder_type"} },
    ["launch_cannon"] = { type="launch_cannon", text={}, ids={"cannon_id"}, enums={"aim.aim_mode", "fire.breaks_action", "fire.fire_on", "sound_id"} },
    ["moving_platform"] = { type="platform", text={}, ids={"activation.trigger_id", "path.path_name", "platform_id", "progression.progression_from", "progression.progression_to", "vehicle.vehicle_alt_path", "vehicle.vehicle_switch_id"}, enums={"path.loop_mode", "platform_type", "vehicle.vehicle_control", "vehicle.vehicle_end"} },
    ["player_start"] = { type="spawn_point", text={}, ids={"checkpoint_id", "spawn_type"}, enums={} },
    ["save_point"] = { type="save_point", text={"display_name"}, ids={"art_item", "save_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "feedback_and_visuals.sound_id", "world_state.presence_timing"} },
    ["teleporter"] = { type="teleporter", text={"presentation.label"}, ids={"access.requires_flag", "art_item", "pair_id", "target_id", "teleporter_id", "world_state.appear_when", "world_state.remove_when"}, enums={"art_feedback.consume_effect", "art_feedback.interact_effect", "presentation.active_effect_id", "presentation.unlock_effect_id", "world_state.presence_timing"} },
    ["wall_jump_surface"] = { type="wall_jump_surface", text={}, ids={"surface_id"}, enums={"abilities.require_ability", "surface_type"} },
    ["wind_current"] = { type="wind_current", text={}, ids={"current_id"}, enums={"direction", "force.wind_mode"} },
    ["zip_line"] = { type="zip_line", text={"prompt.label"}, ids={"progression_from", "progression_to", "zip_id"}, enums={} },
    ["carryable"] = { type="carryable", text={"label"}, ids={"carry_id"}, enums={"kind"} },
    ["grapple_box"] = { type="grapple_box", text={}, ids={}, enums={} },
    ["grapple_slope"] = { type="grapple_slope", text={}, ids={}, enums={} },
    ["pushable_block"] = { type="pushable_block", text={}, ids={"block_id"}, enums={} },
    ["solid_box"] = { type="collision_box", text={}, ids={}, enums={} },
    ["solid_slope"] = { type="collision_slope", text={}, ids={}, enums={} },
}

-- Displayed Tiled map properties (Map Properties, not object fields): the
-- landmark title on area title cards and the pause line.
M.map_properties = { "room_title" }

-- Built-in object names are displayed only by these three families.
M.object_names = { boss=true, fast_travel=true, map_marker=true }
local by_type = {}
for _, row in pairs(M.templates) do
    local fields = by_type[row.type] or {}
    by_type[row.type] = fields
    for _, path in ipairs(row.text) do fields[path:match("([^.]+)$")] = true end
end

-- Runtime aliases as well as .tx basenames are accepted; shared template types
-- intentionally share their displayed-field union (collectible/map_fragment).
function M.fields(kind)
    local row = M.templates[kind]
    return by_type[row and row.type or kind] or {}
end

-- A new .tx string is unclassified until explicitly added to one of these lists.
function M.classify(template, path)
    local row = M.templates[template]
    if not row then return nil end
    if path == "mvtk_template_version" then return "version" end
    for _, category in ipairs({"text", "ids", "enums"}) do
        for _, field in ipairs(row[category]) do
            if field == path then return category == "ids" and "id" or category == "enums" and "enum" or "text" end
        end
    end
    return nil
end
return M
