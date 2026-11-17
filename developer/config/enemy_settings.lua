-- developer/config/enemy_settings.lua
-- Room limits for regular enemies registered with EnemyManager.
-- Boss summons and helper-spawned enemies use this default cap unless their
-- spawn configuration supplies max_enemies_per_room for that instance.
--
-- Enemies placed in Tiled are baked into editable room gameobjects. Their
-- script registers them with a zero limit so every authored enemy remains
-- present; this setting does not remove enemies from the room collection.

return {
    -- Maximum registered enemies in a room for spawns using the default cap.
    -- Game Settings > Enemies and elements > Enemies > Enemy cap per room
    -- publishes an override without editing this baseline file.
    -- Zero disables the cap; a per-spawn value overrides this default.
    -- Every runtime summon carries a room, so this includes boss summons.
    max_enemies_per_room = 25,

    -- Remove runtime-created enemies when the player leaves their room.
    -- False keeps them until room unload, player death or owner cleanup.
    -- Enemies placed in Tiled remain editable, baked room gameobjects.
    remove_spawned_enemies_on_room_exit = true,
}
