-- GUI-owned level wording and XP fill; producers send only numeric progress.
local M = {id="level_xp", layout_key="level_xp", root="level_xp_root", field="hud_level_xp",
    size={w=200,h=30}, nodes={static=3,runtime_max=0}, text_role="hud",
    default_entry={enabled=true,visible=true,anchor="top_right",offset={x=16,y=-72},max_width=356}}
function M.init(state, get_node)
    state.label, state.fill = get_node(M.root), get_node("level_xp_fill")
    local background = get_node("level_xp_background")
    local scale = state.hud_scale or 1
    local maximum = (state.layout or M.default_entry).max_width or math.huge
    state.width = math.min(M.size.w * scale, maximum) / scale
    local ratio = state.width / M.size.w
    -- Text root and children share the authored scale. Keep their height
    -- and text scale while capping width before the host places the block.
    for _, node in ipairs({state.label, background, state.fill}) do
        local size = gui.get_size(node)
        gui.set_size(node, vmath.vector3(size.x * ratio, size.y, size.z))
    end
    state.fill_size = gui.get_size(state.fill)
end
function M.on_data(state, data)
    state.set_text(state.label, {key="hud.level", params={level=data.level}})
    local fraction = data.max and 1 or (data.needed > 0 and data.into / data.needed or 0)
    local size = state.fill_size
    gui.set_size(state.fill, vmath.vector3(size.x * math.max(0, math.min(1, fraction)), size.y, size.z))
end
function M.measure(state) return {w=state.width or M.size.w,h=M.size.h} end
function M.update(state) end
return M
