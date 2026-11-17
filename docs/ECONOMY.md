# Economy

Purchase data lives in `developer/config/shops.lua`; permanent upgrade definitions
live in `developer/config/upgrades.lua`. Catalogs share one purchase menu and
transaction path. Placed shops, upgrade stations and skill trainers open that menu through range interaction.

## Catalogs and offers

Each catalog has a stable id, a translatable name and an ordered `entries` list.
An empty entries list is valid. Each offer needs a stable `id`, `gives` and an
integer `price` of at least 0. A zero price creates no currency cost. Optional
`cost_items = { upgrade_material = 1 }` adds item costs to the same exchange.
The examples are Town Vendor, Apothecary, Forge and Training Hall.

To add an offer:

1. Open `developer/config/shops.lua`.
2. Add an entry to the chosen catalog's `entries` list using the commented fields.
3. Save the file.
4. Choose **Project ▸ Reload Editor Scripts**.
5. Choose **Project ▸ Prepare & Check**.
6. Choose **Project ▸ Build**.

Reopen `MVTK.tiled-project` after changing catalog ids to refresh its shops dropdown.
Keep catalog and entry ids stable after releasing a game: saves use those ids.

## Place a shop

A shop sells entries from a purchase catalog. Without **Art item** or linked
**Object Art**, the shop is invisible. Catalog prices and stock live in
`developer/config/shops.lua`.

1. In Tiled, select the top-level **templates** object layer.
2. Place **Interaction ▸ Shop** from `tiled/templates/interaction/shop.tx`.
3. Choose **Shop id** from the catalog dropdown.
4. Set **Presentation ▸ Prompt text** to the interaction prompt; blank uses the translated Shop prompt.
5. Set **Presentation ▸ Menu title** if this shop needs a title instead of the catalog name.
6. Set **Presentation ▸ Range** to the interaction distance in world pixels.
7. Tick **Presentation ▸ Show on map** if the shop should appear after room entry.
8. Set **Access ▸ Requires flag** if opening this shop needs a saved flag.
9. Set **Access ▸ Locked text** if locked access needs a custom explanation.
10. Set **Art item** if you use catalog artwork.
11. Link an **Object Art** object's **Owner ref** to the shop if you use separate artwork instead.
12. Choose **File ▸ Export Current Room**.
13. In Defold, choose **Project ▸ Reload Editor Scripts**.
14. Choose **Project ▸ Prepare & Check**.
15. Choose **Project ▸ Build**.
16. Open **Layout Editor** from the title screen.
17. Click **Export**.
18. Choose **Play Game** on an empty save slot.
19. Press **Interact** beside the shop.

The paused purchase list shows prices, stock and unavailable offers. A purchase
updates the list immediately; saved stock is shared by all shops using its catalog.

Map icons appear after the shop's room has streamed in during the current session.
The shop rectangle adds no collision body. Analyze Progression models catalog rewards as uncertain: currency affordability,
stock and access conditions still need playtesting.

## Place an upgrade station

An Upgrade Station sells permanent stats from a purchase catalog. Its offers live
in `developer/config/shops.lua`; their stat effects and prerequisite tiers live
in `developer/config/upgrades.lua`. Without **Art item** or linked **Object Art**,
the station is invisible.

1. In Tiled, select the top-level **templates** object layer.
2. Place **Interaction ▸ Upgrade Station** from `tiled/templates/interaction/upgrade_station.tx`.
3. Choose **Upgrade catalog**; **forge** is the sample permanent-stat catalog.
4. Set **Presentation ▸ Prompt text**; blank uses the translated Upgrade prompt.
5. Set **Presentation ▸ Menu title** if this station needs a title instead of the catalog name.
6. Set **Presentation ▸ Range** to the interaction distance in world pixels.
7. Tick **Presentation ▸ Show on map** to show the shop marker after room entry.
8. Set **Access ▸ Requires flag** if opening the station needs a saved flag.
9. Set **Access ▸ Locked text** if locked access needs a custom explanation.
10. Set **Art item** if you use catalog artwork.
11. Link an **Object Art** object's **Owner ref** to the station if you use separate artwork instead.
12. Choose **File ▸ Export Current Room**.
13. In Defold, choose **Project ▸ Reload Editor Scripts**.
14. Choose **Project ▸ Prepare & Check**.
15. Choose **Project ▸ Build**.
16. Open **Layout Editor** from the title screen.
17. Click **Export**.
18. Choose **Play Game** on an empty save slot.
19. Press **Interact** beside the station.

