# Use the optional Steam add-on

The add-on ships off. **Project ▸ Steam Add-on…** changes only the Steam
extension dependency in `game.project`. It does not change your settings or
create a test app-id file. Turning it off leaves in-game achievements working.
Each creator needs their own Steamworks account and app ID; Valve's terms apply.
The supported extension is pinned to version 1.15.0.

For Windows local testing:

1. Stop the running game.
2. Choose **Project ▸ Steam Add-on…**.
3. Click **Turn On**.
4. Click **Turn On** in the **Turn On Steam Add-on** notice.
5. Close the **Steam Add-on On** message to let Defold fetch libraries.
6. Set `app_id` in `developer/config/steam_settings.lua` to your Steam app ID
   (`480` can be used for a first initialization test).
7. Define a goal in the `achievements` table in `developer/config/achievements.lua`
   using the [achievement authoring guide](../../../docs/CREATOR_WORKFLOW.html#add-achievements).
8. Add a mapping in `achievement_names` in `developer/config/steam_settings.lua`
   from that goal's id to an existing, published Steamworks achievement **API Name**
   for the app you are testing, for example `hunter = "ACH_HUNTER"`.
9. Create `steam_appid.txt` beside `game.project` containing only the same numeric
   app ID as `app_id` (for example `480`), followed by a newline.
10. Enable **Game Settings… ▸ Progression ▸ Achievements ▸ Achievements**.
11. Save the Game Settings window.
12. Start the Steam client for the account that can test your app.
13. Choose **Project ▸ Prepare & Check**.
14. Choose **Project ▸ Build**.
15. Unlock the goal in normal play on an empty save slot.
16. Stop the game.
17. Choose **Project ▸ Build** again to check that an unlocked achievement is
    not announced again.

An unmapped goal sends its own id as the API Name. Steam's names, descriptions,
icons and translations are authored in Steamworks. The API Name must belong to
the app ID being tested; an example mapping alone does not create it. Dev Menu
test sessions never send unlocks to Steam. Existing profile unlocks are synced
once per process, including ones earned while the add-on was off.

Prepare & Check warns when the add-on is on with `app_id = 0`, when a mapping
key has no matching achievement id, or when the root `steam_appid.txt` is
missing. It refuses a mixed dependency state; choose **Turn On** or **Turn Off**
in **Steam Add-on…** to repair that state. The add-on settings schema also checks
invalid values. A game that cannot initialize Steam continues without Steam
features; this add-on does not relaunch the game through Steam.

The Steam startup log and overlay notification still need testing in your
Windows editor session. If Steam initialization fails outside Steam, check the
client, app access and app-id file location for the launched executable.
Export Game preserves the dependency and excludes the root local test file.
Steam launches provide the app ID; do not distribute your local `steam_appid.txt`.
The extension's own macOS test file (480) may be bundled by the extension; that
platform's packaging remains unverified.

To turn the add-on off:

1. Stop the running game.
2. Choose **Project ▸ Steam Add-on…**.
3. Click **Turn Off**.
4. Close the **Steam Add-on Off** message to let Defold fetch libraries.
5. Choose **Project ▸ Prepare & Check**.
6. Choose **Project ▸ Build**.

This removes the Steam dependency without deleting your mapping or local test
file. The runtime adapter stays inert when the extension is absent. Any add-on
change makes the published world stale; run Prepare & Check before Export Game.

## Show rich presence

Rich presence shows the title screen, Playing, or the current named region to
Steam friends. It stays off until you enable it. First complete the local
initialization and achievement checks above. App 480 can check initialization
and errors, but cannot display your custom text: its localization is Valve's.
Your own app ID and an uploaded rich-presence localization file are required
to verify the text. Editor runs with your own `steam_appid.txt` should work,
but this integration still needs a real Steam check.

1. Turn the add-on on using the steps above.
2. Set `rich_presence.enabled = true` in `developer/config/steam_settings.lua`.
3. Set the `title`, `playing` and `region` phrases in that file, keeping exactly
   one `{region}` in the region phrase.
4. Give your regions names in `developer/config/biomes.lua`.
5. Translate those source phrases and region names with **Project ▸ Translations…**
   for each language in `developer/config/localization.lua`.
6. Choose **Project ▸ Prepare & Check**.
7. Review `developer/addons/steam/steamworks/rich_presence.vdf`.
8. Upload that file on your app's **Steamworks ▸ Community ▸ Rich Presence** page
   ([Steam's rich presence guide](https://partner.steamgames.com/doc/features/enhancedrichpresence)).
9. Start the Steam client for the account that can test your app.
10. Choose **Project ▸ Build**.
11. Enter a named region in **Play Game**.
12. Check [Steam's rich presence tester](https://steamcommunity.com/dev/testrichpresence)
    for the region text.
13. Check the same text in a friend's Steam list.
14. Quit to the title screen.
15. Check that the title phrase replaces the region phrase.

An unnamed region uses Playing. Region ids must contain only letters, digits
and `_`, and be shorter than 256 bytes. Prepare & Check warns about unusable
named ids, unmapped languages and rejected text. It skips text with `%`, `{`
or `}` outside the single `{region}` placeholder. Backslashes and quotes are
escaped in the VDF. An `english` block is always generated; without `en`, it
uses your fallback language and warns. `steam_languages` can map your language
codes to Steam's API language codes. Upload again after changing phrases,
translations or region names; only languages in the upload are overwritten.

## Use Steam Cloud

Steam Auto-Cloud synchronizes the game's existing save files. There is no
runtime cloud-storage code. **Auto-Cloud syncs only when Steam starts the
game**, and on exit. Nothing about Cloud can be verified from the Defold editor
or with app 480: you need your own app ID, published Cloud settings, an uploaded
build launched from the Steam client, and two machines. Windows is the test
target; macOS/Linux root overrides are experimental and their Cloud paths
remain UNVERIFIED (especially the Linux save location).

1. Turn the add-on on using the steps above.
2. Save your game's permanent identity in **Project ▸ Game Settings… ▸ Game**.
3. Set `cloud_saves.enabled = true` in `developer/config/steam_settings.lua`.
4. Optionally set `cloud_saves.include_preferences = true` to sync volume,
   language and display preferences in `mvtk_settings`.
5. Optionally set `cloud_saves.include_controls = true` to sync remapped controls
   in `mvtk_bindings_v2`.
6. Choose **Project ▸ Prepare & Check**.
7. Open `developer/addons/steam/steamworks/auto_cloud.txt`.
8. Open your app's **Steamworks ▸ Steam Cloud** page
   ([Steam Cloud guide](https://partner.steamgames.com/doc/features/cloud)).
9. Enter each generated Root/Subdirectory/Pattern/OS/Recursive row.
10. Enter the generated **Root Overrides** for your supported operating systems.
11. Set **Number of files allowed per user** using the generated quota advice.
12. Set **Byte quota per user** using the generated upper bound.
13. Click **Save**.
14. **Publish** the Steamworks changes.
15. Upload a build for your app.
16. Run `testappcloudpaths <AppId>` in the Steam console for your own app ID.
17. Run `set_spew_level 4 4` in the Steam console.
18. Launch the uploaded build from the Steam client on machine A.
19. Save a slot on A.
20. Exit the game on A.
21. Launch the build from Steam on machine B.
22. Check that the slot is present on B.
23. Delete that slot on B.
24. Exit the game on B.
25. Launch the build from Steam on A.
26. Check that the slot is empty on A.
27. Play offline on both machines.
28. Reconnect to Steam.
29. Check Steam's conflict window at the next launch.
30. Inspect `%Steam Install%\logs\cloud_log.txt` for sync diagnostics.

The generated patterns include slots and their backups, the last-slot marker
and the profile. They exclude the debug log and the old preferences backup.
Use one Steam account per OS user: this save folder is not separated by Steam
account. See [Steam Cloud save compatibility](../../../docs/SAVE_COMPATIBILITY.md#steam-cloud)
for tombstones, conflicts and offline play. Dev Menu test sessions and designer
previews do not write player slot/profile saves into the synced folder.

Only enabled features generate their files. Repeated Prepare & Check runs keep
unchanged files intact. Turning a switch off does not remove a previous upload
or generated file; change Steamworks settings there as needed. **Reset Project
to Empty (destructive)** backs up and removes `steamworks/`, while this README
stays. **Export Game** excludes these upload instructions and the VDF; upload
them in Steamworks, separately from the game build.
