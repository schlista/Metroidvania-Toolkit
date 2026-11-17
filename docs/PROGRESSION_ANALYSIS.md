# Checking progression

The optional **Layout Editor → Progression** panel analyzes current placement
without publishing it. It is hidden by default; set `ui.enabled=true` in
`developer/config/progression_analysis.lua` to show its preview controls.
**Project → Analyze Progression** analyzes the exported world. **Prepare & Check**,
**Layout Export**, and **Export Game** also check the model. Reload editor scripts
and rebuild after updating the toolkit.

The search follows doors, teleporters, logical areas, pickups and supported gates.
Inventory, collected rewards, opened locks and visited objectives remain separate
for each route. Preview state never changes a player save.

Warp Statues add no graph edges: they return only to a Checkpoint, Save Point or
Fast Travel Station the player has already reached.

Gate **Requirements** combines **Required ability** with the **Required abilities**
checkbox list. **Requirement logic** `all` needs every distinct ability; `any`
needs one. A blank or `none` singular field retains the preset's default;
`ability_requirement` and `ability_marker` have empty defaults for list-only
gates. An empty combined set has no ability requirement. This applies to ability,
height, hazard and destructible gates, including hidden ability markers.
For example, `double_jump` or `air_dash` allows either pickup route. Action
barriers and breakable walls that accept hits from several abilities also use
alternatives. Core attacks still need no unlock. Undefined ability ids remain
unknown and produce a warning; movement and combat still need playtesting.

The search evaluates alternatives together with mandatory requirements.
Its locked-upgrade and cycle diagnostics scan only mandatory AND abilities;
one alternative cannot be treated as a required dependency.

Intangible Barriers require both `intangible_dash` and `air_dash`. With
`player_settings.lua`'s `intangible_dash.during_slide=true`, they require
Intangible Dash plus either Air Dash or Slide, using the same merged player
settings as the game. Turning `during_air_dash` off requires Slide when slide
passage is enabled; disabling both modes blocks the crossing. **Starts open**
does not bypass these requirements for an Intangible Barrier.
Each crossing checks these abilities again: traversal
does not grant a persistent gate or group opening. Map accessibility describes
those owned abilities; it does not satisfy the runtime unlock check. Prepare &
Check warns with `intangible_barrier_too_thick` when the width, or the height
in eight-direction mode, exceeds scaled Air Dash speed × duration. Passage,
safe exit after a dash and collision timing still need a playtest.

## Purchased rewards

Shops, upgrade stations, skill trainers and NPCs with **Vendor ▸ Vendor shop**
set contribute possible catalog rewards: abilities, inventory keys/items, grant
flags, fast-travel unlocks and each entry's success flag. The report marks these
rewards **Unknown**: bought with currency; affordability is not modelled.
A route whose only required ability is sold by a trainer is uncertain instead
of blocked. Stock, material costs, access flags and purchase prerequisites still
need playtesting. A vendor's **Vendor flag** is named in its uncertainty reason;
the analysis does not assume the vendor is open. Other NPC dialogue rewards
remain unmodeled.

## Results

- **Reachable:** a modeled route satisfies the requirements. Select an objective
  for acquisition steps. This does not prove platforming or combat is playable.
- **Blocked:** completed search found no satisfying modeled route. Select Gates
  or Objectives for unmet requirements or an obstruction.
- **Unknown:** geometry or unsupported behavior prevents a conclusion.
- **INCOMPLETE:** a time/state bound was reached. Known paths remain useful;
  unreached results are unknown, not proven impossible.

The campaign asks whether **one run** can visit every required objective. Two
routes spending the same key cannot be combined. Optional objectives have their
own results. With no required objectives, the report explicitly says so.

## Tiled annotations

Add custom properties to existing maps/objects. They describe connectivity;
they never change collisions, grant rewards or create new runtime objects.

