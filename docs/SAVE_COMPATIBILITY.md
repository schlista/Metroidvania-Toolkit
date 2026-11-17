# Game identity and save compatibility

Fast-travel save points now use the same global authored id space as stations,
without a room prefix. Blank save ids and blank names bake the instance id.
Existing save-point travel unlocks use the old ids: **start a new save** after
this toolkit update. The fast_travel provider remains version 2 with the same
payload; there is no save migration.

In Defold, open **Project ▸ Game Settings… ▸ Game**. **Game name** is the display
title in `game.project`. The first **Prepare & Check** (or Game Settings Save)
quietly assigns the permanent game ID in
`developer/config/persistence_settings.lua`; **Game ID** shows it read-only.
Renaming the title keeps that ID and Continue data. A toolkit placeholder title
shows a warning on the name field without blocking Save. Give each game a name
that players can recognise.

A working copy of the same game should keep its ID. For a different game, copy
the project first, clear `game_id` in the copy's `persistence_settings.lua`, then
run **Prepare & Check** once. Export Game reports title and ID and refuses an
uninitialised identity. Empty toolkit packages ship without an ID, so each
creator's first Prepare & Check assigns a new one; exported games retain it.

Game Settings does not copy older player data or import machine-local authoring
settings. Beta saves are disposable; use a fresh slot when testing a new toolkit
or sample world. Player preferences and save slots share the game's player
namespace. Layout drafts use their own scope; export the layout before changing
identity so published project content remains available in the project.

The title, ID, creator overrides and player resources publish together through
the existing transaction journal in `developer/.wizard/`. Opening Game Settings
or running **Prepare & Check** recovers an interrupted project transaction. Do
not delete a pending journal. Keep the game stopped while editing, then Build
to play with the saved identity and settings.

## Player profile

The player-scope `mvtk_profile` file is separate from save slots and is not a
checkpoint provider. Its payload is `{version = 1, game_id, sections}`. The
allocated sections are `achievements`, `records` (best times and endings seen),
and `unlocks` (Extras). Only ids and data are stored, never
translated wording. Finishing an ending writes
`records.endings_seen[ending_id] = true` beside
`records.best_times[ending_id] = min(previous, whole_run_seconds)` and forces a
profile flush, independently of the HUD and ending-time display switches.
Unrelated records fields are retained. Dev Menu test sessions and boss practice
skip both the records update and flush. The profile version remains 1; older
profiles gain the seen marker when an ending is next reached, even when their
previous best time is faster. Journal Records lists configured enabled endings
that have a seen marker, using their current creator titles and best times.
Removed or disabled ending ids remain saved but are absent from that list.

Achievements use `sections.achievements = {unlocked = {id = timestamp}, counters = {id = count}}`.
Unlocks force the profile to disk before publishing the unlock event, notice,
reward or platform call. Event counts stop at their target; ordinary counter
writes are throttled. The optional reward goes once to the slot active at
unlock time, using `achievement:<id>` as its grant once key. Other slots keep
the unlock without receiving that reward. Turning achievements off stops all
tracking and writes; Dev Menu test sessions and boss practice do the same.

Extras use `sections.unlocks = {heard = {track = true}, flags = {flag = true}, cycle = n}`.
`heard` lists music tracks that started playing in any slot; its writes use the
ordinary throttled flush, and shutdown forces them. `flags` lists the authored
unlock flags from `developer/config/extras.lua` that were set while Extras was
enabled; storing the flag rather than an entry id keeps a renamed entry
unlocked. A flag unlock forces the profile to disk before its notice. `cycle`
is the highest New Game+ cycle any slot has started. Each session start records
watched flags that are already set and the current cycle, silently, so entries
added after a save still unlock. Ending and achievement unlocks are read from
`records.endings_seen` and `achievements.unlocked`; they are never copied.
Turning Extras off stops every write; Dev Menu test sessions and boss practice
do the same.

