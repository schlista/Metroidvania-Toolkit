-- Designer-page metadata. Paths refer to real runtime configuration consumers.
-- Every field is saved through the shared wizard document; previews never save.
local Product = require "mvtk.core.product"
local M={fields={},pages={"Camera","HUD and prompts","Map","Saves and checkpoints","Player art","Movement test","Display","Large worlds","Accessibility"}}
local function add(page,key,title,path,kind,default,help,min,max,choices,step)
    local values; if choices then values={}; for _,v in ipairs(choices) do values[v]=true end end
    M.fields[#M.fields+1]={key=key,title=title,page=page,path=path,type=kind,default=default,help=help,
        min=min,max=max,values=values,choices=choices,step=step or 1,label=key:gsub("_"," "),
        owner="creator",scope=Product.id,rebuild=true,units="",action="Save Project, stop, Prepare & Check, Build"}
end
add(1,"camera_zoom","Zoom","camera.default_zoom","number",1,"Global zoom; Tiled camera zones and boss arenas retain authority.",0.1,4,nil,0.1)
add(1,"camera_follow_x","Follow speed X","camera.speed.x","number",99,"Horizontal follow response; higher catches up faster.",1,99)
add(1,"camera_follow_y","Follow speed Y","camera.speed.y","number",99,"Vertical follow response.",1,99)
add(1,"camera_deadzone_x","Dead zone X (world px)","camera.deadzone.x","number",0,"Horizontal dead zone in world pixels.",0,2048,nil,8)
add(1,"camera_deadzone_y","Dead zone Y (world px)","camera.deadzone.y","number",0,"Vertical dead zone in world pixels.",0,2048,nil,8)
add(1,"camera_lookahead","Look-ahead (world px)","camera.lookahead.x","number",0,"Horizontal look-ahead in world pixels.",0,2048,nil,8)
add(1,"camera_offset_x","Offset X (world px)","camera.offset.x","number",0,"Horizontal framing offset in world pixels.",-2048,2048,nil,8)
add(1,"camera_offset_y","Offset Y (world px)","camera.offset.y","number",0,"Vertical framing offset in world pixels.",-2048,2048,nil,8)
add(1,"camera_pixel_snap","Pixel snap","camera.pixel_snap","boolean",true,"Snap rendering to screen pixels; simulation remains fractional.")
add(1,"camera_respawn_snap","Snap on respawn","camera.snap_on_respawn","boolean",true,"Snap on respawn; false uses the configured smooth transition.")
add(1,"camera_respawn_time","Respawn blend time (seconds)","camera.respawn_lerp_time","number",0.2,"Smooth respawn transition in seconds.",0.01,5,nil,0.05)
add(1,"camera_vertical_look","Look up and down","camera.look_y_enabled","boolean",true,"Allow holding up/down to look vertically.")
add(2,"hud_preset","Layout preset","hud_layout.active_preset","string","default","Existing layout preset; individual overrides apply after the preset.",nil,nil,{"default","minimal","bottom_left","centered"})
add(2,"hud_scale","Scale","hud_layout.global.scale","number",1,"Scale HUD elements while retaining their screen anchors.",0.5,2,nil,0.1)
add(2,"hud_theme","Theme","hud_layout.theme_preset","string","authored","Existing theme palette for HUD and prompts; individual color overrides win.",nil,nil,{"authored","classic","neon","minimal","retro","horror"})
add(2,"toast_anchor","Toast position","hud_layout.toast.anchor","string","bottom_center","Where short messages appear. Keep them clear of your bars and dialogue.",nil,nil,{"top_left","top_right","bottom_left","bottom_right","top_center","bottom_center"})
add(2,"toast_y","Toast vertical offset","hud_layout.toast.offset.y","number",120,"Design pixels from the chosen edge to the centre of the message. Positive moves up from the bottom; negative moves down from the top.",-1000,1000,nil,1)
add(2,"toast_text_scale","Toast text size","hud_layout.toast.text_scale","number",1.857142857,"Text size multiplier for your toast font. The default makes the shipped font readable over gameplay.",0.5,4,nil,0.1)
add(2,"prompt_anchor","Prompt position","hud_layout.interact_hint.anchor","string","bottom_center","Where Interact and gate contact hints appear. The text and its backing stay centred together.",nil,nil,{"top_left","top_right","bottom_left","bottom_right","top_center","bottom_center"})
add(2,"prompt_x","Prompt horizontal offset","hud_layout.interact_hint.offset.x","number",0,"Design pixels sideways from the chosen anchor. Zero keeps a bottom-centre prompt centred.",-1000,1000,nil,1)
add(2,"prompt_y","Prompt vertical offset","hud_layout.interact_hint.offset.y","number",360,"Design pixels to the prompt centre. The default leaves room for toasts and the countdown below it.",-1000,1000,nil,1)
add(2,"prompt_opacity","Prompt opacity","hud_layout.interact_hint.opacity","number",1,"How solid Interact and gate hint text looks: 1 is fully visible; 0 hides the text.",0,1,nil,0.05)
add(2,"prompt_text_scale","Prompt text size","hud_layout.interact_hint.text_scale","number",1.857142857,"Text size multiplier for your prompt font. Long hints wrap inside the backing.",0.5,4,nil,0.1)
for _,channel in ipairs({{"r","red",0},{"g","green",0},{"b","blue",0},{"a","opacity",0.75}}) do
    add(2,"message_plate_"..channel[1],"Plate "..channel[2],"hud_layout.message_plate."..channel[1],"number",channel[3],"Backing for toasts, Interact, gate hints and Saving off. Colour channels and opacity run from 0 to 1.",0,1,nil,0.05)
