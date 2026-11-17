-- Opening entry waits for startup and UI ownership before deciding once.
local GameManager = require "mvtk.game.game_manager"
local Pause = require "mvtk.core.pause"
local InputCtl = require "mvtk.rooms.input_controller"
local Flags = require "mvtk.core.flags"
local Checkpoint = require "mvtk.core.checkpoint"
local RuntimeSettings = require "developer.config.runtime_settings"
local Debug = require "developer.config.debug_config"
local C = require "mvtk.core.constants"
local StartupCover = require "mvtk.game.startup_cover"
local M = {}

function M.update(self)
    if self._cutscene_opening_checked then return end
    if self._startup_preparing or not self._startup_checkpoint_applied
        or not GameManager.is_playing() or Pause.get() or InputCtl.get_blocked() then return end
    if StartupCover.active() and not StartupCover.ready() then return end
    self._cutscene_opening_checked = true
    StartupCover.decide(false)
    if not self._seeded_start or (Debug.boot or {}).skip_menu or Flags.has("cutscene_seen_opening") then return end
    local settings = RuntimeSettings.section("cutscenes", require "developer.config.narrative.cutscene_settings")
    local id = tostring(settings.opening or ""):match("^%s*(.-)%s*$")
    if id == "" then return end
    StartupCover.decide(id)
    Checkpoint.batch("cutscene_opening", function() Flags.set("cutscene_seen_opening", true) end)
    msg.post(C.URL.CUTSCENE_MANAGER, "play_cutscene", {id=id})
end

return M
