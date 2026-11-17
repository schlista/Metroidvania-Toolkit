-- Event snapshots feed local display clocks; gameplay owns the authoritative result.
local GeneratedText = require "mvtk.ui.generated_text"
local Text = require "mvtk.ui.trial_text"
local MenuText = require "mvtk.ui.menu_text"
local DisplayText = require "mvtk.ui.display_text"
local Pause = require "mvtk.core.pause"
local Notices = require "mvtk.ui.notices"
local Config = require "developer.config.hud_layout"
local M = {id="trial",layout_key="trial",root="trial_root",field="hud_trial",
    size=Config.trial.size,nodes={static=3,runtime_max=0},text_role="hud",
    default_entry=Config.trial}
local function fit(state, node, source, height, wrap)
    local text = MenuText.render(source,DisplayText)
    if not wrap then text = text:gsub("[\r\n]"," ") end
    local scale = gui.get_scale(node)
    local count = 0; for _ in text:gmatch("[^\128-\191]") do count=count+1 end
    local original = text
    while text ~= "" do
        local size = GeneratedText.metrics(gui.get_font_resource(gui.get_font(node)),text,{
            width=state.width/scale.x,line_break=wrap,leading=gui.get_leading(node),tracking=gui.get_tracking(node)}, resource)
        if size.width*scale.x <= state.width and size.height*scale.y <= height then break end
        count=count-1; text=Notices.trim(original,count)
    end
    state.set_text(node,text,true)
end
local function clock_tick(state)
    if state.data.state == "countdown" then return math.ceil(state.seconds) end
    return math.floor(state.elapsed*10+0.0000001)
end
local function render(state)
    local data = state.data
    if not data or not state.visible then return end
    local goal = data.state == "result" and data.title or Text.goal(data)
    local limits = data.state ~= "result" and Text.limits(data)
    local entry = state.layout or M.default_entry
    local line_height = entry.line_height or Config.trial.line_height
    local height = line_height
    if limits then
        goal = {parts={goal,limits},separator="\n"}
        local scale = gui.get_scale(state.goal)
        local metrics = GeneratedText.metrics(gui.get_font_resource(gui.get_font(state.goal)),
            MenuText.render(goal,DisplayText),{width=state.width/scale.x,line_break=true,
                leading=gui.get_leading(state.goal),tracking=gui.get_tracking(state.goal)}, resource)
        height = math.min(entry.max_goal_height or Config.trial.max_goal_height,
            math.max(line_height,math.ceil(metrics.height*scale.y)))
    end
    if limits or state.expanded then
        local size, scale = gui.get_size(state.goal), gui.get_scale(state.goal)
        gui.set_size(state.goal,vmath.vector3(state.width/scale.x,height/scale.y,size.z))
        gui.set_line_break(state.goal,limits ~= nil and limits ~= false)
        local position = gui.get_position(state.clock)
        position.y = -height
        gui.set_position(state.clock,position)
    end
    state.expanded, state.height = limits ~= nil and limits ~= false, height+line_height
    fit(state,state.goal,goal,height,limits ~= nil and limits ~= false)
    local clock
    if data.state == "countdown" then clock={key="trial.countdown",params={count=math.ceil(state.seconds)}}
    elseif data.state == "result" then clock=data.text
    else
        local ticks=math.floor(state.elapsed*10+0.0000001)
        clock=ticks == 0 and {key="trial.go"} or Text.time(ticks)
        if data.no_damage or data.trial_goal == "survive" then
            clock={parts={clock,Text.hits(data.hits or 0)},separator={key="trial.separator"}}
        end
    end
    fit(state,state.clock,clock,line_height,false)
    state.revision=DisplayText.revision()
    state.display_tick=clock_tick(state)
end
function M.init(state,get_node)
    state.goal,state.clock=get_node("trial_goal"),get_node("trial_clock")
    state.visible=false
    local scale=state.hud_scale or 1
    state.width=math.min(M.size.w*scale,(state.layout or M.default_entry).max_width or 356)/scale
    for _,node in ipairs({state.goal,state.clock}) do
        local size, text_scale=gui.get_size(node),gui.get_scale(node)
        gui.set_size(node,vmath.vector3(state.width/text_scale.x,size.y,size.z))
    end
end
function M.measure(state) return {w=state.width or M.size.w,h=state.height or M.size.h} end
function M.on_data(state,data)
    state.data,state.visible=data,data.state ~= "idle"
    state.seconds,state.elapsed=data.seconds or 0,(data.tenths or 0)/10
    state.remaining=data.duration or 0
    render(state)
end
function M.update(state,dt,frozen)
    if not state.visible then return end
    if not frozen then
        dt=math.max(0,dt)*Pause.dt_scale()
        if state.data.state == "countdown" then state.seconds=math.max(0,state.seconds-dt)
        elseif state.data.state == "fighting" then state.elapsed=state.elapsed+dt
        elseif state.data.state == "result" then
            state.remaining=math.max(0,state.remaining-dt)
            if state.remaining == 0 then state.visible=false; return end
        end
    end
    if state.display_tick ~= clock_tick(state) or state.revision ~= DisplayText.revision() then render(state) end
end
return M