Deleting a save slot keeps the profile. **Project ▸ Reset Project to Empty**
schedules deletion of both `mvtk_profile` and `mvtk_profile_backup` on the next
game launch. Different games use their own game-ID namespaces; a file carrying
a different non-empty game ID is ignored and never overwritten. An absent or
empty stored ID is accepted for compatibility before identity assignment.

Writes retain the previous good payload in `mvtk_profile_backup` before
replacing the main file. Loading falls back to that backup when the main file
is missing or corrupt, and starts empty if neither is usable. Ordinary flushes
are throttled; shutdown and progression milestones can force a flush. Dev Menu
test sessions and boss practice never flush either file, including at shutdown.
The explicit player-data migration includes both files, validates version 1 and
the sections table, and refuses files owned by another game.

## Run statistics

The `run_stats` checkpoint provider is version 1, order 210. It stores whole,
non-negative integers: `playtime_s`, `deaths`, `enemies_defeated`,
`bosses_defeated`, `collectibles_found`, `secrets_found` and `rooms_visited`.
Older slots start these values at zero; there is no conversion from the slot's
wall-clock play time. Only pickups with `respawns = false` count as collectibles.
Provider apply and defaults do not emit events or show feedback.

A normal death restart carries the live statistics, including that death and
unsaved run time, over the loaded checkpoint in the same slot. It writes nothing
immediately; the next save persists the carry. A failed load, another slot,
Dev Menu test session or boss practice discards the carry. Quitting from the
death menu before restarting keeps the last saved statistics. Continue starts
from saved statistics. The slot screen separately measures wall-clock session
time; an in-slot death restart now retains its time since the last save.
The profile's `records` section remains separate from this per-slot provider.
When **Progression ▸ Records ▸ Time on ending** is on, the existing completion
provider captures optional `run_time_s` alongside its inventory statistics.
Ending pages use that saved whole-second snapshot as h:mm:ss; an absent field
retains the previous minutes line, including editor previews and older saves.

Run time stops for pause menus, Settings, Journal, a pausing Inventory, dialogue,
cutscenes, the death screen and loading. Streamed room transitions count.
Hitstop and slow motion slow it because it uses the collection time step.

## Enemy defeats

Enemy nests are Enemies with the `nest` archetype, which defaults to `never`.
They use the same Flags rule below; a stable authored Defeat flag preserves a
cleared nest after saving and reloading. Required action changes no save data.

Placed enemies with **On defeat ▸ Respawn** `never` store a boolean in the
existing Flags provider: the authored **Defeat flag**, or
`enemy_defeated_<defeat_key>` when blank. The baked defeat key is the room
collection instance id. Keep the authored flag stable for important enemies;
room or object identity remaps can alias a generated key. Older saves lack
these optional flags and start with the enemy alive. No provider, provider
version or save-format change is needed.

An authored Defeat flag is written under every policy. `save` and `always`
suppression itself lives only in memory. `always` lifts on room entry;
`save` lifts after Save Point rest, death restore or a new loaded session.
Checkpoints save progress without counting as rest. Only the current room
revives immediately; other rooms wait for entry. `room_reload`, the default,
retains its return-on-room-rebuild behaviour. Runtime-spawned and older
unidentified enemies use `room_reload`.

**Game Settings ▸ Enemies and elements ▸ Enemies ▸ Save after a permanent
defeat** includes the defeat and synchronous listener flags in one save when
enabled. With it off, save normally to keep the defeat; dying before that save
reverts it. Save failures do not make a defeat durable.

### Champion defeats and rewards

A champion with inherited **Respawn** resolves to `never` before archetype or
project defaults. It uses the same persist key: the trimmed authored **Defeat
flag**, or `enemy_defeated_<defeat_key>` when blank. Its reward grant uses
`once_key = "champion:" .. persist_key`, stored as the boolean
`grant_once:champion:<persist_key>` in the existing Flags provider. Keep both
the defeat identity and authored flag stable to preserve defeat and reward
history. Older saves lack these flags and start with the champion alive and
its reward available.