end
add(2,"hud_mode_label","Movement label","hud_layout.mode_label.visible","boolean",false,"Show the player's current movement (Walk, Run, Air Dash ...) under the Menu button. Off by default: a testing aid that the F1 debug overlay shows as State.")
for _,name in ipairs({"health_bar","energy_bar","stamina_bar","currency","abilities","quick_item","interact_hint"}) do
    -- The abilities line is a testing aid, off by default (the F1 debug overlay lists the abilities).
    local help=name=="abilities" and "Show the unlocked abilities as short labels (G S CA ...). Off by default: a testing aid that the F1 debug overlay of debug builds also lists."
        or "Show "..name:gsub("_"," ").." when its gameplay resource is available."
    add(2,"hud_"..name,({health_bar="Health bar",energy_bar="Energy bar",stamina_bar="Stamina bar",currency="Currency",abilities="Abilities",quick_item="Quick item",interact_hint="Interact prompt"})[name],"hud_layout."..name..".visible","boolean",name~="abilities",help)
end
add(2,"hud_area_title","Area titles","hud_layout.area_title.visible","boolean",true,"Show a region's name and subtitle when the player enters it, and a landmark room's title. Pause, dialogue and locked boss arenas hold the card; an unshown card left behind is dropped.")
add(2,"area_titles","When to show","hud_layout.area_title.mode","string","first_visit","first_visit: once per save, the first time the player enters a region; every_entry: each time the player enters it. A region's title_card in biomes.lua wins.",nil,nil,{"first_visit","every_entry"})
add(2,"area_title_seconds","Seconds shown","hud_layout.area_title.duration","number",3,"Seconds the title card stays fully visible, not counting its fades.",0.5,10,nil,0.5)
add(2,"hud_status_chips","Status chips","hud_layout.status_chips.visible","boolean",true,"Show each active player status and its remaining seconds; countdown pauses with the game.")
add(2,"hud_level_xp","Level and XP","hud_layout.level_xp.visible","boolean",true,"Show the level and XP progress bar while Leveling is on.")
add(2,"hud_weapon","Weapon","hud_layout.weapon.visible","boolean",true,"Show the equipped weapon while Weapons is on.")
add(2,"hud_powerups","Power-ups","hud_layout.powerups.visible","boolean",true,"Show active power-up names and remaining play seconds.")
add(2,"hud_goal","Goal","hud_layout.goal.visible","boolean",false,"Show the current goal's title while Goals is on; it changes when a new goal is announced.")
add(2,"hud_countdown","Countdown","hud_layout.countdown.visible","boolean",true,"Show a running countdown's label and clock, then its finish time or failure; pause menus, dialogue and cutscenes hold it.")
add(2,"hud_play_timer","Play timer","hud_layout.play_timer.visible","boolean",false,"Show in-game time as h:mm:ss; pause menus, dialogue, cutscenes, death and loading stop the clock.")
add(2,"hud_trial","Trial","hud_layout.trial.visible","boolean",true,"Show the active trial goal, countdown, clock and result; pause holds its timers.")
add(2,"hud_notices","Notices","hud_layout.notices.visible","boolean",true,"Show queued milestone messages below the minimap. When off, messages use short instant toasts.")
add(2,"hud_currency_format","Currency format","hud_layout.currency.format","string","$ %d","How currency amounts appear. Write {amount} where the number goes, for example {amount} Gems.")
add(2,"hud_health_anchor","Health bar position","hud_layout.health_bar.anchor","string","top_left","Health bar screen anchor.",nil,nil,{"top_left","top_right","bottom_left","bottom_right","top_center","bottom_center"})
for i,name in ipairs({"red","green","blue"}) do
    add(2,"hud_health_"..name,({"Red","Green","Blue"})[i].." (0 to 1)","ui_theme.colors.health."..i,"number",({0.85,0.2,0.15})[i],"Health bar "..name.." channel (0 to 1).",0,1,nil,0.05)
