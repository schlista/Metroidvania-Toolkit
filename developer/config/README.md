# Configuration Handbook

`combat_music.lua` optionally crossfades nearby fights to a registered combat track.
Use **Game Settings > Game > Combat music** to tick **Combat music**, set
**Combat track**, and tune **Quiet delay (seconds)**. It ships off. Room map
`combat_music` uses a `music_tracks` id: blank or `inherit` uses the default,
`none` disables that room. File-only settings tune living same-room proximity,
player hits, spawned enemies and fades (at least 0.5 seconds). Boss, champion
and encounter music take precedence; explicit music lasts until a room change.
Run **Prepare & Check** and **Build** after editing. Audio remains unverified
until heard in the running game.

Start with **[the complete creator guide](../../docs/CREATOR_WORKFLOW.html#12-configuration-without-coding)**. Use **Project ▸ Game Settings…** in Defold for global player, ability, combat, and game-setting presets; use Tiled properties for one placed object; edit the commented files below only when the guide calls for them. Never edit `mvtk/` to tune a game.

## Tiled catalog dropdowns

Entries in the catalog files become Tiled dropdown choices after **Project ▸ Prepare & Check**.
Then reopen `MVTK.tiled-project` in Tiled with **File ▸ Open File or Project...** before picking the new value.
Use the source config's keys; never edit these dropdowns in Tiled's Custom Types Editor.

## Priority

For player, starting-ability, combat and game settings, published
`creator_settings.lua` values override the authored baseline configuration.
Game Settings preserves baseline files, including comments and advanced tuning.
Tiled instance properties retain their precedence for placed objects; player
preferences remain separate from creator defaults.

Each champion's Tiled **Champion seal** and **Champion bar** checkboxes decide
room sealing and health-bar visibility. Neither inherits a project default.
Remove legacy `champion.seal_room` and `champion.show_bar` entries from
`enemy_defaults.lua` or `creator_settings.lua` overrides; Prepare & Check
warns if they remain. Set the checkboxes per champion, export the room, and
run **Prepare & Check** and **Build**.

Game Settings shows blue names for values that differ from toolkit defaults.
Hover over fields for help and use the row's **x** to restore its default, then
Save. **Current** in the preset dropdown restores saved project settings when
applied. Machine-local authoring settings are not imported. Keep the game
stopped, click **Save and Prepare & Check**, then Build. Failed saves preserve
the previous project settings; preparation also recovers interrupted saves.

## Completion

`new_game_plus.lua` holds the optional completed-slot replay policy. It ships off.
Its carry switches select saved progress and its cycle list controls shared
difficulty factors; the last entry repeats. **Game Settings ▸ Progression ▸
New Game+** exposes **Enabled**, the cycle 1 multipliers, **Carry level**,
**Carry equipment** and **Carry currency**. Eligible completed slots offer the
confirmed replay choice on **G** or the top face button on a controller.

`extras.lua` lists the Extras jukebox tracks and gallery images and their unlock
rules (always, heard, ending, achievement, flag or New Game+ cycle). It ships
off. Unlocks are kept in the per-game player profile, so they survive slot
deletion. **Game Settings ▸ Ending ▸ Extras** exposes **Enabled**, **Unlock
notices**, **Show locked entries** and the **Jukebox**, **Gallery** and
**Credits** tabs; the lists stay in the file. A gallery entry's `image` is the
name of a PNG in `developer/assets/extras/` without `.png`; **Prepare & Check**
writes `extras_gallery_generated.lua` (image sizes) and the gallery atlas from
that folder. Do not edit the generated file.

`trial_settings.lua` defines trial countdown, safe-return fades, first-clear saving, rank names and optional sounds.

`completion_tracking.lua` defines weighted completion categories. It ships off;
**Game Settings ▸ Progression ▸ Completion** exposes **Enabled**, **Show on ending**
and **Show in Journal**. Default weights count upgrades, bosses and visited rooms
equally; zero-weight categories retain Records counts. Category filters obey
`world_census.lua`, including respawn and per-type exclusions. Added category ids
need `collectible_categories` and a source-text `label`. **Prepare & Check** warns
when those collectible categories are uncounted. Run **Build** after preparation.

## Weapons

`weapons.lua` defines an ordered list of owned weapons, attack sets and unitless
multipliers. **Game Settings > Equipment > Weapons** offers **Weapons** (off by
default) and **Starting weapon**; blank uses the unarmed moveset. The starter is
virtual and never granted to Inventory. Attack sets may supply grounded and
aerial up attacks. Cooldown changes the gap between attacks, leaving swing timing
unchanged. Optional `damage_type` is overridden by an unlocked infusion. Generated
`weapon_<id>` pickups count toward completion unless `count_in_census = false`;
duplicates pay `duplicate_currency`. Gear rewards use `item:weapon_<id>` through
the shared grants service, which clamps unique items to one while owned. Disabled
world pickups stay in place. The current weapons core does not expose switching
or the Inventory Weapons tab yet.

## Charms

- `crafting.lua` - Optional Inventory recipes for weapon tiers and charms; shared item/currency costs, shipped off.
- `charms.lua` - Optional equipment effects and slot costs for Inventory > Charms; Game Settings > Equipment enables the system.

`charms.lua` defines an ordered list of unique charms, whole slot costs and
stat effects. **Game Settings > Equipment > Charms** offers **Charms** (off by
default), **Base slots** (3) and **Maximum slots** (9). Capacity is the smaller
of the maximum and base slots plus the Inventory count of `charm_slot`.
Generated `charm_<id>` pickups use the shared unique-item grant path; disabled
pickups stay in place. The id `slot` is reserved. Charm Slot cannot be sold.
Additive effects sum and multipliers multiply on the equipment layer;
`damage_taken_mult:fire` provides fire resistance. `invulnerable` is forbidden.
A health charm raises capacity without refilling health. `xp_mult` does nothing
while Leveling is off. `currency_mult` affects currency pickups, including dropped
coins, with integer rounding; it never boosts duplicate-gear payouts. Equipped
ids ride the next normal save. Players toggle equipment anywhere in **Inventory ▸ Charms**;
its header shows slot use and rows that do not fit are disabled. Charm items and
Charm Slots stay out of Items and Sell while enabled; with Charms off, Charm Slot
remains visible under Items. See [Charms](../../docs/CREATOR_WORKFLOW.html#charms).

## Power-ups

`powerups.lua` defines temporary world pickups, their translated source names,
effects, active-play durations and refresh or extend policy. Enable **Power-ups**
in **Game Settings > Equipment > Power-ups**; it ships off. Disabled pickups stay
in place. The countdown is controlled by **HUD and prompts > Show on screen > Power-ups**.

## Beginner-facing files

`reward_text.lua` controls grant notice separators, count/unlock wording,
duration and hidden kinds. `items.lua` accepts optional `unique = true` for
items that grants should award only once while owned. Reward fields are added
by their authoring features; chest and loot drop lists keep their own syntax.

| File | Purpose |
| --- | --- |
| `healing.lua` | Flask, items or channel model, charge refills, drink time and cancellation, air/water rules, movement multiplier (minimum 0.25), quick-item order and hold repeat. Game Settings > Player > Healing exposes model, capacity, heal amount, Heal per channel, Energy per heal and Channel time (seconds). Channel healing spends shared energy only on completion; release or interruption cancels without spending. Holding heals; select quick items in Inventory. Max energy must be above 0, even for a free heal. File-only channel.repeat_while_held and channel.hint_event set repeat and tutorial routing; Combat > Resource gain exposes optional hit, parry and defeat energy gains in every healing model. Max energy 0 disables gains. The Dev Menu's Infinite energy waives channel and attack costs while energy is enabled. Energy is not saved; initial hold timing is in `default_bindings.lua`. |
| `combat_config.lua` | Player attack timelines and optional `energy_cost` in Max energy units, paid once at attack start. `sfx.refuse` names a sound for an unaffordable press. Max energy 0 and Infinite energy waive attack costs. |
| `creator_settings.lua` | Project-owned Game Settings overrides, with version and publication state. Travels with exports. |
| `player_settings.lua` | Player size (`player_scale`, `scale_movement`), movement, walk/run animation pace (`locomotion_animation`), footstep sound cadence (`footsteps`), resources, collision sizes, and traversal tuning. `ladder_climb` sets `hang_idle_animation`, `hang_move_animation` and optional `mesh_animation`. Published Game Settings values can override it. |
| `ability_defaults.lua` | Abilities available at the start of a new game. Published Game Settings values can override it. |
| `combat_overrides.lua` | Authored baseline attack tuning, preserved by Game Settings. |
| `default_bindings.lua` | Current `key_*` / `gamepad_*` allowlist and high-level `actions` mappings. |
| `enemy_types.lua` | Reusable enemy stat and behavior presets; Tiled enemy instances can override them. |
| `enemy_settings.lua` | Global regular-enemy limits and behavior defaults. |
| `shops.lua` | Purchase catalogs: shared stock, grant text, currency and item costs, unlock flags, confirmations, bank transfer steps/autosave and save/sound settings. See [Economy](../../docs/ECONOMY.md). |
| `upgrades.lua` | Named permanent health, energy, stamina and damage upgrades with prerequisite upgrade ids. |
| `steam_settings.lua` | Optional Steam app id, achievement API Name mappings, rich-presence source text, Auto-Cloud switches and language code overrides. Presence and cloud saves ship off; preferences and controls sync only when included. An unmapped achievement id is sent unchanged. |
| `quests.lua` | Optional save-slot quests: source titles, descriptions and giver text, ordered objective steps, flag or explicit starts and once-only turn-in grants. Game Settings > Progression > Quests ships off. |
| `countdowns.lua` | Countdown events: escapes started by a flag condition and timed courses with best times. One runs at a time, holds in menus, dialogue and cutscenes, never survives a load, and sets `countdown_<id>_active` while it runs. Ships one harmless `sample_course`. |
| `npc_settings.lua` | Living NPCs: whether opted-in NPCs show the new-dialogue marker, and its two source texts (unheard lines; lines that start or turn in a quest); whether ambient lines (barks) show and for how long; how long wandering NPCs pause at each end. Game Settings > Game > NPCs edits the switches and the line time. Also the Journal People tab (`people`, Game Settings > Progression > People; ships off). |
| `goals.lua` | Optional ordered goals: source titles, Journal text and hints, done_when requirements (abilities, items, flags, currency, counts and any-of) and an optional objective or marker target. Progress only moves forward. Game Settings > Progression > Goals ships off; the shipped list is empty. |
| `achievements.lua` | Optional goals across save slots, exact event filters and state triggers, source names and grant rewards. Game Settings > Progression > Achievements ships off; rewards go to the slot active at unlock time. |
| `bestiary.lua` | Creature names, descriptions, categories and recording options. Game Settings > Progression > Bestiary ships off; defeats still record. Reset Project to Empty clears its creator content. |
| `leveling.lua` | Optional XP curve, stat growth, milestone flags and source rewards. Game Settings > Progression > Leveling ships off. |
| `run_stats.lua` | Run time and counters; Game Settings > Progression > Records exposes Statistics in Records and Time on ending. Displays ship off; counts are always recorded. |
| `fragments.lua` | Permanent health and energy pieces, custom stamina or flask sets, upgrade amounts and translatable progress notices. Game Settings > Player > Health and resources sets Health fragments per container and Energy fragments per container. |
| `collectible_types.lua` | Collectible ids, values, visuals, and pickup feedback. |
| `loot_tables_authored.lua` | Loot Tables entries; each id replaces the whole matching loot_tables.lua table. Reset Project clears these entries. |
| `gate_types.lua` | Reusable key, ability, item, and action gate presets. |
| `progression_analysis.lua` | Analysis presets, objectives, logical areas and bounds. See [progression analysis](../../docs/PROGRESSION_ANALYSIS.md). |
| `hazard_types.lua` | Reusable environmental hazard presets. |
| `narrative/dialogues.lua` | Lightweight dialogue entries referenced by NPC/dialogue templates. |
| `narrative/dialogues_authored.lua` | Dialogue Editor sequences; each id replaces the whole matching dialogues.lua sequence. Reset Project clears these entries. |
| `ui_theme.lua` | Shared UI colors, fonts, spacing, and style values. |
| `hud_layout.lua` | HUD element placement and sizing. |
| `settings_defaults.lua` | Default audio, graphics and gameplay settings. Controller bindings live in `default_bindings.lua`; accessibility defaults live in `accessibility.lua`. |
| `accessibility.lua` | Player accessibility defaults (including `player.assist`), press-instead-of-hold defaults for grab, grapple, channel healing, run, glide and aim, visible options, assist-use records and achievement restrictions, reading-text sizes and reduced shake, freeze-frame and full-screen flash limits. Reset Project preserves this authored file; saved player choices take precedence for offered rows; hidden hold rows use creator defaults. |
| `map_discovery_settings.lua` | Fog of war, soft edge radius, discovery cell size, nearby reveal radius, and optional whole-room discovery. |
| `persistence_settings.lua` | Permanent game identity for separate player saves, preferences, and layout drafts. |
| `save_migrations.lua` | Exact-path aliases for intentional changes to released room/object identifiers. |
| `stream_settings.lua` | Room preload radius, creation/deletion budgets, and asynchronous resource-load limits and retries. |
| `debug_config.lua` | Development logging and debug-feature switches. |
| `game_config.lua` | Project-wide fallback values, build metadata, camera, window, hazard returns, death currency recovery, save policy, and animation remaps. |
| `difficulty_settings.lua` | Difficulty presets and damage, health, and loot multipliers. |
| `tutorial_popups.lua` | Reusable tutorial titles/body text, input event triggers, and repeat-prevention flags. |
| `boss_types.lua` | Presets for the supported compact five-template boss workflow. Prefer Tiled objects for encounter-specific values. |
| `boss_arenas.lua` | Optional defaults used by supported Tiled boss arenas. |

## Generated or tool-owned files

Room streaming prepares resources before allowing startup, fast travel, respawn,
or a neighboring-room crossing. After upgrading, run **Create Rooms** to regenerate
factories with dynamic resource loading. Elevators prepare and enable their pinned
route before departure. The commented `stream_settings.lua` controls load concurrency,
timeout and retry limits; keep the defaults until profiling demonstrates a need.

Do not edit these by hand:

- `player_resources_generated.lua` — last applied player geometry, used for repeatable scaling
- `tile_settings.lua` — derived by Import Assets from imported Tiled art
- `rooms_config.lua` — generated by Create Rooms
- `elevators_generated.lua` — generated by Create Rooms from Tiled elevator routes
- `runtime_settings.lua` and `resolved_config.lua` — settings merge/load code, not creator data
- `*_generated.lua`, `tiled_enemy_overrides.lua`, and `chest_inline_contents.lua` — sync/import outputs
- `poi.lua` and runtime layout files — written by the Layout Editor

## Supported scope

The live Tiled template catalog covers enemies, collectibles, gates, environmental hazards, NPC dialogue, traversal, and lighting. Boss encounters use `boss`, `boss_arena`, `boss_phase`, `boss_phase_trigger`, and `boss_weak_point`; cross-room elevators use the paired Tiled elevator markers. Place gameplay objects on the top-level `templates` layer. Use Game Settings for shared player and game settings.

Run **Project ▸ Prepare & Check** after changes. Maintainers can regenerate `INDEX.md` with `python developer/tools/generate_config_index.py`.

## Player size

`player_scale` is the uniform body-size factor. Use `1.00` for art drawn at its
intended in-game pixel size, independent of room tile size. Game Settings Save
rebakes recognized generated player resources; keep the game stopped and Build
afterward.
Supported custom resources retain their references and animation mappings.
An ambiguous or unsupported resource stops the save before any file changes.
For direct baseline edits, remove any overriding `creator_settings.lua` scale
value first; **Prepare & Check** uses the same preserved-resource transaction.
Save an existing custom player at its current size once before direct size edits,
so its previous geometry is recorded.
`scale_movement = true` also scales pixel-based movement and traversal values;
`false` changes geometry only.

## Exploration and fog of war

Both maps start hidden and reveal nearby terrain as the player explores. Loading
a neighboring room does not discover it. Discovery and known gate/POI metadata
are saved per slot; a map station reveals its configured rooms without marking
them visited. Use `mode = "room"` for whole-room discovery on entry, or
`enabled = false` to show the complete map. Tiled markers explicitly marked
`visible_from_start` remain visible. No map-image repainting is needed.

`cell_size` is stored with each save; use a fresh slot to test a changed cell
size. Existing saves containing only whole-room exploration retain those known
rooms. `reveal_radius` is in world pixels. Smaller cells or larger fog textures
cost more CPU/memory; the defaults are two-tile cells and a four-tile radius.

## Map item tracking

`map_icons.lua` decides which placed objects the world map and minimap mark.
Every icon comes from the prepared world census, so icons also cover rooms that
are not loaded. **Game Settings ▸ Map ▸ Item tracking** sets the item icon
switch, the rule for items, chests, lore and secrets (`seen` by default), an
optional flag that must be set first, and the room-complete tint. The `kinds`
and `icons` tables set each shape, colour, rule, collected style and legend
label; the file's header explains every value.

Under the default `seen` rule a Map Station reveals a room's layout but not its
items: choose `mapped` to show them. A station icon stays once seen, through room
unloads and saves, until the station is gone for good (a used altar set to Remove
after use, a trainer that leaves, an NPC whose despawn flag is set). An unfound
secret is never marked. Tiled objects can set `map_icon` (`auto`, `hide` or an
id from `icons`) and `hide_on_map`. Reset Project preserves this file and clears
the published Game Settings overrides.

## Random equipment drops

`random_drops.lua` ships off. **Game Settings ▸ Equipment ▸ Random drops** enables
one extra unowned weapon, charm or permanent upgrade per successful enemy defeat
roll. Weapons and Charms also need their own feature switches. Every eligible
item is equally likely; an exhausted pool gives nothing. Bosses and summoned
minions never roll. A pickup left behind is not saved.

Set `random_drop = false` on a catalog entry to protect a gate or story reward.
Set `random_drop_chance` on an enemy type to override the project chance; 0 means
never. Named Loot table entries can use `weapon_<id>`, `charm_<id>` or
`upgrade_<id>`. Upgrades apply through the shared grant path. If already applied
when collected, they pay `duplicate_currency`; unmet prerequisites leave the
pickup in place. Placed upgrades count toward Completion by their pickup ids;
random enemy drops add no world total. Reset Project preserves this config and
its catalogs, and clears the published Game Settings overrides.

## World budget

`performance_budgets.lua` sets how Prepare & Check's **Check world budget**
stage judges a world. The stage counts the game objects, sprites, collision
objects, tilemaps, particle effects, sounds, labels and factories in every baked
room, adds the rooms the streamer keeps loaded around each room, the main
collection and a runtime reserve (`spawn_caps` and `reserve`), and compares the
worst neighbourhood with `game.project`. Tiles are a view estimate: the engine
only draws the tiles on screen. The report is
`developer/assets/tiled/world_budget.txt`; Preparation Status shows its summary.
Findings are warnings unless `block_on_overflow = true`. When a pool overflows,
Preparation Status offers **Apply Recommended Engine Limits**, which raises that
`game.project` limit to the worst count times `margins` after you confirm.
Reset Project removes the report and its cache and keeps this config.

## Save identity and upgrades

The first Prepare & Check (or Game Settings Save) establishes a permanent
`game_id` in `persistence_settings.lua`. The Game tab's name field updates
`game.project`; later title renames keep the ID. Working copies retain it; clear
`game_id` in a copy intended as a different game and run Prepare & Check once. A toolkit placeholder name
shows a warning without blocking Save. The editor does not copy older player
data; use fresh beta saves.

`save_migrations.lua` holds reviewed identifier aliases for compatible content
updates. Supported saves/preferences upgrade on a copy, with verified backups;
newer unsupported data is preserved. See
[save compatibility and room rename auditing](../../docs/SAVE_COMPATIBILITY.md)
for supported versions, backups, and the exact workflow.

### Hazard returns

`game_config.lua` defines `progression.hazard_return`: enabled, default health
cost, fade seconds, protection seconds and world-bottom pit handling. Game
Settings ▸ Game ▸ Hazard returns exposes the first four. Spikes and void pits
use safe_return by default; other hazards retain damage. In `hazard_types.lua`,
`on_contact` sets a type default and optional `return_damage` replaces the game
cost. A placed Hazard can override both. Hazard Return Zones mark challenge
starts; they are transient and do not save or replace checkpoints.

### Death currency recovery

The Game Settings **Game** tab controls death currency recovery, the loss fraction,
and the minimum loss. It starts Off: death restores the last save without a
penalty. When On, an eligible death immediately saves the configured currency
loss and a recovery marker at the last safe grounded position in that room.
Without safe ground, currency is preserved and an existing drop remains; an
eligible death with zero loss clears the previous drop.

`game_config.lua` also sets the maximum loss, marker lifetime, pickup radius,
and recovery sound. A lifetime of `0` keeps the marker until collection or
replacement. Its default pickup radius is `16` world pixels, independent of
player scale. The saved marker returns when its room streams in; turning the
setting Off preserves an existing record while keeping it dormant. See
[the creator recipes](../../docs/CREATOR_WORKFLOW.html) for the complete workflow.

### Game ending

`game_completion.lua` defines the ending ID, region/flag/boss condition, completed/explore Continue policy, return checkpoint, title/body/credits, music, artwork and optional reward flag. Game Settings ▸ Ending publishes common overrides in `creator_settings.lua`. See [Preparation and endings](../../docs/PREPARATION_AND_ENDINGS.md).

### Designer tool configuration

`player_art.lua` describes PNG source geometry, animation ranges/mappings, validation and display size; `movement_test.lua` describes disposable course obstacles. Game Settings publishes overrides in `creator_settings.lua`. HUD layout/theme, discovery, minimap/world-map visibility and save policy fields have tabs in Game Settings. See [Designer tools](../../docs/DESIGNER_TOOLS.md).