Champion defeats always batch the direct reward and defeat/listener flags in
one save, even with **Save after a permanent defeat** off. Explicit repeatable
policies still win: the fight can return, but its grant once key prevents
another reward. A generated permanent-defeat flag is written only for `never`;
an authored Defeat flag is written under every policy. Failed saves are not
durable. No provider, provider version or save-format change is needed.

## Saved switch shortcuts

The existing Flags provider stores `switch_state_<room>_<tiled id>` as a boolean
and `switch_channel_<channel>` as `on|<message>` or `off|<message>`.
Stays-open doors also store the receiver-owned boolean
`switch_state_timed_door:<door_id>`. It preserves their first opening if a sender
later writes off while the door's room is unloaded; no additional baked property
is needed. The colon namespace is distinct from the baker's numeric object IDs.
The baker supplies each lever and plate's stable text `persist_key` from its room
and Tiled object ID. Renaming a target channel changes its saved identity.
Older saves simply lack these optional keys and use authored initial states.
A death restore reverts them to the last save like every other flag. No switch
provider or save-format migration is added. Stays-open timed doors write their
channel; receivers restore without replaying sound or scheduling an auto-close.

## Carryable sockets

Persistent sockets use the existing Flags provider. Their own boolean is
`switch_state_<persist_key>`; blank **Persist key** bakes `<room>_<tiled id>`.
The saved target remains `switch_channel_<target_id>` with `on|<message>`.
The consumed carryable writes `carry_placed_<carry_id>` and hides/disables itself
on every room load. Blank **Carry id** uses the baked instance id. Keep these
identities stable after release; changing one can respawn a consumed object or
reset a socket/channel. A saved fill restores without emitting; each receiver
replays its own channel. **Set flag on** is a one-way authored ever-filled flag.
A non-persistent socket saves neither its fill nor its object and **Take** emits
off after successful pickup. No new provider, provider version, save format or
migration is added; old saves lack the optional keys. Death/load restores the
last saved Flags snapshot, so test persistence after actually saving.

## Supported payloads

| Store | Supported input | Upgrade behavior |
| --- | --- | --- |
| Checkpoint | Version 1 (including unversioned legacy structure), version 2 | Check integrity first; upgrade a copy to version 2, then migrate providers and identifier aliases. |
| Provider payload | Its registered version, or an older version with every migration step supplied | `migrations[old_version](copied_data)` returns the next payload. Missing steps and newer versions block loading/saving. Unknown providers are retained. |
| Player preferences | Unversioned, version 1 | Keep preference values; next successful save writes version 1. |
| Controller bindings | Version 2 | Other versions are not overwritten. |
| Project creator settings | Version 1 | Published project overrides are loaded; machine-local authoring values are not imported. Unknown project versions are rejected. |

Maintainers register one checkpoint provider per subsystem at module load,
using text identities and payloads made of strings, numbers, booleans and
tables. Its `apply` tolerates missing and unknown fields, `defaults` resets
in-memory state, and every version increase supplies each migration step.
To restore a retired provider, opt its id into `mvtk/core/product.lua`'s
`unretire.providers`, register version 2 with
`migrations = { [1] = function() return {} end }`, and add its module to
`test/provider_modules.lua`. Keep the retirement tables and compatibility
suite unchanged; the restoring subsystem's own suite must prove an old
version 1 payload migrates to the empty version 2 shape and a new capture
survives a re-save.

Checksum-bearing saves must pass their stored checksum before migration code
runs. Historical saves without a checksum have structural/version checks only.
Checksums detect accidental changes; they are not authentication.
New saves use a versioned checksum with stable hexadecimal hash identities;
it does not depend on debug names registered during a particular game session.
Legacy checksums are still verified by their original algorithm. Saves rejected
by that older algorithm remain preserved until explicitly deleted. On the slot
screen, keyboard **X** or **Delete**, or controller **X**, clears an unavailable
slot as well as a readable one so it can be reused for a new game.
Migration never overwrites the original during load. Before applying an upgrade,
the first original is preserved and checked in `<slot>_pre_upgrade`. Normal
successful saves rotate `<slot>_backup`. Unversioned preferences are preserved
in `mvtk_settings_pre_upgrade_v0`. Backup failures block the corresponding
operation. Future/foreign saves never trigger fallback restoration; the slot
screen reports them unavailable and does not launch a fresh game over them.

