-- Loads the save slot once per game session.
-- main.script and the room streamer both need the loaded slot during init.
-- Whichever init runs first loads it; the other reuses that result, so work
-- done at session start (quest starts, rewards, New Game+) is never reverted
-- by a second load, and the result does not depend on object init order.
local CheckpointLayout = require "mvtk.rooms.checkpoint_layout"

local M = {}
local started = false

local function current_layout()
    local LayoutIO = require "mvtk.rooms.layout_io"
    return LayoutIO.load({ runtime_preferred = true })
end

-- Drop a saved checkpoint that no longer fits the current layout, in memory
-- only. Every startup reader then falls back to the same starting room.
-- Returns true when a checkpoint was dropped.
function M.drop_stale_checkpoint(layout)
    local Checkpoint = require "mvtk.core.checkpoint"
    local cp = Checkpoint.data and Checkpoint.data.checkpoint
    if cp == nil then return false end
    if layout == nil then layout = current_layout() end
    if CheckpointLayout.is_valid(cp, layout) then return false end
    print(string.format("[SESSION_SAVE] Ignoring stale checkpoint outside current layout: x=%s y=%s room=%s",
        tostring(cp.x), tostring(cp.y), tostring(cp.room_id)))
    Checkpoint.data.checkpoint = nil
    return true
end

-- Load the slot and drop a stale checkpoint, once per session.
-- opts.layout: the layout already loaded by the caller (optional).
-- Returns true for the call that did the load, false for later calls.
function M.begin(opts)
    if started then return false end
    started = true
    require("mvtk.game.save_system.save_manager").init()
    M.drop_stale_checkpoint(opts and opts.layout or nil)
    return true
end

function M.is_started()
    return started
end

-- Called from the game collection's final so the next session loads again.
function M.finish()
    started = false
    -- Keep the sandbox write veto through every final(), but never carry its
    -- memory save across Quit to Menu / another game collection lifetime.
    require("mvtk.core.checkpoint").discard_test_snapshot()
end

return M
