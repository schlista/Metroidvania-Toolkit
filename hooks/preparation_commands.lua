-- Editor-only preparation coordinator. Caller supplies existing generation stages.
local M={}
-- Editor commands yield during dialogs, writes and resource reloads. Another
-- menu invocation can enter meanwhile; it must not reset shared staging or
-- profiler state. Keep the guard shared by coordinators for the same project.
local active_runs={}
local activity_windows={}
function M.new(deps)
local P={}
local ROOT,HEADLESS,editor_api=deps.root,deps.headless,deps.editor
local run_key=tostring(ROOT):gsub("\\","/"):gsub("/$","")
if run_key:match("^%a:") then run_key=run_key:lower() end
local list_dir_filesystem,info,join=deps.list, deps.info, deps.join
local write_if_changed,show_editor_status_dialog=deps.write,deps.dialog
local import_assets,safe_generate,run_validate_all=deps.import, deps.generate, deps.validate
local Preparation=require "developer.tools.preparation"
local World=require "developer.tools.world_layout"
local Stats=require "hooks.core.io_stats"
local profiler=deps.profiler
local profiling=false
local dialog_wait=0
local stage_metrics={}
local outcome
local activity_report
local raw_dialog=show_editor_status_dialog
local function set_active_stage(stage)
    if active_runs[run_key] then active_runs[run_key].stage=stage end
    if activity_report then activity_report(stage) end
end
local function report_failure(message)
    if activity_report then
        activity_report("Preparation failed: " .. tostring(require("hooks.core.error_text").strip(message)), false)
    end
end
local function run_exclusive(label,fn,...)
    local active=active_runs[run_key]
    if active then
        return false,active.label.." is already running: "..active.stage
            ..". Continue or Cancel its existing dialog, or wait for the current stage to finish."
    end
    active_runs[run_key]={label=label,stage="Checking editor scripts and Tiled exports"}
    local ok,result,err=pcall(function(...)
        info("[PREPARE] Starting "..label.."; checking editor scripts and Tiled exports...")
        return fn(...)
    end,...)
    active_runs[run_key]=nil
    if not ok then require("hooks.core.error_text").reraise(result) end
    return result,err
end
show_editor_status_dialog=function(...)
    local started=os.clock()
    local result=raw_dialog(...)
    if profiling then local elapsed=os.clock()-started; dialog_wait=dialog_wait+elapsed; profiler.exclude_wait(elapsed) end
    return result
