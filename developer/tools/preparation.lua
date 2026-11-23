-- Disk-based authoring revisions. Never load cached config modules to approve a build.
local Project = require "developer.tools.relationship_project"
local Model = require "mvtk.core.creator_settings_model"
local Transaction = require "mvtk.editor.project_transaction"
local SpineAddon = require "mvtk.editor.spine_addon"
local M = {version=1, manifest="runtime/layout/publication.lua", prepared="assets/tiled/preparation.lua"}
local roots={"developer/assets/tiled/worlds", "tiled/extensions", "developer/config", "developer/assets/tiled/maps", "developer/assets/tilesheets", "developer/assets/atlas",
    "developer/assets/tiled/templates", "developer/assets/tiled/backgrounds", "developer/assets/tiled/tilesets", "developer/assets/fonts", "developer/assets/fx",
    "developer/assets/generated_audio", "developer/assets/sfx",
    "developer/assets/enemies", "developer/assets/music", "developer/assets/extras", "developer/assets/source", "developer/assets/sprites", "developer/assets/cutscenes",
    "developer/game", "developer/ui", "developer/rooms", "developer/runtime", "hooks"}
-- hooks/project_path.txt and tiled/extensions/export_path.txt only record where
-- this toolkit sits on disk (Project > Set Up This Toolkit, the installers), so
-- moving the folder or re-running setup never makes the publication stale.
local excluded={ ["hooks/project_path.txt"]=true, ["tiled/extensions/export_path.txt"]=true,
    ["developer/"..M.manifest]=true, ["developer/runtime/layout/world_layout.local.lua"]=true,
    ["developer/runtime/layout/draft_revision.lua"]=true,
    ["developer/runtime/layout/manual_backup.lua"]=true,
    ["developer/runtime/layout/previous_world_layout.lua"]=true,
    ["developer/runtime/layout/world_layout.lua"]=true }

M.fingerprint = require("mvtk.core.adler32").fingerprint
local Collection = require "developer.tools.collection_fingerprint"
-- Any editor save re-serializes baked collections without changing them (see
-- collection_fingerprint.lua), so those compare by protobuf meaning. Every
-- other file compares byte for byte.
function M.content_fingerprint(path,content)
    if path:match("%.collection$") then return Collection.fingerprint(content) end
    return M.fingerprint(content)