## Save slot summaries

Every full save writes `meta.summary`, a small table the save slot screen reads
without loading the save. It holds ids and integers only, never display text:
`region` (a `developer/config/biomes.lua` id), `room`, `percent`, `abilities`,
`bosses`, `level` (only while leveling is on) and `ending` (the id of the
ending reached). The region comes from the checkpoint room, because Continue
resumes there. The field is additive: the save format stays version 2, there is
no provider and no migration, and the checksum covers it like the rest of
`meta`. A death's currency drop updates the save without rebuilding the
summary, so the summary always describes the last full save. A save made before
this field existed has no summary and shows the play time and last-saved lines.
`progression.saves` in `developer/config/game_config.lua` sets `show_summary`,
`allow_copy` and `summary_fields`.

Copying a slot writes the source slot's last save onto the target slot, so the
two files are identical, checksum included. The target's previous save moves to
its `<slot>_backup`, and its `<slot>_pre_upgrade` and `<slot>_pre_ngplus` copies
are cleared, because they belong to the replaced game. The last-played slot does
not change. A copy is refused onto the same slot, onto a slot that holds a
foreign or newer save, and onto the active slot while a death is waiting to be
saved.

## Stable authored identities

A persistent Gate group opening uses the existing Flags provider key
`gate_group_<group_id>`, alongside the unchanged per-gate `gate_<id>` keys.
Renaming a group after release forgets that shared opening in existing saves;
keep the authored `group_id` stable. Temporary openings never write the group
flag. Gates that disallow persistence ignore it. No provider version or save
format changes are needed; older saves simply lack the optional group key.

The version 1 `difficulty` checkpoint provider (order 15) stores `{ profile }`
per save slot. Missing or unknown profiles use the configured default; fixed
selection mode always uses that default. A deleted Game Settings default falls
back to the authored file's default. Choosing a profile on a new game happens
after save creation resets providers. Pause-menu changes in anytime mode update
only this provider in the last saved snapshot, preserving unsaved progress as
unsaved until a normal save trigger, including Quit. No migration is needed;
beta saves remain disposable. Start a new save
to test this update.

The version 1 `healing` checkpoint provider (order 48, before abilities at 50)
stores `{ charges, bonus_sources, selected }`. Flask upgrades use each placed
collectible's text ID as their idempotent source. Selection is restored before
ability ownership and falls back when Quick Use is next resolved. A missing
payload uses the configured starting capacity. This is a new provider, so it
needs no migration; beta saves remain disposable. New Game+ carry is decided
with that feature.

Permanent resource bonuses use the version 1 `permanent_stats` checkpoint
provider (order 44). Each entry stores a text key, kind and ID plus a numeric
snapshot of its bonuses. Health, energy and stamina containers retain their
maximum increases across loading and Continue. Registered upgrade definitions
can resolve current bonuses; until then, the saved snapshot is used.
Older saves contain no ledger and cannot recover previously lost bonuses.
Start a new save for this update. Baked container keys follow their instance
names; runtime containers receive a new generated identity on each spawn.

With the Defold 1.13.2 text-property update, new saves store authored gate,
collectible, inventory, fast-travel and flag IDs as text. Chest-opened and
wall-broken flags retain their hexadecimal hash suffixes, including secret-wall
visibility. Saves from earlier betas are not expected to carry over; this
change adds no identifier migration or legacy hash-key adoption. Start a fresh
slot when testing this update.

