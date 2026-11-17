# Preparation and endings

Prepare & Check opens a progress window before scanning files. Click **Continue**
there to begin. The window shows the current stage while the existing
Continue/Cancel menus still appear between stages. When preparation completes,
the same window shows the saved result and next action, and **Close** becomes
available. There is no second completion dialog to dismiss. A failed operation
displays its error in this window.

The stage total is planned once per run from the current project changes. A full
Tiled-world preparation has ten stages; it has nine when Import Assets is
already current, and seven when imports, player settings and room generation are
all current. Manual layouts and empty projects need fewer stages. Continue
prompts list unchanged work that was skipped, and the final result explicitly
reports **Completed N of N stages** using the same total as those prompts.
The final view is refreshed after resource synchronization settles so the saved
result appears without pressing Refresh status.

After installing or updating toolkit scripts, stop the game and run **Project → Reload Editor Scripts**. Export your saved maps from Tiled, then choose **Project → Prepare & Check** in Defold. It saves editor buffers before changing resources, checks imported Tiled copies, imports changed assets, creates rooms and synchronizes resources, then validates the result. You can cancel between complete stages. These individual stages are no longer separate menu choices. Preparation also rebakes player geometry from saved effective settings without publishing unsaved Game Settings edits.

With Tiled World selected, preparation publishes the exported world placement and minimap. With Layout Editor selected, Build, open Layout Editor, rescan and review placements, then **Layout Export** publishes the layout and minimap together. Stop and Build again before playing the newly published world. **Export Game** packages that publication without regenerating rooms underneath an older minimap.

**Project → Preparation Status** explains the next action and lists affected files. Statuses distinguish Tiled export needed, preparation needed, layout publication needed, rebuild needed, ready, failed, and legacy unverified exports. Re-export older maps once to record the imported inputs; re-export an older world with **Export All Maps and Tiled World**. External originals can then be offline or inaccessible to Defold. Ready means the imported export is prepared, not that unexported changes in Tiled have been imported.

Tiled validates the originals during export and records project-relative fingerprints for the localized TMX, tilesets, templates and artwork. Defold validates those imported inputs before Import Assets or Create Rooms; missing or modified copies require re-export. Original paths are retained for attribution, not reopened by Defold. **Export Current Room** updates content without changing exported world placement; resizing rooms, changing the starting room, or rearranging world membership requires **Export All Maps and Tiled World**. Import Assets regenerates tilemaps from imported Lua, so regenerated tilemaps are not treated as stale source copies.

Preparation records successful revisions only. A layout publication records room/settings/generator revisions and the exact minimap outputs. Draft placement edits invalidate publication. A file changing during minimap rendering cancels publication. Failed or cancelled preparation leaves the previously published layout and minimap intact; successfully completed preparation stages can still have updated generated room files.

Reports live in `developer/assets/tiled/preparation_status.json` and `preparation_run.json`. Automation can run `lua tools/prepare_project.lua --status`; `lua tools/prepare_project.lua` performs preparation and returns a failing exit code on errors. Run mutating automation with Defold stopped, preferably in a disposable project. Imported art and the TMX/TSX tile dimensions determine tile size; Game Settings does not offer a tile-size picker.

## Preparation checksum performance

Preparation, source checks, tileset cache keys and minimap PNG encoding share a
portable Lua Adler-32 implementation. It processes sixteen bytes per string call
and reduces the sums once per bounded block. Fingerprints and PNG checksums stay
identical to the previous implementation; binary data stays binary, and only
text-source checks normalize BOM/CRLF. No native extension or external program
is needed by this optimization on Windows, macOS or Linux. Every existing
freshness check still reads current file contents.

On 2026-09-27, a read-only comparison of the same preparation snapshot (5,654
files, 92,544,875 bytes) under standalone Windows Lua 5.1 took 5.351/5.944 seconds
with the previous loop and 1.580/1.488 seconds with the shared checksum. All
snapshot entries matched. This measures snapshot scanning, not total Defold
preparation time; editor integration and timings still need native verification.
Regression coverage is in `test/adler32_tests.lua` and the preparation tests.
The isolated full suite passed 1,459 tests; four failures in player-scale,
Tiled-enum and starting-ability checks reproduced with the original checksum.
Preparation, imported-input, world-layout and PNG/reset checks passed.

