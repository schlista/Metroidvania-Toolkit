/* shared_persistent_channel warns when several rooms restore one saved channel.
 * Tiled-side checks use the last authoritative project index for cross-room
 * facts. Local object links never depend on that cache. Pure functions below
 * also run under Node for regressions; no extra interpreter is needed by Tiled.
 */
// Legacy scripts can overwrite the old alias, but never this namespace.
var MVTKRelationshipsV2 = (function (previous) {
    "use strict";
    var projectPath = typeof tiled !== "undefined" ? String(tiled.projectFilePath || "").replace(/\\/g, "/") : "";
    var scriptPath = typeof __filename !== "undefined" ? String(__filename).replace(/\\/g, "/") : "";
    var projectFolder = projectPath.slice(0, projectPath.lastIndexOf("/") + 1);
    var isProjectCopy = !!(projectFolder && scriptPath && typeof tiled !== "undefined" &&
        (tiled.platform === "windows" ? scriptPath.toLowerCase().indexOf(projectFolder.toLowerCase()) === 0 : scriptPath.indexOf(projectFolder) === 0));
    function keepExisting(api, versionIsCurrent) {
        var fromProject = !!(api && api.fromProject);
        if (fromProject !== isProjectCopy) return fromProject;
        // At equal provenance, keep the existing version rule.
        return !!versionIsCurrent;
    }
    if (keepExisting(previous)) return previous;
    var M = {};
    var aliases = {target_ref:"target_id", boss_ref:"boss_id", arena_ref:"arena_id", encounter_ref:"encounter_id"};
    var targets = {
        target_id:{enemy:"ambush_trigger_id",encounter:"encounter_id",movement_zone:"movement_zone_id",water_volume:"water_id",pendulum_hazard:"pendulum_id",wind_current:"current_id",timed_door:"door_id", hazard:"hazard_id", elevator:"elevator_id", teleporter:"teleporter_id", gate:"gate_id", platform:"trigger_id", moving_platform:"trigger_id"},
        encounter_id:{encounter:"encounter_id"},
        boss_id:{boss:"boss_id"}, arena_id:{boss_arena:"arena_id"}
    };
    function text(v) { return v === undefined || v === null ? "" : String(v).trim(); }
    function own(o,k) { return Object.prototype.hasOwnProperty.call(o,k); }
    // Tiled 1.12 returns enum PropertyValue wrappers, including inside classes.
    // Resolve the authored name before comparing defaults or validating IDs.
    function plainValue(value) {
        if (value && typeof value === "object" && value.typeName &&
            typeof value.value === "number" && typeof tiled !== "undefined" &&
            tiled.project && typeof tiled.project.findTypeByName === "function") {
            var type = tiled.project.findTypeByName(value.typeName);
            if (type && type.isEnum) return type.nameOf(value);
        }
        return value;
    }
    function dict() { return Object.create(null); }
    function instance(o) { return o.room + "_" + o.type + "_" + o.object_id; }
    function issue(out,o,severity,code,property,message,fix) {
        out.push({severity:severity,code:code,file:o.file,room:o.room,layer:o.layer,
            object_id:o.object_id,object_type:o.type,property:property,message:message,
            fix:fix || "Select the reported object and correct its properties, then export again."});
    }
    M.format = function(d) {
        return "[" + d.severity.toUpperCase() + "] " + d.code + " " + (d.file || "?") +
            " room=" + (d.room || "?") + " layer=" + (d.layer || "?") + " object=" + (d.object_id || "?") +
            (d.property ? " property=" + d.property : "") + ": " + d.message + " Fix: " + d.fix;
    };
    M.fingerprint = function(s) {
        // TextFile decodes UTF-8 and may normalize newlines; normalize identically
        // in Lua. UTF-8 encoding keeps non-ASCII paths/text deterministic.
        s = unescape(encodeURIComponent(s.replace(/^\uFEFF/,"").replace(/\r\n/g,"\n")));
        // Defer modulo by zlib's NMAX, preserving the normalized UTF-8 bytes.
        var a=1,b=0,i=0;
        while (i<s.length) {
            var end=Math.min(i+5552,s.length);
            for (;i<end;i++) { a+=s.charCodeAt(i); b+=a; }
            a%=65521; b%=65521;
        }
        return s.length + ":" + a + ":" + b;
    };
    M.fresh = function(registry, room, read, files) {
        if (!registry || registry.version !== 2 || !registry.sources || !Array.isArray(registry.objects) || registry.source_complete===false) return false;
        var base="developer/assets/tiled/maps/";
        for (var path in registry.sources) {
            if (path===base+room+".lua" || path===base+room+".tmx") continue;
            var source=read(path);
            if (source===null || source===undefined || M.fingerprint(source)!==registry.sources[path]) return false;
        }
        for (var i=0;i<files.length;i++) {
            var name=files[i];
            if (/^[^.].*\.lua$/.test(name) && name!==room+".lua" && !own(registry.sources,base+name)) return false;
        }
        return true;
    };
    // Only values in documented class groups are flattened. Explicit legacy
    // flat overrides beat repeated class defaults, just like property_flattener.
    M.flatten = function(properties, kind, schema) {
        var out={}, groups=[];
        for (var k in properties) {
            var v=properties[k];
            if (v && typeof v==="object" && v.typeName && v.value && typeof v.value==="object") groups.push([k,v.value]);
            else out[k]=plainValue(v);
        }
        var variants=schema && schema.objects && schema.objects[kind] || [];
        groups.forEach(function(group) {
            var members={};
            variants.forEach(function(variant) {
                var g=variant.groups && variant.groups[group[0]]; if (g) members=g.members || {};
            });
            for (var field in group[1]) {
                var value=plainValue(group[1][field]), def=members[field];
                if (!own(out,field) || !def || value!==def.default || out[field]===def.default) out[field]=value;
            }
        });
        return out;
    };
    M.collect = function(map,room,schema,templateType) {
        var records=[];
        function objectKind(o, properties) {
            if (o.className || o.type) return o.className || o.type;
            // The exporter supplies saved-TMX template identity. Tiled's
            // scripting wrapper does not expose its internal ObjectTemplate.
            var inherited = templateType && templateType(o);
            if (inherited) return inherited;
            var base = String(properties.mvtk_preset_of || "").trim().replace(/\\/g, "/")
                .replace(/^tiled\/templates\//, "").replace(/\.tx$/, "");
            if (schema && schema.templates && own(schema.templates, base)) return schema.templates[base].type;
            // Native TMX reads can leave inherited template classes blank.
            // Match the generated class signature, which survives object renames.
            var matches={};
            Object.keys(schema && schema.objects || {}).forEach(function(kind) {
                schema.objects[kind].forEach(function(variant) {
                    Object.keys(variant.groups || {}).forEach(function(group) {
                        var value=properties[group];
                        if (value && value.typeName===variant.groups[group].className) matches[kind]=true;
                    });
                });
            });
            var kinds=Object.keys(matches);
            return kinds.length===1 ? kinds[0] : "unknown";
        }
        function walk(layers,path,visible) {
            (layers || []).forEach(function(layer) {
                var name=path ? path+"/"+layer.name : layer.name;
                var shown=visible && layer.visible!==false;
                (layer.objects || []).forEach(function(o) {
                    var properties=o.resolvedProperties();
                    var kind=objectKind(o,properties);
                    records.push({room:room,file:map.fileName,layer:name,object_id:o.id,type:kind,name:o.name,
                        x:o.x,y:o.y,width:o.width,height:o.height,visible:shown && o.visible!==false,properties:M.flatten(properties,kind,schema), native:o});
                });
                walk(layer.layers,name,shown);
            });
        }
        walk(map.layers,"",true); return records;
    };
    M.normalize = function(records) {
        var diagnostics=[], byId=dict();
        records.forEach(function(o) {
            if (own(byId,o.object_id)) issue(diagnostics,o,"error","duplicate_object_id",null,"Tiled object ID is repeated in this map.");
            byId[o.object_id]=o;
        });
        records.forEach(function(o) {
            if (o.visible===false) return;
            Object.keys(aliases).forEach(function(alias) {
                var field=aliases[alias], value=o.properties[alias], source=alias;
                if (value===undefined || value===null || value===0 || (typeof value==="object" && value.id===0)) {
                    value=o.properties[field]; source=field;
                    if (typeof value!=="number" && !(value && typeof value==="object")) return;
                }
                var id=Number(typeof value==="object" ? value.id : value), target=byId[id];
                if (!target || target.visible===false || (value && value.map && o.native && value.map!==o.native.map)) {
                    issue(diagnostics,o,"error","dangling_object_reference",source,"The referenced object is missing, hidden, or belongs to another map (ID " + id + ")."); return;
                }
                var targetField=targets[field][target.type];
                if (field==="target_id" && (o.type==="teleporter")!==(target.type==="teleporter")) targetField=null;
                if (!targetField) { issue(diagnostics,o,"error","wrong_object_reference_type",source,"The referenced object cannot supply " + field + "."); return; }
                var key=text(target.properties[targetField]);
                if (!key && targetField==="boss_id" && target.properties.boss_tag) { key=text(target.properties.boss_tag); target.properties[targetField]=key; }
                if (!key) { key=instance(target); target.properties[targetField]=key; }
                o.properties[field]=key;
                delete o.properties[alias];
            });
        });
        return diagnostics;
    };
    function defaultId(o,prefix) {
        var p=o.properties, value=p[prefix+"_id"];
        if (value==="") return instance(o);
        if (text(value)) return text(value);
        if (text(o.name)) return text(o.name);
        if (o.name==="") return instance(o);
        return prefix+"_"+o.room+"_"+o.object_id;
    }
    function encounterId(o) { return text(o.properties.encounter_id) || instance(o); }
    function encounterLink(spawn, encounters) {
        var p=spawn.properties, ref=p.encounter_ref, numeric=Number(ref && typeof ref==="object" ? ref.id : ref) || 0;
        var explicit=text(p.encounter_id), best=null, bestArea=0;
        encounters.forEach(function(o) {
            if ((numeric && Number(o.object_id)===numeric) || (!numeric && explicit && encounterId(o)===explicit)) {
                best=o; bestArea=-1; return;
            }
            if (numeric || explicit || bestArea===-1) return;
            var x=Number(spawn.x) || 0,y=Number(spawn.y) || 0,ox=Number(o.x) || 0,oy=Number(o.y) || 0;
            var w=Number(o.width) || 0,h=Number(o.height) || 0,area=w*h;
            if (w>0 && h>0 && x>=ox && x<=ox+w && y>=oy && y<=oy+h &&
                (!best || area<bestArea || (area===bestArea && Number(o.object_id)<Number(best.object_id)))) {
                best=o;bestArea=area;
            }
        });
        return best && encounterId(best);
    }
    M.validate = function(localRecords, registry, fresh, room) {
        var diagnostics=[], records=localRecords.slice(), defs=dict(), refs=[], configs=fresh && registry.configs || {};
        if (fresh) (Array.isArray(registry.objects) ? registry.objects : []).forEach(function(o) { if (o.room!==room) records.push(o); });
        else issue(diagnostics,{room:room},"warning","project_index_unverified",null,
            "Cross-room and configuration checks are unverified: the project index is missing or stale.",
            "Export edited maps, run Project > Prepare & Check in Defold, then re-export this map.");
        var encounters=localRecords.filter(function(o) { return o.visible!==false && o.layer==="templates" && o.type==="encounter"; });
        var counts=dict();
        localRecords.forEach(function(o) {
            if (o.visible===false || o.layer!=="templates" || o.type!=="encounter_spawn") return;
            var id=encounterLink(o,encounters);
            if (id) counts[id]=(counts[id] || 0)+1;
            else issue(diagnostics,o,"error","encounter_spawn_orphan","encounter_ref",
                "Encounter Spawn "+o.object_id+" is outside every Encounter or has an invalid Encounter link.",
                "Place the point inside an Encounter or choose an Encounter in this room.");
        });
        encounters.forEach(function(o) {
            if (!counts[encounterId(o)]) issue(diagnostics,o,"warning","encounter_empty",null,
                "This Encounter has no Encounter Spawn points.","Place an Encounter Spawn point inside the rectangle.");
        });
        function add(ns,key,o) {
            key=text(key); if (!key) return;
            var n=defs[ns] || (defs[ns]=dict()); (n[key] || (n[key]=[])).push(o);
        }
        function ref(ns,key,o,field) { if (text(key)) refs.push({ns:ns,key:text(key),o:o,field:field}); }
        records.forEach(function(o) {
            if (o.visible===false) return;
            var p=o.properties,t=o.type;
            [
                {kind:"zip_line",field:"path_ref",shape:"polyline",code:"invalid_zip_line_path"},
                {kind:"hazard",field:"motion_path_ref",shape:"polyline",motion:"path",code:"invalid_hazard_path"},
                {kind:"hazard",field:"motion_pivot_ref",shape:"point",motion:"orbit",optional:true,code:"invalid_hazard_pivot"}
            ].forEach(function(rule) {
                if (o.room!==room || t!==rule.kind || (rule.motion && p.motion_type!==rule.motion)) return;
                var value=p[rule.field], id=Number(value && typeof value==="object" ? value.id : value);
                if (rule.optional && (!id || id===0)) return;
                var path=localRecords.filter(function(r) { return Number(r.object_id)===id; })[0];
                var nativePath=path && path.native, points=nativePath && nativePath.polygon;
                var rightShape=nativePath && typeof MapObject!=="undefined" &&
                    nativePath.shape===(rule.shape==="point" ? MapObject.Point : MapObject.Polyline);
                var badPath=rule.shape==="polyline" && (!points || points.length<2 ||
                    !points.some(function(pt) { return pt.x!==points[0].x || pt.y!==points[0].y; }));
                var templates=path && String(path.layer || "").split("/").indexOf("templates")>=0;
                if (!path || path.visible===false || !rightShape || badPath ||
                    (Number(nativePath.rotation)||0)%360!==0 ||
                    (value && value.map && o.native && value.map!==o.native.map) || (t==="hazard" && templates))
                    issue(diagnostics,o,"error",rule.code,rule.field,
                        "Object "+o.object_id+": select a visible, unrotated "+rule.shape+
                        (rule.shape==="polyline" ? " with at least 2 distinct points" : "")+
                        " in this map"+(t==="hazard" ? " outside templates." : "."));
            });
            if (o.room===room && t==="teleporter" && (p.teleporter_id==="" || (p.teleporter_id===undefined && o.name==="")))
                issue(diagnostics,o,"error","missing_teleporter_id","teleporter_id","Set a unique teleporter_id; an explicitly blank identity cannot resolve in an unloaded room.");
            if (t==="end_game" && o.room===room) {
                var ending=fresh && registry.completion;
                // Another region ending names its own region, as developer/tools/completion_authoring.lua accepts.
                var others=ending && ending.endings && typeof ending.endings==="object" ? ending.endings : [];
                var known=ending && (p.completion_id===ending.id || Object.keys(others).some(function(k) {
                    var other=others[k];
                    return other && other.id===p.completion_id && other.condition==="region";
                }));
                if (ending && !known) {
                    var message="Region completion ID '"+String(p.completion_id)+"' must match a configured region ending ID (main ending '"+String(ending.id)+"').";
                    if (!ending.enabled) message+=" Ending is disabled; use Project > Game Settings... > Ending to match the ID before enabling completion.";
                    issue(diagnostics,o,ending.enabled ? "error":"warning","unknown_completion_id","completion_id",message,
                        "Match the ID in Project > Game Settings... > Ending or correct this region's completion_id and export again.");
                }
                else if (!ending) issue(diagnostics,o,"warning","ending_unverified","completion_id","Run Prepare & Check in Defold to verify the ending relationship.");
            }
            if (t==="teleporter") { add("teleporter",defaultId(o,"teleporter"),o); add("teleporter_pair",p.pair_id,o); ref("teleporter",p.target_id,o,"target_id"); }
            if (t==="enemy") add("trigger_channel",p.ambush_trigger_id,o);
            if (t==="encounter") { add("trigger_channel",encounterId(o),o); ref("trigger_channel",p.target_id,o,"target_id"); }
            if (t==="water_volume") add("trigger_channel",defaultId(o,"water"),o);
            if (t==="pendulum_hazard") add("trigger_channel",defaultId(o,"pendulum"),o);
            if (t==="movement_zone") add("trigger_channel",text(p.movement_zone_id) || instance(o),o);
            if (t==="wind_current") add("trigger_channel",defaultId(o,"current"),o);
            if (t==="timed_door") add("trigger_channel",defaultId(o,"door"),o);
            if (t==="gate") add("trigger_channel",text(p.gate_id) || instance(o),o);
            if (t==="hazard") {
                add("trigger_channel",defaultId(o,"hazard"),o);
                ref("boss",p.boss_id,o,"boss_id"); ref("boss_arena",p.arena_id,o,"arena_id");
                if (p.level_mode && p.level_mode!=="none" && (text(p.arena_id) || text(p.boss_id)))
                    issue(diagnostics,o,"warning","level_hazard_arena_ignored","level_mode",
                        "Level hazards ignore Arena settings.","Clear the arena links or set Level mode to none.");
            }
            if (t==="platform" || t==="moving_platform") { add("trigger_channel",p.trigger_id,o); add("trigger_channel",p.vehicle_switch_id,o); }
            if (t==="elevator") { add("trigger_channel",p.elevator_id,o); if (p.trigger_id!==p.elevator_id) add("trigger_channel",p.trigger_id,o); }
            if (t==="pressure_plate") ref("trigger_channel",p.target_id || defaultId(o,"plate"),o,p.target_id ? "target_id" : "plate_id");
            if (t==="breakable_prop") ref("trigger_channel",p.target_id,o,"target_id");
            if (t==="lever" || t==="strike_switch" || t==="socket") ref("trigger_channel",p.target_id,o,"target_id");
            if (t==="carryable") add("carryable",text(p.carry_id) || instance(o),o);
            if (t==="socket") ref("carryable",p.accepts_id,o,"accepts_id");
            if (t==="boss") {
                var bossId=p.boss_id || p.boss_tag || instance(o);
                add("boss",bossId,o); if (p.boss_tag && p.boss_tag!==bossId) add("boss",p.boss_tag,o);
                add("boss_selector",p.boss_preset || p.boss_type,o);
                ref("fast_travel_station",p.reward_unlock_fast_travel,o,"reward_unlock_fast_travel");
            }
            if (t==="boss_arena") add("boss_arena",p.arena_id || ("arena_"+o.room),o);
            if (t==="arena_boundary") add("arena_boundary",p.boundary_id,o);
            if (t==="boss_add_spawner") { add("boss_add_spawner",p.spawner_id,o); ref("boss",p.boss_id,o,"boss_id"); ref("boss_arena",p.arena_id,o,"arena_id"); }
            if (t==="boss_phase") add("boss_phase",p.phase_id || instance(o),o);
            if (["boss_arena","boss_phase","boss_phase_trigger","boss_weak_point"].indexOf(t)>=0) {
                ref("boss",p.boss_id,o,"boss_id");
                if (!p.boss_id && text(p.boss_preset || p.boss_type).toLowerCase()!=="none") ref("boss_selector",p.boss_preset || p.boss_type,o,"boss_preset");
            }
            if (["boss","boss_phase","boss_phase_trigger","arena_boundary"].indexOf(t)>=0) ref("boss_arena",p.arena_id,o,"arena_id");
            if (t==="cutscene") {
                var sceneId=text(p.cutscene_id) || text(p.cutscene_name) || ("tiled_cutscene_"+o.room+"_"+Math.floor(Number(o.object_id)||0));
                if (p.generate_cutscene===true || [p.video_id,p.video_uri,p.video_editor_uri,p.cutscene_dialogue_id,p.dialogue_id].some(function(v) { return !!text(v); })) add("cutscene",sceneId,o);
                ref("cutscene",sceneId,o,"cutscene_id");
                ref("dialogue",text(p.cutscene_dialogue_id) || p.dialogue_id,o,"cutscene_dialogue_id");
                ref("video",p.video_id,o,"video_id");
            }
            if (t==="boss") {
                ref("cutscene",p.intro_cutscene,o,"intro_cutscene");
                ref("cutscene",p.defeat_cutscene,o,"defeat_cutscene");
            }
            var persistent={chest:"chest_id",breakable_wall:"wall_id",save_point:"save_id"}[t];
            if (persistent) add("persistent_"+persistent,p[persistent] || (t==="save_point" && o.name) || instance(o),o);
            if (t==="fast_travel") add("fast_travel_station",text(p.station_id) || instance(o),o);
            if (t==="save_point" && p.is_fast_travel===true) add("fast_travel_station",text(p.save_id) || text(o.name) || instance(o),o);
            ["destination_room","destination_room_id","target_room","target_room_id"].forEach(function(f) { ref("room",p[f],o,f); });
            ["ability_id","require_ability","requires_ability","reward_ability"].forEach(function(f) { if (text(p[f]).toLowerCase()!=="none") ref("ability",p[f],o,f); });
            ["require_key","key_id","required_key"].forEach(function(f) { if (text(p[f]).toLowerCase()!=="none") ref("key",p[f],o,f); });
            if (["dialogue_trigger","npc","sign","lore_item","hint_stone"].indexOf(t)>=0) ref("dialogue",p.dialogue_id,o,"dialogue_id");
            if (o.room===room && t==="strike_switch" && p.persist_state===true && (text(p.mode)==="timed" || text(p.mode)==="momentary"))
                issue(diagnostics,o,"warning","persist_state_ignored","persist_state","Timed and momentary strike switches ignore Persist state.","Clear Persist state or use toggle or once for a saved shortcut.");
            if (o.room===room && (((t==="lever" || t==="strike_switch" || t==="socket") && !p.target_id && !text(p.set_flag_on)) || (t==="dialogue_trigger" && !p.dialogue_id)))
                issue(diagnostics,o,"warning","blank_reference",t==="dialogue_trigger" ? "dialogue_id" : "target_id","No explicit reference is set; review the intended runtime fallback.");
            if (o.room===room && t==="boss_phase_trigger") {
                var phase=p.phase===undefined ? 1 : Number(p.phase);
                if (!(phase>=1 && phase===Math.floor(phase))) issue(diagnostics,o,"error","invalid_boss_phase","phase","Phase must be a positive integer.");
                if (p.phase_id) issue(diagnostics,o,"warning","unused_phase_id","phase_id","Use numeric phase; the runtime does not consume phase_id here.");
            }
        });
        records.forEach(function(o) {
            if (o.room!==room || o.visible===false) return;
            var p=o.properties || {};
            if ((o.type==="lever" || o.type==="strike_switch") && p.message_on==="elevator_call" && text(p.call_landing)) {
                var targets=(defs.trigger_channel || {})[text(p.target_id)] || [];
                var found=targets.some(function(target) {
                    return target.visible!==false && target.type==="elevator" && records.some(function(node) {
                        var n=node.properties || {};
                        return node.visible!==false && node.type==="elevator_node" && n.elevator_id===target.properties.elevator_id &&
                            (n.node_kind || "landing")==="landing" && n.node_id===p.call_landing;
                    });
                });
                if (!found) issue(diagnostics,o,"error","unknown_elevator_landing","call_landing",
                    "Call landing does not name a floor of the target elevator.","Set Call landing to that elevator floor's node_id.");
            } else if (o.type==="elevator" && p.destination_mode==="direction") {
                var floors=records.filter(function(node) {
                    var n=node.properties || {};
                    return node.visible!==false && node.type==="elevator_node" && n.elevator_id===p.elevator_id && (n.node_kind || "landing")==="landing";
                });
                if (floors.length===2) issue(diagnostics,o,"info","destination_direction_two_stops","destination_mode",
                    "Direction mode has two floors; hold Up or Down to travel to the other floor.");
            }
        });
        Object.keys(defs).forEach(function(ns) {
            Object.keys(defs[ns]).forEach(function(key) {
                var bucket=defs[ns][key];
                if (["fast_travel_station","teleporter","boss","boss_arena","boss_phase"].indexOf(ns)>=0 || ns.indexOf("persistent_")===0) {
                    if (bucket.length>1) bucket.forEach(function(o) {
                        if (o.room===room) issue(diagnostics,o,"error","duplicate_"+ns,null,"ID '"+key+"' is defined by multiple objects.");
                    });
                }
                if (ns==="cutscene") bucket.forEach(function(o) {
                    if (o.room!==room) return;
                    if (bucket.length>1) issue(diagnostics,o,"warning","duplicate_cutscene","cutscene_id","Multiple generating objects resolve to cutscene '"+key+"'.");
                    if (configs.cutscenes && own(configs.cutscenes,key)) issue(diagnostics,o,"warning","shadowed_cutscene","cutscene_id","Generated cutscene '"+key+"' shadows cutscenes.lua.");
                });
                var pairUsed=bucket.some(function(o) {
                    var direct=defs.teleporter && defs.teleporter[text(o.properties.target_id)];
                    return o.properties.one_way!==true && !(direct && direct.length===1);
                });
                if (ns==="teleporter_pair" && bucket.length!==2) bucket.forEach(function(o) {
                    if (o.room===room) issue(diagnostics,o, pairUsed && (fresh || bucket.length>2) ? "error":"warning","teleporter_pair_cardinality","pair_id",
                        "Pair '"+key+"' has "+bucket.length+" known endpoints; exactly two are required.");
                });
            });
        });
        localRecords.forEach(function(o) {
            var p=o.properties;
            if (o.visible===false || o.type!=="boss_phase_trigger") return;
            var selected=p.boss_id ? (defs.boss && defs.boss[p.boss_id] || []) :
                (defs.boss_selector && defs.boss_selector[p.boss_preset || p.boss_type] || []).filter(function(b) { return b.room===o.room; });
            if (selected.length!==1) return;
            var boss=selected[0], bp=boss.properties, bossId=bp.boss_id || bp.boss_tag || instance(boss), preset=bp.boss_preset || bp.boss_type;
            var count=records.filter(function(m) {
                var mp=m.properties;
                return m.visible!==false && m.type==="boss_phase" && m.room===boss.room &&
                    (!mp.boss_id || mp.boss_id===bossId) && (!(mp.boss_preset || mp.boss_type) || (mp.boss_preset || mp.boss_type)===preset) &&
                    (!mp.arena_id || mp.arena_id===bp.arena_id);
            }).length;
            if (!count && bp.attack_pattern_ids) count=1;
            if (!count && configs.boss_phase_counts) count=configs.boss_phase_counts[preset] || 0;
            if (count && Number(p.phase || 1)>count && !bp.phase_config)
                issue(diagnostics,o,"error","missing_boss_phase","phase","The requested phase exceeds this boss's configured phase count ("+count+").");
        });
        refs.forEach(function(r) {
            var bucket=defs[r.ns] && defs[r.ns][r.key] || [];
            if (r.ns==="boss_selector") bucket=bucket.filter(function(o) { return o.room===r.o.room; });
            if (r.ns==="key") {
                if (configs.keys && !own(configs.keys,r.key) && r.o.room===room)
                    issue(diagnostics,r.o,"warning","unknown_key",r.field,"This is not a built-in key ID; confirm that the custom item is granted elsewhere.");
                return;
            }
            if (r.ns==="ability" || r.ns==="dialogue") {
                var set=configs[r.ns==="ability" ? "abilities":"dialogues"];
                if (set && !own(set,r.key) && r.o.room===room) issue(diagnostics,r.o,"error","missing_"+r.ns,r.field,"Unknown "+r.ns+" '"+r.key+"'.");
                return;
            }
            if (r.ns==="cutscene" || r.ns==="video") {
                var isScene=r.ns==="cutscene", definitions=configs[isScene ? "cutscenes":"videos"];
                if (r.o.room!==room || (definitions && own(definitions,r.key)) || (isScene && bucket.length)) return;
                if (!definitions) issue(diagnostics,r.o,"warning",r.ns+"_index_unavailable",r.field,"Definitions were not loaded; this reference is unverified. Run Prepare & Check in Defold.");
                else issue(diagnostics,r.o,isScene ? "error":"warning","missing_"+r.ns,r.field,"Unknown "+r.ns+" '"+r.key+"'.");
                return;
            }
            if (r.ns==="room") {
                if (r.key===room || (fresh && own(registry.sources,"developer/assets/tiled/maps/"+r.key+".lua"))) return;
            }
            if (r.ns==="boss_arena" && configs.arenas && own(configs.arenas,r.key)) return;
            if (r.ns==="trigger_channel" && (r.o.properties.persist_state===true || (r.o.type==="breakable_prop" && r.o.properties.stays_broken===true) || (r.o.type==="encounter" && r.o.properties.repeatable!==true))) {
                if (bucket.some(function(o) { return (o.type==="water_volume" || o.type==="hazard") && o.properties.level_mode==="rise"; }))
                    issue(diagnostics,r.o,"info","persist_state_rise",r.field,"This rising level never replays a stored channel.",
                        "Clear Persist state unless this switch also controls a saved shortcut.");
                var channelRooms=dict(); bucket.forEach(function(o) { channelRooms[o.room]=true; });
                if (bucket.some(function(o) { return o.type==="encounter"; }))
                    issue(diagnostics,r.o,"info","persist_state_encounter",r.field,"This Encounter never replays a stored channel.",
                        "Use a live activate signal to start this Encounter.");
                if (Object.keys(channelRooms).length>1) issue(diagnostics,r.o,"warning","shared_persistent_channel",r.field,
                    "Receivers in several rooms share this saved switch channel.","Use a unique channel per shortcut unless these receivers should share state.");
            }
            if (r.ns==="trigger_channel" && (r.o.type==="socket" || !(r.o.properties.persist_state===true || (r.o.type==="breakable_prop" && r.o.properties.stays_broken===true) || (r.o.type==="encounter" && r.o.properties.repeatable!==true))) && bucket.length && !bucket.some(function(o) { return o.room===r.o.room || (r.o.type!=="socket" && o.type==="elevator"); }))
                issue(diagnostics,r.o,"warning","cross_room_trigger_channel",r.field,r.o.type==="socket" ? "This socket targets another streamed room; saved receivers replay their own channel." : "These listeners are in other streamed rooms and must be loaded to receive the channel.");
            var pair=r.ns==="teleporter" && defs.teleporter_pair && defs.teleporter_pair[text(r.o.properties.pair_id)];
            if (!bucket.length && pair && pair.length===2) {
                issue(diagnostics,r.o,"warning","teleporter_target_fallback",r.field,"The explicit target is missing; runtime falls back to the paired endpoint.");
                return;
            }
            if (!bucket.length) issue(diagnostics,r.o,fresh && r.ns!=="carryable" ? "error":"warning","missing_"+r.ns,r.field,
                "No known "+r.ns+" matches '"+r.key+"'."+(fresh ? "":" Cross-room data is unverified."),
                r.ns==="fast_travel_station" ? "Set reward_unlock_fast_travel to a station_id or a fast-travel save point save_id in Tiled." : undefined);
            else if (r.ns!=="trigger_channel" && bucket.length>1) issue(diagnostics,r.o,"error","ambiguous_"+r.ns,r.field,"More than one object matches '"+r.key+"'.");
        });
        Object.keys(defs.trigger_channel || {}).forEach(function(key) {
            defs.trigger_channel[key].forEach(function(o) {
                if (o.visible!==false && (o.type==="platform" || o.type==="moving_platform") && key===text(o.properties.vehicle_switch_id) &&
                    !refs.some(function(r) { return r.ns==="trigger_channel" && r.key===key && r.o.visible!==false; }))
                    issue(diagnostics,o,"warning","vehicle_switch_unused","vehicle_switch_id","No sender targets this vehicle's track-switch channel.",
                        "Set a lever or strike switch Target id to Vehicle switch id as text; Target references select the activation channel.");
                if (o.room===room && o.visible!==false && o.type==="enemy" && key===text(o.properties.ambush_trigger_id) &&
                    !refs.some(function(r) { return r.ns==="trigger_channel" && r.key===key && r.o.visible!==false; }))
                    issue(diagnostics,o,"warning","ambush_trigger_unused","ambush_trigger_id","No sender targets this ambusher's release channel.",
                        "Set a lever Target id to this Enemy's Ambush trigger id, or select the Enemy with Target.");
                var p=o.properties;
                if (o.room===room && o.visible!==false && (o.type==="water_volume" || o.type==="hazard") &&
                    p.level_mode==="rise" && (p.rise_start || "signal")==="signal" &&
                    !refs.some(function(r) { return r.ns==="trigger_channel" && r.key===key && r.o.visible!==false; }))
                    issue(diagnostics,o,"warning","rise_without_signal","rise_start","No sender targets this rising level's channel.",
                        "Target this object with a switch, or choose room_enter for Rise start.");
            });
        });
        return diagnostics;
    };
    // Every field normalize can fill: each link field and each receiver's id field.
    var linkFields = [];
    Object.keys(targets).forEach(function(field) {
        [field].concat(Object.keys(targets[field]).map(function(type) { return targets[field][type]; }))
            .forEach(function(name) { if (linkFields.indexOf(name) < 0) linkFields.push(name); });
    });
    M.apply = function(records) {
        records.forEach(function(o) {
            if (!o.native) return;
            // Only relationship fields change on the disk-read export copy.
            linkFields.forEach(function(field) {
                var value=o.properties[field];
                if (typeof value==="string") o.native.setProperty(field,value);
            });
            Object.keys(aliases).forEach(function(alias) { o.native.removeProperty(alias); });
        });
    };
    M.select = function(map,diagnostics,room) {
        var ids=dict(); diagnostics.forEach(function(d) { if (d.room===room && d.object_id) ids[d.object_id]=true; });
        var selected=[];
        function walk(layers) { (layers || []).forEach(function(l) {
            (l.objects || []).forEach(function(o) { if (ids[o.id]) selected.push(o); }); walk(l.layers);
        }); }
        walk(map.layers); map.selectedObjects=selected;
    };
    Object.defineProperty(M, "fromProject", {value: isProjectCopy});
    if (typeof tiled !== "undefined" && typeof tiled.log === "function")
        tiled.log('[MVTK] content_relationships.js loaded from the ' + (isProjectCopy ? 'project' : 'global') + ' copy');
    return M;
})(typeof MVTKRelationshipsV2 !== "undefined" ? MVTKRelationshipsV2 : null);
var MVTKRelationships = MVTKRelationshipsV2;
if (typeof module !== "undefined" && module.exports) module.exports=MVTKRelationships;