Room IDs come from the exported room name. Baked object IDs use the existing
`room_type_TiledObjectID` rule. Keep the room name, resolved object type and
Tiled numeric ID stable after release. Moving an object preserves its ID;
deleting/recreating it usually does not. Explicit IDs such as `chest_id`,
`wall_id`, boss and teleporter IDs must remain stable and must be changed when
making a separate copy that must not share state. Tiled gameplay objects stay
on the top-level `templates` layer. Regeneration does not mint new identities.

Before renaming or copying released content, capture a review snapshot:

```text
lua tools/audit_content_identity.lua snapshot .build/before.lua
```

After editing and exporting the rooms, compare it:

```text
lua tools/audit_content_identity.lua compare .build/before.lua .build/remap.lua
```

The optional remap file explicitly pairs removed IDs with their replacements:

```lua
return {
    rooms = {old_room = "new_room"},
    objects = {old_room_chest_7 = "new_room_chest_7"},
}
```

The audit reports removed identities, changed properties and literal references
still pointing to renamed identities. It rejects missing destinations,
many-to-one remaps, and remapping copies whose originals still exist. It emits
reviewable save aliases for checkpoint/world rooms, discovery, and chest/wall
flags. Other providers require explicit review. This audit does not rewrite
Tiled files or validate every typed relationship; that is Phase 3's work.

Review the report's `aliases`, then place the approved entries in
`developer/config/save_migrations.lua` under `identifier_aliases`. Paths target
the actual stored payload, including provider data and any legacy mirror.
Chest/wall aliases use `hash_prefix` because their runtime keys contain Defold
hex hashes. Keep those rules; changing their text changes their identity.
Each applied rule is recorded in save metadata so later progress at the new
identity is not overwritten by its retained old alias. Cycles, ambiguous
merges and conflicting first-time destination values block the upgrade.

Keep backups and test with an older save in a disposable project before
releasing a content rename. Re-export the layout and regenerate rooms; retain
the permanent game ID for a compatible update to the same game.

Completion uses the version 1 `game_completion` checkpoint provider. Older saves
without this provider begin incomplete; loading another slot clears the previous
slot's completion and playtime. The chosen ending's id is stored in `data.id`;
the flat main ending and entries in `game_completion.endings` share that identity
space. No variant field or provider version change is needed. One ending completes
each slot, including after Explore. Keep every ending id stable when changing
text, art or credits. Removing or renaming the stored id makes the slot incomplete
again; use an explicit save migration to preserve finished games. Existing flat
configs and saves continue to work with an empty other-ending list. Test both Continue policies after changing a return room or checkpoint.

## Grant identity and ability sources

Grant transactions store `grant_once:<key>` in the existing flags provider.
Use stable authored keys for retryable rewards. A failed disk write retains
that flag and the complete grant in memory; a retry treats `already_granted`
as done, then retries the surrounding save. Death restoration still discards
unsaved gains. No save provider or schema version is added.

Collectible grant units use ids `grant:<once_key or instance_id>`, then `#n`
for subsequent units. Maximum-stat behaviors record these as
`pickup:grant:<identity>[#n]` in the existing permanent-stat ledger. Compensation
forgets only keys absent before this transaction. Existing pickup keys survive.
Ability source `purchase` records an exchange and is never revoked by start
setting reconciliation; only source `start` is revoked.

### Transient combat statuses

Poison, Burn, Freeze and Slow are never saved and add no save provider or version.
Death, respawn and a new play session clear the status registry and the player's
temporary `status` speed source. Teleport keeps statuses; hazard and Movement
Zone leases clear when the player leaves. Loading a save never restores statuses. HUD chips display only the live status
registry; their countdowns are never stored in a save.

### Encounter authoring identities

