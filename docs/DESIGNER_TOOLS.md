# Designer tools

Stop the game and open **Project ▸ Game Settings…** in Defold. The window
includes **Player**, **Movement feel**, **Player art**, **Camera**, **Enemies and elements**,
**HUD and prompts**, **Map**, **Saves and checkpoints**, **Languages** and
**Movement test**. Edits stay in its draft until **Save**. **Save and Prepare &
Check** also prepares the project; finish its prompts, then Build.

Hover over a name or field for help. Names that differ from toolkit defaults
are blue; the row's **x** restores its default. Range errors appear on the field
and block Save. Enter confirms a typed value without closing the window.
Closing with unsaved changes offers **Discard** or **Keep editing**. Dialog
actions reopen the main window on Player while retaining the draft.

Game defaults for focus loss live in **Game ▸ When the game loses focus**:
**Pause on focus loss** and **Pause when the controller disconnects** start on;
**Mute in the background** starts off. Players can override these in Pause ▸
Settings: Display ▸ Pause when unfocused, Controls ▸ Pause on controller
disconnect, and Audio ▸ Mute when unfocused. Returning to the window never
resumes play automatically. The title screen and Layout Editor are excluded.

## Movement feel

Open **Movement feel** just after **Player**. Use it to tune how quickly the
player starts, stops and turns, how high they jump, and how they move in the air
or on walls. A wall slide is the slow descent the player can make down a wall.

### Feel template

Pick a **Feel template** at the top of the tab. Each template starts from your
project's movement defaults and sets up a different feel.

- **Toolkit default** puts every field on the tab back to its project default, including all dash controls.
- **Swift acrobat** starts quickly, jumps sharply, falls fast, dashes sideways in the air and kicks hard off walls.
- **Instant control** starts and stops almost at once, has one ground speed, and uses a tall jump with a sharp release, a fall limit and a sideways air dash.
- **Agile sprinter** starts quickly and sprints much faster than it walks, with a fast fall, a float during descent and easy kicks off walls.
- **Precision climber** makes short jumps with a brief pause at the top, a slow fall you can speed up with Down, an eight-way dash and a slow wall slide. It sets air jumps to zero.
- **Retro run-and-gun** has one steady speed, quick stops and a medium, floaty jump with strong steering. It suits aiming while moving.
- **Nimble explorer** runs fast and has a high, floaty jump you can cut short, with tight wall kicks and little slowing on a wall.
- **Momentum runner** takes time to gain and lose speed. Turns skid, running jumps go higher, and holding Jump makes a big difference.

**Tuned for:** lists the abilities the template was designed around. Use
**Abilities** to choose which ones the player starts with. **Apply template**
changes only the movement fields in the draft. Starting abilities, health,
combat and art keep their settings. Nothing is published until you click
**Save** or **Save and Prepare & Check**.

### Check jump reach

The read-out estimates full jump height, shortest hop height, time in the air
and the distance a jump covers at walking and running speed. It shows heights
and distances in pixels and tiles. Choose a different template to see its
estimate on the **This template:** line before applying it. The estimate uses an ordinary jump on flat ground
at steady speed, with no boost from abilities or the room.

Check the read-out before saving. A template can change which ledges and gaps
the player can reach, so rooms built for your previous movement may need
changes. Try the jumps in play and run **Analyze Progression** after saving and
preparing if your project uses it to check routes.

### Ground

- **Walk speed (px/s)** sets top walking speed. Higher makes walking faster and lower makes it slower.
- **Run speed (px/s)** sets top running speed. Higher makes running faster and lower makes it slower.
- **Ground acceleration** sets how quickly the player reaches walking speed. Higher gets there sooner and lower builds speed more gradually.
- **Run build-up** sets how quickly the player gains speed while running at or above walking speed. Higher reaches top speed sooner, lower takes longer, and 0 uses **Ground acceleration**.
- **Ground braking** sets how quickly the player stops after you let go. Higher stops sooner and lower lets the player coast farther.
- **Turn braking** sets how quickly the player reverses direction. Higher turns sooner and lower makes the player skid longer.

### Jump