The paused menu shows each upgrade's description and stat changes. A missing
prerequisite reads **Requires Health Boost I**, for example; an owned upgrade
reads **Applied** and cannot be bought again. Buying capacity updates the player
immediately and saves the permanent bonus. A stamina boost enables stamina when
**Max stamina** starts at 0. Upgrade stations do not buy inventory items.

Permanent effects support `max_health`, `max_energy`, `max_stamina` and
`damage_mult`. Add prerequisite upgrade ids to an upgrade's `requires` list for
tiers. An offer uses `gives = "upgrade:<id>"` and its currency `price` plus any
`cost_items`. Keep upgrade ids stable after release: the saved ledger records
`upgrade:<id>` once. Damage Boost multiplies outgoing damage by 1.05; breakable
walls keep counting damage, so a wall with health 3 still takes three light hits.

## Place a bank

A bank moves currency between the carried balance and one shared saved balance.
Banked currency stays safe from the death drop. Banks have no purchase catalog.
Without **Art item** or linked **Object Art**, the bank is invisible.

1. Open `MVTK.tiled-project` in Tiled.
2. Select the top-level **templates** object layer.
3. Place **Interaction ▸ Bank** from `tiled/templates/interaction/bank.tx`.
4. Set **Bank id** to a unique stable name.
5. Choose **Access ▸ Bank mode**: **both**, **deposit** or **withdraw**.
6. Set **Presentation ▸ Menu title** if the bank needs a custom title.
7. Clear **Presentation ▸ Prompt text** to use the translated Bank prompt.
8. Set **Presentation ▸ Range** to the interaction distance in world pixels.
9. Tick **Presentation ▸ Show on map** to show the shop marker after room entry.
10. Set **Access ▸ Requires flag** if access needs a saved flag.
11. Set **Access ▸ Locked text** if access needs a custom explanation.
12. Choose **Art item** if using catalog artwork.
13. Link an **Object Art** object's **Owner ref** to the bank if using separate artwork.
14. Choose **File ▸ Export Current Room**.
15. Close Defold after changing toolkit modules.
16. Open Defold.
17. Choose **Project ▸ Reload Editor Scripts**.
18. Choose **Project ▸ Prepare & Check**.
19. Choose **Project ▸ Build**.
20. Open **Layout Editor** on the title screen.
21. Click **Export**.
22. Choose **Play Game**.
23. Start on an empty save slot.
24. Press **Interact** beside the bank.

The paused menu shows carried and banked balances. Each permitted direction lists
its configured amounts followed by **Deposit all** or **Withdraw all**. A row is
disabled when its full amount is unavailable; it never transfers a smaller amount.
The default amounts are 10 and 100, set by `settings.bank.steps` in
`developer/config/shops.lua`. All banks share the balance regardless of **Bank id**.
Blank menu titles use the translated Bank title. Journal ▸ Records shows **Banked**
while that balance is above 0.

Transfers autosave both balances by default (`settings.bank.autosave` in
`shops.lua`). A disk failure keeps the transfer in memory and shows a save-failure
notice. A pending death drop or a sandbox session suspends saving: transfers then
stay in memory without a failure notice. Save after recovering the death drop to
keep those changes. With the death drop enabled, dying drops only carried currency;
it leaves the saved bank balance intact. Withdrawn currency returns to the carried
balance shown by the HUD. Quit and load to check persistence.

## Place an offering altar

An offering altar trades once: its currency and optional item cost buy the
reward written on the object. It has no catalog. Without **Art item** or linked
**Object Art**, the altar is invisible.