Keep an authored Encounter id stable after release. A non-repeatable encounter's
clear flag defaults to `encounter_cleared_<encounter identity>`; an explicit
Clear flag replaces that default. Its target shortcut uses the existing
`switch_channel_<target id>` Flags entry. Repeatable encounters do not persist
clear flags or shortcut channels. Mid-fight state is never saved; no save provider
or format version is added. With Autosave on clear enabled, clear flags, shortcut
channels and synchronous encounter-cleared listener changes share one save.
Loading a saved clear never restarts the fight or re-emits its target message;
linked doors replay the saved channel themselves. Death or abandoning an
unsealed fight resets its waves without a clear reward.

### Container fragments

Fragment progress uses the existing Flags provider: `fragment_count_<set>` stores
the total pieces collected and `fragment_piece_<collectible id>` prevents counting
a placed piece twice. Granted pieces use stable `grant:<once key or instance id>`
identities, with `#n` for later units. Keep placed identities and set keys stable
once saves are published.

Each completed set records `fragment:<set>:<n>` in the permanent-stat ledger, or
in the healing provider's bonus sources for flask charges. Both are idempotent;
partial progress and completed increases survive a save/load together. There is
no new provider or save version. Piece-count changes take effect at the next
pickup, without revoking earlier increases. Autosave on collectible pickup keeps
its existing setting; fragments never force an additional save. Notices and
translated text are never stored in saves.

### Banked currency

The restored `bank` provider is version 2, order 41, with a `{ balance }` payload
and no legacy mirror key. A version 1 bank payload migrates to an empty payload:
its old balance is discarded. New saves preserve the captured balance on reload
and re-save. Missing or invalid balances default to zero; negative values clamp
to zero and fractional values round down. Applying or defaulting this provider
stays silent and never changes carried currency.

Deposits and withdrawals accept positive whole amounts and refuse insufficient
funds without a partial transfer. `shops.lua` `settings.bank.autosave` defaults
to true: each completed transfer batches carried and banked balances into one
save. A suspended save keeps the transfer in memory without a failure notice;
a real write failure keeps it in memory and shows the save-failed notice.
Death fees affect carried currency only and leave the bank payload untouched.
The bank station and its menu arrive separately.

### Catalog purchases and permanent upgrades

`shop_sold:<catalog>:<entry>` stores a numeric count in Flags, shared across all
stations using that catalog. Raising configured stock reopens the added units.
Entry set flags use the existing Flags provider. Permanent upgrades use
`upgrade:<id>` in `permanent_stats`, with four-key delta snapshots and a current
config resolver installed by gameplay services. A removed definition falls back
to its stored snapshot. Container purchases use
`pickup:grant:shop:<catalog>:<entry>:<n>` (and `#n` for additional grant units).
Catalog and entry ids must remain stable after release. Purchased abilities keep
source `purchase` and survive removal of their starting-unlock setting. No save
provider or format version is added. Refused purchases write no save; committed
purchases whose save is suspended or fails remain only in memory until saved.

### Level and experience

The existing `progression` provider stays version 1, order 45. It now stores
whole nonnegative `experience` and a derived `level`. Loading recomputes level
from XP using the current curve, caps XP at the maximum level, and idempotently
rebuilds the permanent PlayerStats `leveling` source without notices, events,
healing or milestone grants. Older saves default to level 1 and XP 0. Malformed
XP (including numeric strings and nonfinite numbers) becomes 0. Legacy
`skill_points` and `experience_to_next` remain discarded. The legacy `leveling`
provider remains retired. Turning leveling off suspends gains and clears its stat
growth; existing capped XP is retained. Death reloads saved XP as normal.

The `bestiary` checkpoint provider is version 1, order 220. It stores
`species[id] = {defeats, skin, enemy_type, archetype}` and
`bosses[preset] = {defeats}`. These are creature IDs and numeric counts; names
and descriptions remain in `developer/config/bestiary.lua`. Missing data
starts empty. Apply and defaults never post notices or emit events. Defeats
record while visibility is off; `in_bestiary = false` excludes an enemy, and
`include_spawned` and `include_bosses` control those records and census totals.
Counts persist at the next normal save; the listener never saves by itself.

