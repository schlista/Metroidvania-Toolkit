-- Pure completion state machine. Dependencies provide persistence and gameplay state.
local Model=require "mvtk.core.creator_settings_model"
local Endings=require "mvtk.game.endings"
local M={}
function M.new(deps)
    local self={data={},pending=false,error=nil,shown=false,regions={}}
    function self:load(data)
        self.ending=nil; self.data=Model.copy(data or {}); self.pending=false; self.error=nil; self.shown=false; self.regions={}
    end
    function self:enter(id,token)
        self.regions[id]=self.regions[id] or {}; self.regions[id][token or id]=true
    end
    function self:leave(id,token)
        if self.regions[id] then self.regions[id][token or id]=nil; if not next(self.regions[id]) then self.regions[id]=nil end end
    end
    function self:retry() self.error=nil end
    function self:tick(dt,cfg)
        if not cfg.enabled then return end
        local completed=Endings.find(cfg,self.data.id)
        if completed then
            self.ending=completed
            if not self.shown and completed.continue_policy=="completed" then self.shown=true; return "show" end
            return
        end
        if deps.playing and not deps.playing() then return end
        self.data.playtime_s=(self.data.playtime_s or 0)+math.max(0,dt or 0)
        if self.error then return end -- one failure dialog; explicit Retry resumes saving
        local selected=self.pending and Endings.find(cfg,self.ending and self.ending.id)
        local eligibility={has_flag=deps.has_flag,completion_percent=deps.completion_percent,
            playtime_s=deps.playtime_s or function() return self.data.playtime_s end}
        for _,ending in ipairs(selected and {} or Endings.list(cfg)) do
            if Endings.trigger_met(ending,deps,self.regions)
                and (ending==cfg or Endings.requirements_met(ending,eligibility)) then selected=ending; break end
        end
        if not selected or (deps.busy and deps.busy()) then return end
        cfg=selected; self.ending=selected; self.pending=true
        local point,err=deps.return_point(cfg)
        if cfg.continue_policy=="explore" and not point then self.error=err or "No valid return checkpoint"; return "save_failed",self.error end
        local before=Model.copy(self.data)
        self.data.id=cfg.id; self.data.stats=deps.stats(); self.data.return_point=point
        self.data.run_time_s=self.data.stats.run_time_s
        self.data.stats.run_time_s=nil -- optional run clock belongs to the ending snapshot
        -- The adapter groups rewards/checkpoint/completion capture in one save;
        -- grant once keys protect rewards that stayed in memory after disk failure.
        local called,ok,reason=pcall(deps.save,cfg,point)
        if not called or not ok then self.data=before; self.error=tostring(called and reason or ok); return "save_failed",self.error end
        self.pending=false; self.shown=true; return "show"
    end
    return self
end
return M
