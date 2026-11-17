-- GUI-owned display; producers send seconds and the shared formatter owns h:mm:ss.
local TimeText = require "mvtk.ui.time_text"
local M = {id="play_timer", layout_key="play_timer", root="play_timer_root", field="hud_play_timer",
    size={w=160,h=24}, nodes={static=1,runtime_max=0}, text_role="hud",
    default_entry={enabled=true,visible=false,anchor="top_right",offset={x=16,y=-44}}}
function M.init(state, get_node)
    state.label = get_node(M.root)
end
function M.on_data(state, data)
    -- The host resolves this source description, including later language changes.
    state.set_text(state.label, TimeText.playtime(data.seconds))
end
function M.update(state) end
return M
