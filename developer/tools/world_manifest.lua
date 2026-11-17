-- Leaf selected-world reader shared by provenance and content validation.
-- No validator dependency: the editor/runtime resource build graph stays acyclic.
local Source = require "developer.tools.project_source"
local M = {}
function M.selected_manifest(opts)
    local root=opts.root or ".";local read=opts.read or Source.read
    local function load(path) return Source.load_table(read(root.."/developer/"..path),path) end
    local config=load("config/world_layout_source.lua")
    if not config or config.owner~="tiled" then return nil,false end
    local active=load(config.manifest or "assets/tiled/worlds/active.lua")
    local pending=load("assets/tiled/worlds/pending.lua")
    local manifest=pending and active and pending.source==active.source and pending or active
    return manifest,true
end
return M
