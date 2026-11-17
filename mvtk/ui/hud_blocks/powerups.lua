-- Local display clocks follow source snapshots; no per-frame world messages.
local DisplayText = require "mvtk.ui.display_text"
local Pause = require "mvtk.core.pause"
local Fit = require "mvtk.ui.hud_text_fit"
local M = {id="powerups", layout_key="powerups", root="powerups_root", field="hud_powerups",
    size={w=200,h=66}, nodes={static=2,runtime_max=2}, text_role="hud",
    default_entry={enabled=true,visible=true,anchor="top_right",offset={x=16,y=-136},max_width=356}}
local function render(state)
    local count = 0
    for i, node in ipairs(state.nodes) do
        local row = state.rows[i]
        local shown = row ~= nil and row.remaining > 0
        gui.set_enabled(node, shown)
        if shown then
            count = count + 1
            gui.set_position(node, vmath.vector3(0,-(count-1)*22,0))
            state.set_text(node, Fit.line(gui, resource, node, DisplayText.ui("hud.powerup_row", {
                label=DisplayText.render(row.label), seconds=math.ceil(row.remaining),
            })), true)
        end
    end
    state.visible = count > 0
    state.height = count * 22
    state.revision = DisplayText.revision()
end
function M.init(state, get_node)
    local root, template = get_node(M.root), get_node("powerup_row")
    state.nodes, state.rows, state.visible = {}, {}, false
    local scale = state.hud_scale or 1
    local maximum = (state.layout or M.default_entry).max_width or M.default_entry.max_width
    state.width = math.min(M.size.w * scale, maximum) / scale
    local size = gui.get_size(template)
    for i=1,3 do
        local node = i==1 and template or gui.clone(template)
        gui.set_size(node, vmath.vector3(size.x * state.width / M.size.w, size.y, size.z))
        gui.set_parent(node, root, false)
        gui.set_position(node, vmath.vector3(0,-(i-1)*22,0))
        gui.set_enabled(node, false)
        state.nodes[i] = node
    end
end
function M.on_data(state, data)
    state.rows = {}
    for i, row in ipairs(data.rows or {}) do
        if i > #state.nodes then break end
        state.rows[i] = {label=row.label, remaining=row.remaining}
    end
    render(state)
end
function M.measure(state) return {w=state.width or M.size.w,h=state.height or 0} end
function M.update(state, dt, frozen)
    local changed = state.revision ~= DisplayText.revision()
    if not frozen then
        for _, row in ipairs(state.rows) do
            local seconds = math.ceil(row.remaining)
            row.remaining = math.max(0,row.remaining-math.max(0,dt)*Pause.dt_scale())
            changed = changed or seconds ~= math.ceil(row.remaining)
        end
    end
    if changed then render(state) end
end
return M