- **Jump height (px)** sets the height of a held jump. Higher sends the player higher and lower keeps the jump closer to the ground.
- **Running jump bonus** raises a ground jump as takeoff speed goes from walking to running speed. Higher adds more height, lower adds less, and 0 turns the bonus off.
- **Gravity** sets the pull toward the ground. A value farther below 0 pulls harder and a value closer to 0 pulls more gently.
- **Jump release** sets what happens when you let go of Jump during the rise. **Stronger gravity** pulls down harder and **Cut speed** removes some upward speed once. **Shortest jump (seconds)** sets when an early release can take effect.
- **Short hop gravity (x)** sets that extra pull in **Stronger gravity** mode. Higher gives a lower short hop and lower lets it rise higher.
- **Speed kept on release** is shown in **Cut speed** mode. Higher keeps more upward speed, 0 ends the rise, and 1 keeps all the speed.
- **Shortest jump (seconds)** sets how long a jump gets its normal rise even after a tap. Higher gives a taller hop and lower lets the jump end sooner.
- **Coyote time (seconds)** is the time you can still jump after walking off a ledge. Higher gives you longer to press Jump and lower needs closer timing.
- **Jump buffer (seconds)** remembers a Jump press just before landing so the next jump can start when you land. Higher lets you press earlier and lower needs closer timing.
- **Corner correction (px)** lets a rising player slip sideways past a solid ceiling corner when there is room beside it. The shipped default is 24. Facing either way gives the same clear or stop result for a jump from the same spot. Higher can clear a larger overlap. Set it to 0 to turn the correction off, as in **Retro run-and-gun** and **Momentum runner**.
- **Air jumps** sets how many extra jumps you can make before landing once Double Jump is unlocked. Higher adds jumps, lower gives fewer, and 0 gives none.

### In the air

- **Air control** sets how strongly you can steer in the air. Higher responds more quickly and lower changes speed more slowly.
- **Air braking** sets how quickly sideways motion slows in the air. Higher slows it sooner and lower carries more speed through a jump.
- **Apex hang speed (px/s)** sets when the player starts to hang near the apex, the top of a jump. Higher starts the hang farther from the top and lower makes the window narrower.
- **Apex hang gravity (x)** sets the pull during that hang. Higher gives a shorter hang and lower keeps the player near the top longer when **Apex hang speed (px/s)** is set.

### Falling

- **Fall gravity (x)** sets the pull during descent. Higher builds falling speed faster and lower gives a gentler descent.
- **Fast fall gravity (x)** sets the pull when you hold Down during a fall. Higher pulls harder and lower pulls more gently.
- **Fast fall top speed (x)** sets the falling speed limit while you hold Down. Higher raises the limit, 1 keeps the usual limit, and releasing Down restores it.
- **Top falling speed (px/s)** sets the normal falling speed limit. Higher allows faster falls up to the game's upper limit, lower caps the fall sooner, and 0 uses the game's upper limit alone.

### Walls

- **Wall slide speed (px/s)** sets how fast the player can slide down a wall. Higher allows a faster slide, lower caps it sooner, and 0 removes the cap.
- **Wall jump grace (seconds)** sets how long the player can still wall jump after letting go of a wall slide. Higher gives you more time and lower needs closer timing.
- **Wall jump push (px/s)** sets the push away from an ordinary wall. Higher sends the player farther, lower keeps them closer, and changing the player's size leaves this speed alone.
- **Wall jump steering lock (seconds)** sets how long the player steers and faces away after a wall jump or a kick away from a ledge. Higher holds that direction longer, lower returns control sooner, and 0 gives control back immediately.
- **Wall climb speed (px/s)** sets climbing speed. Higher climbs faster and lower climbs more slowly.
- **Cling fall speed (px/s)** sets how fast the player drifts down while clinging to a wall. Higher slips faster, lower slips more slowly, and 0 stays still.

### Dash and slide

- **Air dash speed (px/s)** sets the speed of an air dash. Higher sends the player faster and lower slows the dash.
- **Air dash time (seconds)** sets how long the dash lasts. Higher makes it last longer and lower ends it sooner.
- **Air dash cooldown (seconds)** sets the wait after a dash. Higher makes the player wait longer and lower lets them use another available dash sooner.
- **Air dash count** sets the number of air dashes available before landing. Higher gives more dashes and lower gives fewer.
- **Air dash directions** can be **Eight** to follow the stick or **Horizontal** for sideways dashes that keep vertical motion.
- **Pause gravity while dashing** holds vertical speed during an eight-way dash when on, so a sideways dash flies flat. Turn it off to let gravity pull during the dash.
- **Vertical speed kept after a dash** sets how much upward or downward speed remains after an eight-way dash. Higher keeps more and lower keeps less.
- **Extra dashes per upgrade** adds air dashes before landing once Extra Air Dash is unlocked. Higher adds more and lower adds fewer.
- **Slide speed (px/s)** sets how fast a slide travels. Higher gives a faster slide and lower gives a slower one.
- **Slide time (seconds)** sets how long a slide lasts. Higher keeps it going longer and lower ends it sooner.

### Glide

- **Glide gravity (x)** sets how quickly a glide gains falling speed. Higher makes the player drop sooner and lower makes the glide floatier.
- **Glide falling speed (px/s)** caps the glide's descent. Higher allows a faster descent, lower caps it sooner, and 0 removes the glide cap.

### Limits to check in play

