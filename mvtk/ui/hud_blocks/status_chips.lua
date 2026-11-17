-- Source snapshots come from the status registry; only this GUI renders text.
local DisplayText = require "mvtk.ui.display_text"
local Pause = require "mvtk.core.pause"
local Config = require "developer.config.hud_layout"
local Fit = require "mvtk.ui.hud_text_fit"
local M = { id="status_chips", layout_key="status_chips", root="status_chips_root", field="hud_status_chips",
    size=Config.status_chips.size, nodes={static=3,runtime_max=6}, text_role="hud",
    default_entry=Config.status_chips }

local function render(state)
    local shown = 0
    for i, chip in ipairs(state.chips) do
        local effect = state.effects[i]
        local visible = effect ~= nil and effect.remaining > 0
        gui.set_enabled(chip.bg, visible); gui.set_enabled(chip.text, visible)
        if visible then
            shown = shown + 1
            local color = effect.color
            gui.set_color(chip.bg, vmath.vector4(color[1],color[2],color[3],1))
            state.set_text(chip.text, Fit.line(gui, resource, chip.text, DisplayText.ui("hud.status_chip", {
                label=DisplayText.render(effect.label), seconds=math.ceil(effect.remaining),
            })), true)
        end
    end
    state.visible = shown > 0
    state.revision = DisplayText.revision()
end

function M.init(state, get_node)
    local root = get_node(M.root)
    local bg, text = get_node("status_chip_bg"), get_node("status_chip_text")
    state.chips, state.effects, state.visible = {}, {}, false
    local maximum = math.max(1, math.min(4, math.floor(state.layout.max_chips or 4)))
    local step = state.layout.chip_step or Config.status_chips.chip_step
    local inset = state.layout.text_offset or Config.status_chips.text_offset
    for i=1,maximum do
        local chip = {bg=i==1 and bg or gui.clone(bg), text=i==1 and text or gui.clone(text)}
        gui.set_parent(chip.bg,root,false); gui.set_parent(chip.text,root,false)
        gui.set_position(chip.bg,vmath.vector3((i-1)*step.x,(i-1)*step.y,0))
        gui.set_position(chip.text,vmath.vector3((i-1)*step.x+inset.x,(i-1)*step.y+inset.y,0))
        gui.set_enabled(chip.bg,false); gui.set_enabled(chip.text,false)
        state.chips[i] = chip
    end
end

function M.on_data(state, data)
    -- Own the local clocks without modifying the producer's message snapshot.
    state.effects = {}
    for i, effect in ipairs(data.effects or {}) do
        if i > #state.chips then break end
        state.effects[i] = {label=effect.label,color=effect.color,remaining=effect.remaining}
    end
    render(state)
end

function M.update(state, dt, frozen)
    local changed = state.revision ~= DisplayText.revision()
    if not frozen then
        for _, effect in ipairs(state.effects) do
            local seconds = math.ceil(effect.remaining)
            effect.remaining = math.max(0,effect.remaining-math.max(0,dt)*Pause.dt_scale())
            changed = changed or seconds ~= math.ceil(effect.remaining)
        end
    end
    if changed then render(state) end
end
return M