After this module update, **restart Defold**, then **Reload Editor Scripts →
Prepare & Check → Build**. Reload alone can leave required Lua modules cached.
The first preparation also records the updated generator sources.

## Preparation I/O and timings

Shared imported files are read once within each freshness check. Each later
check starts with fresh disk reads, including publication-time checks. World
members are validated once per pass, and preparation no longer repeats the
entire world check before step 1. No freshness checks are skipped across runs.

On 2026-09-29, read-only profiling of the 307-room project in standalone Lua
measured a world check at 32.241 s / 21,888 file opens before the change and
1.986 s / 734 opens afterward. Step-1 provenance checks fell from 62.252 s /
43,775 opens to 2.349 s / 734 opens. These are individual check timings, not
full Defold preparation timings; native UI behavior and total time need an
editor check after a full restart.

The performance update normalizes blank lines in generated prototypes once. It also
canonicalizes equivalent `-0` values to `0` in the generated art manifest. The next
unchanged generation should perform no generated-resource rewrites. Tiled objects
remain baked, editable gameobjects in their room collections.

Prepare & Check prints one `[PERF]` report on success, failure or cancellation.
Stage and total times exclude the Continue dialogs. The report distinguishes
unchanged files, existing rewrites, new batched resources, raw writes, estimated
resource synchronizations, and full/partial snapshots. Synchronizations are an
estimate from filesystem operations, not a Defold internal profiler counter.
Repeated disk writes with different content produce a churn warning.

`developer/config/editor_performance.lua` controls Windows batching, its minimum
file count, and debug-log rotation. The console explicitly reports when preparation
is waiting for a Continue/Cancel dialog between stages.
Preparation and world-publication commands reject overlapping invocations with
an "already running" message naming the active stage. A retry cannot reset the
active run's staged files or timing counters. The guard clears after completion,
cancellation, or failure.
Existing changed resources are written through
one PowerShell bundle and verified by reading each target back. The bundle stores
length-prefixed raw bytes instead of encoding every content byte in editor Lua.
Console timings distinguish packing, helper validation/writing, and the combined
helper/editor refresh wait. Failures fall back
to the ordinary writer. Other platforms retain ordinary writes. `.mvtk_tmp` is
ignored by Defold and excluded from releases. At the first logged editor command
of a session, a Windows debug log larger than 5 MiB rotates to `debug_output.txt.1`.
Repeated invisible-object warnings list object IDs together per room/layer/type.

After updating the toolkit, fully restart Defold, then Reload Editor Scripts,
Prepare & Check, and Build.

## Configure an ending

Stop the game, choose **Project ▸ Game Settings…** in Defold, then click **Ending**. These fields share the window's unsaved draft. Hover over a name or field for help, use the row's **x** to restore its default, and use **Edit lines…** for body text or credits. Click **Save and Prepare & Check**, finish the preparation prompts, then Build to play with the saved ending.

The commented baseline is `developer/config/game_completion.lua`. One stable ending ID identifies completion in each save slot. Choose a condition:

| Condition | Authoring |
| --- | --- |
| Region | Place `tiled/templates/logic/end_game.tx` on a top-level `templates` layer. Set its `completion_id` to the configured ending ID. Resize its rectangle in Tiled. |
| Flag | Set the flag name that existing gameplay grants. Completion waits until that flag is set. |
| Boss | Set the boss preset or persistent boss identity used by `boss_defeated_<id>`. Completion waits for rewards and arena cleanup. |

The region becomes a visible, editable gameobject in the baked room collection, with its own rectangle and script properties. Its editor collision outline is disabled during play; the script checks player entry. It is never created again by the runtime Tiled spawner. Version 2.8 adds the ending template while keeping supported 2.x templates readable.

The main ending is a required progression objective. Other endings are optional objectives. Boss combat and unmodeled flag sources remain uncertain in progression analysis; a route in that model still needs a gameplay check. Relationship validation catches a region referring to an unknown ending or a boss ending referring to a missing boss.