1. Select the top-level `templates` layer in Tiled.
2. Place **Interaction ▸ Offering Altar** from `tiled/templates/interaction/offering_altar.tx`.
3. Set **Altar id** to a stable unique name for this altar.
4. Set **Offer ▸ Cost currency** to a nonnegative whole amount.
5. Set **Offer ▸ Cost item** to an item id if the trade also costs items.
6. Set **Offer ▸ Cost item count** to the positive whole item count.
7. Set **Payout ▸ Reward** to grant text, such as `collectible:health_container`.
8. Set **Payout ▸ Reward text** if the question needs a custom reward label.
9. Set **Presentation ▸ Menu title** if the menu needs a custom title.
10. Clear **Presentation ▸ Prompt text** to use the translated Offer prompt.
11. Set **Lifecycle ▸ Requires flag** if access needs a saved flag.
12. Set **Lifecycle ▸ Locked text** if access needs a custom explanation.
13. Set **Lifecycle ▸ Set flag** if the reward should also set a flag.
14. Tick **Lifecycle ▸ Remove after use** if the used altar should disappear.
15. Choose **Art item** if using catalog artwork.
16. Link an **Object Art** object's **Owner ref** to the altar if using separate artwork.
17. Choose **File ▸ Export Current Room**.
18. Close Defold after changing toolkit modules.
19. Open Defold.
20. Choose **Project ▸ Reload Editor Scripts**.
21. Choose **Project ▸ Prepare & Check**.
22. Choose **Project ▸ Build**.
23. Open **Layout Editor** on the title screen.
24. Click **Export**.
25. Choose **Play Game**.
26. Start on an empty save slot.
27. Press **Interact** beside the altar.
28. Choose **Yes** in its cost-and-reward question.

A blank reward label describes the grant; a blank menu title uses Offering.
Currency and items are charged together only when the reward can be given.
A refused or unaffordable trade changes nothing. A used altar refuses further
offerings after loading too. **Remove after use** removes its linked art along
with it, both immediately and on later loads. Keep **Altar id** unchanged after
publishing: it keeps the saved used state stable. A blank id uses the baked object
id, which changes if the object is recreated.

The reward uses the same grant grammar as catalog `gives`, for example
`item:potion_small:2`, `ability:double_jump`, `flag:altar_blessed` or
`collectible:health_container`. Separate multiple grants with commas.
Analyze Progression treats the reward as uncertain because offering costs need
playtesting. There is no repeat-use option or use counter.

## Place a skill trainer

A skill trainer sells ability unlocks from `developer/config/shops.lua`.
Training Hall sells Wall Jump and Double Jump. Each entry uses `ability:<id>`;
ability ids and descriptions come from `developer/config/abilities.lua`.
Without **Art item** or linked **Object Art**, the trainer is invisible.

1. Select the top-level **templates** layer in Tiled.
2. Place **Interaction ▸ Skill Trainer** from `tiled/templates/interaction/skill_trainer.tx`.
3. Choose **Trainer catalog**.
4. Set **Presentation ▸ Menu title** to override the catalog name if needed.
5. Set **Presentation ▸ Prompt text** if the button needs different wording.
6. Set **Presentation ▸ Range** for the interaction distance.
7. Tick **Presentation ▸ Show on map** to show the shop marker after room entry.
8. Set **Access ▸ Requires flag** if opening the trainer needs a saved flag.
9. Set **Access ▸ Locked text** to explain that requirement.
10. Tick **Lifecycle ▸ Leave when done** to remove the trainer after every catalog ability is learned.
11. Choose **Art item** for catalog artwork.
12. Link an **Object Art** object's **Owner ref** to the trainer when using separate artwork.
13. Choose **File ▸ Export Current Room**.
14. Close Defold after updating toolkit authoring modules.
15. Open the project in Defold.
16. Choose **Project ▸ Reload Editor Scripts**.
17. Choose **Project ▸ Prepare & Check**.
18. Choose **Project ▸ Build**.
19. Click **Export** in the Layout Editor.
20. Choose **Play Game** on an empty save slot.
21. Press **Interact** beside the trainer.

Purchased abilities work immediately and survive loading even if unticked in
**Game Settings ▸ Abilities**. Start unlocks show **Learned** too; unticking a
start unlock revokes it only when that save never earned or purchased it.
A finished trainer with **Leave when done** disappears with its art, including
when loading a save that already owns every catalog ability. Locked and hidden
catalog entries still count toward completion. Trainers do not buy items.
**Project ▸ Analyze Progression** treats purchased rewards as uncertain because
it does not prove affordability or access conditions.

## Turn an NPC into a vendor

NPC vendors share the purchase catalogs, stock and menu used by shops. A vendor's
menu title is the NPC's display name. Supply **Art item** or linked **Object Art**
for its appearance; choosing a preset does not supply baked NPC art.