- **Run build-up** takes effect when the player is running, at or above walking speed, and gaining speed. Hold Dash after a slide to run. A **Slide speed (px/s)** below **Run speed (px/s)** lets the player build speed right after the slide. A faster slide starts above the run's top speed, so the player brakes first. If the player slows down while still holding Dash, the same setting applies when they speed up again.
- **Cut speed** leaves launches, bounces and super jumps alone. Fast fall starts while falling, so holding Down during the rise leaves the jump height alone.
- The player can still rise past a corner when less than about a tenth of the body's width is under it, even at 0. Solid pieces only a few pixels thick can escape the checks. **Corner correction (px)** is off when the Spine add-on uses the player's bones for collision.
- Older settings kept outside a field's range can still work. Correct or reset a flagged value before saving again. A saved 0 for **Apex hang gravity (x)** only warns and you can save other edits. Enter 0.05 or higher to change it.
- **Shortest jump (seconds)** uses 60 frames a second as its guide. For 0.05 seconds, or three frames, the game aims to apply an early release at the start of the third frame.
- You can use the reach estimate for the same gaps on fast displays and at 60 frames a second. At the defaults, a held jump is about 432 pixels. Held jumps with an apex hang follow the same curve at both rates. A quick tap can still vary with the frame that sees the release.

## Shops

**Game ▸ Shops**, immediately after **Death drop**, holds **Sell price share**.
The default is **0.5**, with a range of **0** to **1** and a step of **0.05**.
Sales round the item's base price down after applying the share; items worth 0
are hidden. The baseline is `settings.sell_share` in `developer/config/shops.lua`.
A store can override the project share. Keep discounted catalog prices at least
as high as sale values to prevent buying and reselling for a profit.

1. Open **Project ▸ Game Settings…** with the game stopped.
2. Select **Game**.
3. Set **Shops ▸ Sell price share**.
4. Click **Save and Prepare & Check**.
5. Choose **Project ▸ Build**.

## Directional combat

In **Attacks**, **Post-hit recovery (seconds)** is the wait after the last hit
window closes. An attack without a hit window waits through startup and then
recovery. The recovery value in `developer/config/combat_config.lua` sets the
same wait. Attack and parry windows follow the 60-frame game on faster displays.

**Combat ▸ Parry** sets the parry window and how far a parried enemy slides straight away from you, slowing to a stop: **Parry push** after an ordinary parry and **Perfect parry push** after a perfect one, in pixels (0 turns that push off). An enemy's knockback resistance shortens the slide and walls stop it; bosses keep only their parry stun, and a parried shot never pushes its shooter. `knockback_time` in the commented `combat_config.lua` **parry** block sets how long the slide lasts.

**Combat ▸ Invincibility**, after **Parry**, sets after-hit, Slide, Dash and after-parry times in seconds; Slide and Dash require their Invincibility unlocks, and 0 covers their whole movement.
After-hit protection also counts down while swimming or climbing. Enemy and
boss protection after a hit uses game time. Hit freezes and the pause menu
hold it, and slow motion slows its countdown.

