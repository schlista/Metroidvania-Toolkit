-- mvtk/prefabs/pushable_capture_layers.lua
-- The tile layers a Pushable Block with move_embedded_tiles carries with it. Its runtime capture
-- (mvtk/prefabs/pushable_block.script) and the chunk Create Rooms bakes for it (hooks/editor_script.lua)
-- both read this list, so a block never takes background or foreground art along, and never leaves a
-- hole in them. Paint a block's own tiles on one of these layers.
return { "bounds", "solid", "destructible", "scenery" }