1. In Tiled, select the top-level **templates** object layer.
2. Place **Interaction ▸ NPC** from `tiled/templates/interaction/npc.tx`.
3. Set **Npc id** to a stable, unique id.
4. Set **Npc name** to the display name and shop title.
5. Choose **Vendor ▸ Vendor shop** from the catalog dropdown.
6. Set **Vendor ▸ Vendor flag** to a saved story flag if trading needs an unlock.
7. Choose **Vendor ▸ Vendor greeting**: **first_visit**, **every_visit** or **never**.
8. Enter **Dialogue ▸ Dialogue text** for a short greeting, or set **Dialogue id** to a reusable sequence.
9. Set **Art item** to your NPC artwork.
10. Choose **File ▸ Export Current Room**.
11. In Defold, choose **Project ▸ Reload Editor Scripts**.
12. Choose **Project ▸ Prepare & Check**.
13. Choose **Project ▸ Build**.
14. Open **Layout Editor** from the title screen.
15. Click **Export**.
16. Choose **Play Game** on an empty save slot.
17. Press **Interact** beside the NPC.

With a **Vendor flag**, the NPC talks normally until that flag is true. A
`set_flag = "met_merchant"` action on a dialogue choice or a `flag:met_merchant`
grant from any reward can unlock a vendor whose **Vendor flag** is `met_merchant`.
A Sign's **Conditions and persistence ▸ Set flag** can unlock it too.
**first_visit** greets once after unlocking and opens the shop when the dialogue
closes normally. Later visits open directly. **every_visit** greets each time;
**never**, or no dialogue, opens directly. Leaving the room or a rejected dialogue
opens no shop and does not use up the first greeting. Greeting state is saved
with the NPC id; keep that id stable after release.

The **merchant** and **alchemist** choices in **Npc type** supply their catalog,
name and greeting from `developer/config/npc_types.lua`. **Vendor shop = none**
keeps that preset's catalog; on a preset without a catalog it leaves a normal NPC.
NPC names and dialogue remain source text collected by **Project ▸ Translations…**.

## Rewards, stock and access

`gives` accepts comma-separated grant text or a list of such strings:
`item:potion_small:2`, `collectible:map_fragment`, `upgrade:health_boost_1`,
`ability:double_jump`, `currency:50`, `flag:met_smith`, and `fast_travel:<point_id>`.
Item and collectible counts default to 1. Currency amounts and counts must be
positive integers. Collectible grants need a stable transaction identity; nearby
map reveals also need the station's world position. Permanent upgrades use only
`max_health`, `max_energy`, `max_stamina` and `damage_mult`; their `requires` list
names prerequisite upgrades. Cycles and unsupported effect keys are errors.

`stock` is a positive integer total, shared by every station using that catalog.
Omit it for unlimited purchases. Saves count units sold rather than remaining
stock, so increasing stock makes the additional units available in old saves.
A container offered without stock grants a new bonus each purchase. Unique items,
learned abilities and applied upgrades cannot be purchased again when exhausted.

`requires_flag` hides an offer until its flag is true; `show_locked = true` keeps
it visible but unavailable. `locked_text` explains the lock. `set_flag` and any
`flag:` reward are written only after a successful purchase. Names, descriptions
and lock explanations are creator text collected by **Project ▸ Translations…**.

## Upgrade materials

One shared Upgrade Material funds both permanent stat upgrades at stations and
weapon tiers or charms through **Inventory ▸ Crafting** when Crafting is enabled
in **Game Settings ▸ Equipment**. Their purpose differs: stations improve permanent stats; crafting
improves gear. The Forge's Health Boost II costs 200 currency and one material,
after Health Boost I. Heavy Maul tier 2 costs two materials and 100 currency;
tier 3 costs three and 200. Ember Charm costs two materials. A charm upgrade can
consume its base as another item cost, unequipping its last copy. Both sinks use
the same item/currency cost grammar and one grant exchange transaction.
Sample shops do not sell materials; exploration awards them.
To split the economies, add a second item in `items.lua`, provide its collectible
definition and change the chosen offers' or recipes' item costs to that id. The
same item-cost grammar handles either material without framework changes.

## Potions

