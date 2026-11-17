# Metroidvania Toolkit release notes

This file contains the creator release notes shipped with this toolkit.

## 0.1.0-alpha.1 — 2026-11-16

This is the toolkit's first alpha. Its features are built and pass automated
tests, but not every feature has been checked by hand yet. The list below names
the checks that remain open so you can decide what to try in your own game.
Report problems using [Report a problem](README.md#report-a-problem).

### Before you start

**Start a new save.** Saves from earlier toolkit builds and betas do not carry
over. See [save compatibility](docs/SAVE_COMPATIBILITY.md).
After copying in a newer toolkit, run **Project ▸ Prepare & Check** again before
building and playing.

### What's in this release

#### Movement and traversal

- Build routes around unlockable Double Jump, High Jump, Air Dash, Blink, Super Jump, Compact Form and defensive abilities.
- Tune walking, running, jumping, sliding and wall movement in Game Settings, and use Tiled wall surfaces to change how the player climbs or slides.
- Set up Pull or Swing grappling in Game Settings ▸ Grapple, with hook speed, hanging, swing pumping and release controls.
- Place ladders, hang bars, climb meshes, conveyors, ice, wind, angled launch pads and launch cannons.
- Draw tracks for carts, gondolas, rafts and elevators with several floors, including rides across room boundaries.
- Make swimming routes with currents, air pockets, floating crates and switch-controlled water levels; see [traversal recipes](docs/CREATOR_WORKFLOW.html#add-simple-traversal).

#### Combat and enemies

- Edit each active player attack's damage, timing, cooldown, energy cost and knockback in Game Settings ▸ Attacks.
- Combine melee, charged attacks, directional shots, down strikes, bombs and an optional aim stance.
- Configure parries, perfect-parry pushes, energy gained from combat and optional projectile cutting or reflection.
- Choose enemy art separately from its archetype, then tune movement, two attack slots, defenses and rewards in Tiled.
- Build guards, armored foes, turrets, crawlers, ambushers, swimmers, hoppers, summoners, swarms and enemies with death effects.
- Give enemies elemental affinities, Poison, Burn, Freeze or Slow, and make named champions with their own bar, rewards and room seal; see [enemy tuning](docs/CREATOR_WORKFLOW.html#tune-enemy-movement-and-attacks-in-tiled).

#### Bosses and combat challenges

- Build bosses with authored phases, weak points, arena boundaries, phase-controlled hazards and capped add spawners.
- Set a boss's displayed bar name, intro animation, music, defeat scene and rewards in Tiled.
- Enable stagger gauges, phase immunity, absorb shields and counter stances for the fights that need them.
- Put two or three bosses in one arena with separate bars or shared health, and let surviving partners change phase.
- Author Encounter waves and repeatable combat trials with ranks, safe retries, first-clear rewards and optional ability or attack limits; see [boss encounters](docs/CREATOR_WORKFLOW.html#build-a-compact-boss-encounter).

#### World, hazards and switches

- Open routes with keys, ability requirements, shared gate groups, ordered switches and gates that count progress across rooms.
- Link levers, plates, timed doors and Strike Switches to moving platforms, hazards and water.
- Set damage, safe returns, kill contacts and heat, acid or cold protection for hazards, including moving saws, crushers, pendulums and rising lava.
- Hide secrets behind breakable walls, bomb walls, one-sided walls and Reveal Lens discoveries.
- Make carry-and-throw puzzles with crates, orbs, bomb fruit and sockets.
- Change placed objects and tile layers with story flags, abilities and inventory conditions; see [world conditions](docs/CREATOR_WORKFLOW.html#make-objects-appear-or-disappear-with-story-flags).

#### Economy, equipment and progression

- Place shops, NPC vendors, banks, offering altars, skill trainers and permanent upgrade stations, with shared catalogs and configurable costs.
- Give collectibles, chests and enemy loot tables currency, items, abilities or permanent upgrades.
- Split health, energy and flask upgrades into collectible fragments, and choose flask, potion or channel healing.
- Enable owned weapons, crafting, charms or random equipment drops in Game Settings ▸ Equipment; Weapons, Crafting, Charms and Random drops all ship off.
- Add optional experience levels, temporary power-ups and weighted completion, with Journal records and configurable HUD blocks.
- Write item pools in Project ▸ Loot Tables...; see [economy recipes](docs/CREATOR_WORKFLOW.html#add-a-shop).

#### Map, regions and travel

- Arrange connected rooms in the Layout Editor, then Export the layout for play.
- Name regions and landmarks, give them colors, title cards, music and ambience, and choose when their titles appear.
- Offer a zoomable world map and minimap with fog, station icons, item tracking, completion tints and saved player reminder stamps.
- Connect save points and Fast Travel Stations in one network, with departures, costs, fades and boss-fight restrictions in Game Settings ▸ Map.
- Place teleporters and Warp Statues for local trips or a return to the last checkpoint; see [travel rules](docs/CREATOR_WORKFLOW.html#fast-travel-network-and-rules).

#### Story, quests and endings

- Write branching conversations in Project ▸ Dialogue Editor..., and give NPCs greetings, barks, wandering and new-dialogue markers.
- Author opening scenes, cutscene triggers, video clips, fallback cards, captions and boss defeat scenes.
- Turn on Quests and Goals in Game Settings ▸ Progression to offer tracked quests, ordered goals and goal hints; both ship off.
- Collect readable lore and relics in the Journal, and optionally record Achievements, Bestiary entries and People in Game Settings ▸ Progression; all three ship off.
- Set requirements, presentation, rewards and credits for several endings, with optional ending statistics and best times.
- Enable the title-screen jukebox, gallery and credits replay in Game Settings ▸ Ending ▸ Extras; Extras ships off; see [story recipes](docs/CREATOR_WORKFLOW.html#add-npcs-signs-hints-and-dialogue).

#### Menus, HUD, text and languages

- Restyle menus, prompts, toasts, resource bars and feature panels for your game without editing the framework.
- Choose HUD elements in Game Settings ▸ HUD and prompts ▸ Show on screen; Abilities and Movement label start hidden, and the debug F1 overlay shows them for testing.
- Offer keyboard and controller remapping, device-aware button prompts and button tokens in dialogue, signs, hints and lore.
- Export and import checked translation tables with Project ▸ Translations..., and let players choose a language or start from their system language.
- Use Vector UI text by default in Game Settings ▸ Languages ▸ Text rendering, or choose Distance field for OpenGL ES 2 and WebGL 1 devices.
- Generate glyphs Built with the game by default, using a font that covers your languages; see [language fonts](docs/CREATOR_WORKFLOW.html#choose-a-font-for-your-languages).

#### Display, accessibility and atmosphere

- Set wide-screen framing, bar colors and optional whole-pixel scaling in Game Settings ▸ Display, while keeping menus and the HUD in the safe area.
- Add dark rooms, placed lights, torches and a carried Lantern, with configurable light shapes and falloff.
- Combine regional sound, positional sources, ambience, particles, combat music and optional screen effects.
- Choose creator defaults and player-visible options in Game Settings ▸ Accessibility for shake, flashes, freeze frames, vibration, captions and reading text size.
- Offer assist options for game speed, damage and pit rescue, and press-instead-of-hold controls, with optional achievement restrictions and assist-use records; see [accessibility](docs/CREATOR_WORKFLOW.html#accessibility).

#### Saves, difficulty and replay

- Place checkpoints and save points, choose respawn rules and configure save-slot summary cards, copying and deletion in Game Settings ▸ Saves and checkpoints.
- Choose fixed difficulty, a new-game choice or changes during play in Game Settings ▸ Game ▸ Difficulty.
- Decide which enemies stay defeated and which return on room reload or rest, and choose how death affects carried currency.
- Offer New Game+ with configurable carried progress, cycle difficulty and a confirmed same-slot restart with a backup in Game Settings ▸ Progression ▸ New Game+; it ships off.
- Keep ending records and unlocked Extras across save slots in the game's profile; see [save cards](docs/CREATOR_WORKFLOW.html#save-slot-cards-copy-and-delete).

#### Creator tools in Defold

- Use Project ▸ Set Up This Toolkit to configure an unzipped toolkit, then follow the shipped Creator Guide to make your first rooms.
- Tune your game in Project ▸ Game Settings..., with field help, reset controls and Save and Prepare & Check.
- Run Project ▸ Prepare & Check to prepare imported art, generate editable room collections, refresh catalogs and check content before Build.
- Inspect freshness, generated-file counts, world budgets and recommended engine limits in Project ▸ Preparation Status.
- Use Project ▸ Analyze Progression to inspect routes, ability barriers, uncertain rewards and world pacing, then test the routes in play.
- Test with room warps, the debug overlay, temporary save-sandbox sessions and boss practice, and create a standalone game with Project ▸ Export Game; see [designer tools](docs/CREATOR_WORKFLOW.html#designer-tools).

#### Tiled tools

- Start rooms and worlds with File ▸ new_room_blank and File ▸ Start a New World..., keeping originals outside the toolkit folder.
- Paint shaped collision tiles and doors, place gameplay templates, and export copies with File ▸ Export Current Room.
- Use File ▸ Add Connected Room..., File ▸ Check Door Seams and File ▸ Copy Room Properties to Rooms... to grow a consistent world.
- Save a tuned placement with Save as Template Preset..., then update its placements by editing that preset.
- Keep every exported object as an editable gameobject in its Defold room collection; see [template presets](docs/CREATOR_WORKFLOW.html#reuse-a-tuned-object-with-a-template-preset).

#### Optional add-ons

- The sprite player ships ready to use; Project ▸ Spine Add-on... enables optional Spine animation and requires your own Spine Editor license.
- Project ▸ Steam Add-on... enables optional Steam achievements, rich presence and Steam Auto-Cloud for your own Steamworks setup.
- The Steam and Spine add-ons both ship off, and their hand checks remain open below; see [add-on setup](docs/CREATOR_WORKFLOW.html#use-the-optional-steam-add-on).

### Not yet verified by hand

The 496 checks below have not been fully checked by hand for this alpha.
"Partly checked" means some parts were tried, but the whole check is still open.
The separate Showcase download includes signs labeled with a check ID and its
check text, so you can find a check by ID. Some checks require changed settings,
a disposable project copy or extra hardware rather than a sign in the world.

SC-STEAM-005 (custom rich presence text) and SC-STEAM-006 (Steam Cloud between
two PCs from a build uploaded to Steam) need your own Steamworks app ID and a
SteamPipe upload, which the toolkit's testing did not have.

#### Controls, menus, HUD, display, accessibility and language (46 checks)

- SC-HUD-011: Menu text, prompts, page counters and four-choice dialogue at different window sizes.
- SC-CTRL-002: Every default action works on keyboard and pad. Remap one, restart: kept. Reset restores. A used button swaps.
- SC-CTRL-003: Read the sign, hint, lore and Pip with keyboard, then pad: each names your real button. Try all three icon themes. (partly checked)
- SC-HUD-001: Currency formatting in Game Settings ▸ HUD and prompts ▸ Show on screen.
- SC-HUD-002: Pick up a relic, a lore item, a secret and coins: each toast shows its text. An ability pickup shows two toasts.
- SC-CTRL-004: D-pad Left opens the Inventory. Start/Esc close it without the pause menu. Esc closes a talk once. (partly checked)
- SC-HUD-003: Read every HUD block (notices, chips, timer, weapon, power-ups, area title, goal, trial, clock): none clips or overlaps.
- SC-DISP-001: Resize to 21:9 and 16:10, then fullscreen: HUD, darkness, torch light, fades, menus, map and title stay readable and in place.
- SC-HUD-006: Learn two abilities quickly: notices queue under the minimap. Minimap off: they move up. Pause hides them.
- SC-HUD-007: Notices off uses short toasts; larger notice text wraps clear of tutorial boxes.
- SC-CTRL-005: World Map opens the map. Journal shows Records. Inventory then B: back with Inventory selected.
- SC-CTRL-006: Pause rows close gaps when Fast Travel or Difficulty is hidden.
- SC-CTRL-007: Alt-Tab or minimise: the pause menu opens and stays. Unplug the pad you use: it pauses and asks to reconnect.
- SC-DEV-001: F1 shows FPS and state; F2 shows hit boxes. F4: type a room name, Enter: you warp there. In the pause menu F4 does nothing.
- SC-CTRL-008: Difficulty selection, fixed starts and changes during play survive death and reload.
- SC-CTRL-009: Controls lists 15 actions; Heal / Item is on page 2. Remap Grapple to a stick click: it works and is kept after a restart.
- SC-CTRL-010: Creator default keys, Heal hold time and field resets in Game Settings ▸ Controls.
- SC-DISP-002: Resize to 21:9, 16:10, 4:3, 32:9, fullscreen: more world, nothing stretched; 32:9 has side bars. Torches stay put.
- SC-DISP-003: The player Wide screens choice, masked room edges and stretched backdrops.
- SC-DISP-004: At 21:9, in single-screen Pitch Gallery, the space outside the room is bar-coloured, under Rail Lagoon's water tint too.
- SC-DISP-005: Background image coverage warnings and stretched skies in letterbox mode.
- SC-DISP-006: Whole-pixel scaling at Camera zoom 2, including the HUD on 1440p and 4K screens.
- SC-DISP-007: Settings ▸ Display ▸ Brightness changes the picture at once and is kept after a restart.
- SC-DISP-008: Picture tone and retro effects together, without filtering menus, HUD or editor screens.
- SC-CTRL-011: Near the sign, Pip and the chest a prompt such as Interact (E): Read shows your last device. The gate shows its hint. (partly checked)
- SC-CTRL-013: Hiding interaction prompts also hides gate hints.
- SC-LANG-002: On a PC whose Windows language is not English, start with no saved settings: the game starts in English.
- SC-LANG-003: HUD, dialogue, toasts, the oxygen meter, boss bars and the map read as before. Death reads YOU DIED, Try Again, Quit.
- SC-LANG-004: Title, slots, pause, every Settings tab, Controls, Inventory and Journal read as before; button names unchanged.
- SC-LANG-005: Read one lore item of each kind: Journal ▸ Lore heads them Notes, Journals and Lore.
- SC-LANG-006: Toasts and labels read right: Ability Unlocked, Health restored (+N), the map station room count. Gate hints name abilities.
- SC-LANG-007: Settings shows Display, no Language row. F4 ▸ Languages ▸ Pseudo On: all text shows in [brackets]. Off: English.
- SC-LANG-009: At 1080p and 4K every screen looks as before with no clipped letters. The dialogue continue mark is a small triangle.
- SC-CTRL-014: Talk to Pip, press the HUD Menu button, load the slot again: walking, jumping and attacking still work.
- SC-CTRL-016: Settings Reset restores the creator's focus-loss and background-mute defaults.
- SC-AUDIO-005: Music and sound volumes, mute and focus mute apply on the title screen and in game.
- SC-CTRL-017: On the death screen pad Start does not quit; Esc and B do. On the map Start and P close it and keep the picked marker.
- SC-EQUIP-010: In Inventory ▸ Charms one click on a selected charm equips it, and it stays equipped.
- SC-ACC-001: Settings has four tabs. Every Accessibility row works with keys, pad and mouse; each choice survives a restart.
- SC-ACC-002: In the Warden fight, Flashes, Screen shake and Freeze frames look different at Full, Reduced and Off. Vibration Off stops rumble.
- SC-ACC-003: Set Text size 150 %: Pip long line pages inside its box; lore, toasts and these check boxes grow. HUD and menus keep size.
- SC-ACC-004: Assist: Game speed 50 % slows play, not menus. Damage taken 0 %: hits do nothing but pits kill. Pit rescue saves you here.
- SC-ACC-005: After using assist, Records says Assist used. A course finished at 50 % saves no best time and says why; at 100 % it does.
- SC-ACC-006: Slow the game, die before saving, then reach an ending: no best time is saved.
- SC-ACC-007: Press instead of hold: grab the crate, stay hooked, glide and keep running after a slide with single presses.
- SC-ACC-008: Channel healing and aim stance with press-instead-of-hold controls.

#### Movement and traversal (69 checks)

- SC-MOVE-001: Spine off: walk, run, jump, glide, slide, dash, climb, swim, grapple, carry, pound, fight, die and cross room seams as before. (partly checked)
- SC-MOVE-002: Grapple swing pumping, braking, dead-hang starts and Pull hang on or off.
- SC-MOVE-003: Walk and run on every floor of the showcase: no dips, shakes or fall frames at door seams. Say if anything feels wrong. (partly checked)
- SC-MOVE-004: Run full speed into a sealed door: note if you poke into it for a frame. Tell us if it needs fixing.
- SC-TRAV-001: Authored off. Leave the room and come back: does it start moving by itself? Note what you see.
- SC-MOVE-005: Walk, run, jump, glide, slide, dash, wall jump, ladders, swim, grapple, conveyors, rides and slopes feel as before. (partly checked)
- SC-TRAV-003: With wall jump and climb: on ice you slide fast and cannot cling. The grey wall refuses wall jumps. Plain walls as before.
- SC-MOVE-006: Jump, double jump, shoot in the air, press Jump: no third jump. Same with a down strike. (partly checked)
- SC-MOVE-007: Dash, air dash and double jump behave as before. (partly checked)
- SC-TRAV-004: This ability marker draws nothing, blocks nothing, shows no hint and has no map marker.
- SC-MOVE-008: Note your jump, take High Jump, jump again: about 1.5 times as high. Double and wall jumps as before. Kept after save and load.
- SC-MOVE-009: High Jump with a larger player size scales both normal and upgraded jumps.
- SC-MOVE-010: Air-dash in all eight directions on keyboard and pad. A down-diagonal ends on landing. Extra Air Dash chains two.
- SC-MOVE-011: Air Dash restricted to horizontal movement.
- SC-MOVE-012: During an air dash press Dash again to blink over the spikes. Toward a wall, ceiling or door it is shortened or refused.
- SC-MOVE-013: Hold Down standing still, then Jump: a super jump. Under the cracked ceiling it breaks from below.
- SC-MOVE-014: Down + Slide: crawl through the tunnel. Up or Jump under the roof: still small. The floor spike hurts; the roof spike does not.
- SC-TRAV-005: The lift raises you to its cap with Jump held, without it and gliding. It blows 3 s and stops 2 s. The lever turns it off.
- SC-TRAV-006: Painted ice: you slide when you stop and skid when you turn; it is invisible and holds you. The rectangle feels different.
- SC-TRAV-007: Custom painted-ice tuning and normal air control after jumping off.
- SC-TRAV-009: Ride into the next room: it streams in and the camera follows. Jump lets go. A hit or the water ends the ride.
- SC-TRAV-010: Zip-line hang offset places the hands at the cable.
- SC-TRAV-011: Ride each platform: line, up-down, circle, open and closed path, plate-started, one-shot. Each moves, waits and starts as before.
- SC-TRAV-012: Board: it rides to the next floor, stopping at the middle. The middle lever calls the cabin. Save there and load: still there. (partly checked)
- SC-TRAV-013: Elevator direction controls choose the next floor above or below.
- SC-TRAV-014: An elevator's Choose a floor menu lists stops and crosses rooms to the chosen one.
- SC-TRAV-015: Hold Right: the cart speeds up; Left brakes, then reverses; Jump leaves. Flip the lever: the cart takes the second track.
- SC-TRAV-016: A cart falling off its track returns to its start and lets the rider land cleanly.
- SC-WATER-003: Board: the raft top sits just above the water. Pull the lever: it sinks with the water and rests on its track; again, it rises.
- SC-WATER-004: An automatic raft runs while boarded and drifts when empty.
- SC-TRAV-017: Hold Left or Right in the tram: it rides to the next station and stops at the middle one. Ride on through the door.
- SC-TRAV-019: A hang bar with Can jump off disabled still releases with Down.
- SC-TRAV-020: The 45 and 135 pads throw you diagonally. With the lock, Left/Right wait. Without momentum, sideways speed fades sooner.
- SC-TRAV-021: Walk in: held inside, visible, with a prompt. Jump fires you. Sweep swings, auto fires itself, art turns.
- SC-TRAV-022: Low gravity: higher, slower falls. Heavy: lower, faster. Sticky: slow, also where it meets low gravity. Sinking: Jump out.
- SC-TRAV-023: Lift the crate: slower, no jump, no attacks or dashes. Throw (Up+Attack higher): it hurts the dummy and breaks the wall.
- SC-TRAV-024: Throw a crate at the switch: it toggles. Drop one in the right socket: the door opens and stays after a reload.
- SC-TRAV-025: Warp with F4: the frost wind pushes you, the ice slides, an arena pendulum hits you and a vault prop breaks.
- SC-TRAV-026: Leave a zip line or a cannon: one double jump is left. Dash does nothing on a cable. A hit before a ride gives no long immunity.
- SC-TRAV-028: Pull the call lever: it shows the request and the cabin arrives, as before.
- SC-TRAV-029: Press backdash on a zip line or inside a loaded cannon: nothing happens.
- SC-TRAV-030: Backdash, then grab the zip line at once: the grab waits for the backdash. A hit during the ride lands.
- SC-MOVE-015: Grapple with the default hook speed: it feels as before.
- SC-MOVE-016: A flying grapple hook catches with the right sound and cost, and can be cancelled.
- SC-MOVE-017: Let go of the grapple: the fall pose shows (this player has no grapple_release clip).
- SC-MOVE-018: An imported grapple-release animation plays after release and not after a cannon launch.
- SC-SGN-001: Take this pickup: Wall Jump unlocks and its popup shows. Then slide down a wall and jump off it. (partly checked)
- SC-SGN-023: The camera zooms in over the pads, and back out when you leave, once each way.
- SC-SGN-028: Low gravity: jump higher and fall slower. The lever turns this zone off and on.
- SC-SGN-029: Land on this ledge from above. Jump up through it, or hold Down and Jump to drop.
- SC-SGN-052: Carry the crate here, press Interact: it drops in and the door opens. Save and load: still open.
- SC-SGN-060: Step on the spring: it launches you straight up, once per cooldown.
- SC-SGN-062: The belt carries you and loose objects to the right.
- SC-SGN-063: Stand on it: it shakes, crumbles, then comes back once.
- SC-SGN-067: Aim the grapple at the ring: the hook catches it.
- SC-SGN-068: Grapple the underside: the hook catches. You can jump up through it.
- SC-SGN-070: Stop on this ice: you slide. Turn: you skid. It feels unlike the painted ice. Jump: normal air control.
- SC-SGN-072: Walk in: you are held inside. Press Jump: you fly along the barrel. Nothing can hurt you while loaded.
- SC-SGN-073: Ride it both ways: it carries you and keeps its platform id.
- SC-SGN-077: With Wall Jump owned, slide down this wall and jump off it.
- SC-SGN-078: Stand in the wind: you drift sideways without running in place, and can still walk against it.
- SC-SGN-079: Interact to ride. Jump lets go. Grapple and attacks do nothing. Ride on into the next room.
- SC-SGN-080: Lift the crate: you walk slower and cannot jump. Throw it with Attack, or set it down with Interact.
- SC-SGN-081: Grapple the bottom of this box: the hook catches. You pass through it.
- SC-SGN-082: Grapple the sloped underside: the hook catches. You pass through it.
- SC-SGN-084: The solid edges here match the painted box exactly.
- SC-SGN-085: Walk up and down this slope smoothly.
- SC-SGN-088: The cabin from the market arrives here after crossing into this room.
- SC-SGN-091: Set the bomb fruit down by the bomb wall: when its fuse ends, the wall opens.

#### Hazards, switches, gates, secrets, water and light (61 checks)

- SC-TRAV-031: A pushable block stays on the floor, preserves wall art and keeps its position on re-entry.
- SC-LIGHT-006: Lit and unlit torch art follows its saved state on leaving and returning.
- SC-AUDIO-006: A crusher's slam sound and caption stay in its own room.
- SC-HAZ-001: This saw art shows when the saw is out and hides when it pulls back. Nothing new appears in the log.
- SC-TRAV-002: Fast travel, teleport and cross seams: each fades and arrives. With death drop on, die: money drops at safe ground. (partly checked)
- SC-SWCH-001: Pull a wrong lever first: fail sound, levers reset. Pull a, b, c: the gate opens. b is momentary and still counts.
- SC-SWCH-002: Prepare & Check reports a misspelled switch-order entry.
- SC-HAZ-002: These spikes hurt until you own Double Jump. Take the pickup, touch them again: no damage. (partly checked)
- SC-HAZ-003: Spikes: 1 damage, fade, back to safe ground. Pit: same, no death. At 1 health spikes kill. Dash through: no return. (partly checked)
- SC-HAZ-004: Hazard returns off, including spike damage, lethal pits and god-mode rescue.
- SC-SECR-001: Air-dash into the arrow wall: it breaks. Air-dash the plain wall: nothing. Sword on the star wall: nothing.
- SC-HAZ-005: Lava, acid and cold hurt. Take Heat Resistance: lava stops hurting, acid and cold still do. The lava gate lets you pass.
- SC-SWCH-003: Pull: the door opens and stays open after leaving, save and load, and streaming. The plate stays pressed after a reload.
- SC-SWCH-005: This gold gate needs every listed ability: it opens only once you own both Double Jump and Wall Jump.
- SC-SWCH-006: Open this gate, walk to the vault: its twin is open too. Save and load: both open, and the map shows both open.
- SC-SWCH-007: Pull the three levers (switch hall, vault, court) in any order: the hint counts up and the gate opens on the last.
- SC-SECR-002: Down + Ranged places a bomb; its fuse holds while paused. Only a bomb breaks this wall and finds the bomb secret.
- SC-SECR-003: Walk near the marked spot: nothing. Take Reveal Lens, walk near again: it reveals with a toast and a map marker.
- SC-SECR-004: Air-dash into the barrier: you stop and its map icon is locked. With Intangible Dash you dash through both ways.
- SC-SWCH-008: Pull the lever here, then walk to the court: its switch gate is already open. The local gate follows its lever.
- SC-SWCH-009: Sword, shot, down strike and slam each work only their own switch; others play the reject sound. The timed one holds in pause.
- SC-HAZ-006: Default blade: one hit per pass with knockback. Return blade: back to safe ground for Return damage. Kill blade kills.
- SC-HAZ-007: A safe-return pendulum deals damage when hazard returns are disabled.
- SC-AUDIO-001: Walk to the falls: the sound fades in and pans to its side. Between both sources: no louder. Leave, return: no stuck loop.
- SC-TRAV-008: Touch the summit checkpoint, come here, use the statue: fade, the summit loads, you stand at the checkpoint; 10 coins once.
- SC-SECR-005: Slash the pot: effect, sound, broken art, drops by chance. The crate prop clears its painted tiles. The barrel opens the door.
- SC-HAZ-008: Saws follow their line and path, the fire bar circles, the crusher warns, slams with dust, holds and rises. Pause freezes all.
- SC-HAZ-009: The painted saw moves with its hazard and leaves no copy behind. The floor under its start holds you; static spikes are unchanged. (partly checked)
- SC-WATER-001: Pull: the water drains, painted rows vanish one by one, swimming ends as the surface passes. The plate raises the other pool.
- SC-HAZ-010: Enter the room: the lava rises after its delay. A return or a death puts it back down. With Heat Resistance it does not hurt.
- SC-WATER-002: Swim until oxygen drops, enter the air pocket: it refills. Stand on the floating crate. Pull: it sinks with the water and rests.
- SC-LIGHT-001: Dark room: lamps and torches light the art with a soft warm edge, no yellow wash. The moving light keeps up.
- SC-LIGHT-002: Glow-only darkness builds without shader errors and leaves the title undarkened.
- SC-LIGHT-003: No carried light before the Lantern. Take it: a light follows you and flickers, even in a dash. Pitch Gallery: black without it.
- SC-LIGHT-004: Lantern radius, brightness and color changes in a fully dark room.
- SC-HAZ-012: Pause 5 s: the blade stands still, then continues. Pull the lever, pause past its reset: on resume the blade resets.
- SC-AUDIO-004: Listen: jump, a different double jump, station chime, checkpoint chime, save sound. The rock wall crumbles with a blast. (partly checked)
- SC-LIGHT-005: Changing the authored light shape preserves the intended torch-light size.
- SC-HAZ-013: Tile writes: level art hides and returns, the saw tiles hide and return, the crate tiles move, wall tiles clear.
- SC-CTRL-015: In this gate-heavy room: the Inventory arrows move and it closes; Escape opens a working pause menu; you can walk.
- SC-WSTATE-011: After Prepare & Check the crate tiles draw only on the crate, not also where it started.
- SC-SWCH-010: These levers are linked by Target with blank ids: one moves the water, the other frees the lurker.
- SC-TRAV-027: Put the crate in the socket, leave and come back: nothing invisible blocks where the crate first stood.
- SC-SGN-002: Walk in: the cave sound fades in and the room music ducks. Walk out: both return smoothly.
- SC-SGN-004: Exactly one looping sparkle effect plays at the foot of the waterfall.
- SC-SGN-005: Walk toward the falls: the sound fades in smoothly and pans to its side. Two sources together are no louder than one.
- SC-SGN-021: Swim here when oxygen runs low: it refills while you stay inside the bubbles.
- SC-SGN-022: Slash the pot: one effect and sound, broken art stays, a drop may fall. You can walk through it.
- SC-SGN-025: This lamp lights the dark around it at its set radius and brightness.
- SC-SGN-030: This blade hits once per swing and knocks you along. Its art swings with it from the first frame.
- SC-SGN-031: Dive in: the screen turns underwater blue. Climb out: the tint goes away fully.
- SC-SGN-032: Break the cracked wall: Secret found shows, the map reveals it and the reward comes, all once.
- SC-SGN-033: Pull the lever: this door opens, then shuts again after five seconds.
- SC-SGN-034: Swim: the current pushes, oxygen drains, water slows and lifts you. All return to normal when you leave.
- SC-SGN-036: Hit this cracked wall until it breaks: its tiles change and the secret behind it opens.
- SC-SGN-044: Pull: only its own door reacts. Pulling again at once does nothing until the cooldown ends.
- SC-SGN-048: Stand on the plate: its door opens. Step off: it closes.
- SC-SGN-053: Hit it with sword, shot, down strike, slam or bomb: it toggles. Enemy shots do not.
- SC-SGN-054: Interact: the torch lights and burns. Again: it goes out, unlit. Leave and return: it keeps its state and its picture.
- SC-SGN-056: Touch the Lift Summit checkpoint, then use this statue (10 coins): you return there with a fade.
- SC-SGN-083: Push the crate onto the plate: the plate presses and holds.

#### Enemies and combat (68 checks)

- SC-CMBT-002: Difficulty scales incoming hits, outgoing hits and weak points while pits remain lethal.
- SC-CMBT-003: Melee, shots and dash hits deal their usual damage; slide and dash i-frames protect you; the pit still kills. (partly checked)
- SC-CMBT-004: Defeat this enemy: your money rises by 10.
- SC-CMBT-005: Hard difficulty scales enemy and boss health, phase thresholds and currency rewards.
- SC-BOSS-001: Below half health the sentinel summons slimes: at most 4, they drop nothing, and they vanish when you win or lose.
- SC-BOSS-002: Leaving during a boss summon clears its minions before returning.
- SC-ENMY-001: An enemy dies and drops rewards once; summoned defeats identify their owner.
- SC-DEV-004: F4 ▸ Stats: labels follow each enemy and the boss. The DPS meter counts a weak-point hit once.
- SC-CMBT-007: Crits and heals keep their colours. In acid, pause a few seconds: health stays. Resume: ticks come at their interval. (partly checked)
- SC-ENMY-002: These two look alike but move, attack and take hits differently. The knight takes more hits.
- SC-ENMY-003: Archetype gallery: each pen holds one shipped archetype, named on its plate. Each moves and attacks as named; no two act alike. (partly checked)
- SC-ENMY-004: A new enemy archetype appears in the Tiled dropdown.
- SC-ENMY-005: An art-only enemy inherits the default archetype, with a warning if that default is removed.
- SC-ENMY-006: F2 physics view on: the summoned helpers show their own art and boxes and stand on the floor.
- SC-ENMY-007: The configured room summon cap limits a boss's minions.
- SC-ENMY-008: Enemy size appears as editable scale in the baked room collection.
- SC-ENMY-009: F2 physics view: each box matches its art and stands on the floor; the big marksman shoots from the right height.
- SC-ENMY-010: Hit both snails: the green one takes extra damage and flashes; the grey one shows IMMUNE, no damage or knockback.
- SC-ENMY-011: Enemy attack damage types use the player's configured resistance factors.
- SC-ENMY-012: A fire-only wall and fire hazard follow configured ability infusions and damage factors.
- SC-HAZ-011: Lava: a hit, then burning after you leave. Acid: poison and half speed inside. Cold slows strongly. Acid plus sticky: one slow.
- SC-HUD-009: Get Poison and Slow from the hazards: one chip each with its seconds. Pause: they hold, then resume.
- SC-HUD-010: Status chips can be hidden while the configured status damage still applies.
- SC-ENMY-013: Let the spotted slime hit you: you are poisoned. The block slime is immune to poison.
- SC-ENMY-014: Configured Burn and Freeze affect regular enemies and bosses appropriately.
- SC-CMBT-009: Shots travel straight ahead when directional aiming is disabled.
- SC-CMBT-010: Hold-to-aim releases a shot, yields to bombs and cancels cleanly on a jump or hit.
- SC-CMBT-011: Combat energy gains, attack costs, refusal sounds and infinite-energy testing.
- SC-CMBT-012: Channel healing spends energy, stops on a hit or empty energy and warns when energy is disabled.
- SC-ENMY-015: Each turret aims at you along its mount; with lead on its shots lead you. Hide behind the wall: they stop firing.
- SC-ENMY-016: Hit the knight with its guard up: BLOCK, a sound and flash, no damage. Guard down: normal damage. (partly checked)
- SC-ENMY-017: Defeat the ringed worm, touch the checkpoint. F4 ▸ Saves, type sw_guard: sw_guard_down is listed.
- SC-ENMY-018: A permanent enemy defeat advances a staged gate and is modeled by Analyze Progression.
- SC-ENMY-020: Enemy project defaults apply to placements that inherit them.
- SC-ENMY-021: Walk up: it charges, then helpers drop to the floor, never more than its limit. Defeat it: its helpers vanish.
- SC-ENMY-022: Summons remain after their owner falls when configured, and respect caps and cooldowns.
- SC-ENMY-023: The hive stays put and touching it is harmless; it charges before helpers. Hits on the stone hive: BLOCK. Ground Pound hurts it.
- SC-ENMY-024: Walk in: doors seal, travel refuses, Wave 1 of 2. Clear both: death clip, doors open, Area cleared, music, the door opens.
- SC-ENMY-025: Encounter project defaults apply to authored encounters.
- SC-ENMY-026: Watch the jumper a minute: it stays on the floor. Lure the brown mouse off the ledge: it lands below. Pit: dies, no loot.
- SC-ENMY-027: Archetype-level falling matches the corresponding per-placement behavior.
- SC-ENMY-028: Brown mouse falls off ledges. Blue patrols on top and drops only when chasing you. Grey turns at the edge.
- SC-ENMY-029: Art-only ground enemies inherit project falling and gravity settings.
- SC-ENMY-030: Front hits on the shield: BLOCK, spark, push back. From behind: damage. Heavy or parry opens it. Armor: three heavy hits. (partly checked)
- SC-ENMY-031: Red shield: only heavy hits from the front break its guard. Bronze worm: two bomb hits break its armor.
- SC-ENMY-032: Prepare & Check warns when a directional guard has no usable guard-breaking attack.
- SC-ENMY-033: The ladybug goes round every corner of the block, art turned to the surface. Lurkers hide until near; the lever frees the other.
- SC-ENMY-034: The fish stays in its pool and chases only when you swim in it; drain it with the lever: it idles. The frog hops the steps.
- SC-ENMY-035: Approach the swarm: a leader chases and the others circle it. Defeat the leader: another leads as the ring forms again.
- SC-ENMY-036: Defeat the splitter: smaller ones land. The puffer fires shots as it dies. The dark slime leaves a hazard that holds in pause.
- SC-ENMY-037: Approach clear of the doorway: the room seals, its named bar and music start, low on health it adds a dash. Win: reward once.
- SC-ENMY-038: This champion shows its named bar but never seals the room. Hurt it, leave and return: full health, no extra attack.
- SC-CMBT-013: Optional melee shot cutting and perfect-parry reflection, including pause and turning them off.
- SC-AUDIO-002: Fight a group: the combat track fades in; walk away: room music returns after the quiet delay. Bosses keep their own. (partly checked)
- SC-AUDIO-003: Prepare & Check warns about unknown or missing combat music.
- SC-CMBT-014: Optional parry tells on melee, shots and boss telegraphs across display filters.
- SC-ENMY-041: Defeat the gold mouse: gems drop, lifted and spread like a chest. The Bestiary drops line names them after enough defeats.
- SC-EQUIP-009: Random equipment drops grant eligible unowned rewards and stop when disabled or exhausted.
- SC-ENMY-042: Note where the brown mouse stands. Leave, go two rooms away, come back: it is still near there and fights normally.
- SC-ENMY-043: Hidden neighboring rooms keep their enemy and collision state when streamed into view.
- SC-ENMY-044: An enemy's temporary death hazard uses its configured width and height.
- SC-ENMY-045: Live shot and damage-number caps preserve player shots where possible and keep locked boss attacks intact.
- SC-ENMY-046: Lead the leashed wave-1 enemy away: it walks home, stops at its post and fights again.
- SC-ENMY-047: Champion room seals and health bars follow each placement's independent switches.
- SC-ENMY-048: Hiding a champion's bar works, and retired project seal settings produce a warning.
- SC-SGN-003: Walk in: the music changes to the authored track. It never switches to silence by mistake here.
- SC-SGN-018: Step in: doors seal, two waves come. Clear them: doors open, Area cleared, a reward drops and a door opens.
- SC-SGN-019: Wave 1 appears here after a short warning and lands on the floor. The marker itself stays invisible.

#### Bosses (32 checks)

- SC-BOSS-030: Boss entry locks, bars, defeat gates and the transition into the twin fight.
- SC-BOSS-031: Each boss health bar displays its authored name. (partly checked)
- SC-BOSS-032: A custom boss bar name and the blank-name fallback.
- SC-BOSS-004: Bosses without an intro animation start in idle.
- SC-BOSS-005: Start the fight: this wall blocks the exit in phase 1 and opens in phase 2. Win: it stays open. Lose: it blocks again. (partly checked)
- SC-BOSS-006: Phase 1: no adds. Phase 2: adds chase and shoot, never more than 2. Win: they vanish; none appear during the defeat. (partly checked)
- SC-BOSS-007: Configured boss adds remain after victory and clear on room exit.
- SC-BOSS-008: Parry a boss: it is stunned, no number, bar unmoved. Duo: after one falls doors and hazards stay until the other falls. (partly checked)
- SC-BOSS-009: Before the fight these spikes are invisible and harmless. In phase 2 they blink, then hurt. After the win they vanish. (partly checked)
- SC-BOSS-010: Arena gravity changes jump height only during the fight.
- SC-BOSS-011: Enter: the doors lock; win: they open. In the fight fast travel refuses, also in the beam boss fight (no arena object). (partly checked)
- SC-BOSS-012: Hit the Warden often: it is knocked down, takes extra damage, recovers. Parry: health never moves. (partly checked)
- SC-BOSS-013: A thin gauge under the Warden bar fills with hits and knocks it down when full. In phase 2 it never knocks down. (partly checked)
- SC-BOSS-014: A boss stagger gauge fits inside the health-bar area at different screen shapes.
- SC-BOSS-015: Both twins start; one intro; bars Twin Moss and Twin Stone, each with a gauge. One falls: doors, hazards, music stay; none saved.
- SC-BOSS-016: Three boss bars with long translated names fit both screen framings.
- SC-BOSS-017: A short boss death still clears the arena and plays one scene; rage survives pause.
- SC-BOSS-019: Beat the Sentinel: the gate atop the steps opens. Floor under the twins: no fight; climb: both start. Moss falls: Stone rages.
- SC-BOSS-020: A shared boss health pool and named group bar drain from hits on either partner.
- SC-DEV-005: Beat the Warden and save. F4 ▸ Boss practice ▸ Warden: you warp in, Saving off shows. Win: the game restarts from your save.
- SC-BOSS-021: Beat the Warden without taking damage: an extra large health pickup drops. On another slot take one hit: none.
- SC-BOSS-022: Push the sentinel past its first phase: flash and a camera shake. It fires a glowing beam along the line that hurts.
- SC-BOSS-023: Prepare & Check warns about obsolete configured arena hazards.
- SC-BOSS-024: Boss mines persist until triggered or timed out, and wave attacks draw as rings.
- SC-BOSS-025: At a phase change the camera shakes hard but the arena stays in view. (partly checked)
- SC-BOSS-026: Defeat one twin, quit, Continue, defeat both: each pays once and counts once in the Bestiary.
- SC-BOSS-028: Win the Warden fight: the locked doors open. In a sealed encounter: no Unlock prompt, Interact does nothing; clear it to open. (partly checked)
- SC-SGN-006: During boss phase 1 this wall blocks the exit. It opens in phase 2 and stays open after you win. (partly checked)
- SC-SGN-008: In boss phase 2 adds appear, chase and shoot; never more than 2. They vanish when the boss falls. (partly checked)
- SC-SGN-009: Entering locks the doors and changes camera and music. After the win, doors, camera and music return. (partly checked)
- SC-SGN-010: At half health the boss changes phase exactly once.
- SC-SGN-090: Hidden and harmless before phase 2. In phase 2 it blinks, then hurts. It is gone after the win. (partly checked)

#### Economy and progression (46 checks)

- SC-EQUIP-001: Take the container: its bar grows at once. Save, quit and load: still larger. Die before saving: back to the saved maximum.
- SC-ECON-001: Map station: Need 50 and no charge when short; 50 once when you can pay. Full energy: the station charges nothing. (partly checked)
- SC-ECON-002: A map station displays its currency cost using the chosen currency wording.
- SC-PROG-001: Pick up the key and the container: both work and their toasts show text. (partly checked)
- SC-PROG-002: Hurt, press Quick Use: the flask heals 2/2 to 1/2. A hit stops a drink. Small Health does not refill it; resting does.
- SC-PROG-003: Potion-only healing removes the flask and keeps the quick slot clear in every HUD layout.
- SC-PROG-004: Journal ▸ Relics shows 0 of 2. Take a relic: 1 of 2 with its text. Read the lore: it opens in Journal ▸ Lore.
- SC-ECON-003: Take this pickup: Inventory ▸ Items shows Red Key x2.
- SC-EQUIP-002: Take three pieces: Health fragment 3/4. Save and load. Take the fourth: max health +1 at once. Reload: no second bonus.
- SC-EQUIP-003: A changed fragment count completes a health container at the configured number.
- SC-ECON-005: Take both potions. Hold Quick Use until Small Potion shows; hurt, tap: you heal. Items then lists Small Potion x1.
- SC-ECON-009: A store with full sale share buys an eligible potion at its full price.
- SC-ECON-010: Health Boost II reads Requires Health Boost I. Buy I: the bar grows and stays after a reload. Damage Boost: light hits read 1.05.
- SC-ECON-011: Learn Double Jump from the first trainer, use it at once; kept after a reload. Glide shows Learned. The second leaves when done.
- SC-ECON-012: Without money the altar changes nothing. Then Yes: 10 coins, +1 max health. Reload: it refuses. The other altar vanishes.
- SC-ECON-013: Deposit 100, die, Continue: the bank keeps it, only carried money dropped. Withdraw: HUD money rises. Records shows Banked.
- SC-PROG-005: Play with a stopwatch, pausing it for menus and talk. Die twice. Records: Deaths 2 and a matching play time.
- SC-PROG-007: Level gains, health growth and refill, notices and saved XP after Continue.
- SC-PROG-008: Authored enemy XP rewards and the Level and XP HUD at different sizes.
- SC-PROG-009: Defeat a slime: New bestiary entry. Another slime: none. The ladybug counts as its own species: a second notice.
- SC-PROG-010: Defeat a slime, open Journal ▸ Bestiary: name, idle picture, Defeated 1; others show ???. Three defeats show its drops.
- SC-PROG-011: A missing Bestiary species description produces a preparation warning.
- SC-PROG-012: In an F4 test session defeat three: no notice. End it. Defeat three: First Victories and 10 coins. Another slot: nothing.
- SC-PROG-013: Journal ▸ Achievements: First Victories unlocked, Growing Stronger described, 1 / 2 unlocked (0 hidden).
- SC-PROG-014: Talk to the Wanderer: Quest started. Walk into the trigger: Quest complete. Talk again: 100 coins and an Upgrade Material.
- SC-EQUIP-004: Speed: faster on flat, slope and ice. Invincible: no damage from spikes or the return pit, but lava still kills. Pause holds.
- SC-EQUIP-005: Take the maul: notice, it equips, the weapon block shows it. Take the caster: C or stick click cycles. The blade pays coins.
- SC-EQUIP-006: Turning Weapons off preserves ordinary combat and hides Next Weapon.
- SC-EQUIP-007: Take both charms and the slot. Inventory ▸ Charms: Slots 0/4, then 2/4. Vitality adds max health without healing.
- SC-EQUIP-008: Inventory ▸ Crafting with under 100 coins: Heavy Maul tier 2 shows what is missing; confirming spends nothing.
- SC-PROG-015: Collect one upgrade, open Journal ▸ Records: Completion N% with found of total. Reach the ending: its first page adds it.
- SC-ECON-015: Walk the floor: no trial. Interact: doors close, countdown, two waves. Under 20 s: rank, time, 25 coins, once.
- SC-ECON-016: The start screen shows goal, ranks and best result. Pause in the countdown and fight: the clock stops. Records shows Trials.
- SC-ECON-017: A combat trial uses the configured start countdown.
- SC-ECON-018: This trial lists Dash and Ranged attack as blocked. During it they do nothing; after 20 s they work again.
- SC-PROG-023: Level and play-time HUD labels display values and follow the selected language.
- SC-ECON-019: Purchases report their rewards without forced saving, and a finished trainer leaves.
- SC-SGN-026: Locked: carry the red key to open it. The key is not used up.
- SC-SGN-035: Deposit, die and continue: banked money stays. Withdraw raises your money. Records shows Banked.
- SC-SGN-037: Interact to start: doors seal, two waves come. Win in 20 s for the top rank and 25 coins, once.
- SC-SGN-040: Use it with energy spent: it restores energy exactly, then waits out its cooldown.
- SC-SGN-042: Use it when hurt: it heals exactly what you lost, a limited number of times.
- SC-SGN-047: Interact: it asks 10 coins for +1 max health. Yes pays once; after a reload it refuses.
- SC-SGN-051: Get coins (funds chest or F4). Learn Double Jump and use it at once. Glide shows Learned.
- SC-SGN-055: Health Boost II needs Health Boost I. Buy I: the health bar grows at once and stays after save and load.
- SC-SGN-059: With the Wanderer's quest active, walk in: its objective advances once.

#### World map, regions and travel (26 checks)

- SC-MAP-002: Hurt, then Activate with Interact: sound, health and flask refill, a map marker. Interact again: travel map, no refill.
- SC-MAP-003: Activate two stations, travel from the pause menu: fade out, hold, fade in. In a locked boss fight travel is refused.
- SC-MAP-005: Visit the market: the map shows the shop icon. Walk near the hidden marker: its icon shows and stays after unloading and a reload.
- SC-MAP-007: Rooms without their own music play their region track; the lagoon plays its own; Pitch Gallery is silent. Map tints by region.
- SC-MAP-010: Walking through a snapped door between the mine and the fully dark gallery.
- SC-MAP-011: Note the loading screen time. Walk through ten rooms: no missing floors, nothing pops at the seams.
- SC-MAP-013: Walk into a new region: its card shows name and subtitle once. Pause: the info line names the region.
- SC-MAP-014: Region cards on every entry fit the screen and shorten long names.
- SC-MAP-015: Region cards and the pause location line use translated region names.
- SC-MAP-016: Walk into a second room, open Pause ▸ World Map: it opens at its usual zoom and fog, unexplored rooms hidden. Esc closes.
- SC-MAP-018: D-pad Up opens the map. Right stick zooms one step, LT out, left stick pans, Right Stick click recentres. Wheel, drag, E/Q, W/D, C work.
- SC-MAP-020: The map shows a legend, a centre cross and a panel naming region and room. Region names show only over visited rooms.
- SC-MAP-022: In the map press X: six stamps, Star. Stick right: Important. A places a red !. Stamp three rooms; the minimap shows boxes.
- SC-MAP-023: Saved map stamps move with a relocated room and obey the marker limit.
- SC-MAP-024: At detail zoom the chest and pickup show icons; open the chest: faded, Opened. Take the pickup: the room tints green.
- SC-MAP-025: The minimap shows shapes at the chest, pickup and save point. Learn trainer B out: its map icon goes.
- SC-MAP-027: Open travel at a station near the map centre and press Down: the next stop is picked and stays. The mouse picks by pointing.
- SC-MAP-028: Zoom in one level at a time: the whole screen shows sharp outlines at every level, no blurry bands.
- SC-MAP-029: Zoom in and pan to every corner: each visible corner is sharp.
- SC-SGN-017: Take the scroll: Lockstone Works shows on the world map, once.
- SC-SGN-027: Walk near this flag: a marker appears on the world map at this spot.
- SC-SGN-045: Use it (50 coins): this area shows on the map, once.
- SC-SGN-066: Interact: the station activates once and refills health and flask. Interact again: the travel map opens.
- SC-SGN-076: Step on: a fade takes you to the barracks pad, facing the right way. The pad waits a cooldown.
- SC-SGN-086: Step on: you return to the guild pad. Arriving does not send you straight back.
- SC-SGN-087: This station costs 999. With less, it refuses and neither charges nor heals you.

#### World state, countdowns, NPC life, story, goals, endings and extras (51 checks)

- SC-NPC-001: Stand right beside the walker while it talks: does your sprite cover its line? Tell us if the line should sit higher.
- SC-NPC-002: This room is away from the layout origin: walking in starts the talk and the scene here.
- SC-STORY-001: Cutscene triggers and their scene identities appear in the prepared room collection. (partly checked)
- SC-STORY-002: Each scene plays once. The set-flag scene opens the requires scene and turns off the skip-if scene.
- SC-STORY-003: Prepare & Check reports an unknown cutscene on a trigger.
- SC-STORY-004: Caption lines advance on their own. Hold Jump 0.8 s: the scene ends without a jump. Pause and Resume: you still cannot move.
- SC-STORY-005: Disabling skip prevents held Jump from skipping; choices and flag-changing dialogue stay unskippable.
- SC-PROG-006: The play timer shows top right. Finish the quick ending: Time h:mm:ss. Faster on another slot: Records keeps the best time.
- SC-END-001: Finish without pulling the Pitch Gallery lever: the main ending. On another slot pull it first, then finish: the other.
- SC-END-002: An added ending previews and plays its own title, text and credits.
- SC-END-003: Finish the main ending on one slot and the other on another. Records lists 2 of N endings with best times.
- SC-END-004: Reach an ending, quit. Select the slot: New Game+ in the legend. G then Cancel: nothing. G then Yes: a new cycle starts.
- SC-END-005: Take this ability: Extra unlocked with its title shows once. Quit and Continue: no second notice. (partly checked)
- SC-END-006: An Extras unlock flag with no writer produces a preparation warning.
- SC-PROG-018: New goal: Find the Dash. The goal line sits under the money, clear of prompts. Journal opens on Goals.
- SC-PROG-019: The enlarged goal HUD fits; disabling Goals removes its tab, line and notices.
- SC-END-007: Fresh profile: the title has only PLAY GAME and LAYOUT EDITOR. After an ending EXTRAS appears below; Enter, pad and mouse open it.
- SC-END-008: After an ending open EXTRAS ▸ Jukebox: Stop music and the region tracks. Play one: Playing at your music volume. E opens Credits.
- SC-END-009: Pull this lever (it sets sw_alt_ending): Extra unlocked. Title EXTRAS ▸ Gallery shows the image with its caption. (partly checked)
- SC-END-010: Prepare & Check rejects an Extras image whose filename uses unsupported characters.
- SC-WSTATE-003: Pull the lever, walk into the next room for 2 s, come back: Lumi is gone. The second lever removes the pink NPC at once.
- SC-COUNT-001: A cross-room escape countdown holds in pause, refuses saves, times out and restarts safely.
- SC-COUNT-002: Pull the alarm: a red tint and a clock start; the vault seals a door. Run to the Switch Hall flag before time runs out.
- SC-WSTATE-005: Pull the lever, walk into the mine: the green NPC is there. Walk back: Lumi is gone. Fresh slot: the mine sign is absent.
- SC-WSTATE-006: A misspelled NPC presence flag produces a warning with the likely intended flag.
- SC-COUNT-004: Countdown clock formatting, warning color, pause, timeout, restarts, scaling and hidden-clock mode.
- SC-PROG-020: The stone prompt shows Inspect (5). Short of 5: it says so and charges nothing. With money: hint, 5 taken once, then free.
- SC-PROG-021: Goal-target map rings work without item icons, missing targets warn and disabled Goals stay free of charges.
- SC-NPC-004: A ! floats over the guide. Talk to the end: it goes. Pull the lever: it returns until you talk again; then it stays gone.
- SC-NPC-005: Disabling new-dialogue markers hides the NPC marker.
- SC-WSTATE-010: The pit in the corridor is open. Pull the lever: rubble fills it at once. It still holds you after leaving and a reload.
- SC-NPC-006: The walker paces, faces where it walks, says a line when you come near, stops and turns to you. Pause and talk: it holds.
- SC-NPC-007: Disabling ambient NPC lines prevents barks.
- SC-NPC-008: Journal ▸ People (fourth tab): ??? rows and 0 met. Talk to the Wanderer: its row names it and shows the bio and Last said.
- SC-NPC-009: People titles, biographies and last lines translate, and the unmet-people switch hides unknown people.
- SC-COUNT-006: Left ledge: 1:30 starts. Off and on: it keeps running. Middle ledge: Cancelled. Right ledge: Finished and your time.
- SC-COUNT-008: During a run: no travel entry in the pause menu, FT2 keeps you here, the statue shows its blocked text and charges nothing.
- SC-COUNT-009: Prepare & Check warns about an unknown countdown music track.
- SC-NPC-010: This NPC has only its type barks: walk near and they show.
- SC-PROG-022: Finish the last goal by holding a Small Potion, drink it, save, quit, Continue: no goal comes back on the HUD or in the Journal.
- SC-STORY-006: This scene starts a quest, so it cannot be skipped. The quest starts.
- SC-PROG-024: Goals still advance: the dash pickup finishes the ability goal, holding a Small Potion finishes the item goal.
- SC-END-011: Play a room with music, quit to the title, open Extras ▸ Jukebox: no row says Playing.
- SC-STORY-007: Two captions show above the skip hint, one with a speaker. Caption background Off, Dim and Solid differ. Holding skip hides it.
- SC-STORY-008: The clip with no file shows your title card, never CUTSCENE TEST CLIP. With Captions On the other plays its subtitled version.
- SC-STORY-009: A missing video with blank fallback text continues the scene without a card.
- SC-STORY-010: With Captions On, a sound caption shows at most once per repeat gap.
- SC-SGN-038: Walk in: a short scene plays once, with two captions. Hold Jump to skip it.
- SC-SGN-039: Walk in: a short conversation starts. Walk in again later: it starts again.
- SC-SGN-057: Step on the left ledge: a 1:30 clock starts at the bottom. It holds while paused. Reach the right ledge.
- SC-SGN-058: Touch to end the game: the ending saves once, credits page through, Continue follows the setting.

#### Creator windows and Prepare & Check (77 checks)

- SC-EDIT-063: Every active attack has editable settings, applies changed damage and rejects invalid timing.
- SC-EDIT-001: Each exported gameplay object appears once as an editable room gameobject.
- SC-EDIT-002: Preparation Status is fresh and the prepared grapple point catches the hook.
- SC-EDIT-003: Game Settings ▸ Grapple exposes hanging, pumping and braking with help and reset controls.
- SC-EDIT-004: Analyze Progression gives ordered routes and explains uncertain fight and puzzle routes.
- SC-EDIT-005: Directed progression links require the annotated ability before an area is reachable.
- SC-HUD-004: Dash a few times: the stamina bar drains and refills.
- SC-HUD-005: Disabled resource bars close their HUD gaps while movement and save/load still work.
- SC-EDIT-006: Prepare & Check reports an energy gate or pickup when the energy resource is disabled.
- SC-EDIT-007: Gameplay events fire once for defeats, pickups, chests and deaths, and stay silent during save restoration.
- SC-EDIT-008: The prepared world's flag ledger has no unexpected warnings.
- SC-EDIT-009: Unknown flags identify room, object, property and likely spelling; strict errors block Build.
- SC-EDIT-010: Prepared Tiled dropdowns list the current keys, gate abilities and regions.
- SC-EDIT-011: Adding and removing an NPC type refreshes the Tiled dropdown.
- SC-EDIT-012: Running Prepare & Check twice leaves generated cutscene content unchanged.
- SC-EDIT-013: The world census lists all published rooms and their collectibles, bosses and travel points.
- SC-EDIT-014: Catalog warnings remain readable and valid content still builds.
- SC-EDIT-015: Invalid NPC, sound and ability choices identify their source, with the appropriate error or warning.
- SC-EDIT-016: A boss summon using a missing enemy type produces a preparation warning.
- SC-EDIT-017: Baked enemies retain their placed defeat identity in the room collection.
- SC-EDIT-018: The Movement test preview skips the game's opening scene.
- SC-EDIT-019: Fast-travel settings and Analyze Progression respect a boss-unlocked destination.
- SC-EDIT-020: Ability markers and dash-only walls supply the right requirements to Analyze Progression.
- SC-EDIT-021: Analyze Progression recognizes a High Jump ability marker.
- SC-EDIT-022: Analyze Progression models either of the abilities accepted by an any-ability gate.
- SC-EDIT-023: Analyze Progression models the cross-room elevator route.
- SC-EDIT-024: The Lantern pickup appears in Tiled and is required for the annotated dark-room route.
- SC-EDIT-025: An unmarked fully dark room produces a preparation warning.
- SC-EDIT-026: Game Settings ▸ Languages saves the default language and language-choice visibility.
- SC-LANG-011: A redistributable CJK font displays the translated text in a real build.
- SC-EDIT-027: Analyze Progression excludes phase-controlled arena hazards from permanent barriers.
- SC-EDIT-028: Encounter zones and spawn points are editable room objects whose markers remain hidden during play.
- SC-EDIT-029: Invalid encounter content produces the expected preparation warnings and blocking errors.
- SC-ENMY-039: Champion defaults apply after clearing placement overrides, with preparation notices.
- SC-EDIT-030: Analyze Progression treats a champion's reward as requiring an unproven fight.
- SC-ENMY-040: The Creator Guide's champion recipe works in a fresh toolkit copy.
- SC-ECON-007: Game Settings ▸ Game ▸ Shops accepts and applies the configured sale share.
- SC-EDIT-031: Analyze Progression treats a trainer-only ability as an uncertain purchase rather than a blocked route.
- SC-ECON-014: Invalid economy costs, rewards and catalogs report the object and a useful correction.
- SC-EDIT-032: A quest trigger bakes its selected quest and action into the room collection.
- SC-EDIT-033: A quest trigger naming no quest blocks preparation and identifies the object.
- SC-EDIT-034: Collectible dropdowns retain all ability pickups after preparation.
- SC-EDIT-035: A trial linked to an encounter with the wrong start mode produces a useful error.
- SC-EDIT-036: Analyze Progression treats a combat-trial reward as needing a playtest.
- SC-EDIT-038: Game Settings ▸ Ending ▸ Credits ▸ Edit lines keeps added, edited and removed lines.
- SC-EDIT-039: Progression diagnostics assign an authored door to the correct logical area.
- SC-EDIT-040: Compressed Tiled room layers prepare in the editor, and errors avoid repeated location prefixes.
- SC-EDIT-041: Prepare & Check and Preparation Status report world budgets and unchanged rooms on a second run.
- SC-EDIT-042: The tile-rendering budget estimate agrees with real engine limits in a dense view.
- SC-EDIT-043: A twelve-room chain warns about distant save points and dead ends, and obeys the lint switch.
- SC-PROG-016: Game Settings ▸ Progression ▸ Goals saves valid settings and starts the game successfully.
- SC-PROG-017: Prepare & Check rejects invalid goal definitions.
- SC-MAP-008: The world census and Game Settings ▸ Map ▸ Item tracking expose object names and tracking settings.
- SC-MAP-009: A custom item-tracking condition starts without a configuration error.
- SC-EDIT-044: Preparation Status offers confirmed engine-limit changes and raises only the recommended settings.
- SC-EDIT-045: Generated-file counts match the prepared files and identify unused resources.
- SC-EDIT-046: Game Settings ▸ Game ▸ Large worlds exposes warming, hidden-enemy and live-effect limits.
- SC-WSTATE-001: Invalid world-state conditions and unwritten flags produce preparation and progression diagnostics.
- SC-WSTATE-007: A conditional tile layer bakes as its own editable object and follows its flag.
- SC-WSTATE-008: Duplicate conditional tile-layer names are rejected during preparation.
- SC-EDIT-047: Repeated preparation preserves needed generated files and builds playable rooms.
- SC-EDIT-048: Removing a chest removes its unused generated resources without warnings.
- SC-EDIT-049: Shared generated prototypes keep per-object values editable and preserve collected items after Continue.
- SC-EDIT-051: Repeated Prepare & Check gives the same result with NPCs, world-state layers and Extras images.
- SC-EDIT-052: Rooms still build and play with the default generated-room folder.
- SC-EDIT-053: A custom generated-room folder prepares, builds and plays across rooms.
- SC-ACC-009: Game Settings ▸ Accessibility applies new defaults and hides unselected player options.
- SC-ACC-010: Disabling assist hides its rows, and achievement restrictions distinguish assisted and clean saves.
- SC-EDIT-054: Prepare & Check picks up a new authored NPC dialogue without restarting Defold.
- SC-EDIT-055: Project ▸ Dialogue Editor... saves a new sequence that the assigned NPC speaks.
- SC-EDIT-056: Dialogue editing supports reverting, confirmed rename or deletion and unsaved-close warnings.
- SC-EDIT-057: Dialogue choices with links and quest actions play as authored.
- SC-EDIT-058: Project ▸ Loot Tables... creates a table with item amount and chance choices.
- SC-EDIT-059: Loot Tables rejects invalid chances and warns about repeated item types.
- SC-EDIT-060: Loot Tables saves overrides, reverts shipped tables and deletes custom tables.
- SC-EDIT-061: An enemy and chest use an authored loot table, and Bestiary text names its items.
- SC-EDIT-062: Analyze Progression's documented limit for grapple-only ledges matches its report.

#### Tiled extensions (6 checks)

- SC-TLD-004: Opening the template test world in Tiled.
- SC-TLD-013: Save as Template Preset... writes a reusable hazard preset into the chosen folder.
- SC-TLD-014: Editing a hazard preset updates both placed copies.
- SC-TLD-015: A per-placement override survives exporting rooms that use a preset.
- SC-TLD-016: Preset placements prepare without warnings, share damage and keep individual knockback overrides.
- SC-TLD-017: Saving an existing preset offers a confirmed update before overwriting it.

#### Steam add-on On (5 checks)

- SC-STEAM-001: Steam achievements unlock once with the add-on on, and turning it off leaves no Steam errors.
- SC-STEAM-003: Prepare & Check generates Steam Cloud paths and rich-presence text, including renamed regions.
- SC-STEAM-004: Playing through regions with Steam app 480 produces no Steam errors.
- SC-STEAM-005: Custom rich presence shows the current region and title through the creator's own Steamworks app.
- SC-STEAM-006: Steam Cloud carries saves, deletions and offline conflicts between two PCs using an uploaded build.

#### Spine add-on On (5 checks)

- SC-SPINE-001: A Spine boss plays its intro once and then loops idle.
- SC-SPINE-002: Spike and pit returns with the Spine player.
- SC-SPINE-003: Ice sliding, skidding and jumping off with the Spine player.
- SC-SPINE-004: Hang bars and climb meshes with the Spine player, including hand placement.
- SC-SPINE-005: Straight and angled bounce pads launch the Spine player.

#### Large world and stress (4 checks)

- SC-SCALE-001: A dense room of enemy death effects and drops stays within engine buffers.
- SC-SCALE-002: World-map opening time and frame time in a large stress world.
- SC-SCALE-003: Deepest map zoom and panning performance in a large stress world.
- SC-SCALE-004: Defold and language-server peak memory while opening a large stress world.

### Also not yet verified

Game Settings ▸ Languages ▸ Glyph generation ▸ On demand has not been run in a real build. Built with the game is the default and was checked.