| Where | Property | Type | Meaning |
| --- | --- | --- | --- |
| Map | `progression_open` | Bool | Asserts an unsplit room is internally traversable; its area is `main`. |
| Map | `requires_light` | Bool | Requires `light_ability` when entering from an area outside light-required rooms. Internal movement and exits gain no light requirement. |
| Map | `progression_areas` | String | Comma-separated internally traversable areas: `entry,upper,vault`. No connections between areas are assumed. |
| Map | `progression_doors` | String | Door assignments: `left=entry,right=vault,up=upper`. |
| Map | `progression_links` | String | Directed connections between declared areas: `entry>ledge=wall_climb`. Separate links with commas; join required abilities with `+`. Omit `=...` for a free connection. |
| Map | `progression_required` | Bool | Requires reaching the first declared area. |
| Pickup, teleporter, objective object | `progression_area` | String | Area containing this object. |
| Existing gate/locked door/barrier | `progression_from`, `progression_to` | String | Areas on either side of the barrier. |
| Existing barrier | `progression_one_way` | Bool | Asserts physical traversal is only from → to; does not change gameplay. |
| Any existing visible object | `progression_objective` | String | Unique objective ID at this location. |
| Objective object | `progression_optional` | Bool | Excludes it from required campaign visits. |

Area names use letters, digits, underscores, dots or hyphens. Config references
use `room_id:area_name`. Multiple doors on one side can use saved coordinates:
`right:512:128=vault`. Coordinates are `cx`/`cy` in the exported layout's `doors`,
not Tiled object coordinates. Neighbor records supply the actual room connections.

Mark rooms the player cannot cross without light with `requires_light=true`, including
every darkness-1 room without an always-lit route. Darkness **1** is fully dark in
Light mask mode. `developer/config/progression_analysis.lua` sets `light_ability`
to `lantern`; a blank value disables both the light gate and its warning.
Darkness alone never creates a progression requirement. An unmarked room at
darkness **1 or more** gives the `dark_room_unmarked` warning; it remains ungated.
A room whose own lights already show the way may ignore that warning. Nearly
black rooms below 1 still need marking by hand when light is necessary.
For a dark Screen Effect Zone inside a room, use a directed `progression_links`
annotation such as `entry>deep=lantern` instead.

Example: declare `entry,vault`, assign `left=entry,right=vault`, put
`progression_from=entry` / `progression_to=vault` on the locked door, and
`progression_area=vault` on the upgrade. It cannot be collected from the entrance.

For a room whose `progression_areas` already lists `entry,ledge`, with a
`wall_climb` pickup in `entry` and an objective in `ledge`:

1. In Tiled, choose **Map ▸ Map Properties…**.
2. In the **Properties** panel, click **Add Property (+)**.
3. Enter `progression_links` in **Property name**.
4. Choose **string** from the adjacent type list.
5. Press **Enter** to add the property.
6. Set the new property's value to `entry>ledge=wall_climb`.
7. Choose **File ▸ Export Current Room**.
8. Choose **Project ▸ Reload Editor Scripts** in Defold.
9. Choose **Project ▸ Prepare & Check**.
10. Choose **Project ▸ Analyze Progression**.
11. Open `developer/assets/tiled/progression_diagnostics.txt` to inspect the route.

The route must collect the ability before crossing to `ledge`. Links describe
the room's existing geometry; they do not alter movement or collisions. For a
return route, add `ledge>entry` as a second comma-separated link. For a crossing
that needs two abilities, use `entry>ledge=wall_climb+double_jump`.
An unknown area, an empty ability name or a link without declared areas reports
`invalid_progression_link` once for that entry.

For an invisible ability crossing in a room that already declares `entry,ledge`
in `progression_areas`:

