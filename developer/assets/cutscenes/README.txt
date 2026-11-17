Place cutscene videos (.mp4) in developer/assets/cutscenes/common/.
Keep this README.txt at the folder root, outside the bundle.

List each clip in developer/config/narrative/videos.lua (editor_uri includes
common/, uri is the bundled name; common/ is copied to the bundle root), then play it from a cutscene step in
developer/config/narrative/cutscenes.lua.