end
add(3,"map_fog","Fog of war","map_discovery.enabled","boolean",true,"Hide unexplored map areas; disabling fog still records discovery.")
add(3,"map_discovery_mode","Discovery mode","map_discovery.mode","string","nearby","Reveal the visible screen plus nearby radius, or reveal the whole current room.",nil,nil,{"nearby","room"})
add(3,"map_reveal_radius","Reveal radius (world px)","map_discovery.reveal_radius","number",512,"Extra reveal radius around the player, beyond the visible screen; preserves saved exploration.",0,8192,nil,32)
add(3,"map_softness","Fog edge softness (world px)","map_discovery.edge_softness","number",128,"Visual fog edge softness in world pixels; does not change discovery.",0,2048,nil,16)
add(3,"map_visible","World map","world_map.enabled","boolean",true,"Allow opening the full world map.")
add(3,"minimap_visible","Minimap","minimap.enabled","boolean",true,"Show the minimap panel.")
add(3,"map_marker_limit","Marker limit","screenshot_markers.max_markers","number",10,"Maximum player-created screenshot map markers.",0,100)
add(3,"map_max_zoom","Maximum zoom","world_map.zoom.max_level","number",8,"Deepest world map zoom, as a multiple of the zoom that fits the whole world. Larger values show more room detail on big worlds.",2,8,nil,2)
add(3,"map_pan_speed","Pan speed (GUI px/s)","world_map.pan.speed","number",900,"How fast the left stick and the WASD or arrow keys move the world map, in GUI pixels per second at any zoom.",100,4000,nil,50)
add(3,"map_show_legend","Show legend","world_map.show_legend","boolean",true,"Show the button hints and the kinds of icon on screen under the world map. Players can still show or hide it with I or the top face button.")
add(3,"map_item_icons","Item icons","map_icons.item_tracking.enabled","boolean",true,"Mark items, chests, lore and found secrets on the maps. Stations, locked barriers and Map Markers show either way.")
add(3,"map_item_rule","Show items when","map_icons.item_tracking.rule","string","seen","seen: the spot was on screen (a Map Station alone does not count); visited: the room was entered; mapped: seen or revealed by a Map Station; always: from the start.",nil,nil,{"seen","visited","mapped","always"})
add(3,"map_item_flag","Required flag","map_icons.item_tracking.require_flag","string","","Item icons appear only once this save flag is set, for example by a map upgrade. Leave empty for none.")
add(3,"map_room_complete_tint","Room complete tint","map_icons.room_complete.enabled","boolean",true,"Tint a visited room on the world map once every counted item in it is found. Colour and other icons are in map_icons.lua.")
add(3,"map_marker_size","Marker size (GUI px)","minimap.custom_markers.size_px","number",6,"Player-created marker size in GUI pixels.",2,32)
add(3,"map_stamps_enabled","Map stamps","world_map.stamps.enabled","boolean",true,"Let players leave their own stamps, such as a star, ! or ?, on the world map with X. The stamp palette is in world_map_settings.lua.")
add(3,"map_stamps_max","Stamp limit","world_map.stamps.max","number",32,"Most stamps one save can hold, from 0 to 64. 0 turns placing off; saved stamps stay.",0,64)
add(3,"fast_travel_from","Travel from","fast_travel.travel_from","string","anywhere","Start trips anywhere, or only at stations and fast-travel save points.",nil,nil,{"anywhere","stations"})
add(3,"fast_travel_cost","Travel cost (currency)","fast_travel.travel_cost","number",0,"Currency charged once on accepting a trip; later loading failures are not refunded.",0,999999)
add(3,"fast_travel_fade","Fade time (seconds)","fast_travel.transition_time","number",0.3,"Fade-out hold and fade-in time, each in seconds.",0,3,nil,0.1)
add(3,"fast_travel_block_boss","Block in boss fights","fast_travel.block_in_boss_fight","boolean",true,"Refuse trips from every source during a locked boss fight or a sealed fight in the current room.")
add(4,"save_slots","Save slots","progression.saves.max_slots","number",3,"Visible save slots (1 to 3). Hiding a slot does not erase its file.",1,3)
add(4,"save_slot_summary","Slot summaries","progression.saves.show_summary","boolean",true,"Show each save slot's region, colour and summary fields (summary_fields in game_config.lua) on the save slot screen. Off shows play time and last-saved date.")
add(4,"save_slot_copy","Copy saves","progression.saves.allow_copy","boolean",true,"Let players copy a save slot onto another slot after a confirmation. The replaced save stays in that slot's backup.")
add(4,"save_autosave","Timed autosave","progression.saves.autosave_enabled","boolean",true,"Enable timed autosaves; explicit checkpoints and progression commits remain durable.")
add(4,"save_interval","Autosave interval (seconds)","progression.saves.autosave_interval","number",0,"Timed autosave seconds; zero uses event saves only.",0,3600,nil,30)
add(4,"save_room_change","Save on room change","progression.saves.autosave_on_room_change","boolean",true,"Request a save when entering another room.")
add(4,"save_pickup","Save on pickup","progression.saves.autosave_on_collectible_pickup","boolean",false,"Save after each collectible pickup.")
add(5,"art_source","Source","player_art.source","string","","PNG sheet or sequence directory. Sequence names: idle_001.png, run_001.png, etc.")
add(5,"art_mode","Mode","player_art.mode","string","sequence","Import uniformly sized PNG frames or slice a regular PNG sheet.",nil,nil,{"sequence","sheet"})
add(5,"art_frame_width","Frame width (source px)","player_art.frame_width","number",64,"Frame width in source pixels; sheets must divide exactly.",1,2048)
add(5,"art_frame_height","Frame height (source px)","player_art.frame_height","number",64,"Frame height in source pixels; sheets must divide exactly.",1,2048)
add(5,"art_animations","Animations","player_art.animations","string","idle=1-1;run=2-5;jump=6-6;fall=7-7","Sheet frame ranges (row-major, starting at 1): name=first-last;name=first-last.")
add(5,"art_mappings","Mappings","player_art.mappings","string","","Optional gameplay=animation mappings separated by semicolons. Required states must resolve.")
add(5,"art_fps","FPS (frames/s)","player_art.fps","number",12,"Animation frames per second.",1,60)
add(5,"art_once","Non-looping animations","player_art.once","string","jump;land;hurt;death","Semicolon-separated non-looping animations; other animations loop.")
add(5,"art_required","Required states","player_art.required","string","idle;run;jump;fall","Semicolon-separated gameplay states to validate. Include custom attack animation names.")
add(5,"art_fallback","Fallback animation","player_art.fallback","string","","Blank rejects missing states. An imported animation name explicitly supplies missing required states.")
add(5,"art_width","Width (world px)","player_art.width","number",0,"Displayed width in world pixels at Player Size 1.00. Zero uses the frame width; a different width stretches the model.",0,7168)
add(5,"art_height","Height (world px)","player_art.height","number",0,"Displayed height in world pixels at Player Size 1.00. Zero uses the frame height; a different height stretches the model.",0,7168)
add(5,"art_origin_x","Origin X (world px)","player_art.offset_x","number",0,"Sprite center offset from the player origin in world pixels at Player Size 1.00.",-3584,3584)
add(5,"art_origin_y","Origin Y (world px)","player_art.offset_y","number",0,"Sprite center offset from the player origin in world pixels at Player Size 1.00.",-3584,3584)
add(5,"art_body_width","Body half-width (world px)","player.collider_half_width","number",46.45158,"Player collider half-width in world pixels at Player Size 1.00.",1,896)
add(5,"art_body_height","Body half-height (world px)","player.collider_half_height","number",59.9999575,"Player collider half-height in world pixels at Player Size 1.00.",1,896)
-- Movement test geometry is authored data, scaled using current player settings.
add(6,"test_floor_tiles","Floor length (tiles)","movement_test.floor_tiles","number",32,"Length of the disposable movement course in tiles.",16,128)
add(6,"test_step_tiles","Step height (tiles)","movement_test.step_tiles","number",2,"Height of the jump obstacle in tiles.",1,8)
add(6,"test_gap_tiles","Gap width (tiles)","movement_test.gap_tiles","number",3,"Width of the dash gap in tiles.",1,12)
add(7,"display_view_mode","View on other screen shapes","display.view.mode","string","expand","Show more world fills other screen shapes without stretching; Keep 16:9 with bars preserves the design picture.",nil,nil,{"expand","letterbox"})
add(7,"display_mask_outside_room","Mask outside room","display.view.mask_outside_room","boolean",true,"Cover space outside smaller clamped or locked rooms using the bar colour; named camera zones can override it.")
add(7,"display_hud_frame","HUD frame","display.view.hud_frame","string","safe","Keep HUD within the safe 16:9 area, or place it at the picture edges.",nil,nil,{"safe","picture"})
add(7,"display_scale_rule","Pixel scaling","display.view.scale_rule","string","fit","Fit uses the available space; Integer keeps art pixels whole at Camera > Zoom. Smaller windows fall back to fit. Other zone zooms may shimmer; HUD and menus keep their fitted size.",nil,nil,{"fit","integer"})
add(7,"display_player_choice","Players can change it","display.view.player_choice","boolean",false,"Offer Wide screens in player Settings > Display; it starts at the creator's choice.")
add(7,"display_min_aspect","Narrowest shape","display.view.min_aspect","number",1.3333,"Width divided by height; 4:3 is about 1.33 and 16:10 is 1.6. Bars return below this limit.",1,1.7778,nil,0.01)
add(7,"display_max_aspect","Widest shape","display.view.max_aspect","number",2.4,"Width divided by height; 21:9 screens are about 2.37-2.39. Bars return above this limit.",1.7778,4,nil,0.01)
for i,name in ipairs({"red","green","blue"}) do
    add(7,"display_bar_"..name,"Bar "..name,"display.letterbox_color."..({"r","g","b"})[i],"number",0,"Opaque bar colour "..name.." channel, from 0 to 1.",0,1,nil,0.05)