1. In Tiled, select the top-level **templates** layer.
2. Place the `interaction/gate.tx` template at the crossing.
3. Set `gate_id` to a unique id such as `upper_ledge_marker`.
4. Set **Gate type** to `ability_marker`.
5. In **Requirements**, set **Required ability** to `double_jump`.
6. In the **Properties** panel, click **Add Property (+)**.
7. Enter `progression_from` in **Property name**.
8. Choose **string** from the adjacent type list.
9. Press **Enter** to add the property.
10. Set `progression_from` to `entry`.
11. Click **Add Property (+)**.
12. Enter `progression_to` in **Property name**.
13. Choose **string** from the adjacent type list.
14. Press **Enter** to add the property.
15. Set `progression_to` to `ledge`.
16. Choose **File ▸ Export Current Room**.
17. In Defold, choose **Project ▸ Prepare & Check**.
18. Choose **Project ▸ Analyze Progression**.

The marker is a baked room gameobject. It draws no sprite, has no blocking
collision, shows no proximity hint and supplies no minimap or world-map icon.
The room geometry must enforce the crossing; the marker only describes it.
Keep the Tiled object visible so the analyzer includes it.

Unannotated rooms are unknown internally. Missing barrier endpoints make the
room uncertain even with `progression_open`. Incomplete split-room annotations
permit only speculative connections. Hidden objects supply no rewards; gameplay
objects nested in groups cannot establish a known route.

## Controls and configuration

Click the category button to cycle Areas, Gates, Objectives, Diagnostics,
Abilities, Items, Flags, Presets and Start. Select a row, then use **Apply** to
toggle an ability/flag, select a preset, or set the start area. **+ / −** changes
item counts. **Run** rereads project files and current placement. **Prev / Next**
pages results. Full paths remain in the text report.

Map labels show status words and color, including separate logical areas.
Placement changes clear stale results; disk edits need an explicit Run. Closing
the panel restores labels. Preview overrides last for the editor session.

New-game state uses ability metadata, then `ability_defaults.lua`, then published
wizard overrides. Presets and session edits overlay that state. No save slot or
local wizard draft is read. Default start is the first placed room's first area.

The commented `developer/config/progression_analysis.lua` defines presets,
objectives, bounds and optional map annotations for sources you cannot edit.
Objective conditions support `abilities={id=true}`, `items={key_red=2}`,
`flags={boss_defeated=true}`, and `resources={energy=3}`. Conditions are ANDed;
unknown predicates are unknown. Preset item aliases such as `red` normalize to
`key_red`. These settings describe analysis, not runtime gameplay rules.

### World pacing

Analyze Progression and every publication check (Prepare & Check, Layout
Export, Export Game) also check pacing. The `pacing` block in
`developer/config/world_lint.lua` controls it:

- `enabled` (default `true`) turns the pacing lines on or off.
- `max_rooms_without_save` (default `8`) is the most room-to-room hops a placed
  room may be from the nearest save point, checkpoint, fast travel station or
  the start room.
- `dead_end_info` (default `true`) adds an info line for each room with one exit
  and no save point, reward, map station, vendor or other counted content.

Rooms connect through doors, elevators, zip lines, vehicles and teleporters.
Fast travel does not count, because a station must be reached first, and gates
are ignored. Hops ignore room size, so a world of very large rooms may need a
lower limit. Hidden objects and objects inside Tiled groups are not anchors.

Pacing gives at most one warning per kind, naming six rooms and counting the
rest: `pacing_rooms_without_save` and `pacing_unreachable_room` (a placed room
that no route reaches from the start room). Dead ends are `pacing_dead_end_room`
info lines, one per room. Pacing never blocks publication or Build, and it
skips a model that already has errors. Warnings also appear in Project ▸
Preparation Status; info lines stay in the report.

### Goal targets

When Goals is on (Game Settings ▸ Progression ▸ Goals), Analyze Progression and
every publication check read each goal's `target` in
`developer/config/goals.lua`, with your saved Game Settings applied:

- `goal_target_missing` (error) means no visible object in a room placed in the
  Layout Editor has that `progression_objective`, or no placed Map Marker has
  that `marker_id`. An objective listed only in config does not count. This
  error blocks publication until the target exists or the goal is corrected.