A normal hit on a boss gives a freeze of about 33 milliseconds with
**Freeze frames** set to **Full** and the shipped settings. **Off** removes
the freeze. Boss warning and attack times follow the seconds set in their
patterns across refresh rates. For movesets, floor attacks, beams and testing
baked properties in Defold, see [Design a boss](CREATOR_WORKFLOW.html#design-a-boss).

**Combat ▸ Up attack**, after **Heavy attack**, holds **Up attack damage**.
**Combat features ▸ Directional attacks**, after **Aerial attacks**, holds
**Up attacks**, **Aim ranged attack** and **Aim stance**. Up + Light attack strikes above the
player on the ground and in the air. Aim ranged attack defaults to **eight**;
**four** selects cardinal directions and **facing** restores straight shots.
Neutral input uses facing. Downward shots require being airborne by default;
`developer/config/combat_config.lua` can permit them on the ground and tune the
deadzone, threshold, attack definitions and optional directional shot clips.

1. Open **Project ▸ Game Settings…** with the game stopped.
2. Select **Combat features ▸ Directional attacks ▸ Aim ranged attack**.
3. Choose **facing** to restore straight shots.
4. Click **Save and Prepare & Check**.
5. Choose **Project ▸ Build**.
6. Check shots on an empty save slot.

Up attacks use the existing weapon attack animation until creators supply an
upward clip. Missing aim clips retain the existing animation-controller fallback.
Check hitbox placement, keyboard/controller aim and Up near ladders in play.

**Aim stance** starts off. When enabled, holding Ranged on the ground stops
horizontal walking and aims with the stick; release fires the stored aim.
Down + Ranged still places a usable bomb. Compact Form, stun, climbing and
hanging cannot enter the stance. Other movement and external forces remain available.

1. Open **Project ▸ Game Settings…** with the game stopped.
2. Enable **Combat features ▸ Directional attacks ▸ Aim stance**.
3. Click **Save and Prepare & Check**.
4. Choose **Project ▸ Build**.
5. Choose **Play Game** on an empty save slot.
6. Hold Ranged on the ground to aim without walking.
7. Release Ranged to fire.
8. Test Down + Ranged with Bomb unlocked.

Disable **Aim stance** to restore shots on press. Settings edits require
**Prepare & Check** again before **Export Game**.

## Enemies and elements

The **Enemies and elements** tab sits immediately after **Combat features**.
Its **Enemies** section holds **Default archetype for art-only enemies**. This
selects stats and behaviour from `developer/config/enemy_types.lua` when an
enemy's art has no matching enemy type and its **Archetype** is unset. Explicit
archetypes and matching enemy types keep their own settings. The default is
`slime`; saving writes an override without changing `enemy_defaults.lua`.

1. Open **Project ▸ Game Settings…** with the game stopped.
2. Select **Enemies and elements**.
3. Choose **Default archetype for art-only enemies**.
4. Click **Save and Prepare & Check**.
5. Choose **Project ▸ Build**.

New `enemy_types.lua` keys appear in this dropdown after closing and reopening
the Defold editor. If a published default was removed, Prepare & Check warns;
art-only enemies use the runtime fallback and log one warning for each cached
art/default resolution.

## Languages

Game Settings ▸ Languages sets **Default language** (`auto` or a supported
registry code) and **Show language choice**. The saved player preference wins.
When it is `auto`, a supported system language wins, then the creator's
**Default language** code, then the fallback. These fields save creator
overrides; the commented registry stays in `developer/config/localization.lua`.

1. Open **Project ▸ Game Settings…** with the game stopped.
2. Select **Languages**.
3. Choose **Default language**.
4. Set **Show language choice**.
5. Click **Save and Prepare & Check**.
6. Choose **Project ▸ Build**.

Players choose **Pause ▸ Settings ▸ Display ▸ Language**. The row cycles
supported languages by their own names and saves the code immediately. It hides
when only one language is registered or **Show language choice** is off.
Adding languages and importing translations are separate authoring work.

In a debug build, press **F4** and select the Dev Menu's **Languages** page.
Confirm **Pseudo-language** to bracket resolved game text; confirm again to turn
it off. It changes no language preference or registry entry and does not persist
across a restart. Disabled developer tools and release builds refuse it; Export
Game removes its Dev Menu entry point.

## Player art

Enter a project-relative PNG sheet path or a directory containing PNG sequences,
for example `idle_001.png`, `idle_002.png`, `run_001.png`. **Browse…** selects a
sheet; sequence folders use the validated source text field. Sequence numbers
start at 1 with no gaps, and all frames have the configured dimensions. Sheets
must divide exactly into those dimensions. Sheet ranges are row-major, starting
at 1: `idle=1-2;run=3-8;jump=9-9;fall=10-10`.

Map gameplay names to your animations with entries such as `run=running;hurt=damage`,
separated by semicolons. Required states are listed in the field help; add names
used by custom attacks. Missing states stop import. An explicit fallback can
supply missing required states, and the preview lists every state using it.
The non-looping animation list controls playback for gameplay IDs; other IDs loop.

Click **Import and preview…** to check PNGs, frame geometry, ranges and mappings.
The **Player art preview** window shows the selected animation's first frame,
its frame count, the green body box and the origin crosshair. The dropdown
changes the animation. Width and height `0` use the source frame dimensions;
explicit dimensions can stretch the art, which the preview reports. Player size
`1.00` uses the model's own in-game pixels.

**Use this art** keeps the import in the draft; **Cancel** discards that preview.
Save commits PNGs, atlas, sprite resource, geometry and settings together.
Changed source files, import settings or player size require another import.
Imports are limited to 512 frames and 16 million total pixels. The editor
accepts non-interlaced PNGs; re-export 16-bit images as 8-bit PNGs.

PNG import selects the sprite player. Spine is an optional add-on and ships off.
To use it, you need your own Spine Editor license: choose **Project ▸ Spine
Add-on…**, then **Turn On**, and follow its library-refresh instructions before
**Prepare & Check**. Add-on resources stay under `developer/addons/spine/`;
PNG import preserves them. See the [Spine add-on guide](../developer/addons/spine/README.md).
Custom sprite components and unrelated references are preserved. Ambiguous or
unsupported resource geometry stops the save with an error.

## Camera

Tune zoom, follow response, dead zones, framing offset, horizontal look-ahead,
vertical look, pixel snapping, respawn transitions and default shake. Look-ahead
smooths an input-directed offset of the follow target. Tiled camera zones and
boss arenas retain their authority; player shake preferences remain separate.

**Launch room preview** plays a disposable copy of the published rooms with the
draft's settings and pending player art. Publish a Tiled world with **Prepare &
Check** or export rooms from Layout Editor first. Use Movement test when the
project is still empty.

## Display

Game Settings ▸ Display places Screen shape, Framing and Pixel scaling before
the picture effects below.

### Picture tone and Retro screen

After **Display ▸ Pixel scaling**, **Picture tone** offers Brightness (0.5–1.5),
Gamma (0.5–2), Saturation (0–2), Tint red/green/blue and Tint strength (0–1),
all in 0.05 steps. **Players can change brightness** starts on and exposes
**Settings ▸ Display ▸ Brightness**, 50–150 percent in 5 percent steps.
Player Brightness multiplies creator Brightness; disabling permission ignores
the saved player value. **Retro screen** has Scanlines and Vignette (0–1,
step 0.05), and Curvature (0–0.25, step 0.01). Scanline count stays config-only.

Defaults leave the world picture unchanged and bypass the render target.
Effects cover the world only; HUD, menus, dialogue, masks, bars and GUI world
overlays stay sharp. The title screen and Layout Editor are unfiltered.
Gamma above 1 lifts shadows; Saturation 0 gives grey; Tint strength 0 is off.
Curvature bends the picture but pointer-to-world coordinates remain flat.
Save, Prepare & Check and Build to inspect each effect and the combined result.
Rendering and Vulkan/Metal shader translation still need native checks.

### Lighting

After **Retro screen**, **Display ▸ Lighting** offers **Dark rooms**: **Light mask**
(the default) reveals dark-room art near lit Torches and Light Sources; **Glow only**
restores the old tint and additive glow, capped at 0.9. Shadow red/green/blue and
Light red/green/blue are 0–1 in 0.05 steps. **Falloff** is 0.25–4 in 0.05 steps;
smaller values spread the light and larger values tighten its edge. Save and Build
before checking the look in a dark room or **Launch room preview**.

Set per-room darkness in Tiled. `developer/config/lighting.lua` keeps
`max_darkness` config-only (default 1 = fully dark outside lights; 0.9 retains a
faint view). `mask_scale`, `glow_with_mask`, `light_shape` and `max_lights` also stay
config-only. Glow-material art remains bright; HUD, menus, bars and room masks
are unaffected. Bright rooms retain their existing torch glows.

## HUD and prompts

Choose layout and theme presets, visibility, scale, health anchor and colour,
plus the default controller icon theme. Individual overrides apply after
presets. Gameplay can still hide unavailable resources, and player icon
preferences override creator defaults. Save and Build to check the result.
**Show on screen ▸ Abilities** (short labels such as G S CA) and **Movement label**
(Walk, Run, Air Dash under the Menu button) are testing aids and start off; the F1
debug overlay of debug builds lists the abilities and shows the movement as State.

Feature displays have their own editable `developer/ui/game/feature_hud.gui`
scene. Each feature adds its Show on screen toggle and commented
`hud_layout.lua` entry when it arrives; the host alone adds no toggles.
**Show on screen ▸ Play timer** is off by default and displays in-game h:mm:ss
in the top-right column. It uses the same clock as Journal Records.
Shown top-right blocks pack above the minimap, and notices follow below it
(moving up when off, stopping just under the top boss health bar).
`notices_top_floor` sets that minimum distance from the picture top;
`notices_max_width` caps the scaled panel width beside the tutorial popup
(default 722 design pixels). Text wraps to that capped width.
`column_gap` controls spacing; minimap size stays
independent of HUD scale. With no block shown the minimap stays where it is.
Custom health-bar anchors may require moving feature offsets as well.

**Show on screen ▸ Notices** enables the milestone queue. Off routes new
messages to short instant toasts. Configure panel width, maximum height,
duration, fades and waiting capacity in `developer/config/hud_layout.lua`'s
commented `notices` entry. Menus, dialogue and cutscenes hide and freeze the
queue until gameplay resumes, including the Items-only Inventory.

In **Show on screen ▸ Currency format**, write `{amount}` where the number
goes, for example `{amount} Gems`. The legacy `%d` also works; `%%` displays
a percent sign. Use exactly one amount placeholder and at most 40 characters.
Invalid formats show an error and disable Save. The default is `$ %d`.
For digit grouping, set `currency.thousands_separator` in
`developer/config/hud_layout.lua` to `","` (for `1,200 Gems`) or leave it
empty. Save, Prepare & Check and Build to update the HUD and Inventory header.

## Controls

The Controls tab follows HUD and prompts. Set default keys and controller
buttons for movement, combat, items, interaction, maps and menus. Each key
and button belongs to one action: a conflict marks both fields and disables
Save. None clears a slot; a missing player key or button shows a warning.
Escape always opens Pause. WASD, arrows, R, F1–F7, the camera stick and Guide
are unavailable here. Menu navigation stays in `developer/config/menu_settings.lua`.

Button timing sets Heal / item hold time (seconds) (default 0.35) and Quick
item step repeat (seconds) (default 0.45). Save publishes creator overrides
without rewriting `default_bindings.lua` or `healing.lua`. Players can remap
on top in Pause ▸ Settings ▸ Controls; Reset returns to these creator defaults.
Players with older full binding saves must press Reset once to receive them.
Use each field's x to return to the authored baseline.

## Map

The map discovers the gameplay camera's visible area in enabled rooms. Set
whole-room discovery or an extra nearby reveal radius, fog and feathering,
map and minimap visibility, and screenshot-marker count and size. Presentation
changes do not erase explored cells. Secret-room rules, map stations and
streamed markers retain their existing Tiled and runtime settings.

**Player markers** also sets **Map stamps** (default on) and **Stamp limit**
(0 to 64, default 32). Stamps are reminders players leave on the world map,
such as a star, `!` or `?`: **X** or the **X** key opens the palette at the
cursor, and **X** on a stamp removes it. Each save keeps its own stamps in the
room they were placed in, so moving a room in the Layout Editor moves its
stamps. A limit of 0, or Map stamps off, stops placing and hides them without
deleting saved ones. The palette's ids, glyphs, colours and labels are
`stamps.icons` in `developer/config/world_map_settings.lua`; glyphs and labels
are translated like other creator text. The minimap shows each stamp as a box
in its colour; `stamps.show` in `developer/config/minimap_settings.lua` turns
that off.

**World map**, below **Player markers**, sets **Maximum zoom** (2 to 8 times the
zoom that fits the whole world, default 8), **Pan speed (GUI px/s)** (default
900) and **Show legend** (default on: the button hints and the kinds of icon on
screen; players still toggle it with **I** or the top face button). The map
opens zoomed to the player's current room, then players zoom and pan from there.
In `developer/config/world_map_settings.lua`, `open_zoom = "room"` chooses the
deepest available zoom where the room fits within `open_room_fraction` of both
screen dimensions (default `0.5`, or half). `open_zoom = "world"` restores the
whole-world fit times `scale_multiplier`, raised to `min_scale`; missing room
outlines or bounds also use this fallback. Each opening checks the current room
again. Fast travel uses the same room zoom and centres on the selected stop so
the destination stays visible. Zoom also stops where one tile would span more
than `zoom.max_px_per_tile` screen pixels, and `pan.margin_px` sets how far a
panned view may show past the map's edges; both are in
`developer/config/world_map_settings.lua`.

**Fast travel**, below **World map**, sets **Travel from** (anywhere by
default, or stations), **Travel cost (currency)**, **Fade time (seconds)** and
**Block in boss fights**. Station-only trips start at stations, benches or
travel-enabled save points; the pause row hides without a gap. A trip costs
once when its message is accepted, with no refund for a later room-load failure.

## Saves and checkpoints

Set visible slots, timed autosave and its interval, room-change and collectible
save policies, and starting resource maxima. Death currency recovery is on the
**Game** tab. Hiding a slot preserves its file. Timed autosave also respects the
player's preference; interval `0` disables its timer. Explicit checkpoints,
ending commits and progression providers can still save. Room-change saves
retain the existing checkpoint location.

Restart loads the saved checkpoint; invalid room or position data falls back
to a valid spawn. It restores full health and resets motion and death state.
Other resource and progression values follow their checkpoint providers.
Display, audio and input preferences remain separate from progression.

## Movement test and room previews

On **Movement test**, set the course length, jump-step height and dash-gap width,
then click **Launch test course**. Both preview buttons build a separate project
under `.build/designer-preview/<job>/project`, applying the unsaved settings and
pending imported art. The course uses ordinary editable gameobjects baked into
its room collection. The live project and its saved settings stay unchanged.

Previews require Windows, Lua, PowerShell 7 (`pwsh.exe`) and a Defold installation
located by `tools/defold_bob.bat` (`DEFOLD_PACKAGES_DIR` and `DEFOLD_HOME` are
supported). Dependency downloads need network access. On other platforms the
buttons say **Previews need Windows for now** and are disabled.

The Game Settings window reopens while the preview builds. Click **Refresh
status** to read its progress. Launching again during a build shows the current
job status. In the preview, F5 / controller Back restarts, F6 / left-stick click
selects an ability, and F7 / right-stick click toggles it. Use the game's normal
movement controls. Close the preview game when finished; the draft remains in
Game Settings, ready for another experiment or Save.

The copy has a unique identity and keeps progress in its own `preview_saves`
directory. Job folders are excluded from release packages and can be removed
after the preview closes. `status.txt`, `stage.log`, `course.log`,
`generation.log` and `build.log` report progress or failures. A failed build
does not publish the draft or alter creator progress.

## Grapple and ending

With the same swing inputs, the grapple follows the 60-frame path on faster displays.
Tune the **Grapple** tab and use **Camera ▸ Launch room preview** to try its
settings in your rooms. See [Grappling](GRAPPLING.md).

The **Ending** tab's **Preview ending…** opens an editor dialog with the unsaved
title, body, artwork's first image and paged credits. Previous and Next move
between pages. Playtime and item counts are sample values; music plays only in
the game. The dialog shows the same validation issues as the Ending tab. See
[Preparation and endings](PREPARATION_AND_ENDINGS.md).

## Progression

The **Progression** tab follows **Ending**. Its **Records** section offers
**Statistics in Records** and **Time on ending**, both off by default.
Statistics are recorded even when hidden. **Time on ending** captures the run's
in-game h:mm:ss on the ending page; off keeps the existing minutes line. Best
times per ending are saved in the player profile independently of these switches.
Journal Records always shows the run's in-game **Play time**. See [run statistics](CREATOR_WORKFLOW.html#show-a-play-timer-and-run-statistics).

## Verification boundary

Automated tests check validation, import planning, transactions, draft isolation,
course generation and shared ending page rules. Check rendering, physics,
controller behaviour, camera zones and ending music in the running game.
After changing required editor Lua modules, restart Defold, run **Project ▸
Reload Editor Scripts**, then **Prepare & Check** before **Export Game**.

### Ice floors

**Game Settings ▸ Advanced ▸ Ice** has **Acceleration multiplier**, **Stopping
multiplier** and **Turn braking multiplier** (defaults 0.35, 0.08 and 0.15).
These values are unscaled. Painted `ice` and Ice Floor zones with `-1` values
use them after **Save** and **Build**. Smaller values build speed slowly,
coast farther and skid longer; jumping keeps normal air control.
Wall Jump Surface's `ice` preset is a separate wall movement rule, not a floor preset.

### Zip lines

**Game Settings ▸ Advanced ▸ Zip line** follows **Ice**. **Hang offset** is the
player-origin distance below the cable, in **base px** (default 70, range 0–210),
and follows Player Size even with movement scaling off. **Jump lets go** defaults
on. Save, then Build to check the hands against the cable. Per-line **ride ▸ Speed**,
**Exit boost**, **Auto start** and the selected **path_ref** live on the Zip Line
in Tiled. The commented `player_settings.lua` `zip_line` block also provides the
release jump speed and player animation state.

### Hang bars

**Game Settings ▸ Advanced ▸ Hang bar** follows **Zip line**. **Hang offset** is the
player-origin distance below a hang bar's centre line, in **base px** (default 0, range
0–210), and follows Player Size even with movement scaling off. 0 hangs the player at
the ladder hand height, `player_settings.lua` `ladder_climb.hand_height_ratio` collider
half heights, which suits art that raises its hands. Art that hangs with its arms down
needs a smaller value. Save, then Build to check the hands or head against the bar.