end
local function profile_lines()
    local lines=Stats.lines();local s=Preparation.stats()
    for _,line in ipairs(stage_metrics) do lines[#lines+1]=line end
    lines[#lines+1]=string.format("[PERF] snapshots: %d full, %d partial, %d build extensions; %d files / %d bytes; %d ms",s.snapshots,s.partial_snapshots,s.build_snapshots,s.files,s.bytes,math.floor(s.seconds*1000+.5))
    for _,call in ipairs(s.calls) do lines[#lines+1]=string.format("[PERF] snapshot %s: %d files / %d bytes / %d ms",call.caller,call.files,call.bytes,math.floor(call.seconds*1000+.5)) end
    lines[#lines+1]=string.format("[PERF] excluded dialog wait: %d ms",math.floor(dialog_wait*1000+.5))
    return lines
end
local function preparation_opts() return {root=ROOT,list_dir_filesystem=list_dir_filesystem,write=write_if_changed} end
local hook_paths={"hooks.editor_script","hooks/editor_core.lua","hooks/editor_generators.lua","hooks/editor_commands.lua","hooks/preparation_commands.lua","hooks/preparation_activity.lua",
    "hooks/core/room_collision.lua",
    "hooks/core/bakes/wind_current_bake.lua","hooks/core/bakes/ice_floor_bake.lua","hooks/core/bakes/pendulum_bake.lua","hooks/core/bakes/warp_statue_bake.lua",
     "hooks/core/bakes/trade_station_bake.lua","hooks/core/bakes/quest_trigger_bake.lua","hooks/core/bakes/countdown_zone_bake.lua","hooks/core/bakes/combat_trial_bake.lua",
    "hooks/core/bakes/hazard_bake.lua","hooks/core/bakes/water_volume_bake.lua","hooks/core/bakes/air_pocket_bake.lua","hooks/core/bakes/launch_cannon_bake.lua","hooks/core/bakes/movement_zone_bake.lua","hooks/core/bakes/carryable_bake.lua","hooks/core/bakes/socket_bake.lua","hooks/core/platform_resources.lua","hooks/core/elevator_resources.lua","hooks/core/elevator_manifest.lua","hooks/core/elevator_config.lua","mvtk/elevators/elevator_contract.lua","mvtk/elevators/layout_resolver.lua","hooks/core/bakes/breakable_prop_bake.lua","hooks/editor_script.lua","hooks/core/bakes/zip_line_bake.lua","hooks/core/path_points.lua","hooks/core/ice_layer_bake.lua","hooks/core/presence_bake.lua","hooks/core/grapple_layer_bake.lua","hooks/core/bake_audit.lua","hooks/core/bakes/strike_switch_bake.lua","hooks/core/feature_bakes.lua","hooks/core/bakes/encounter_bake.lua","mvtk/tiled/encounter_links.lua","hooks/core/bake_kit.lua","hooks/core/bakes/grapple_point_bake.lua","hooks/core/bakes/boss_add_spawner_bake.lua","hooks/core/bakes/cutscene_trigger_bake.lua","hooks/core/bakes/hazard_return_zone_bake.lua",
    "hooks/steam_addon.lua","mvtk/editor/steam_addon.lua","mvtk/editor/steamworks_files.lua","mvtk/platform/rich_presence_tokens.lua","mvtk/platform/steam_languages.lua","mvtk/editor/addon_dependency.lua","mvtk/editor/proto_emit.lua","mvtk/tiled/tiled_carriers.lua","mvtk/tiled/text_fields.lua","mvtk/dialogue/dialogue_registry.lua","mvtk/dialogue/dialogue_sources.lua","mvtk/game/loot_tables_source.lua","mvtk/editor/loot_document.lua","mvtk/editor/loot_editor_window.lua","mvtk/editor/dialogue_document.lua","mvtk/editor/dialogue_editor_window.lua","developer/tools/localization_collect.lua","mvtk/tiled/property_groups.lua","mvtk/tiled/catalog_enums.lua","mvtk/tiled/enum_usage.lua","mvtk/editor/fresh_config.lua","mvtk/collectibles/generated_types.lua","mvtk/core/creator_settings_model.lua","developer/config/new_game_plus.lua","developer/config/extras.lua","developer/config/run_stats.lua","developer/config/leveling.lua","developer/config/bestiary.lua","developer/config/achievements.lua","mvtk/core/game_events.lua","mvtk/game/progression/achievement_rules.lua","mvtk/game/quests/quest_rules.lua","developer/config/quests.lua","mvtk/game/goal_rules.lua","developer/config/goals.lua","mvtk/game/countdown_rules.lua","developer/config/countdowns.lua","developer/config/npc_settings.lua","hooks/core/npc_behavior_bake.lua","developer/config/random_drops.lua","developer/config/powerups.lua","developer/config/weapons.lua","developer/config/charms.lua","developer/config/crafting.lua","mvtk/ui/time_text.lua","mvtk/core/config_schemas.lua","developer/config/ui_text.lua","developer/config/encounter_settings.lua","developer/config/combat_music.lua","mvtk/editor/ttf_cmap.lua","mvtk/editor/ui_font.lua","mvtk/editor/ui_font_manifest.lua","mvtk/editor/ui_font_resources.lua","mvtk/ui/generated_text.lua","mvtk/editor/translation_tsv.lua","mvtk/editor/translation_project.lua","mvtk/editor/translations_window.lua","mvtk/editor/game_settings_window.lua","mvtk/editor/game_settings_context.lua","mvtk/editor/creator_settings_writer.lua","developer/tools/game_settings_layout.lua","developer/tools/designer_fields.lua","mvtk/core/input_binding_rules.lua","mvtk/rooms/input_actions.lua","mvtk/ui/input_prompts.lua","mvtk/ui/input_prompt_labels.lua","mvtk/editor/room_catalogs.lua","mvtk/editor/room_catalogs/cutscenes.lua","mvtk/game/cutscene_ids.lua","mvtk/game/cutscene_policy.lua","mvtk/game/video_variants.lua","mvtk/editor/room_catalogs/world_census.lua","developer/tools/world_census.lua","mvtk/enemies/enemy_species.lua","mvtk/enemies/enemy_skin_sync.lua","mvtk/enemies/enemy_type_overlay.lua","mvtk/enemies/enemy_respawn_policy.lua","mvtk/enemies/enemy_overrides.lua","mvtk/enemies/enemy_defense.lua","mvtk/enemies/enemy_behavior_resolver.lua","hooks/core/catalog_sync.lua","mvtk/editor/export_packager.lua","mvtk/editor/export_manifest.lua","mvtk/editor/export_workspace.lua","hooks/export_workspace.ps1","developer/config/map_icons.lua",
    "mvtk/editor/shared_atlas.lua","mvtk/editor/asset_scanner.lua","mvtk/combat/multipliers.lua",
    "mvtk/combat/multiplier_sources.lua","mvtk/player/player_stats.lua","mvtk/player/stat_keys.lua",
    "mvtk/bosses/patterns/attack_patterns.lua",
    "hooks/core/validation.lua","hooks/core/tiled_objects.lua","mvtk/editor/background_atlas.lua","mvtk/core/adler32.lua","mvtk/editor/object_art.lua","mvtk/editor/prefab_generators.lua","mvtk/editor/resource_text.lua","mvtk/editor/file_utils.lua","mvtk/editor/tilesheet_sync.lua","mvtk/editor/tilemap_regen.lua","mvtk/editor/player_scale_writer.lua","mvtk/editor/player_resource_patch.lua","mvtk/player/collider_geometry.lua","mvtk/player/player_scale.lua","mvtk/world/wall_surfaces.lua","mvtk/world/switch_state.lua","mvtk/editor/tile_settings_writer.lua","mvtk/editor/project_transaction.lua","hooks/core/io_stats.lua","hooks/core/write_bundle.lua","hooks/core/go_generation.lua","hooks/core/parallax_bake.lua","hooks/core/tilemap_split.lua","hooks/core/state_layer_bake.lua","developer/tools/parallax_coverage.lua","mvtk/camera/camera_zones.lua","hooks/core/tilesource.lua","hooks/enemy_art_sync.lua","developer/tools/relationship_project.lua","developer/tools/content_relationships.lua","developer/tools/object_references.lua","developer/tools/flag_ledger.lua","mvtk/bosses/boss_identity.lua","developer/tools/progression_rules.lua","developer/tools/progression_search.lua","developer/tools/progression_closure.lua","developer/tools/progression_routes.lua","mvtk/world/gates/requirements.lua","mvtk/world/presence_condition.lua","mvtk/abilities/ability_tags.lua","mvtk/world/breakable_rules.lua","mvtk/world/hazard_immunity.lua","developer/tools/progression_graph.lua","mvtk/game/grant_spec.lua","developer/tools/content_checks.lua","developer/tools/pickup_art_checks.lua","mvtk/world/chest_contents.lua","mvtk/collectibles/reward_drops.lua","mvtk/enemies/loot_table_drops.lua","mvtk/game/trial_limits.lua","developer/tools/economy_checks.lua","mvtk/economy/selling.lua","mvtk/economy/vendor.lua","mvtk/hazards/hazard_contact.lua","mvtk/hazards/pendulum_geometry.lua","mvtk/world/kinematic_path.lua","mvtk/world/path_vehicle.lua","developer/tools/progression_project.lua","developer/tools/dev_helpers.lua","developer/tools/regenerate_minimap.lua","tools/validate_tiled_export.lua","hooks/core/filesystem.lua","developer/tools/preparation.lua","developer/tools/world_layout.lua","developer/tools/world_provenance.lua","developer/tools/world_manifest.lua","mvtk/tiled/world_properties.lua","developer/tools/imported_inputs.lua",
    "developer/tools/layout_publication.lua","developer/tools/layout_minimap.lua","developer/tools/layout_geometry.lua","developer/tools/completion_authoring.lua","developer/tools/goal_authoring.lua","developer/tools/world_pacing.lua","mvtk/game/endings.lua","developer/config/completion_tracking.lua","mvtk/map/layout_vectors.lua",
    "mvtk/editor/room_outline.lua","mvtk/editor/room_doors.lua","mvtk/editor/locked_door_reader.lua","hooks/toolkit_setup.lua",
    -- Editor-loaded through the spawner-service check or Prepare & Check; listed so an
    -- edit triggers the restart guard (AUDIT_EDITOR_SANDBOX.md, Freshness lists).
    "mvtk/ui/notices.lua","mvtk/ui/hud_bus.lua","mvtk/ui/menu_text.lua","mvtk/game/delivery.lua",
    "mvtk/game/progression/level_curve.lua","mvtk/render/view_policy.lua","mvtk/enemies/enemy_spawn_service.lua",
    "developer/tools/collection_fingerprint.lua","mvtk/editor/spine_addon.lua","mvtk/tiled/template_versions.lua","mvtk/tiled/template_presets.lua","mvtk/tiled/template_index.lua","developer/tools/template_preset_checks.lua",
    "hooks/core/error_text.lua","mvtk/core/fixed_decimal.lua",
    "developer/tools/world_budget.lua","developer/config/performance_budgets.lua","developer/config/stream_settings.lua","developer/tools/engine_limits.lua","developer/tools/generated_census.lua",
    "mvtk/editor/extras_gallery.lua","hooks/core/generated_sweep.lua","mvtk/editor/shared_proto.lua"}
local hook_revision=Preparation.snapshot({root=ROOT,paths=hook_paths})
local function require_current_hooks()
    local current=Preparation.snapshot({root=ROOT,paths=hook_paths})
    assert(#Preparation.diff(hook_revision,current)==0,"Editor scripts changed. Restart Defold to clear cached Lua modules, then Project > Reload Editor Scripts before preparing.")
end
local function show_preparation_status(base,complete_activity,stage_count,catalog_result,translations)
    local opts=preparation_opts(); local report=Preparation.status(opts,base)
    report.translations=translations or (Preparation.load(opts,"assets/tiled/preparation_run.lua") or {}).translations
    Preparation.write_report(opts,"assets/tiled/preparation_status.lua",report)
    write_if_changed(join(ROOT,"developer/assets/tiled/preparation_status.json"),require("developer.tools.relationship_project").json(report))
    local lines={Preparation.status_label(report.status),report.next_action,"Prepare & Check publishes Tiled world placement; Layout Export publishes manual placement. Export Game packages that publication."}
    local catalog_line=require("hooks.core.catalog_sync").summary(catalog_result)
    if catalog_line then lines[#lines+1]=catalog_line end
    for _,line in ipairs(report.translations and report.translations.lines or {}) do lines[#lines+1]=line end
    for _,line in ipairs(report.world_budget and report.world_budget.lines or {}) do lines[#lines+1]=line end
    for i,p in ipairs(report.affected) do if i<=8 then lines[#lines+1]=p end end
    for i,d in ipairs(report.diagnostics) do if i<=6 then lines[#lines+1]=d.path..": "..d.message end end
    lines[#lines+1]="Full affected-file list: developer/assets/tiled/preparation_status.json"
    if complete_activity and activity_report then
        -- Deliver completion while the result is known and saved. The progress
        -- window is also the result window, so Close does not depend on a second
        -- modal dialog or on the profiling callback finishing its disk writes.
        activity_report(string.format("Preparation complete. Completed %d of %d stages.\n",stage_count,stage_count)..table.concat(lines,"\n"),false)
    else
        -- G8-04b: offer Apply Recommended Engine Limits when the last world
        -- budget report predicts an overflow that game.project still has.
        -- The handler (deps.apply_limits) guards, saves and refreshes itself,
        -- because this read-only command skips the menu wrapper.
        local overflows=report.world_budget and report.world_budget.overflows
        local offer=not HEADLESS and deps.apply_limits and editor_api and editor_api.ui and type(overflows)=="table" and #overflows>0
            and #require("developer.tools.engine_limits").recommend(overflows,(deps.read or require("mvtk.editor.project_transaction").read)(ROOT.."/game.project"))>0
        if offer then
            lines[#lines+1]="Some engine limits in game.project are below the last world budget report. Apply Recommended Engine Limits shows the changes before saving."
            local answer=show_editor_status_dialog("Project Preparation",lines,{extra_buttons={
                editor_api.ui.dialog_button({text="Apply Recommended Engine Limits",result="apply_limits"})}})
            if answer=="apply_limits" then deps.apply_limits(overflows) end
        else
            show_editor_status_dialog("Project Preparation",lines)
        end
    end
    return report
end
local function choose_world(force)
    local opts=preparation_opts();local pending,signature=World.pending_export(opts)
    local owner=World.source(opts)
    if not pending then assert(not force,"Export All Maps and Tiled World in Tiled first");return owner end
    local active=World.manifest(opts)
    if not force and active and active.source==pending.source then return owner end
    if not force and owner.seen_export==signature then return owner end
    if HEADLESS then
        assert(not force,"Headless source changes require World.select(opts,true)")
        return owner
    end
    local lines={pending.source,string.format("%d rooms; starting room: %s",#pending.maps,pending.start_room),
        "Use Tiled World Layout replaces published placement on the next successful preparation. The manual draft is preserved.",
        owner.owner=="tiled" and "Keep Current World preserves the currently selected Tiled world." or "Keep Layout Editor Layout leaves manual placement in control."}
    local previous=Preparation.load(opts,"runtime/layout/world_layout.local.lua") or {rooms={}}
    local by_id={};for _,r in ipairs(previous.rooms or {}) do by_id[r.id]=r end
    local moved,added,removed=0,0,0
    for _,r in ipairs(pending.maps) do local old=by_id[r.id]
        if not old then added=added+1 elseif old.x~=r.x+pending.tile_width or old.y~=-r.y-r.height+pending.tile_height then moved=moved+1 end
        by_id[r.id]=nil
    end
    for _ in pairs(by_id) do removed=removed+1 end
    lines[#lines+1]=string.format("Placement changes: %d moved, %d added, %d removed. Tags on removed rooms stay in the previous publication/backup.",moved,added,removed)
    local answer=show_editor_status_dialog("Tiled World Placement",lines,{cancel_text="Cancel",extra_buttons={
        editor_api.ui.dialog_button({text="Use Tiled World Layout",result="tiled"}),
        editor_api.ui.dialog_button({text=owner.owner=="tiled" and "Keep Current World" or "Keep Layout Editor Layout",result="manual"})}})
    assert(answer=="tiled" or answer=="manual","World selection canceled; published layout preserved")
    if answer=="tiled" then
        local selection,manifest=World.selection(opts)
        return selection,manifest,selection
    end
    return World.select(opts,false)
end
local function publish_world()
    require_current_hooks()
    local opts=preparation_opts();assert(World.source(opts).owner=="tiled","Choose Use Tiled World Layout first")
    local candidate=World.candidate(opts)
    for _,message in ipairs(candidate.diagnostics or {}) do info("[WORLD] "..message) end
    assert(run_validate_all({skip_tests=true,layout=candidate.layout,map_files=candidate.map_files,world_manifest=candidate.manifest})~=false,"Validation failed")
    World.publish(opts,candidate)
    return true
end
local function prepare_and_check(selected_owner,selected_world,selection)
    require_current_hooks()
    local opts=preparation_opts()
    if not selected_owner then selected_owner,selected_world,selection=choose_world(false) end
    opts.selection=selection
    local world=selected_world or World.manifest(opts)
    opts.world_manifest=world
    if world then
        -- Step 1 checks the selected world's provenance and all imported room
        -- inputs together. Do not read the same world again before that step.
        assert(world.version==1 and type(world.maps)=="table" and #world.maps>0,"Invalid/empty Tiled world manifest")
        opts.map_files={};for _,map in ipairs(world.maps) do opts.map_files[#opts.map_files+1]=map.id..".lua" end
    end
    -- A new game gets its permanent save ID here, before the snapshot, so the
    -- prepared and published revisions already include it and Export Game
    -- never waits for a Game Settings Save.
    local id_file,game_id=require("developer.tools.project_identity").assign_missing(ROOT,
        {read=deps.read or require("mvtk.editor.project_transaction").read,new_id=deps.new_game_id})
    if id_file then
        write_if_changed(join(ROOT,id_file.path),id_file.content)
        info("[PREPARE] Gave this game its permanent save ID "..game_id.." in "..id_file.path)
    end
    local candidate
    local tilemaps_regenerated=false
    local current=Preparation.load(opts,Preparation.prepared)
    set_active_stage("Scanning project files for changes...")
    if not deps.ui_font then
        for _,path in ipairs(require("mvtk.editor.ui_font").prepare(opts)) do info("[FONT] Updated "..path) end
    end
    local snapshot=Preparation.preparation_snapshot(opts)
    require("hooks.core.filesystem").begin_tilemap_staging()
    local changed=not current or #Preparation.diff(current.inputs,snapshot)>0
    local _,map_files=list_dir_filesystem(join(ROOT,"developer/assets/tiled/maps"))
    local has_rooms=false
    for _,name in ipairs(map_files or {}) do if name:match("%.lua$") then has_rooms=true; break end end
    local catalog_result,translation_result
    local stages={{name="Check Tiled exports",run=function()
        if deps.catalogs then
            local err
            catalog_result,err=deps.catalogs()
            if not catalog_result then error(err or "Catalog sync failed",0) end
        end
        Preparation.require_exports(opts)
        -- Generated chest lookups are rebuilt by the Create Rooms stage below.
        -- Validate All still requires them before publication.
        require("developer.tools.relationship_project").require_valid({root=ROOT,list_dir_filesystem=list_dir_filesystem,files=opts.map_files,check_generated=false})
    end}}
    local skipped={}
    if changed and has_rooms and (not current or Preparation.import_changed(current.inputs,snapshot)) then
        stages[#stages+1]={id="import",name="Import Assets",run=function()
            local result=import_assets({suppress_dialog=true,strict=true,world_manifest=world,profile_session=profiling,exports_checked=true})
            tilemaps_regenerated=result~=false; return result
        end}
    elseif has_rooms then
        skipped[#skipped+1]="Import Assets"
    end
    if changed and deps.apply_settings then
        stages[#stages+1]={id="settings",name="Apply player settings",run=deps.apply_settings}
    elseif deps.apply_settings then
        skipped[#skipped+1]="Apply player settings"
    end
    if changed and has_rooms then
        stages[#stages+1]={id="rooms",name="Create Rooms and synchronize resources",run=function() return safe_generate(nil,{open_perf_report=false,strict=true,world_manifest=world,profile_session=profiling,exports_checked=true,tilemaps_regenerated=tilemaps_regenerated}) end}
    elseif has_rooms then
        skipped[#skipped+1]="Create Rooms and synchronize resources"
    end
    stages[#stages+1]={name="Check translations",run=function()
        translation_result=(deps.translations or require("mvtk.editor.translation_project").check)(opts)
        for _,line in ipairs(translation_result.lines) do info("[TRANSLATIONS] "..line) end
        assert(translation_result.errors==0,table.concat(translation_result.lines,"\n"))
    end}
    stages[#stages+1]={name="Build UI font",run=function()
        local result,err=(deps.ui_font or require("mvtk.editor.ui_font").build)(opts)
        assert(result,err)
        for _,line in ipairs(result.lines) do info("[FONT] "..line) end
        assert(result.errors==0,table.concat(result.lines,"\n"))
    end}
    if world then stages[#stages+1]={name="Resolve Tiled world",run=function()
        candidate=World.candidate(opts,world)
        for _,message in ipairs(candidate.diagnostics or {}) do info("[WORLD] "..message) end
    end} end
    stages[#stages+1]={name="Validate All",run=function()
        -- Creator preparation validates content. Maintainer suites run separately
        -- in disposable fixture projects and must never mutate creator content.
        return run_validate_all({skip_tests=true,allow_empty=not has_rooms,layout=candidate and candidate.layout,map_files=candidate and candidate.map_files,world_manifest=world})
    end}
    local steamworks_opts={root=ROOT,read=deps.read or require("mvtk.editor.project_transaction").read}
    if require("mvtk.editor.steamworks_files").enabled(steamworks_opts) then
        stages[#stages+1]={name="Write Steamworks files",run=function()
            for _,file in ipairs(require("mvtk.editor.steamworks_files").files(steamworks_opts)) do
                if write_if_changed(join(ROOT,file.path),file.content) then
                    info("[STEAM] Wrote "..file.path.."; upload it in Steamworks")
                end
            end
        end}
    end
    if has_rooms then stages[#stages+1]={name="Check world budget",run=function()
        -- Counts read through opts.read; no full snapshot here (the run takes one at the end).
        local layout=candidate and candidate.layout or Preparation.load(opts,"runtime/layout/world_layout.local.lua")
        local result=(deps.world_budget or require("developer.tools.world_budget").check)({root=ROOT,read=opts.read,
            write=write_if_changed,list_dir_filesystem=list_dir_filesystem,layout=layout})
        for _,line in ipairs(result.lines or {}) do info("[BUDGET] "..line) end
        assert((result.errors or 0)==0,table.concat(result.lines or {},"\n"))
    end} end
    if world then stages[#stages+1]={name="Publish Tiled world and minimap",run=function() return World.publish(opts,candidate) end} end
    -- The plan is fixed for this run. Freshness may shorten the next run, but
    -- every Continue prompt and the final result use this same denominator.
    local stage_count=#stages
    local skipped_line=#skipped>0 and ("Already current; skipped: "..table.concat(skipped,", ")..".") or nil
    info(string.format("[PREPARE] Planned %d stages for this run.",stage_count))
    if skipped_line then info("[PREPARE] "..skipped_line) end
    opts.progress=function(i,n,name)
        local stage=string.format("%d/%d %s",i,n,name)
        set_active_stage(stage)
        info("[PREPARE] "..stage)
    end
    opts.render_progress=function(message) set_active_stage(message);info("[PREPARE] "..message) end
    opts.cancelled=function(i,stage)
        if HEADLESS or i==1 then return false end
        set_active_stage("Waiting for Continue or Cancel before "..stage.name)
        info("[PREPARE] Waiting for Continue or Cancel in the Prepare & Check dialog; next: "..stage.name)
        return show_editor_status_dialog("Prepare & Check",{
            string.format("Completed %d of %d stages. Next: %s",i-1,stage_count,stage.name),
            "Cancel stops before the next stage. The published layout and minimap are preserved.",
            skipped_line,
        },{cancel_text="Cancel",extra_buttons={editor_api.ui.dialog_button({text="Continue",result="continue"})}})~="continue"
    end
    if profiling then
        local before
        opts.stage_start=function(name)
            profiler.start("stage: "..name)
            before={};for key,value in pairs(Stats.stats()) do if type(value)=="number" then before[key]=value end end
            before.snapshots=Preparation.stats().snapshots
        end
        opts.stage_stop=function(name)
            profiler.stop("stage: "..name)
            local s=Stats.stats()
            stage_metrics[#stage_metrics+1]=string.format("[PERF] stage I/O %s: %d rewrites, %d creates, %d full snapshots",name,
                s.rewritten_existing-before.rewritten_existing,s.created_batched-before.created_batched,Preparation.stats().snapshots-before.snapshots)
        end
    end
    local report,base=Preparation.run(opts,stages)
    report.translations=translation_result
    require("hooks.core.filesystem").cancel_tilemap_staging()
    outcome=report.status
    -- Release the progress window before report writes or profiling can yield.
    if report.status=="failed" then report_failure(report.error) end
    if profiling then profiler.start("status and report tail") end
    Preparation.write_report(opts,"assets/tiled/preparation_run.lua",report)
    write_if_changed(join(ROOT,"developer/assets/tiled/preparation_run.json"),require("developer.tools.relationship_project").json(report))
    assert(report.status~="failed",report.error)
    if report.status=="cancelled" then
        info("[PREPARE] Cancelled between stages")
        if activity_report then activity_report("Preparation cancelled between stages.",false) end
    else
        set_active_stage("Preparation complete; reviewing the result")
        info("[PREPARE] Preparation complete. Saving the result...")
        show_preparation_status(base,true,stage_count,catalog_result,translation_result)
        info("[PREPARE] Result saved. Preparation finished.")
    end
    return true
end
local unprofiled_prepare=prepare_and_check
prepare_and_check=function(...)
    if not profiler then return unprofiled_prepare(...) end
    profiler.reset(); Stats.reset(info); Preparation.reset_stats(); dialog_wait=0; stage_metrics={};outcome=nil;profiling=true
    profiler.start("TOTAL Prepare & Check (excluding dialogs)")
    local ok,result=pcall(unprofiled_prepare,...)
    if not ok then report_failure(result) end
    require("hooks.core.filesystem").cancel_tilemap_staging()
    profiler.stop_all(); profiling=false
    -- Account for the report's own one physical close before rendering counters.
    Stats.add("raw_writes")
    local lines=profile_lines(); lines[#lines+1]="[PERF] outcome: "..(ok and (outcome or "completed") or tostring(result))
    local reported,report_error=pcall(profiler.report,lines); Stats.finish()
    if not reported then info("[PERF] Could not write report: "..tostring(report_error)) end
    if not ok then require("hooks.core.error_text").reraise(result) end
    return result
end
function P.on_target_launched(opts)
    _G.MVTK_RUNNING_TARGETS=_G.MVTK_RUNNING_TARGETS or {}
    _G.MVTK_RUNNING_TARGETS[opts.url or "local"]=true
end
function P.on_target_terminated(opts)
    if _G.MVTK_RUNNING_TARGETS then _G.MVTK_RUNNING_TARGETS[opts.url or "local"]=nil end
end
function P.on_build_finished(opts)
    if opts.success then local config=preparation_opts()
        local current,base=Preparation.build_snapshot(config)
        if P.build_inputs and #Preparation.diff(P.build_inputs,current)==0 then
            -- Recording the revision is freshness bookkeeping for a build that
            -- has ALREADY succeeded. A failure here must degrade to unverified
            -- freshness, never surface as "hook on_build_finished failed":
            -- that reads as a broken build and hides which step actually died.
            local recorded,err=pcall(Preparation.write_report,config,"assets/tiled/build_revision.lua",
                {version=Preparation.version,inputs=current,sources=base})
            if not recorded then
                info("[PREPARE] Could not record the build revision; build freshness remains unverified: "..tostring(err))
            end
        else info("[PREPARE] Files changed during build; build freshness remains unverified.") end
    end
    for _,line in ipairs(profile_lines()) do info(line) end
    Stats.finish()
end
function P.on_build_started()
    local active=active_runs[run_key]
    assert(not active,"Preparation is still running. Wait for it to finish before building.")
    Stats.reset(info); Preparation.reset_stats();stage_metrics={};dialog_wait=0
    P.build_inputs=Preparation.build_snapshot(preparation_opts())
    for _,line in ipairs(profile_lines()) do info(line) end
end

P.publish_world=function() return run_exclusive("Publish Tiled World",publish_world) end
P.use_world=function()
    return run_exclusive("Use Tiled World Layout",function() return prepare_and_check(choose_world(true)) end)
end
P.run=function(...) return run_exclusive("Prepare & Check",prepare_and_check,...) end
-- Report the shared guard without exposing its mutable state to other menus.
function P.active_stage()
    local active=active_runs[run_key]
    if active then return active.label,active.stage end
end
-- Open this lightweight window BEFORE any freshness scan. The run itself owns
-- the concurrency guard, even if the progress window is closed while it works.
P.run_visible=function()
    if HEADLESS then return P.run() end
    if active_runs[run_key] then return P.run() end
    if activity_windows[run_key] then return false,"Prepare & Check is already open. Use its Continue button." end
    activity_windows[run_key]=true
    local ok,result,err=pcall(function()
        return require("hooks.preparation_activity").show(editor_api.ui,function(report)
            activity_report=report
            local ran,value,err=pcall(P.run)
            activity_report=nil
            if not ran then require("hooks.core.error_text").reraise(value) end
            return value,err,outcome
        end,{
            -- Re-post completion after resource refreshes have settled, just
            -- as Export Game does, so the saved result reaches the visible UI.
            settle=function()
                local quiet={reload_resources=false,out="discard",err="discard"}
                if editor_api.platform:find("win32",1,true) then editor_api.execute("cmd","/c","exit","0",quiet)
                else editor_api.execute("true",quiet) end
            end,
        })
    end)
    activity_windows[run_key]=nil
    if not ok then require("hooks.core.error_text").reraise(result) end
    return result,err
end
P.status=show_preparation_status
P.require_current_hooks=require_current_hooks
return P
end
return M