- `goal_target_blocked` (warning) means the search reports the target objective
  as blocked or unknown. Marker targets have no objective, so they get no
  warning. The warning never blocks publication.

A disabled goals config is not checked.

## Runtime rules and limits

The pure requirement evaluator is also used by the runtime gate manager.
Locked doors check ability and key/item, consume one key when configured, and
remain open on that branch. Item gates honor preset consumption. Inventory and
ability collectible presets are read from configuration. Pickups are one-time
rewards; respawning inventory sources make the economy uncertain. True flag
requirements follow `Flags.has`, including non-boolean set values.

Teleporters are directed: `one_way=true` means receive-only. Explicit targets,
pair fallback and required flags follow runtime rules. No modeled return path
produces a one-way warning, allowing intentional routes.

Height, hazard and destructible gate presets use their **Required ability**
override or preset ability. This includes hidden `ability_marker` gates.
Action barriers map **Required action** to the abilities that emit that hit tag:
`dash` requires `air_dash`, while `light_attack` and `heavy_attack` need no
unlock. Breakable walls reverse the runtime hit tags of **Required ability**:
a `dash` wall needs `air_dash`; a `ground_pound` wall needs `ground_pound`.
A wall with no requirement is open to core attacks for every wall type,
including `bomb_only` under the current hit rules. Several possible emitters
remain unknown pending any-of support; no emitter produces a warning.
Hazards resolve **Required resistance** or their type's immunity ability;
lava and the `lava_floor` gate need `heat_resistance`. Undefined ability ids
produce `undefined_ability_requirement` and stay unknown. Hazards without
ability protection remain unknown.

These annotations do not prove jumping distance, attack execution or safe
hazard traversal. Timed/custom gates, switches and temporary unlocks still
require playtesting. Grapple reachability is not modeled: a ledge the player
can reach only by grappling counts like any other ledge in its area, so a
missing grapple ability never blocks it in the report. Split such a ledge into
its own `progression_areas` entry and join it with a `progression_links` entry
that requires the `grapple` ability (for example `main>ledge=grapple`), or
playtest it. Valid, visible elevators connect consecutive landing
areas in both directions, using each node's `progression_area`. The controller
and every route node must be on the top-level `templates` layer, with a valid
shaft and final layout. `trigger_only` routes remain unknown with **Elevator
runs only when switched**. Invalid, disabled or incomplete elevators retain
the unknown traversal warning; hidden markers contribute no route. Floor
annotations prove connectivity, while riding, streaming and safe arrival
still need an in-game check. Boss defeat flags enter
only the speculative search; reaching a boss does not prove it can be defeated.
Random loot, custom collectible callbacks and dialogue rewards are unknown.
Unmodeled reward/traversal sources keep otherwise blocked conclusions uncertain.
Preview inventory/flags can investigate a known post-event state.

Missing areas/rooms, duplicate objective IDs, malformed configuration and invalid
source data stop publication before replacing output. Reachability, cycles,
traps and uncertain geometry are warnings, not export blockers.

## Reports and verification

`switch_gate` reports `switch-opened gate (channel <id>): playtest`;
the analyzer does not prove lever or plate timing or unloaded-room replay.

`staged_gate` uses **stages ▸ stage_flags** and **stages_required**: `0` means
all listed, `-1` inherits the preset, and positive counts need that many flags.
The shared requirement evaluator clamps the count to the list length; Prepare
& Check rejects an authored count above that length. Producers resolve after
all objects have been indexed. Lever/plate event flags remain unknown, and
boss flags remain unknown because combat cannot be proved. Flags supplied in
the preview start state can make a staged route reachable. Unknown switch
flags never prove a route blocked; modeled producers still have to be reached.
Other uncertainty, including temporary openings, still requires playtesting.