Reset Project to Empty clears ending settings. Re-exporting maps restores their
authored ending regions, but does not restore the project ending configuration.
While completion is disabled, a region with a different ending ID produces a
warning and permits preparation/build. Open **Project ▸ Game Settings… ▸ Ending**,
set its ID to the region's `completion_id`, enable completion and click
**Save and Prepare & Check**, then Build. An ID mismatch blocks preparation/publication
once completion is enabled. See the preparation order above after changing ending configuration.

### Add other endings

The flat fields in `developer/config/game_completion.lua` remain the main ending.
The ordered `endings` list holds complete other endings. Each checks its own trigger
and all its requirements before the main ending is considered. The top-level
`enabled` switch controls every ending. The main ending has no `requires`.

1. Choose **Project ▸ Game Settings…**.
2. Click the **Ending** tab.
3. Click **Edit other endings…**.
4. Click **Add ending**.
5. Set **ID** to a unique, permanent ending ID.
6. Choose **Condition**.
7. Set **Flag** or **Boss ID** for that condition.
8. Set **Required flags** to any additional flag names, separated by commas or spaces.
9. Set **Required bosses** to any additional boss IDs, separated by commas or spaces.
10. Set **Minimum completion %** if the ending needs completion tracking.
11. Set **Finish within minutes** if the ending has a play-time limit.
12. Set **Title** to this ending's title.
13. Click **Edit lines…** beside **Body** to edit its pages.
14. Click **Use lines** to keep the body text.
15. Click **Edit lines…** beside **Credits** to edit its credits.
16. Click **Use lines** to keep the credits.
17. Set **Reward** to optional grant text.
18. Click **Preview ending…** to inspect this ending's unsaved pages.
19. Click **Close** to return to its editor.
20. Click **Use ending** to keep this ending in the list draft.
21. Click **Use endings** to keep the list in the Game Settings draft.
22. Click **Save and Prepare & Check**.
23. Choose **Project ▸ Build**.
24. Start an empty save slot to test the main ending without the optional flags.
25. Start another empty save slot to test the other ending with those flags.

Use **Edit…** to change an existing ending, **Remove** to delete it, and **Move up**
or **Move down** to change which other ending is checked first. **Cancel** discards
only the current sub-dialog's changes. Changes reach the project only when Game
Settings saves. The first section still edits the main ending and its master
**Enabled** switch; an other ending's **Enabled** controls only that entry.

The commented baseline file can also hold complete entries, for example:

```lua
endings = {
    {
        id = "restored_world", enabled = true,
        condition = "flag", flag = "journey_finished", boss_id = "",
        continue_policy = "completed", return_room = "", return_x = 0, return_y = 0,
        title = "The world restored", body = "Your journey has changed the world.",
        credits = "Created by you", music = "", artwork = "",
        reward_flag = "world_restored", reward = "flag:restoration_reward",
        requires = { flags = {"optional_story_complete"}, bosses = {},
            completion_percent = 100, max_minutes = 0 },
    },
},
```

Use your own existing flags and text. `requires.bosses` lists boss preset or
persistent boss identities. `completion_percent` ranges from 0 to 100 and needs
completion tracking enabled; omit it when no percentage is needed. `max_minutes`
uses in-game play time, with 0 meaning no limit. The first eligible ending wins.
Each ending owns its title, body, credits, music, artwork, reward and Continue
policy. `font`, `text_scale` and `credits_per_page` are shared. A Game Settings
override of `endings` replaces the entire baseline list, including an empty list.
The list editor replaces the baseline list as a whole. Set **Minimum completion %**
to 0 for no percentage requirement; **Finish within minutes** at 0 means no limit.