end
for i,name in ipairs({"red","green","blue"}) do
    add(7,"startup_cover_"..name,"Startup cover "..name,"display.startup.color."..({"r","g","b"})[i],"number",0,"Opaque session startup cover colour channel, from 0 to 1.",0,1,nil,0.05)
end
add(7,"startup_cover_fade","Startup reveal time (seconds)","display.startup.fade_out_seconds","number",0.2,"Fade out the startup cover after the room, player and camera are ready. Zero reveals instantly. Opening scenes take over while fully covered.",0,5,nil,0.05)
add(7,"display_post_brightness","Brightness","display.post.brightness","number",1,"World picture only. Picture brightness; 1 unchanged. Multiplies player Brightness.",0.5,1.5,nil,0.05)
add(7,"display_post_gamma","Gamma","display.post.gamma","number",1,"World picture only. Above 1 lifts shadows; below 1 deepens them.",0.5,2,nil,0.05)
add(7,"display_post_saturation","Saturation","display.post.saturation","number",1,"World picture only. 0 grey; 1 unchanged; 2 stronger colour.",0,2,nil,0.05)
add(7,"display_post_tint_red","Tint red","display.post.tint.r","number",1,"World picture only. Red multiplier at full colour-filter strength.",0,1,nil,0.05)
add(7,"display_post_tint_green","Tint green","display.post.tint.g","number",1,"World picture only. Green multiplier at full colour-filter strength.",0,1,nil,0.05)
add(7,"display_post_tint_blue","Tint blue","display.post.tint.b","number",1,"World picture only. Blue multiplier at full colour-filter strength.",0,1,nil,0.05)
add(7,"display_post_tint_strength","Tint strength","display.post.tint.strength","number",0,"World picture only. 0 disables the colour filter; 1 uses the full tint.",0,1,nil,0.05)
add(7,"display_post_scanlines","Scanlines","display.post.scanlines","number",0,"World picture only. Alternating line darkening; 0 off. Line count is config-only.",0,1,nil,0.05)
add(7,"display_post_curvature","Curvature","display.post.curvature","number",0,"World picture only. Screen bulge; 0 flat. Mouse-to-world coordinates remain flat.",0,0.25,nil,0.01)
add(7,"display_post_vignette","Vignette","display.post.vignette","number",0,"World picture only. Darker corners; 0 off.",0,1,nil,0.05)
add(7,"display_post_player_brightness","Players can change brightness","display.post.player_brightness","boolean",true,"Offer Settings > Display > Brightness from 50 to 150 percent; it multiplies the creator brightness.")
add(7,"lighting_mode","Dark rooms","lighting.mode","string","mask","Light mask reveals art near lights and permits full black; Glow only keeps the dark tint and warm additive glow, stopping at 0.9.",nil,nil,{"mask","glow"})
M.fields[#M.fields].choice_labels = { mask = "Light mask", glow = "Glow only" }
for i,name in ipairs({"red","green","blue"}) do
    local channel=({"r","g","b"})[i]
    add(7,"lighting_shadow_"..name,"Shadow "..name,"lighting.shadow_color."..channel,"number",0,"Unlit areas fade toward this colour channel, from 0 to 1.",0,1,nil,0.05)
    add(7,"lighting_light_"..name,"Light "..name,"lighting.light_color."..channel,"number",({1,0.92,0.7})[i],"Colour channel of revealed light and optional additive glow, from 0 to 1.",0,1,nil,0.05)
end
add(7,"lighting_falloff","Falloff","lighting.falloff","number",0.6,"Light edge exponent; below 1 spreads light, above 1 tightens it.",0.25,4,nil,0.05)
-- Game > Large worlds (CP04). Defaults are literals here and are tested against
-- developer/config/stream_settings.lua and performance_budgets.lua.
add(8,"prewarm_scope","Warm rooms","stream_settings.room.prewarm_scope","string","all","Which rooms load their art before play starts. All: every room, the slowest start with no first-visit pauses. Region: the starting region and the regions next to it, then nearby regions warm as you travel. None: rooms load when first needed. Prewarm off in stream_settings.lua always means none.",nil,nil,{"all","region","none"})
M.fields[#M.fields].choice_labels = { all = "All", region = "Region", none = "None" }
add(8,"prewarm_adjacent_regions","Regions around it","stream_settings.room.prewarm_adjacent_regions","number",1,"Regions beyond the current one to keep warm, counted through doors between regions. 0 warms only the current region.",0,4)
M.fields[#M.fields].applies_when = { "prewarm_scope=region" }
add(8,"actor_sleep","Enemies wait in hidden rooms","stream_settings.room.actor_sleep","boolean",true,"Enemies in rooms that are loaded but not shown stop where they stand and resume when the room appears. Off lets them keep moving, and falling enemies there can be lost.")
add(8,"max_live_projectiles","Live shots","performance_budgets.spawn_caps.projectile","number",96,"Shots alive at once. Past this, the oldest enemy shot disappears; player shots go only when no enemy shot is left. Nothing disappears during a locked boss fight. Rewards are never capped.",1,1024)
add(8,"max_live_damage_numbers","Live damage numbers","performance_budgets.spawn_caps.damage_number","number",48,"Damage numbers shown at once; extra numbers are skipped. They share game.project's label limit with signs, levers and other labels. 0 shows none.",0,128)
-- Accessibility starts with player defaults and row visibility; later sections
-- add assist and captions without changing these fields' order.
add(9,"accessibility_text_size","Text size","accessibility.player.text_size","number",1,"Starting reading text size for players without a saved choice. Scales dialogue, lore, toasts, tutorial boxes and notices; HUD labels, menus and prompts keep their size.",1,1.5,require("developer.config.accessibility").text_sizes,0.25)
M.fields[#M.fields].check = function(value)
    for _, choice in ipairs(require("developer.config.accessibility").text_sizes) do
        if value == choice then return true end
    end
    return false, "Unsupported reading text size"
end
M.fields[#M.fields].choice_labels = { [1] = "100 %", [1.25] = "125 %", [1.5] = "150 %" }
add(9,"accessibility_shake","Screen shake","accessibility.player.shake","string","auto","Starting Screen shake choice for players without a saved choice. Auto follows Game > Options > Camera shake; Full, Reduced and Off override it.",nil,nil,{"auto","full","reduced","off"})
M.fields[#M.fields].choice_labels = { auto = "Auto", full = "Full", reduced = "Reduced", off = "Off" }
add(9,"accessibility_flashes","Flashes","accessibility.player.flashes","string","full","Starting full-screen flash choice for players without a saved choice. Reduced makes flashes dimmer and slower; Off hides them. Sprite colour flashes are separate.",nil,nil,{"full","reduced","off"})
M.fields[#M.fields].choice_labels = { full = "Full", reduced = "Reduced", off = "Off" }
add(9,"accessibility_freeze_frames","Freeze frames","accessibility.player.freeze_frames","string","full","Starting impact freeze choice for players without a saved choice. Reduced shortens each freeze; Off removes it.",nil,nil,{"full","reduced","off"})
M.fields[#M.fields].choice_labels = { full = "Full", reduced = "Reduced", off = "Off" }
add(9,"accessibility_show_text_size","Text size","accessibility.show.text_size","boolean",true,"Show Text size first in Pause > Settings > Accessibility. Hiding the row keeps saved player choices.")
add(9,"accessibility_show_shake","Screen shake","accessibility.show.shake","boolean",true,"Show Screen shake in Pause > Settings > Accessibility so players can choose Auto, Full, Reduced or Off. Hiding the row keeps saved player choices.")
add(9,"accessibility_show_flashes","Flashes","accessibility.show.flashes","boolean",true,"Show Flashes in Pause > Settings > Accessibility so players can choose Full, Reduced or Off. Hiding the row keeps saved player choices.")
add(9,"accessibility_show_freeze_frames","Freeze frames","accessibility.show.freeze_frames","boolean",true,"Show Freeze frames in Pause > Settings > Accessibility so players can choose Full, Reduced or Off. Hiding the row keeps saved player choices.")
add(9,"accessibility_show_vibration","Vibration","accessibility.show.vibration","boolean",true,"Show Vibration in Pause > Settings > Accessibility so players can turn controller vibration on or off. Hiding the row keeps saved player choices.")
add(9,"accessibility_show_toggles","Players can choose press instead of hold","accessibility.show.toggles","boolean",true,"Offer press-instead-of-hold choices for block grab, Grapple and channel healing when the game uses them. Off hides the rows and uses the creator defaults in accessibility.lua.")
add(9,"assist_allowed","Players can use assist options","accessibility.assist.allowed","boolean",true,"Offer Damage taken, Game speed and Pit rescue in Pause > Settings > Accessibility. Off hides the rows and ignores saved assist choices.")
add(9,"assist_pit_damage","Pit rescue damage","accessibility.assist.pit_damage","number",1,"Damage charged when Pit rescue returns a player from a pit or kill-mode hazard. Damage taken and difficulty still apply.",0,100,nil,1)
add(9,"assist_record_use","Record assist use","accessibility.assist.record_use","boolean",true,"Mark saves that use assist and show Assist used in Journal Records and ending statistics. Best times are refused while slowed even when this is off.")
add(9,"assist_block_achievements","No achievements on saves that used assist","accessibility.assist.block_achievements","boolean",false,"Refuse achievement unlocks on saves marked Assist used. Requires Record assist use; counters continue counting.")
add(9,"captions_default","Captions","accessibility.captions.enabled","boolean",false,"Starting Captions choice for players without a saved choice. Chooses subtitled clip variants and sound captions; scene caption steps always show.")
add(9,"caption_background","Caption background","accessibility.captions.background","string","dim","Starting caption backdrop for players without a saved choice: Off, Dim or Solid.",nil,nil,{"off","dim","solid"})
add(9,"captions_player_choice","Players can change captions","accessibility.captions.show_options","boolean",true,"Show Captions and Caption background in Pause > Settings > Accessibility. Hiding the rows keeps saved player choices.")
for _,f in ipairs(M.fields) do
    if f.key:match("^test_") or f.key:match("^art_frame_") or f.key=="art_fps" or f.key=="save_slots" or f.key=="map_marker_limit" or f.key=="map_stamps_max"
        or f.key=="prewarm_adjacent_regions" or f.key:match("^max_live_") or f.key=="map_max_zoom" then f.integer=true end
end
return M