Catalogs sell potions through item rewards such as `item:potion_small` or
`item:potion_large`; chest contents can also grant `potion_small:2`. Names and
healing amounts live in `developer/config/items.lua`. Inventory **Items** shows
these same configured names and counts. See [Healing](CREATOR_WORKFLOW.html#healing)
for healing modes and selecting and drinking potions with **Quick Use**.

Provide artwork before exporting a world with potion pickups or drops:

1. In Tiled, add an image tile to a collection-of-images tileset.
2. Set the tile's **item_type** custom property to `potion_small`.
3. Add another image tile for `potion_large`.
4. Set that tile's **item_type** custom property to `potion_large`.
5. Choose **File ▸ Export Current Room** for each room that uses the tileset.
6. In Defold, choose **Project ▸ Reload Editor Scripts**.
7. Choose **Project ▸ Prepare & Check**.
8. Choose **Project ▸ Build**.

Prepare & Check generates the item-art catalog from those tiles. Rectangle
pickups inherit their collectible type's item image; **Art item** can select a
named image explicitly. A pickup without an item image or its own tile art is
hidden with a warning. Runtime drops also need the item image.

## Selling rules

Shops and NPC vendors buy eligible inventory items by default. The paused trade
list appends **Sell** below the purchase catalog, with owned counts and the price
for one copy. Selling refreshes that list and the carried currency immediately.
Untick **Selling ▸ Buys items** on a Shop or **Vendor ▸ Buys items** on an NPC to
hide the section and refuse sales. Set the same group's **Sell share** to **-1**
to inherit the project share, or a number from **0** to **1** to override it.


Eligible inventory items sell one copy at a time for
`floor(items.lua price * sell share)`. The item price is the buying and selling
base; catalog offers can set a different purchase price. The project share is
**Game Settings ▸ Game ▸ Shops ▸ Sell price share** (default **0.5**, range **0**
to **1**, step **0.05**), over `settings.sell_share` in `shops.lua`. A store share
from 0 to 1 overrides it; **-1** inherits the project share. The store must buy
items.

An item needs a positive `items.lua` price and must not set `sellable = false`.
Unowned items and items whose rounded sale value is 0 stay hidden. Keys never
sell, including aliases: selling a key could lock the player out of a gate.
Items owned by other Inventory tabs, including weapons and charms, never sell,
to prevent accidental gear loss. Charm Slot ships with `sellable = false` because
selling capacity could remove a slot. Only a unique item needs confirmation
before selling; there is no project-wide sale-confirmation switch.

Shares above 1 are refused so buying and reselling at the same base price never
earns currency. **When discounting a catalog offer, keep its buy price at least
as high as its sale value.** Catalog prices and item base prices are independent.

`Transaction.sell(item_id, ctx)` rechecks `ctx.buys`, the item exclusions and the
current share (`ctx.sell_share`, or the project default). `ctx.registry` supplies
Inventory-tab ownership; omitted uses the shared registry. It exchanges one item
for currency through Grants with source and reason `sale`, without a reward
notice. The purchase autosave switch also controls sales: success attempts at
most one save; refusal saves nothing. Save failures retain committed memory and
return `saved = false` and `save_error`; suspended saves behave the same way as
purchases. `item_sold` emits once after a successful exchange and its optional
save attempt, with `item_id`, `count = 1`, `price` and `station_kind`.

## Transactions and saves

`Transaction.buy(ctx, entry_id)` resolves the live catalog entry. `ctx` contains
`catalog_id`, `station_kind` and a plain numeric `position = { x, y }` for reveals.
`buy_inline(ctx, entry)` accepts the same entry shape for authored exchanges.
Inline owners may supply `instance_id`, `once_key` and `set_flags` for their stable
identity and one-time access. Without a catalog id, an inline exchange requires
an explicit identity or once key and has no catalog stock counter; use its once
key for a one-time offering. Its event's catalog field is empty. Both paths recheck visibility, stock, prerequisites
and costs before committing through Grants. Costs and reversible rewards roll
back together if a give fails. A refused purchase writes no save.

With `settings.autosave_after_purchase = true`, a successful purchase and any
ability autosave share one save. A disk failure leaves committed memory and
returns `saved = false` with `save_error`. While a death drop suspends saves,
purchases remain in memory; dying again restores the last save and undoes those
unsaved purchases. Turning purchase autosaves off still permits the existing
ability-unlock autosave. `purchase_completed` emits once after commit, with
`station_kind`, `catalog`, `entry` and numeric `price`.

## Purchase menus

The shared purchase menu pauses gameplay and shows carried currency. Each visible
catalog offer shows its name, full currency and item costs, stock or availability,
and a description. Upgrade details list permanent stat changes. Hidden offers
remain absent until their access flag is set; shown locks explain their requirement.
Owned unique items, learned abilities, applied upgrades and sold-out offers stay
visible but unavailable. Unaffordable offers show the missing cost. An offer with
`confirm = true` asks before purchasing through the menu's Yes and No buttons.

Offer and catalog names, descriptions and lock explanations remain creator text.
An owner's nonempty `menu_title` overrides the catalog name; without either, the
menu uses the translated title for its station kind (Shop or Upgrades). Framework wording lives in
`developer/config/ui_text.lua`; money and stock counts resolve when displayed.

The owner rechecks each purchase using its own catalog and world position, and
refuses to open in a fight-locked room. Successful purchases show the bought name;
cost refusals show the grant service's explanation. A failed save shows a save-point
reminder. A save suspended by a pending death drop keeps the purchase in memory
without a save-failure warning. Buy and failure cues use the `settings.sounds`
sound-bank ids in `shops.lua` through the shared menu.

## Prepare & Check diagnostics

**Project ▸ Prepare & Check** checks every catalog offer and the visible stations
in the world. Errors block preparation; warnings identify possible design mistakes;
information does not block it. Each object diagnostic names its room, object ID
and field. Config diagnostics name their file and catalog entry.

| Message code | Meaning and fix |
|---|---|
| `catalog_value_unknown` | A Shop's **Shop id**, NPC's **Vendor ▸ Vendor shop**, Upgrade Station's **Upgrade catalog** or Skill Trainer's **Trainer catalog** is missing from the catalog dropdown. Choose a listed catalog in Tiled, or restore it in `developer/config/shops.lua`. |
| `economy_bad_grant` | A catalog's `gives` or altar's **Payout ▸ Reward** has invalid grant text or an unknown id. Correct it in the named config entry or Tiled object. Use `currency:<amount>` for currency; currency collectibles cannot be granted with `collectible:`. |
| `economy_bad_cost_item` | A catalog's `cost_items` or altar's **Offer ▸ Cost item** is unknown, or its count is not a positive whole number. Correct the item id and count in the named entry or object. |
| `economy_upgrade_requires` | A catalog references an undefined upgrade. Use an id from `developer/config/upgrades.lua`. That file's schema separately rejects unknown prerequisites and cycles in `requires`. |
| `economy_trainer_start_unlocked` | A trainer sells an ability already unlocked at the start. Untick its start unlock in **Game Settings ▸ Abilities**, or choose a different trainer catalog if this is unintended. Published Game Settings overrides are included. |
| `economy_catalog_kind` | An Upgrade Station catalog has no `upgrade:` grants, or a Skill Trainer catalog has no `ability:` grants. Choose the intended catalog or add the matching offers in `shops.lua`. Empty catalogs are allowed but produce this warning on these station kinds. |
| `economy_currency_sources` | Information: a station charges currency but the world has no currency pickup, chest reward or enemy loot source. Place a currency pickup or configure currency rewards for a chest or enemy in the world. Banks only transfer money and do not count as costs or sources. |
| `economy_altar_without_reward` | An altar has a blank **Payout ▸ Reward**. Enter grant text; every altar trades once. |
| `economy_sell_share_range` | A store's **Sell share** must be **-1** to inherit, or **0** to **1**. Correct it in Tiled. Also check **Game Settings ▸ Game ▸ Shops ▸ Sell price share** and `shops.lua`'s `settings.sell_share`. |
| `economy_sell_above_buy` | Selling one eligible item at the highest buying store share pays more than its lowest single-item catalog price. Raise that purchase price, lower the store or project share, or set the item to `sellable = false` in `items.lua`. Bundles and offers with item costs are excluded. |
| `economy_sellable_required_item` | A Gate requires an item that players can sell. Set `sellable = false` for that item in `developer/config/items.lua` to prevent losing access. Gate collectible types resolve through their `item_id`; keys remain excluded from selling. |

After correcting a Tiled object:

1. Choose **File ▸ Export Current Room** in Tiled.
2. Choose **Project ▸ Prepare & Check** in Defold.

After correcting a config entry:

1. Save the config file.
2. Choose **Project ▸ Prepare & Check**.

These checks read config files fresh. Build is not needed to repeat a diagnostic
check. Playtest prices, currency availability, access conditions and stock before
releasing a world; a clean report does not prove every purchase is affordable.