The `npc_memory` checkpoint provider is version 1, order 215. It stores
`seen[npc_id] = signature`, a number computed from the source text of the lines
an NPC would show when its last conversation ended, and
`people[npc_type] = {last = text}`, the last line that type said, as source text.
Keep `npc_id` stable after release, as for vendor greetings. Missing data starts
empty, so every opted-in NPC shows its new-dialogue marker again. Editing a
conversation's text changes its signature, so existing saves see that marker once.
Apply and defaults never emit `npc_met`. New Game+ does not carry it: every NPC is
unheard in a new cycle.

### Quest state

The restored `quests` provider is version 2, order 48 (ties sort by provider id).
Its payload is `{quests = {id = {state, step, counters}}}`. States are
`not_started`, `active`, `completed`, `turned_in` and `failed`; counters use step
ids and non-negative integers. Display text remains in `developer/config/quests.lua`.
Version 1 payloads migrate to `{}` and are deliberately discarded because the
old representation is incompatible. Apply/defaults never emit facts, mirror
flags or rewards; session start evaluates the current conditions separately.
Turn-in batches the reward once key `grant_once:quest:<id>`, quest state and
`quest_turned_in_<id>` mirror with one save. Start, complete and fail also expose
`quest_started_<id>`, `quest_completed_<id>` and `quest_failed_<id>` mirrors.
The run statistics provider adds `quests_completed`, defaulting missing values
to zero; it increments on completion rather than turn-in. No provider version
change is required for that additive normalized counter.

### Equipped weapon

The `weapons` provider is version 1, order 46, and stores `{equipped}` as a
stable weapon id. Ownership stays in the existing Inventory provider; the
configured starting weapon is virtual and is never granted by defaults or
apply. Restore silently rejects unknown, unowned or ability-locked ids and
falls back to an eligible starting weapon, or unarmed. Apply is idempotent and
posts no events, notices or rewards. Optional `tiers = {[weapon_id] = tier}` shares this version; absent data means
tier 1. Empty maps are omitted. Apply silently drops unknown weapons and invalid
tier numbers. Equip changes ride the next normal save; crafting saves tiers and
costs in one exchange. No crafting provider is added; its v1/order 49 reservation
is released because weapon state belongs to the weapons provider.

### Equipped charms

The `charms` provider is version 1, order 47, storing `{equipped = {ids}}` in
equip order. Ownership and Charm Slot counts remain in Inventory. Apply drops
unknown, duplicate or unowned ids, then removes last-equipped charms until the
total cost fits `min(max_slots, base_slots + Inventory.count(slot_item))`.
Defaults and apply rebuild one equipment-layer `charms` stat source without
notices, events, grants or saves. Reapplying identical state does not churn stat
listeners. Equip and unequip changes ride the next ordinary save. Consuming a
charm's last Inventory item unequips it; losing slot capacity trims the tail.

### Combat trial records

Trials use the existing Flags provider, with no new provider or version change.
`trial_cleared_<trial_id>` (or the authored Clear flag) stores a successful clear;
`trial_rank_<trial_id>` stores the best rank index, and `trial_best_<trial_id>`
stores the best metric (integer tenths of a second, or hits for survive goals).
`grant_once:trial:<trial_id>` protects the first-clear reward. Keep Trial id and
Clear flag stable after publishing. Active fights are transient: loading a save
starts idle, while completed records and granted rewards remain saved.

### Countdown records