Only one ending can be completed per save slot, including after **Explore**.
An optional `reward` uses the shared grant grammar and once key `ending:<id>`;
it and `reward_flag` are saved with completion. Do not test endings inside a
Dev Menu test session, where saves are sandboxed. For world changes after an
ending, use the flag-driven presence and replacement workflows in
[Creator workflow](CREATOR_WORKFLOW.html#make-objects-appear-or-disappear-with-story-flags).

## Ending records

Finishing an ending records it in the game's player profile, shared by every
save slot. **Journal ▸ Records** shows **2 of 3 endings**, followed by each seen
ending's title and **Best time: h:mm:ss**. The total includes the enabled main
and other endings; unseen endings have no title row. Removing or disabling an
ending hides its row while retaining its profile data. Deleting a save slot
keeps the endings seen and best times. Dev Menu test sessions and boss practice
do not write these records. The timer and ending-time display switches do not
affect recording.

1. Finish one ending on an empty save slot.
2. Finish a different ending on another empty save slot.
3. Open **Pause ▸ Journal ▸ Records**.
4. Check the ending count and each seen ending's best time.
5. Delete one completed slot from the save-slot screen.
6. Open **Pause ▸ Journal ▸ Records** on the remaining slot.
7. Check that both endings remain listed.

An achievement can use `trigger = {type="ending", ending_id="main"}` in
`developer/config/achievements.lua`. Use the configured ending's id and add
`max_playtime_s = 3600` to require an in-game run time of at most one hour.
The optional limit uses RunStats seconds, including when the ending time is
hidden; omit it for any time. This trigger checks the active slot's completed
ending, independently of records from other slots. Achievement unlocks themselves
belong to the shared profile.

## Presentation and Continue

Title, body and newline-separated credit entries are data. Music uses an existing Sync Music track ID. For artwork, add your image/animation to `developer/ui/game/completion.atlas`, then enter its animation ID in the Ending page. Leave music or artwork blank to omit it. The GUI's font and text scale are configurable in the baseline file. Credits support Enter/A/Right for the next page, Left for the previous page, and Escape/B to return to the menu.

**Preview ending…** shows the unsaved title, body and credit pages in an editor dialog. Previous and Next move between pages. It uses the game's page-building rules with sample values of zero minutes and zero items, and shows the artwork animation's first image when available. Missing artwork and Ending-field issues are displayed in the dialog. Preview does not set flags, change checkpoints, complete a slot, or save player data. Music plays only in the game.

**Completed** Continue shows the completion screen again. **Explore** Continue resumes at the configured return room and world coordinates, or the last saved checkpoint when the return room is blank. A return point must lie inside its published room; configure it somewhere safe and outside hazards. Revisiting the ending region does not trigger completion again.

The completion provider records the ending ID, gameplay time and an inventory snapshot (items held and currency). These are supported snapshot statistics, not a lifetime collectible percentage. An optional reward flag and the return checkpoint are committed with completion in one checkpoint save. Boss rewards are processed by the boss system before this transition. A failed save shows an error and Retry; it does not claim completion or unload the game. Keep Playing dismisses the error without claiming the save succeeded.

The empty toolkit leaves completion disabled. Reset Project to Empty and the empty release builder clear authored ending settings. Preparation reports and layout draft metadata are excluded from game packages.

## Acceptance checks in Defold

Headless tests exercise revisions, cancellation, baking, save/retry/reload, slot isolation and navigation logic. They cannot establish native rendering, input focus, physics, music or editor buffer reload behavior. Check the native workflow after Reload Editor Scripts: prepare, build, rescan/publish, rebuild, test each ending condition, retry a failed save, restart both Continue policies, and launch an exported game under its own save namespace.

## World budget

When the world has rooms, Prepare & Check runs **Check world budget** after
Validate All and before it publishes the Tiled world. The stage counts what each
baked room puts into the engine's pools: game objects, sprites, collision
objects, tilemaps, particle effects, sounds, labels, factories and collection
factories. It adds the rooms the streamer keeps loaded around each room (the
preload distance, the lookahead room and the inactive room cache from
`developer/config/stream_settings.lua`), the main collection and player, and a
reserve for shots, damage numbers, enemies and pickups. It then compares the
worst neighbourhood with the limits in `game.project`. Tiles are an estimate of
one screen at the default camera zoom on the widest allowed window, plus the
next room at a doorway, because the engine only draws the tiles in view. It
also estimates the save size and flags rooms large enough to pause the game
while they stream in.

To read the result:

1. Choose **Project ▸ Prepare & Check**.
2. Open `developer/assets/tiled/world_budget.txt`.
3. Read each "Over the limit" line. It names the neighbourhood, its densest room
   and a remedy.
4. Choose **Project ▸ Preparation Status** to see the same summary later.

Findings are warnings. Prepare & Check still succeeds unless
`block_on_overflow = true` in `developer/config/performance_budgets.lua`, which
also holds the margins, the runtime reserve and the slow-room threshold. Without
an exported layout, the report gives per-room totals and asks you to export the
layout. The report and its cache are left out of releases, and Reset Project
removes them. Unchanged rooms are not counted again.

The same stage counts the files Create Rooms has written to
`developer/rooms/generated/` and its `shared` folder. Objects, artwork and
collision shapes that are the same share one file in `shared`, named by its
content; each object stays in its room collection with its own values.
Preparation Status shows "Generated room files: N (M unused)", and the report
lists them by kind. Unused files are ones no room collection or factory refers
to, such as the leftovers of a deleted Tiled object or a removed room. Prepare &
Check deletes them after it has rebuilt every room. It deletes only files whose
names start with a room's name and unused files in `shared`, and it keeps the
`_mvtk_elevators` folder and the pushable-block snapshot it needs on the next run;
the count includes that snapshot but never calls it unused. Create Rooms for
selected rooms deletes nothing. The count therefore stays at 0 unused after
Prepare & Check, unless you keep files of your own in that folder.

### Apply Recommended Engine Limits

When the last report found a pool over its `game.project` limit, Preparation
Status offers **Apply Recommended Engine Limits**. It raises only those limits,
to the worst count times the pool's margin from `performance_budgets.lua`,
never lowering a value and never going above the engine's maximum. You never
edit `game.project` by hand for this.

1. Stop the game if it is running.
2. Choose **Project ▸ Preparation Status**.
3. Click **Apply Recommended Engine Limits**.
4. Read each listed setting's old and new value.
5. Click **Apply**, or **Cancel** to leave `game.project` unchanged.
6. Click **Close**.
7. Choose **Project ▸ Prepare & Check**.
8. Choose **Project ▸ Build**.

Every other setting in `game.project` keeps its exact text. A limit capped at
the engine's maximum still overflows: split the densest room the report names.

## World census

Prepare & Check writes `developer/config/world_census_generated.lua` from the
world's generated collections and content index. It lists rooms and placed
items, chests, lore, secrets, bosses, barriers, travel points, map icons,
enemies and objectives with their baked ids and positions. It creates no
gameobjects. Reset Project to Empty restores an empty census automatically.

Runtime totals include every room in the published layout, even before a room
is visited. Configure counted item categories in `developer/config/world_census.lua`;
the defaults count abilities, upgrades, weapons, charms, progression items, relics, lore and keys.
Consumables, currency, materials and power-ups are excluded, as are respawning
items, reusable chests and blank lore ids. Prepare & Check warns when a lore
id is blank because it cannot persist. A collectible type can set
`count_in_census = false`. Category and respawn defaults are read at runtime.
Secrets, bosses and single-use chests also count. Existing save flags supply
found/open state; no save migration is needed. An object with an
`appear_when` or `remove_when` condition counts only while that condition lets
it exist, unless `count_presence_gated` in `developer/config/world_census.lua`
is `always`.

Optional weighted completion uses this same published membership. Enable it in
**Game Settings ▸ Progression ▸ Completion**. The commented
`developer/config/completion_tracking.lua` gives upgrades (including abilities,
fragments, weapons and charms), bosses and visited rooms equal weights by default.
Secrets, single-use chests, collection, quests, bestiary and guardians have zero
weight but show their counts in **Journal ▸ Records**. A creator can change the
weights or add a labelled collectible category. Categories with no entries are
excluded from the weighted average; no qualifying category displays `-`.
Map rooms count only when visited, not merely revealed. Census exclusions remain
authoritative, and **Prepare & Check** warns about an uncounted collectible category.
When **Show on ending** is enabled, the ending captures an integer percentage
and shows **Completion: N%** in its first page's statistics. Turning completion
off preserves the existing ending wording. No new save provider is introduced.

After changing editor-loaded census code, restart Defold, then use Project ▸
Reload Editor Scripts, Prepare & Check and Build. Re-export a changed layout
from the Layout Editor so runtime membership matches it. Hooks changes stale
the publication: run Prepare & Check again before Export Game.