Persistent Gates with the same nonblank `group_id` share the analysis unlock
key `group:<group_id>`. Traversing one member opens every member in that search
branch, even if another member requires an ability the player does not own.
Temporary or nonpersistent gates do not grant that shared unlock. The runtime
saves the opening as `gate_group_<group_id>`; check cross-room travel, save/load
and the map in game as well as the analysis report.

`developer/assets/tiled/progression_diagnostics.txt` contains paths/explanations;
`progression_analysis.json` contains machine-readable results. World pacing
lines (see World pacing above) are in the same report. Both are disposable
and excluded from game/toolkit packages.

```powershell
lua tools/analyze_progression.lua
lua tools/analyze_progression.lua --preset=new_game --start=room_a:entry --ability=double_jump:true --item=red:1 --flag=boss_defeated:true
```

CLI exit 1 means a source/model error. Unknown or bounded results remain explicit
warnings. CLI/menu analysis uses published layout; the panel uses draft placement.

Fixtures cover valid ability routes, self-locks, cycles, disconnected/optional
objectives, internal barriers, one-way teleporters, competing key paths, persistent
unlocks, bounds, presets, publication preservation and preview input. Native GUI
and gameplay acceptance still require Reload Editor Scripts → Prepare & Check →
Build, then inspecting Progression and playtesting.
Headless checks do not prove Defold rendering or editor integration.

September 17 verification: 1,160 isolated Lua tests passed, zero failed/skipped,
including 24 progression scenarios; 12 release-helper checks and configuration
validation passed. Full log: `.build/tests-20260917-115516-e1b514c3/tests.log`.
Additional reports are under `.build/phase4/`.

Fast travel uses one global station id space, including travel-enabled save
points. Reaching a station grants `fast_travel_<id>`; boss rewards grant the
same destination flag, including for unvisited rooms. The graph connects station
areas to destinations requiring their unlock flag. Positive activation costs
mark these edges unknown because the currency economy needs playtesting.
Analyze Progression models the station-gated route; it does not prove fade,
streaming, travel fees or safe landing. Check those in game.

## Zip line connectors

A Zip Line can declare **progression_from** and **progression_to** as logical
areas in its own room. The analyzer adds a one-way connector by default; set
**progression_one_way** to false to model both directions. These annotations
change the analysis only. They do not change the cable's travel direction.
Both endpoints must name areas in the same room, even when the physical cable
crosses a streamed room seam; model cross-room access with the room's normal
door/layout links. Leave the fields blank when no internal connector is needed.
Playtest timing, terrain clearance and streaming.

## Vehicle connectors

A Moving Platform with **Vehicle control** `throttle` or `auto` may declare
**progression_from** and **progression_to** as areas in its own room. The analyzer
adds a one-way edge, or a reverse edge too when **progression_one_way** is false,
as for Zip Lines. Ordinary moving platforms add no connector. These annotations
do not change driving, return behavior or the track-switch channel. Playtest
switch timing, rider clearance, braking and the fall-away endpoint; the graph
cannot prove those physical details. Vehicles and both tracks must stay in one room.

## World-state tile layers

A world-state tile layer (a tile layer with **appear_when** or **remove_when**)
can be a barrier between two areas of its room. Add the layer custom properties
**progression_from** and **progression_to** (strings naming areas from
`progression_areas`). The analyzer adds an edge each way between them.

By default the barrier can be crossed while the layer is absent: while
**appear_when** does not hold, or while **remove_when** does. A layer that is
something to walk on, such as a bridge, takes the bool property
**progression_passable_when_present** = true; it can then be crossed only while
the layer is present. Only conditions made of flags (`flag`, `!flag`, commas and
`|`) are modelled. A condition that names `ability:` or `item:` leaves the edge
unknown, so playtest that crossing.

A layer that can collide (its **state_collision** is not `none`) and lacks
either endpoint gives the `state_layer_barrier_unknown` warning. The analysis
then ignores the layer, and the room's own annotations still describe its
traversal: a decorative layer may legitimately have no endpoints. These
properties change only the analysis, never the layer's tiles or collision.