Countdowns use the existing Flags provider, with no new provider or version change.
The finish flag (`countdown_cleared_<id>`, or the entry's `finish_flag`) stores a
finish; `countdown_best_<id>` stores the best time in integer tenths of a second,
and `grant_once:countdown:<id>` protects the first-finish reward. Keep countdown
ids stable after publishing. A run itself is never saved: any load ends it, and
starting a play session clears every configured `countdown_<id>_active` flag, so
a save made while a run was active (with `block_saves = false`) loads with the
run stopped.

## New Game+ replay core

The optional `new_game_plus` provider is version 1, order 205, storing only
`{cycle}` (0 for the first run). It restores silently. It does not change the
profile's achievements, endings seen or best times. The feature ships off;
Game Settings > Progression > New Game+ enables its save-slot choice. G or the
top face button opens a prompt on an eligible completed slot. No is selected
initially; No or Cancel writes nothing. Yes starts another cycle in the same
slot. A cycle above 0 appears beside the slot's last-saved date.

A request rewrites the same completed slot. Before any reset, the validated raw
save is written to `<slot>_pre_ngplus` and read back with a matching checksum.
That backup is replaced for each new cycle, rather than retaining an earlier
run. A failed backup leaves the slot untouched. A failed transformation or save
restores the completed backup and reports the failure. Keep a separate copy of
valuable player data before testing. Never test replay inside a Dev Menu test
session or boss practice; saves are suspended there.

Difficulty always carries. The defaults carry level and total experience only
from progression; owned weapon/charm items, equipped weapons/charms and weapon
tiers; wallet and bank currency; bestiary knowledge; and `cutscene_seen_*` flags.
`carry.items` optionally keeps other inventory items, including keys.
`carry.abilities` keeps acquired abilities. `carry.upgrades` defaults false and
controls the complete permanent-stat ledger (including purchased upgrades and
containers) plus healing bonus charges; spent charges and quick-item selection
reset. Carried ledger sources remain idempotent: collecting them again adds no
bonus. Stored provider versions remain attached to carried entries and the
normal reapply path restores the legacy inventory/progression mirrors.

Everything else resets: checkpoint position and health, discovery, bosses and
permanent enemy defeats, doors, gates, travel, elevators, death drops, shops,
altars, quests, run statistics, ending state, fragment progress and trial records.
Only seen-cutscene flags can survive the flag reset. Runtime starts at the Tiled
player start when no checkpoint remains. The opening scene replays when its
seen flag was not carried.

Reset Project to Empty and slot deletion also clear `_pre_ngplus`, alongside
`_pre_upgrade` and ordinary backups. Player-data migration includes both backup
suffixes. A deletion tombstone counts as absent when preserving the next
pre-upgrade copy for a reused slot.

## Steam Cloud

The optional Steam add-on uses Steam Auto-Cloud with the existing permanent
game identity and player save folder. It ships off. Follow
[Use Steam Cloud](../developer/addons/steam/README.md#use-steam-cloud) to generate
the Steamworks rows and quotas with Prepare & Check, then publish them for
your own app ID. Auto-Cloud syncs only when Steam starts the game, and on exit;
editor runs and app 480 cannot verify it. Testing requires an uploaded build
launched from the Steam client and two machines. macOS/Linux paths remain
experimental and UNVERIFIED.

The patterns sync `mvtk_save_slot_*` (including `_backup`, `_pre_upgrade` and
`_pre_ngplus`), `mvtk_last_slot` and `mvtk_profile*` (profile and backup).
`mvtk_settings` syncs only with `include_preferences`; `mvtk_bindings_v2` only
with `include_controls`. Display preferences and controller mappings may differ
between machines. `game_debug.txt` and `mvtk_settings_pre_upgrade_v0` never
sync. Layout and wizard data live in other folders and are not included.

Slot deletion writes tombstones: these sync as ordinary files, so a deletion
can reach the other machine without a remote-delete API. Steam owns the
conflict window at launch when local and cloud copies disagree; the toolkit
does not merge them or choose a winner. A newer or foreign save stays
unavailable through the existing save checks, rather than falling back to an
older backup or being overwritten. Keep the permanent `game_id` stable after
release, and use one Steam account per OS user because the local folder is
shared by those accounts.

Offline play keeps using local files. It syncs at the next Steam launch after
reconnecting; editing saves offline on both machines can cause Steam's conflict
window. Keep a separate backup when testing those conflicts. Dev Menu test
sessions suspend slot/profile writes, and designer previews use disposable
folders, outside the synced player folder.