### Lantern

**Game Settings ▸ Advanced ▸ Lantern** follows **Hang bar**. **Radius** is in
unscaled world pixels (32–1200, default 280); Player Size never changes it.
**Intensity** is 0.1–4 (default 0.9), **Flicker** is 0–1 (default 0.08; 0 is
steady), and **Minimum darkness** is 0–0.9 (default 0.2). The colour comes from
**Display ▸ Lighting ▸ Light red/green/blue**. The commented `player_settings.lua`
`lantern` block also sets the ability id and flicker cycles per second.
**Abilities ▸ Utility ▸ Lantern** grants the passive light to fresh games;
an Ability Pickup set to `lantern` grants it later. Save, then Build to check
the light while moving. Mark rooms that need it with the Tiled Bool map property
`requires_light` so Analyze Progression models the entry requirement.

### Enemy and boss elements

Tiled Enemy **elements** and Boss **damage_affinities** offer the multi-select
**weak_to**, **resist_to**, **immune_to** and **vulnerable_to** fields. Enemy
**damage_type** sets contact, melee and shots; **none** inherits its preset.
Prepare & Check refreshes choices from `developer/config/damage_types.lua`;
reopen the Tiled project afterwards. Weak and immune feedback remains subject
to the in-game checks in the creator workflow.

