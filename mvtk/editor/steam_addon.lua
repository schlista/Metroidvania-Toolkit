-- Steam state is controlled only by game.project's dependency line.
-- Pure text transforms; no filesystem, runtime or editor APIs.
local Dependency = require "mvtk.editor.addon_dependency"
local M = {}

M.DEPENDENCY_URL = "https://github.com/defold/extension-steam/archive/refs/tags/1.15.0.zip"
M.CONTROL_PATHS = {"game.project"}

function M.dependency_text(text, enabled)
    return Dependency.dependency_text(text, enabled, "extension-steam", M.DEPENDENCY_URL)
end

function M.state(files)
    local text = files["game.project"]
    if type(text) ~= "string" or Dependency.project_sections(text) ~= 1 then
        return "mixed", "game.project must contain exactly one [project] section"
    end
    local entries = Dependency.entries(text, "extension-steam")
    if #entries == 0 then return "off" end
    if #entries == 1 and entries[1].url == M.DEPENDENCY_URL then return "on" end
    return "mixed", "Steam dependency must use the supported URL exactly once"
end

function M.plan(files, target)
    assert(target == "on" or target == "off", "Steam target must be on or off")
    local text = M.dependency_text(files["game.project"], target == "on")
    local changes = {}
    if text ~= files["game.project"] then changes[1] = {path="game.project", content=text} end
    assert(M.state({["game.project"]=text}) == target, "Steam state repair did not reach " .. target)
    return changes, {["game.project"]=text}
end

return M
