local DisplayText = require "mvtk.ui.display_text"
-- Two authored templates and a bounded pool of flask pips, owned by the feature HUD.
local Prompts = require "mvtk.ui.input_prompts"
local RuntimeSettings = require "developer.config.runtime_settings"
local HudLayout = require "mvtk.ui.hud_layout"
local Config = require "developer.config.hud_layout"
local Fit = require "mvtk.ui.hud_text_fit"
local M = { id="quick_item", layout_key="quick_item", root="quick_item_root", field="hud_quick_item",
    size=Config.quick_item.size, nodes={static=2,runtime_max=10}, text_role="hud",
    default_entry=Config.quick_item }
local function render(state)
    local data=state.data or {}; state.visible=(data.name or "")~=""
    local text=""
    if data.stepping then
        local rows,selected,selected_row={}
        if data.entries then
            for _,entry in ipairs(data.entries) do
                local row=DisplayText.ui("hud.quick_entry",{name=DisplayText.render(entry.name),count=entry.count})
                rows[#rows+1]=entry.selected and DisplayText.ui("hud.quick_selected",{entry=row}) or row
                if entry.selected then selected,selected_row=entry,rows[#rows] end
            end
        else
            -- Compatibility with older source payloads; current producers send entries.
            for name in (data.list_text or ""):gmatch("[^|]+") do
                rows[#rows+1]=DisplayText.render((name:gsub("^%s+",""):gsub("%s+$","")))
            end
        end
        text=table.concat(rows,DisplayText.render(state.layout.separator or " | "))
        text=Fit.line(gui,resource,state.label,text)
        if selected and not text:find(selected_row,1,true) then
            -- A bounded list may lose its tail; always show the current choice.
            text=Fit.decorated(gui,resource,state.label,DisplayText.render(selected.name),function(name)
                return DisplayText.ui("hud.quick_selected",{entry=DisplayText.ui("hud.quick_entry",
                    {name=name,count=selected.count})})
            end)
        end
    elseif state.visible then
        local button=state.layout.show_button~=false and DisplayText.ui("hud.quick_button",
            {button=Prompts.action_label("QUICK_USE",{device="active"})}) or ""
        local count=data.count ~= nil and DisplayText.ui(data.maximum and "hud.quick_capacity" or "hud.quick_count",
            {count=data.count,maximum=data.maximum}) or (data.count_text or "")
        text=Fit.decorated(gui,resource,state.label,DisplayText.render(data.name),function(name)
            return DisplayText.ui("hud.quick_item",{button=button,name=name,count=count})
        end)
    end
    -- Already rendered at this GUI-owned boundary; the host must not translate twice.
    state.set_text(state.label,text,true)
    for i,node in ipairs(state.pips) do gui.set_enabled(node,state.visible and i<=(data.charges or 0)) end
    state.revision=DisplayText.revision()
end
function M.init(state,get_node)
    state.label=get_node("quick_item_root")
    local template=get_node("quick_item_pip")
    local layout=RuntimeSettings.section("hud_layout",require "developer.config.hud_layout")
    local theme=HudLayout.theme(RuntimeSettings.section("ui_theme",require "developer.config.ui_theme"),layout,
        (RuntimeSettings.load() or {}).ui_theme)
    local c=theme.colors.heal or theme.colors.text_primary
    local color=vmath.vector4(c[1],c[2],c[3],c[4] or 1)
    gui.set_color(state.label,color); gui.set_color(template,color)
    state.pips={}; state.visible=false
    for i=1,10 do
        local node=gui.clone(template); gui.set_parent(node,state.label,false)
        gui.set_position(node,vmath.vector3((i-1)*(state.layout.pip_step or Config.quick_item.pip_step),
            state.layout.pip_y or Config.quick_item.pip_y,0))
        gui.set_enabled(node,false); state.pips[i]=node
    end
end
function M.on_data(state,data) state.data=data; render(state) end
function M.update(state)
    if state.data and state.revision~=DisplayText.revision() then render(state) end
end
return M
