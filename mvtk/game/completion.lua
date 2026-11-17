local CP=require "mvtk.core.checkpoint"
local GameEvents=require "mvtk.core.game_events"
local Flags=require "mvtk.core.flags"
local Inventory=require "mvtk.core.inventory"
local Runtime=require "developer.config.runtime_settings"
local Baseline=require "developer.config.game_completion"
local Model=require "mvtk.core.creator_settings_model"
local State=require "mvtk.game.completion_state"
local Endings=require "mvtk.game.endings"
local M={active=false}
local cached_config, cached_revision
local function effective_config()
    local revision=Runtime.revision()
    if cached_revision~=revision then
        cached_config=Endings.effective({},Runtime.section("game_completion",Baseline))
        cached_revision=revision
    end
    return cached_config
end
function M.config()
    return Model.copy(effective_config())
end
local function return_point(cfg)
    if cfg.continue_policy~="explore" then return nil end
    local point=cfg.return_room~="" and {room_id=cfg.return_room,x=cfg.return_x,y=cfg.return_y,position_kind="feet"} or CP.data.checkpoint
    if not point then return nil,"Set a return room/position or activate a checkpoint before finishing." end
    local layout=require("mvtk.rooms.layout_io").load({runtime_preferred=true})
    for _,room in ipairs(layout and layout.rooms or {}) do
        if room.id==point.room_id and point.x>=room.x and point.x<=room.x+room.w and point.y>=room.y and point.y<=room.y+room.h then return Model.copy(point) end
    end
    return nil,"Ending return checkpoint is outside its published room. Correct Ending settings and rebuild."
end
local state=State.new({has_flag=Flags.has,return_point=return_point,
    completion_percent=function() return require("mvtk.game.completion_tracker").percent() end,
    playtime_s=function() return require("mvtk.game.run_stats").playtime_s() end,
    playing=function() local Game=require "mvtk.game.game_manager"; return Game.get_state()==Game.STATE.PLAYING end,
    busy=function() return require("mvtk.bosses.boss_manager").completion_pending() end,
    stats=function()
        local stats = Model.copy(Inventory.export())
        local RunStats = require "mvtk.game.run_stats"
        if RunStats.settings().show_on_ending then stats.run_time_s = RunStats.playtime_s() end
        stats.completion_percent = require("mvtk.game.completion_tracker").ending_snapshot()
        return stats
    end,
    save=function(cfg,point)
        local plan,refusal
        if cfg.reward and cfg.reward~="" then
            plan,refusal=require("mvtk.game.grants").prepare(cfg.reward,{source="reward",reason="ending_reached",once_key="ending:"..cfg.id})
            if not plan and (not refusal or refusal.code~="already_granted") then
                return false,refusal and (refusal.message or refusal.code) or "Invalid ending reward"
            end
        end
        local mark=GameEvents.hold()
        local called,ok,err=pcall(CP.batch,"game_completed",function()
            if plan then require("mvtk.game.grants").commit(plan) end
            if cfg.reward_flag and cfg.reward_flag~="" then Flags.set(cfg.reward_flag,true) end
            if point then CP.set_checkpoint(point,point.room_id,point.position_kind) end
        end)
        if not called or not ok then GameEvents.discard(mark); return false,called and err or ok end
        GameEvents.release(mark)
        GameEvents.emit("ending_reached",{ending_id=cfg.id})
        return true
    end})
CP.register_provider("game_completion",{version=1,order=200,
    capture=function() return Model.copy(state.data) end,
    apply=function(data) state:load(data) end,
    defaults=function() state:load({}) end})
local function present(cfg,ending)
    -- Other endings own all content; only these three presentation fields are shared.
    local out=Model.copy(ending)
    out.font=cfg.font; out.text_scale=cfg.text_scale; out.credits_per_page=cfg.credits_per_page
    out.endings=nil
    return out
end
function M.presentation()
    local cfg=effective_config()
    return present(cfg,state.ending or Endings.find(cfg,state.data.id) or cfg)
end
-- One configured ending by id, merged as presentation() merges it (Extras
-- credits replay). Nil for an id the current settings no longer define.
function M.presentation_for(id)
    local cfg=effective_config()
    local ending=Endings.find(cfg,id)
    return ending and present(cfg,ending) or nil
end
function M.enter(id,token) state:enter(id,token) end
function M.leave(id,token) state:leave(id,token) end
function M.retry() state:retry() end
function M.data() return Model.copy(state.data) end
function M.begin_session() M.active=true; state.shown=false; state.ending=nil; state.pending=false; state.regions={}; state.error=nil end
function M.update(dt) if M.active then return state:tick(dt,effective_config()) end end
return M
