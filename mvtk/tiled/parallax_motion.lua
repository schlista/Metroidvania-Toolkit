-- Shared camera hook for independently baked scenery GOs. Never creates objects.
local CameraState = require "mvtk.camera.camera_state"
local M = {}
local entries = {}
local stretches = {}
local stretch_revision, stretch_x, stretch_y
local hook = "tiled_parallax_motion"

local function apply(entry, x, y)
    local p = entry.position
    p.x = entry.base.x + (x - entry.anchor.x) * (1 - entry.factor_x)
    p.y = entry.base.y + (y - entry.anchor.y) * (1 - entry.factor_y)
    -- Z is authored draw order, independent of scrolling speed.
    go.set_position(p, entry.id)
end

local function rescale()
    if not next(stretches) then return end
    local ViewPolicy = require "mvtk.render.view_policy"
    -- view_scale refreshes current policy and window-size caches before revision.
    local kx, ky = ViewPolicy.view_scale()
    local revision = ViewPolicy.revision()
    if stretch_revision == revision and stretch_x == kx and stretch_y == ky then return end
    stretch_revision = revision
    for id, entry in pairs(stretches) do
        go.set_scale(vmath.vector3(kx, ky, 1), id)
    end
    stretch_x, stretch_y = kx, ky
end

local function publish(x, y)
    rescale()
    for _, entry in pairs(entries) do apply(entry, x, y) end
end

function M.register(id, base, anchor, factor_x, factor_y, stretch_to_fill)
    local entry = {id=id, base=vmath.vector3(base), position=vmath.vector3(base),
        anchor=vmath.vector3(anchor), factor_x=factor_x, factor_y=factor_y}
    entries[id] = entry
    stretches[id] = stretch_to_fill and entry or nil
    if stretch_to_fill then stretch_revision = nil; rescale() end
    CameraState.on_publish(hook, publish)
    local ready, x, y = CameraState.get()
    if ready then apply(entry, x, y) end
    return entry
end

function M.unregister(entry)
    if entry and entries[entry.id] == entry then
        entries[entry.id] = nil
        stretches[entry.id] = nil
    end
    if not next(entries) then stretches = {}; stretch_revision = nil end
    if not next(entries) then CameraState.off_publish(hook) end
end

return M