end
local function get(opts,path) return (opts.read or Project.read)((opts.root or ".").."/"..path) end
local function listing(opts,dir)
    if opts.list_dir_filesystem then return opts.list_dir_filesystem((opts.root or ".").."/"..dir) end
    local dirs,files={},{}
    if editor and editor.can_get then
        if editor.can_get("/"..dir,"children") then
            for _,p in ipairs(editor.get("/"..dir,"children")) do
                local attrs=editor.resource_attributes(p); local name=p:match("([^/]+)$")
                if attrs.is_directory then dirs[#dirs+1]=name elseif attrs.is_file then files[#files+1]=name end
            end
        end
        return dirs,files
    end
    -- Runtime authoring/headless branch: reuse the existing read-only process
    -- directory listing. It handles dotted directory names without probe writes.
    return require("hooks.core.filesystem").list_dir_filesystem((opts.root or ".").."/"..dir)
end
local metrics={snapshots=0,partial_snapshots=0,build_snapshots=0,files=0,bytes=0,seconds=0,calls={}}
function M.reset_stats() metrics={snapshots=0,partial_snapshots=0,build_snapshots=0,files=0,bytes=0,seconds=0,calls={}} end
function M.stats() return metrics end
local function fingerprint(path, content, metric)
    if metric then metric.files=metric.files+1; metric.bytes=metric.bytes+#content end
    return M.content_fingerprint(path,content)
end
local function record(metric, started)
    metric.seconds=os.clock()-started
    metrics.files=metrics.files+metric.files; metrics.bytes=metrics.bytes+metric.bytes
    metrics.seconds=metrics.seconds+metric.seconds; metrics.calls[#metrics.calls+1]=metric
end
local function walk(opts,dir,out,metric)
    local dirs,files=listing(opts,dir)
    for _,name in ipairs(files or {}) do
        local p=dir.."/"..name
        if not excluded[p] and not name:match("^%.") then
            local content=get(opts,p)
            if content then out[p]=fingerprint(p,content,metric) end
        end
    end
    for _,name in ipairs(dirs or {}) do if not name:match("^%.") then walk(opts,dir.."/"..name,out,metric) end end
end
function M.snapshot(opts,caller)
    opts=opts or {}; local out={}
    local started=os.clock(); local metric={caller=caller or opts.caller or "snapshot",files=0,bytes=0}
    local key=opts.paths and "partial_snapshots" or "snapshots"; metrics[key]=metrics[key]+1
    if opts.paths then
        for _,p in ipairs(opts.paths) do local s=get(opts,p); out[p]=s and fingerprint(p,s,metric) or "missing" end
    else
        for _,dir in ipairs(roots) do walk(opts,dir,out,metric) end
        local project=get(opts,"game.project") or ""
        local selected=require("mvtk.editor.ui_font_manifest").selection(project)
        if selected and not selected:find("..",1,true) then
            local path=selected:sub(2);local content=get(opts,path)
            out[path]=content and fingerprint(path,content,metric) or "missing"
        end
        -- Ignored Spine art does not affect an Off project's publication.
        -- Read the controls from disk each time, so a toggle cannot be hidden
        -- by cached runtime config or an editor module's previous state.
        local spine_controls={}
        for _,p in ipairs(SpineAddon.CONTROL_PATHS) do spine_controls[p]=get(opts,p) end
        if SpineAddon.state(spine_controls)=="on" then walk(opts,SpineAddon.ADDON_DIR,out,metric) end
        for _,p in ipairs({"game.project",".defignore","hooks.editor_script","mvtk/editor/spine_addon.lua","hooks/steam_addon.lua","mvtk/editor/steam_addon.lua","mvtk/editor/steamworks_files.lua","mvtk/platform/rich_presence_tokens.lua","mvtk/platform/steam_languages.lua","mvtk/editor/addon_dependency.lua","mvtk/editor/proto_emit.lua","mvtk/elevators/elevator_contract.lua","mvtk/elevators/layout_resolver.lua","mvtk/tiled/tiled_carriers.lua","mvtk/tiled/text_fields.lua","mvtk/dialogue/dialogue_registry.lua","mvtk/dialogue/dialogue_sources.lua","mvtk/game/loot_tables_source.lua","mvtk/editor/loot_document.lua","mvtk/editor/loot_editor_window.lua","mvtk/editor/dialogue_document.lua","mvtk/editor/dialogue_editor_window.lua","developer/tools/localization_collect.lua","mvtk/tiled/catalog_enums.lua","mvtk/tiled/enum_usage.lua","mvtk/editor/fresh_config.lua","mvtk/collectibles/generated_types.lua","mvtk/core/config_schemas.lua","developer/config/ui_text.lua","developer/config/encounter_settings.lua","developer/config/combat_music.lua","mvtk/editor/ttf_cmap.lua","mvtk/editor/ui_font.lua","mvtk/editor/ui_font_manifest.lua","mvtk/editor/ui_font_resources.lua","mvtk/ui/generated_text.lua","mvtk/editor/translation_tsv.lua","mvtk/editor/translation_project.lua","mvtk/editor/translations_window.lua","mvtk/editor/game_settings_window.lua","mvtk/editor/game_settings_context.lua","mvtk/editor/creator_settings_writer.lua","developer/tools/game_settings_layout.lua","developer/tools/designer_fields.lua","mvtk/core/input_binding_rules.lua","mvtk/rooms/input_actions.lua","mvtk/ui/input_prompts.lua","mvtk/ui/input_prompt_labels.lua","mvtk/editor/room_catalogs.lua","mvtk/editor/room_catalogs/cutscenes.lua","mvtk/game/cutscene_ids.lua","mvtk/game/cutscene_policy.lua","mvtk/game/video_variants.lua","mvtk/editor/room_catalogs/world_census.lua","developer/tools/world_census.lua","mvtk/enemies/enemy_species.lua","mvtk/enemies/enemy_skin_sync.lua","mvtk/enemies/enemy_type_overlay.lua","mvtk/enemies/enemy_respawn_policy.lua","mvtk/enemies/enemy_overrides.lua","mvtk/enemies/enemy_defense.lua","mvtk/enemies/enemy_behavior_resolver.lua","mvtk/tiled/property_groups.lua","mvtk/combat/multipliers.lua",
            "mvtk/combat/multiplier_sources.lua","mvtk/player/player_stats.lua","mvtk/player/stat_keys.lua",
            "mvtk/bosses/patterns/attack_patterns.lua",
            "mvtk/tiled/template_versions.lua","mvtk/tiled/template_presets.lua","mvtk/tiled/template_index.lua","developer/tools/template_preset_checks.lua","mvtk/core/creator_settings_model.lua","developer/config/new_game_plus.lua","developer/config/extras.lua","developer/config/run_stats.lua","developer/config/leveling.lua","developer/config/bestiary.lua","developer/config/achievements.lua","mvtk/core/game_events.lua","mvtk/game/progression/achievement_rules.lua","mvtk/game/quests/quest_rules.lua","developer/config/quests.lua","mvtk/game/goal_rules.lua","developer/config/goals.lua","mvtk/game/countdown_rules.lua","developer/config/countdowns.lua","developer/config/npc_settings.lua","hooks/core/npc_behavior_bake.lua","developer/config/random_drops.lua","developer/config/powerups.lua","developer/config/weapons.lua","developer/config/charms.lua","developer/config/crafting.lua","mvtk/ui/time_text.lua","mvtk/core/adler32.lua","mvtk/editor/object_art.lua","mvtk/editor/prefab_generators.lua","mvtk/editor/shared_atlas.lua","mvtk/editor/asset_scanner.lua","mvtk/editor/resource_text.lua","mvtk/editor/file_utils.lua","mvtk/editor/tilesheet_sync.lua","mvtk/editor/tilemap_regen.lua","mvtk/editor/player_scale_writer.lua","mvtk/editor/player_resource_patch.lua","mvtk/player/collider_geometry.lua","mvtk/player/player_scale.lua","mvtk/world/wall_surfaces.lua","mvtk/world/switch_state.lua","mvtk/editor/tile_settings_writer.lua","mvtk/editor/project_transaction.lua","hooks/core/io_stats.lua","hooks/core/write_bundle.lua","hooks/core/go_generation.lua","hooks/core/parallax_bake.lua","hooks/core/tilemap_split.lua","hooks/core/room_collision.lua","hooks/core/state_layer_bake.lua","hooks/core/bakes/wind_current_bake.lua","hooks/core/bakes/ice_floor_bake.lua","hooks/core/bakes/pendulum_bake.lua","hooks/core/bakes/warp_statue_bake.lua","developer/config/map_icons.lua",
        "hooks/core/bakes/trade_station_bake.lua","hooks/core/bakes/quest_trigger_bake.lua","hooks/core/bakes/countdown_zone_bake.lua","hooks/core/bakes/combat_trial_bake.lua",
            "hooks/core/bakes/hazard_bake.lua","hooks/core/bakes/water_volume_bake.lua","hooks/core/bakes/air_pocket_bake.lua","hooks/core/bakes/launch_cannon_bake.lua","hooks/core/bakes/movement_zone_bake.lua","hooks/core/bakes/encounter_bake.lua","mvtk/tiled/encounter_links.lua","hooks/core/bakes/carryable_bake.lua","hooks/core/bakes/socket_bake.lua","hooks/core/platform_resources.lua","hooks/core/elevator_resources.lua","hooks/core/bakes/breakable_prop_bake.lua","hooks/editor_script.lua","hooks/core/bakes/zip_line_bake.lua","hooks/core/path_points.lua","hooks/core/ice_layer_bake.lua","hooks/core/presence_bake.lua","hooks/core/grapple_layer_bake.lua","hooks/core/bake_audit.lua","hooks/core/tilesource.lua","hooks/enemy_art_sync.lua","developer/tools/parallax_coverage.lua","mvtk/camera/camera_zones.lua","developer/tools/relationship_project.lua","developer/tools/content_relationships.lua","developer/tools/object_references.lua","developer/tools/flag_ledger.lua","mvtk/bosses/boss_identity.lua","developer/tools/progression_rules.lua","developer/tools/progression_search.lua","developer/tools/progression_closure.lua","developer/tools/progression_routes.lua","mvtk/world/gates/requirements.lua","mvtk/world/presence_condition.lua","mvtk/abilities/ability_tags.lua","mvtk/world/breakable_rules.lua","mvtk/world/hazard_immunity.lua","developer/tools/progression_graph.lua","mvtk/game/grant_spec.lua","developer/tools/content_checks.lua","developer/tools/pickup_art_checks.lua","mvtk/world/chest_contents.lua","mvtk/collectibles/reward_drops.lua","mvtk/enemies/loot_table_drops.lua","mvtk/game/trial_limits.lua","developer/tools/economy_checks.lua","mvtk/economy/selling.lua","mvtk/economy/vendor.lua","mvtk/hazards/hazard_contact.lua","mvtk/hazards/pendulum_geometry.lua","mvtk/world/kinematic_path.lua","mvtk/world/path_vehicle.lua","developer/tools/progression_project.lua","developer/tools/dev_helpers.lua","developer/tools/regenerate_minimap.lua","tools/validate_tiled_export.lua","hooks/core/filesystem.lua","developer/tools/preparation.lua","developer/tools/collection_fingerprint.lua",
            "developer/tools/layout_publication.lua","developer/tools/completion_authoring.lua","developer/tools/goal_authoring.lua","developer/tools/world_pacing.lua","mvtk/game/endings.lua","developer/config/completion_tracking.lua","developer/tools/world_layout.lua","developer/tools/world_provenance.lua","developer/tools/world_manifest.lua","mvtk/tiled/world_properties.lua","developer/tools/imported_inputs.lua","mvtk/editor/background_atlas.lua","developer/tools/layout_minimap.lua","developer/tools/layout_geometry.lua","MVTK.tiled-project","mvtk/editor_host/rooms_manifest.collection","mvtk/map/layout_vectors.lua",
            -- They shape layout and minimap publication (world_layout.lua, layout_minimap.lua).
            "mvtk/editor/room_outline.lua","mvtk/editor/room_doors.lua","mvtk/editor/locked_door_reader.lua",
            -- The world budget stage (G8-04).
            "developer/tools/world_budget.lua","developer/config/performance_budgets.lua","developer/config/stream_settings.lua",
            -- Apply Recommended Engine Limits (G8-04b).
            "developer/tools/engine_limits.lua","developer/tools/generated_census.lua",
            -- The Extras gallery generator (WM15c).
            "mvtk/editor/extras_gallery.lua",
            -- The stale generated-file sweep (CP05b).
            "hooks/core/generated_sweep.lua",
            -- The content-addressed generated store (CP05c).
            "mvtk/editor/shared_proto.lua"}) do
            local s=get(opts,p); out[p]=s and fingerprint(p,s,metric) or "missing"
        end
    end
    record(metric,started)
    return out
end
function M.diff(a,b)
    local changes,seen={},{}
    for p,v in pairs(a or {}) do if not b or b[p]~=v then changes[#changes+1]=p; seen[p]=true end end
    for p,v in pairs(b or {}) do if not seen[p] and (not a or a[p]~=v) then changes[#changes+1]=p end end
    table.sort(changes); return changes
end
function M.preparation_snapshot(opts,base)
    local out=Model.copy(base or M.snapshot(opts,"preparation_snapshot"))
    -- Layout-authored POI tags affect publication/build, not room generation.
    out["developer/config/poi.lua"]=nil
    return out
end
function M.load(opts,path) return Project.load_table(get(opts,"developer/"..path),path) end
function M.encode(value) return "-- Generated successful authoring revision; do not edit.\nreturn "..Model.encode(value).."\n" end
function M.commit(opts,path,value)
    return Transaction.commit((opts.root or ".").."/developer",{{path=path,content=M.encode(value)}},opts.transaction)
end
-- Disposable single-file diagnostics do not need a multi-file recovery journal.
function M.write_report(opts,path,value)
    assert(path:match("^assets/tiled/[%w_]+%.lua$"),"Invalid report path")
    local absolute=(opts.root or ".").."/developer/"..path
    local text=M.encode(value)
    if get(opts,"developer/"..path)==text then return {} end
    local write=opts.write or (opts.transaction and opts.transaction.fs and opts.transaction.fs.write)
    if write then write(absolute,text)
    else
        require("developer.tools.dev_helpers").ensure_dir(absolute:match("^(.*)/[^/]+$"))
        local f=assert(io.open(absolute,"wb")); local ok,err=f:write(text);local closed,close_err=f:close()
        assert(ok and closed,err or close_err)
        if package.loaded["hooks.core.io_stats"] then package.loaded["hooks.core.io_stats"].add("raw_writes") end
    end
    return {absolute}
end
function M.provenance(opts)
    local Imported=require "developer.tools.imported_inputs"
    opts=Imported.check_context(opts)
    local fingerprint=Imported.memo_fingerprint(M.fingerprint)
    local World=require "developer.tools.world_provenance"
    local issues,checked
    if opts.world_manifest then issues,checked=World.check_manifest(opts,opts.world_manifest,fingerprint)
    else issues,checked=World.check(opts,fingerprint) end
    checked=checked or {}
    if get(opts,"developer/assets/tiled/.world_export_transaction.json") then
        issues[#issues+1]={status="export_needed",path="Tiled world transaction",message="Interrupted world export. Run Export All Maps and Tiled World to recover."}
    end
    local _,files=listing(opts,"developer/assets/tiled/maps")
    if opts.map_files then files=opts.map_files
    else
        local world=opts.world_manifest or World.selected_manifest(opts)
        if world then files={};for _,map in ipairs(world.maps or {}) do files[#files+1]=map.id..".lua" end end
    end
    for _,name in ipairs(files or {}) do if name:match("%.lua$") and not checked[name:gsub("%.lua$","")] then
        local path="developer/assets/tiled/maps/"..name
        local map=Project.load_table(get(opts,path),path)
        local provenance=map and map.mvtk_provenance
        if provenance and provenance.version==2 then
            for _,d in ipairs(Imported.check(opts,map,name:gsub("%.lua$",""),fingerprint)) do issues[#issues+1]=d end
        elseif not provenance or provenance.version~=1 then
            issues[#issues+1]={status="unverified",path=path,message="Re-export this map from Tiled to record source dependencies."}
        else
            for _,dep in ipairs(provenance.dependencies or {}) do
                local absolute=dep.path:match("^%a:[/\\]") or dep.path:sub(1,1)=="/"
                local readable,content=pcall(opts.read or Project.read,absolute and dep.path or ((opts.root or ".").."/"..dep.path))
                if not readable then content=nil end
                if not content then issues[#issues+1]={status="unverified",path=dep.path,message="Source unavailable; freshness cannot be verified."}
                elseif (dep.binary and M.fingerprint(Imported.dependency_content(dep.path,content,opts.root)) or
                    Project.fingerprint(Imported.dependency_content(dep.path,content,opts.root)))~=dep.fingerprint then
                    issues[#issues+1]={status="export_needed",path=dep.path,message="Source changed; export the map from Tiled."}
                end
            end
            if #(provenance.dependencies or {})==0 then issues[#issues+1]={status="unverified",path=path,message="No source dependencies recorded."} end
        end
    end end
    return issues
end
function M.require_exports(opts)
    for _,d in ipairs(M.provenance(opts)) do assert(d.status~="export_needed",d.path..": "..d.message) end
    return true
end
local function boss_edit_signatures(opts,inputs)
    local boss_edit_inputs={}
    for path in pairs(inputs) do
        if path:match("^developer/rooms/collections/.+%.collection$") then
            local text=get(opts,path)
            if text then boss_edit_inputs[path]=Collection.boss_edit_fingerprint(text) end
        end
    end
    return boss_edit_inputs
end

local function without_boss_edits(opts,changes,signatures)
    if not signatures then return changes end
    local remaining={}
    for _,path in ipairs(changes) do
        local expected=signatures[path]
        local text=expected and get(opts,path)
        if not text or Collection.boss_edit_fingerprint(text)~=expected then
            remaining[#remaining+1]=path
        end
    end
    return remaining
end

function M.publication(opts,files,layout)
    local outputs={}
    for _,f in ipairs(files) do outputs["developer/"..f.path]=M.content_fingerprint(f.path,f.content) end
    local inputs=M.snapshot(opts,"publication")
    return {version=M.version,inputs=inputs,outputs=outputs,layout=layout,boss_edit_inputs=boss_edit_signatures(opts,inputs),
        draft=get(opts,"developer/runtime/layout/draft_revision.lua")}
end
function M.publication_changes(opts,base,allow_boss_edits)
    local manifest=M.load(opts,M.manifest)
    if not manifest or manifest.version~=M.version then return {"developer/"..M.manifest} end
    local changes=M.diff(manifest.inputs,base or M.snapshot(opts,"publication_changes"))
    if allow_boss_edits then changes=without_boss_edits(opts,changes,manifest.boss_edit_inputs) end
    if manifest.draft~=get(opts,"developer/runtime/layout/draft_revision.lua") then changes[#changes+1]="Layout Editor draft placements" end
    for p,signature in pairs(manifest.outputs or {}) do local s=get(opts,p)
        if not s or M.content_fingerprint(p,s)~=signature then changes[#changes+1]=p end
    end
    return changes
end
function M.require_published(opts,allow_boss_edits)
    local changes=M.publication_changes(opts,nil,allow_boss_edits)
    assert(#changes==0,"Layout publication is stale. For Tiled World run Prepare & Check. For manual placement, prepare/rebuild then Layout Export. Changed: "..table.concat(changes,", "))
    for _,d in ipairs(M.provenance(opts)) do
        assert(d.status~="export_needed","Tiled export is stale: "..d.path)
    end
    return true
end
function M.require_built_sources(opts)
    local built=M.load(opts,"assets/tiled/build_revision.lua")
    assert(built and built.version==M.version,"No successful build revision was recorded. Stop the game, Reload Editor Scripts, Prepare & Check, then Build. If this repeats, check the editor console for an on_build_finished error.")
    assert(built.sources,"Build again to record the source revision before publishing a layout.")
    local before=Model.copy(built.sources)
    local current=M.snapshot(opts)
    -- POI tags are authored by the Layout Editor itself and published below.
    before["developer/config/poi.lua"]=nil; current["developer/config/poi.lua"]=nil
    before["developer/config/world_layout_source.lua"]=nil; current["developer/config/world_layout_source.lua"]=nil
    local changed=M.diff(before,current)
    assert(#changed==0,"The running Layout Editor uses older resources. Stop, Prepare & Check, Build, rescan, and export. Changed: "..table.concat(changed,", "))
end
-- Room generation leaves retired-world outputs in place. Report those files
-- without changing the freshness decision or deleting creator content.
local function generated_orphan_warning(opts)
    opts=opts or {}
    local directory="developer/rooms/generated"
    local _,files=listing(opts,directory)
    if not files or #files==0 then return nil end
    -- Reuse provenance's active/pending world selection without a static
    -- dependency on world_layout (which already requires this module).
    local world,tiled=opts.world_manifest
    if not world then world,tiled=require("developer.tools.world_provenance").selected_manifest(opts) end
    if tiled and not world then return nil end -- Missing world is already a provenance error.
    local prefixes={}
    if world then
        for _,map in ipairs(world.maps or {}) do
            if type(map.id)=="string" and map.id~="" then prefixes[#prefixes+1]=map.id.."_" end
        end
    else
        -- Match Create Rooms: manual placement includes both Lua exports and
        -- tilemap-only rooms, including exports not placed in the layout yet.
        local _,maps=listing(opts,"developer/assets/tiled/maps")
        local seen={}
        for _,name in ipairs(maps or {}) do
            local id=name:match("^(.*)%.lua$") or name:match("^(.*)%.tilemap$")
            if id and id~="" and not seen[id] then
                seen[id]=true; prefixes[#prefixes+1]=id.."_"
            end
        end
    end
    local retired={}
    for _,name in ipairs(files) do
        if not name:match("^%.") then
            local current=false
            for _,prefix in ipairs(prefixes) do
                if name:sub(1,#prefix)==prefix then current=true;break end
            end
            if not current then retired[#retired+1]=name end
        end
    end
    if #retired==0 then return nil end
    table.sort(retired)
    local samples={}
    for i=1,math.min(5,#retired) do samples[i]=retired[i] end
    local remainder=#retired>#samples and string.format("; and %d more",#retired-#samples) or ""
    return {status="warning",code="orphan_generated_files",path=directory,count=#retired,samples=samples,
        message=string.format("Warning: %d generated room files do not match the current world. First files: %s%s. Review these leftovers; Prepare & Check does not remove them.",
            #retired,table.concat(samples,", "),remainder)}
end
-- Words for the report's status ids. The result window and Preparation Status show
-- these; preparation_status.lua and .json keep the ids for tools.
local STATUS_LABELS={
    ready="Status: ready.",
    export_needed="Status: export from Tiled needed.",
    failed="Status: the last preparation failed.",
    preparation_needed="Status: Prepare & Check needed.",
    layout_publication_needed="Status: layout publication needed.",
    rebuild_needed="Status: Build needed.",
    unverified="Status: some sources could not be checked.",
}
function M.status_label(status)
    return STATUS_LABELS[status] or ("Status: "..tostring(status):gsub("_"," ")..".")
end
function M.status(opts,base)
    base=base or M.snapshot(opts,"status")
    local report={version=M.version,status="ready",next_action="Build/run to play; Export Game packages the published world.",affected={},diagnostics=M.provenance(opts)}
    local has_provenance_diagnostics=#report.diagnostics>0
    -- Validation publishes this report before recording successful preparation.
    -- Reuse its flag, player-size and scrolling-layer lines without rescanning rooms on each UI
    -- refresh; freshness above still tells the creator when to prepare again.
    for line in (get(opts,Project.report_path) or ""):gmatch("[^\r\n]+") do
        local severity=line:match("^%[([A-Z]+)%] flag_")
            or line:match("^%[([A-Z]+)%] player_size_out_of_proportion ")
            or line:match("^%[([A-Z]+)%] scrolling_layer_collision ")
        if severity then report.diagnostics[#report.diagnostics+1]={
            path=Project.report_path,severity=severity:lower(),message=line} end
    end
    -- The last world budget stage's summary (developer/tools/world_budget.lua).
    local budget=M.load(opts,"assets/tiled/world_budget.lua")
    if type(budget)=="table" and type(budget.summary)=="table" then report.world_budget=budget.summary end
    -- World pacing warnings live in the progression report (lowercase severity).
    -- Info lines such as dead ends stay in the report only.
    local pacing_report="developer/assets/tiled/progression_diagnostics.txt"
    for line in (get(opts,pacing_report) or ""):gmatch("[^\r\n]+") do
        if line:match("^%[warning%] pacing_") then report.diagnostics[#report.diagnostics+1]={
            path=pacing_report,severity="warning",message=line} end
    end
    local warning=generated_orphan_warning(opts)
    if warning then report.diagnostics[#report.diagnostics+1]=warning end
    for _,d in ipairs(report.diagnostics) do if d.status=="export_needed" then
        report.status="export_needed"; report.next_action=d.message; report.affected[#report.affected+1]=d.path
    end end
    if report.status=="export_needed" then return report end
    local last=M.load(opts,"assets/tiled/preparation_run.lua")
    if last and last.status=="failed" then report.status="failed"; report.next_action="Correct the last preparation failure, then Prepare & Check: "..tostring(last.error); return report end
    local prepared=M.load(opts,M.prepared)
    local changes=M.diff(prepared and prepared.inputs,M.preparation_snapshot(opts,base))
    if not prepared or prepared.version~=M.version or #changes>0 then
        report.status="preparation_needed"; report.next_action="Stop the game, then Project > Prepare & Check."; report.affected=changes
    else
        changes=M.publication_changes(opts,base)
        if #changes>0 then report.status="layout_publication_needed"; report.next_action="Publish your active layout source: Prepare & Check for Tiled World, or Layout Export for Layout Editor."; report.affected=changes
        else
            local built=M.load(opts,"assets/tiled/build_revision.lua")
            if not built or #M.diff(built.inputs,M.build_snapshot(opts,base))>0 then report.status="rebuild_needed"; report.next_action="Build the project to use the published revision." end
        end
    end
    if has_provenance_diagnostics and report.status=="ready" then report.status="unverified"; report.next_action="Restore unavailable sources or re-export legacy maps in Tiled; see diagnostics." end
    return report
end
function M.import_changed(before,after)
    for _,p in ipairs(M.diff(before,after)) do
        -- Taking a Tiled world into the Layout Editor expands generation to all
        -- exported rooms. Those additional rooms also need their assets imported,
        -- even when their exports predate the last world-only preparation.
        if p:match("^developer/assets/") or p:match("^hooks/") or p=="developer/config/tile_settings.lua"
            or p=="developer/config/world_layout_source.lua" or p=="mvtk/editor/asset_scanner.lua" then return true end
    end
    return false
end
function M.build_snapshot(opts,base)
    metrics.build_snapshots=metrics.build_snapshots+1
    base=base or M.snapshot(opts,"build_snapshot/base")
    local out=Model.copy(base)
    local started=os.clock(); local metric={caller="build_snapshot/extra",files=0,bytes=0}
    if not opts.paths then walk(opts,"mvtk",out,metric) end
    local manifest=M.load(opts,M.manifest)
    for p in pairs(manifest and manifest.outputs or {}) do local s=get(opts,p); out[p]=s and fingerprint(p,s,metric) or "missing" end
    local s=get(opts,"developer/"..M.manifest); out["developer/"..M.manifest]=s and fingerprint(M.manifest,s,metric) or "missing"
    record(metric,started)
    return out,base
end
function M.begin_build(opts)
    M.write_report(opts,"assets/tiled/build_pending.lua",{version=M.version,inputs=M.build_snapshot(opts)})
end
function M.record_build(opts)
    local pending=M.load(opts,"assets/tiled/build_pending.lua")
    local inputs,base=M.build_snapshot(opts)
    assert(pending and pending.version==M.version,"Record the inputs with --begin-build before starting the build.")
    assert(#M.diff(pending.inputs,inputs)==0,"Files changed during build; rebuild before recording a successful revision.")
    M.write_report(opts,"assets/tiled/build_revision.lua",{version=M.version,inputs=inputs,sources=base})
end
-- Stage callbacks may yield to native progress UI. Cancellation is checked only
-- between complete stages; no stage publishes draft layout/minimap files.
function M.run(opts,stages)
    local report={version=M.version,status="preparing",stages={},diagnostics={}}
    for i,stage in ipairs(stages) do
        if opts.cancelled and opts.cancelled(i,stage,report) then report.status="cancelled"; return report end
        if opts.progress then opts.progress(i,#stages,stage.name) end
        if opts.stage_start then opts.stage_start(stage.name) end
        local ok,result,err=pcall(stage.run)
        if opts.stage_stop then opts.stage_stop(stage.name) end
        report.stages[#report.stages+1]={name=stage.name,ok=ok and result~=false}
        if not ok or result==false then report.status="failed"; report.error=tostring(not ok and result or err or (stage.name.." returned failure; see its diagnostics.")); return report end
    end
    local base=M.snapshot(opts,"run/end")
    M.write_report(opts,M.prepared,{version=M.version,inputs=M.preparation_snapshot(opts,base)})
    report.status="prepared"; return report,base
end
return M