### Player and world elements

**Enemies and elements ▸ Elements** generates **Player damage taken: <type>** fields from
`damage_types.lua`, with factors from 0 (immune) to 10. **Weakness multiplier**, **Resistance
multiplier** and **Colour damage numbers by element** publish through Game Settings overrides.
Use **Save and Prepare & Check**, then **Project ▸ Build**.

The empty toolkit has no attack infusion. Configure per-attack `damage_type` in
`combat_config.lua` or `player_actions.lua`, or add an ordered ability row to
`damage_types.lua`'s `player_attack_infusions`. The first unlocked row wins; omitted categories
retain their base type. See [Elements](CREATOR_WORKFLOW.html#elements) for numbered steps.
Hazard **Elements ▸ Damage type** inherits its preset when **none**; Pendulum Hazard
**Damage and knockback ▸ Damage type** defaults to slash. Water maps types for players and
enemies. Breakable Wall **Durability ▸ Required damage type** is independent of
**Required ability**, and Analyze Progression includes matching infusion abilities or an
unknown when no base category or infusion emits that type. Per-attack-only overrides are
conservatively unknown unless also represented by those configured categories or infusions.

### Hazard statuses

Tiled **Hazard ▸ Status** exposes **Status effect**, **Status duration** and
**Status chance**. `none` and `-1` inherit the hazard preset and effect duration.
The presets burn in lava and flame jets, poison in acid and poison gas, and
freeze in cold. Configure the effects in `developer/config/status_effects.lua`;
run Prepare & Check to refresh the status dropdowns.

**Game Settings ▸ Enemies and elements ▸ Status effects** provides **Status effects on**
and catalog-generated **Duration (seconds)**, **Tick interval (seconds)**,
**Damage per tick** and **Speed multiplier** fields prefixed with each effect's
source label, such as **Poison: Damage per tick**. Save with **Save and Prepare & Check**,
then **Project ▸ Build**. The saved overrides control runtime ticks without editing
baseline configuration. **HUD and prompts ▸ Show on screen ▸ Status chips** hides
or shows the chips without changing gameplay effects.

The editable `developer/ui/game/feature_hud.gui` contains `status_chips_root`,
`status_chip_bg` and `status_chip_text`. One chip per effect shows its translated
label and remaining seconds; Poison stacks share one chip. Pause holds the
countdown. `hud_layout.status_chips` controls placement and a maximum of four chips.
The subtree has three authored nodes and at most six cloned nodes; clones keep
`ui_text.font`. See [Status effects on the player](CREATOR_WORKFLOW.html#status-effects-on-the-player)
for the numbered workflow. Configuration, UI and hook edits require Prepare & Check
again before Export Game.

Statuses and hazard slows require effective damage mode and respect hazard
protection. Acid/cold slow leases share group `zone` with Movement Zones, so
only the strongest zone slow applies. Status slows multiply separately, never
lock player actions and do not affect swimming or ladders. Everything is
transient; pause holds clocks, death and respawn clear statuses.

Harness `sample_map5` object 605 is `tt_status_hazard` at (1344,1248), 128×32,
with Poison for 3 seconds and the preset contact damage. It has no painted tiles and
does not overlap the other combat-room checks. Its runtime collection contains
an editable baked hazard gameobject; no script creates the Tiled object.

Enemy Elements now supplies Status immune, Status on hit and Status chance;
Boss Damage affinities supplies Status immune. Preset and placed immunities add.
Freeze stops regular enemies; bosses ignore it by default (status_effects.lua).
Boss movement remains unaffected when that immunity is removed. See
[Status effects on enemies and bosses](CREATOR_WORKFLOW.html#status-effects-on-enemies-and-bosses).

## Leveling

**Progression ▸ Leveling** appears before **Records**. **Leveling** ships off.
Its dependent fields are **Maximum level** (1–99), **First level XP** (1–100000),
**XP growth** (1–3), **Enemy XP** (0–10000), **Boss XP** (0–100000),
**Health per level** (0–5) and **Full heal**. They apply only with Leveling on.
The XP curve uses whole requirements and caps at Maximum level. Health growth
rounds down after accumulating; 0.5 gives +1 capacity at level 3. Full heal runs
once per gain that crosses levels. Journal ▸ Records shows Level and Total XP.
The commented `developer/config/leveling.lua` holds sparse table curves,
milestone flags and other stat/source settings. See
[Turn on leveling](CREATOR_WORKFLOW.html#turn-on-leveling) for the creator steps.
HUD and prompts ▸ Show on screen ▸ Level and XP controls the label and XP bar;
it starts showing data only while leveling is on. Tiled Enemy ▸ Rewards ▸ XP value
overrides one enemy; Boss ▸ Rewards and persistence ▸ Reward XP overrides one boss.

## Equipment

The **Equipment** tab follows **Progression**. **Weapons**, above **Power-ups**,
offers **Weapons** (off by default), **Quick switch** and **Starting weapon**. Choose a configured
weapon or **Unarmed** for a blank starting id. The starting weapon is virtual;
ownership of other weapons comes from `weapon_<id>` items. The commented
`weapons.lua` list defines attack sets, damage, reach, cooldown, knockback and
optional ranged overrides. **Quick switch** enables C / Left Stick click and
the remappable **Next Weapon** row in Controls ▸ Combat. Players equip directly
in **Inventory ▸ Weapons** and see the equipped weapon on the HUD. The
**Weapon** toggle in HUD and prompts ▸ Show on screen controls that block. **Save and Prepare & Check** publishes the settings.

The **Charms** section, after **Weapons**, offers **Charms** (off by default),
**Base slots** (3) and **Maximum slots** (9). Click **Save and Prepare & Check**
to publish changes. `charms.lua` defines names, descriptions, slot costs and
stat effects. Players toggle owned charms in **Inventory ▸ Charms**, anywhere;
the header shows slot use and rows that do not fit are disabled. Charm Slot
pickups add capacity up to the maximum. A health charm raises the bar without
refilling health; removing it clamps current health. The next normal save keeps
the equipped set. See [Charms](CREATOR_WORKFLOW.html#charms) for placement and effects.

Its **Power-ups** section offers
**Power-ups**, off by default. Turning it on enables temporary world pickups
from `powerups.lua`; **Save and Prepare & Check** publishes the switch. Reopen
`MVTK.tiled-project` in Tiled to see catalog additions. The **HUD and prompts ▸
Show on screen ▸ Power-ups** switch controls the three countdown rows. Timers
hold during pause and end on death; disabled pickups stay in place.
