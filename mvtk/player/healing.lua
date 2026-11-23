-- Saved quick-item selection and flask capacity; drinks belong to each host instance.
local Util = require "mvtk.core.util"
local Timers = require "mvtk.player.timers"
local M = {}
local charges, bonus_sources, selected = nil, {}, "heal"
local cached, cached_revision
local function copy(t)
    local out = {}; for k,v in pairs(t or {}) do out[k]=v end; return out
end
function M.settings()
    local runtime = require "developer.config.runtime_settings"
    local revision = runtime.revision()
    if not cached or cached_revision ~= revision then
        cached = runtime.section("healing", require "developer.config.healing")
        cached_revision = revision
    end
    return cached
end
local function maximum()
    local total = M.settings().flask.max_charges
    for _,n in pairs(bonus_sources) do total=total+n end
    return math.max(0,total)
end
local function current() if charges == nil then charges=maximum() end; return charges end
local function state(self)
    return self and self._host and self._host.features and self._host.features.healing
end
local function valid(self) return self and type(self.health)=="number" and type(self.max_health)=="number" end
local function inventory() return require "mvtk.core.inventory" end
function M.entries(self)
    local cfg, list = M.settings(), {}
    if cfg.model=="flask" and maximum()>0 and require("mvtk.abilities.ability_manager").can_use_ability("healing") then
        list[#list+1]={id="heal",name=cfg.heal_name,count=current(),maximum=maximum(),heal=cfg.flask.heal_amount,use_time=cfg.flask.use_time}
    end
    local items=require "developer.config.items"
    for id,count in pairs(inventory().all()) do
        local item=items[id]
        if count>0 and item and item.quick_use then
            list[#list+1]={id=id,name=item.name or id,count=count,heal=item.heal or 0,use_time=item.use_time or 0}
        end
    end
    local order={}; for i,id in ipairs(cfg.quick.order) do order[id]=i end
    table.sort(list,function(a,b)
        local left,right=order[a.id] or math.huge,order[b.id] or math.huge
        return left==right and a.id<b.id or left<right
    end)
    return list
end
function M.select(id)
    if type(id)~="string" or id=="" then return false end
    selected=id; return true
end
local function find(list,id)
    for i,entry in ipairs(list) do if entry.id==id then return entry,i end end
end
local function selection(list)
    local entry=find(list,selected)
    if not entry then entry=list[1]; if entry then selected=entry.id end end
    return entry
end
local function refused(self)
    local use=M.settings().use
    return not valid(self) or self._is_dead or (self._stun_t or 0)>0 or self._in_climb or self._grapple_active
        or self._ledge_hanging or self._ledge_kinematic or (self._dash_t or 0)>0 or (self._slide_t or 0)>0
        or self._pound_active or self._attack or self._room_arrival or (self._in_water and not use.allow_in_water)
        or (not self.grounded and not use.allow_in_air) or self.health>=self.max_health
end
local function sound(id) if id and id~="" then require("mvtk.audio.audio").sfx(id) end end
local function channel_usable()
    local energy=require "mvtk.player.energy_state"
    return require("mvtk.abilities.ability_manager").can_use_ability("healing")
        and energy.enabled() and energy.has(M.settings().channel.cost)
end
local function cancel(self)
    require("mvtk.player.hold_toggles").clear(self, "heal")
    local s=state(self)
    if s and s.drink then
        s.drink=nil
        require("mvtk.player.player_stats").clear_source("ability:healing")
    end
end
local function complete(self)
    local s=state(self); local drink=s.drink; local entry=drink.entry
    if drink.channel then
        if not channel_usable() or not require("mvtk.player.energy_state").consume(M.settings().channel.cost,{reason="heal"}) then
            cancel(self); return false
        end
    elseif entry.id=="heal" then
        if current()<=0 then cancel(self); return false end
        charges=charges-1
    elseif not inventory().consume(entry.id,1) then cancel(self); return false end
    local before=self.health
    self.health=self.health+entry.heal
    local resources=require "mvtk.player.resources"
    resources.clamp_health(self)
    resources.post_resource_float(-(self.health-before),"heal")
    msg.post("main:/mode_hud#mode_hud","hud_health",{hp=self.health,hp_max=self.max_health})
    local use=M.settings().use
    sound(use.sound_use)
    if use.fx~="" then require("mvtk.fx.fx").play(use.fx,self.pos) end
    cancel(self)
    selection(M.entries(self))
    return true
end
-- Kept separate from the hold handler for the optional press-to-channel control.
function M.start_channel(self, latched)
    local s=state(self); if not s or not valid(self) or s.drink then return false end
    local cfg=M.settings()
    if cfg.model~="channel" or refused(self) or not channel_usable() then
        sound(cfg.use.sound_refuse); return false
    end
    s.stepping=false
    local toggles=require "mvtk.player.hold_toggles"
    toggles.sync(self, "heal")
    if latched and not toggles.set(self, "heal", true) then return false end
    s.drink={channel=true,latched=latched==true,entry={heal=cfg.channel.heal_amount},remaining=cfg.channel.channel_time,health=self.health}
    Timers.start_combat_window(s.drink, "remaining", cfg.channel.channel_time, nil, 1e-7)
    require("mvtk.player.player_stats").set_source("ability:healing",{speed_mult=cfg.use.move_mult},{layer="temporary"})
    return true
end
function M.on_tap(self)
    local s=state(self); if not s or not valid(self) then return false end
    if s.suppress_toggle_tap then s.suppress_toggle_tap=false; return false end
    if s.drink and s.drink.latched then cancel(self); return true end
    if s.drink then return false end
    local cfg,list=M.settings(),M.entries(self)
    local entry=selection(list)
    if cfg.model=="channel" and not entry then
        if require("mvtk.player.hold_toggles").enabled("heal") then return M.start_channel(self, true) end
        if (s.hint_toast_t or 0)<=0 then
            require("mvtk.prefabs.prefab_utils").toast({key="healing.hold_to_heal"})
            Timers.start_combat_window(s, "hint_toast_t", 3)
        end
        return false
    end
    if entry and entry.count<=0 and cfg.quick.auto_fallback then
        local _,index=find(list,entry.id)
        -- The fallback keeps the saved selection, so a refilled flask is used next.
        for offset=1,#list do
            local candidate=list[(index+offset-1)%#list+1]
            if candidate.count>0 then entry=candidate; break end
        end
    end
    if refused(self) or not entry or entry.count<=0 then sound(cfg.use.sound_refuse); return false end
    s.drink={entry=entry,remaining=entry.use_time,health=self.health}
    Timers.start_combat_window(s.drink, "remaining", entry.use_time, nil, 1e-7)
    require("mvtk.player.player_stats").set_source("ability:healing",{speed_mult=cfg.use.move_mult},{layer="temporary"})
    if entry.use_time<=0 then return complete(self) end
    return true
end
local function step(self)
    local list=M.entries(self); if #list<2 then return end
    selection(list); local _,index=find(list,selected); selected=list[index%#list+1].id
end
function M.on_hold(self)
    local s=state(self); if not s or not valid(self) then return false end
    if s.suppress_toggle_tap then return false end
    if M.settings().model=="channel" then
        return M.start_channel(self, require("mvtk.player.hold_toggles").enabled("heal"))
    end
    if #M.entries(self)<2 then return M.on_tap(self) end
    cancel(self); step(self); s.stepping=true
    s.repeat_t, s.repeat_age = M.settings().quick.step_repeat_seconds, 0
    return true
end
local function publish(self)
    local s=state(self); local list=M.entries(self); local entry=selection(list)
    local names,signature,entries={},{},{}
    for _,row in ipairs(list) do
        entries[#entries+1]={name=row.name,count=row.count,maximum=row.maximum,selected=row.id==selected}
        names[#names+1]=(row.id==selected and "> " or "")..row.name.." "..row.count
        signature[#signature+1]=row.id..":"..row.name..":"..row.count..":"..tostring(row.maximum)
    end
    local data={entries=entries,count=entry and entry.count,maximum=entry and entry.maximum,name=entry and entry.name or "",count_text=entry and (entry.maximum and (entry.count.."/"..entry.maximum) or tostring(entry.count)) or "",
        list_text=table.concat(names," | "),stepping=s.stepping==true,charges=entry and entry.id=="heal" and entry.count or 0}
    local prompt=require("mvtk.ui.input_prompts").revision()
    local key=table.concat(signature,"|")..":"..selected..":"..tostring(data.stepping)..":"..prompt
    if s.signature~=key then require("mvtk.ui.hud_bus").post("quick_item",data); s.signature=key end
end
function M.init(self)
    local s=state(self); if s and valid(self) then s.last_health=self.health end
end
function M.update(self,dt,input)
    local s=state(self)
    -- Old host fixtures and non-gameplay callers have no Quick Use input schema.
    if not s or not valid(self) or not input or input.quick_use_held==nil then return end
    local cfg=M.settings()
    local toggles=require "mvtk.player.hold_toggles"
    local blocked=toggles.sync(self, "heal")
    if input.quick_use_down then
        s.suppress_toggle_tap=false
        if s.drink and s.drink.latched then
            cancel(self); s.suppress_toggle_tap=true
        end
    end
    Timers.tick_combat_window(s, "hint_toast_t", dt)
    local damaged=s.last_health and self.health<s.last_health
    if damaged and not s.hint_shown then
        if cfg.model=="channel" then
            if channel_usable() then s.hint_pending=true end
        else
            for _,entry in ipairs(M.entries(self)) do
                if entry.count>0 then s.hint_pending=true; break end
            end
        end
    end
    -- Damage normally stuns before this hook runs. Keep that first hint until
    -- the player can act again, even though health does not drop a second time.
    if s.hint_pending and not refused(self) then
        if cfg.model=="channel" then
            if channel_usable() then
                s.hint_shown=true; s.hint_pending=false
                if toggles.enabled("heal") then
                    require("mvtk.prefabs.prefab_utils").toast({key="healing.press_to_heal"})
                else require("mvtk.ui.tutorial_popups").on_event(cfg.channel.hint_event) end
            end
        else
            for _,entry in ipairs(M.entries(self)) do
                if entry.count>0 then
                    s.hint_shown=true; s.hint_pending=false
                    require("mvtk.ui.tutorial_popups").on_event(cfg.hint_event); break
                end
            end
        end
    end
    s.last_health=self.health
    if s.drink then
        local latched=s.drink.latched
        local interrupted=(cfg.use.interrupt_on_damage or latched) and self.health<s.drink.health
            or (latched and damaged)
        if cfg.use.cancel_on_action then
            for _,key in ipairs({"jump_down","slide_down","light_down","heavy_down","ranged_down","parry_down","grapple_down"}) do
                interrupted=interrupted or input[key]
            end
        end
        local channel=s.drink.channel
        local holding=input.quick_use_held or (latched and toggles.get(self, "heal"))
        if interrupted or refused(self) or (channel and (blocked or not holding or not channel_usable())) then cancel(self)
        else
            local remaining = dt
            while s.drink do
                local ready, spent = Timers.tick_combat_deadline(s.drink, "remaining", remaining)
                if not ready then break end
                if not complete(self) or not channel or not cfg.channel.repeat_while_held or not holding
                    or refused(self) or not channel_usable() or not M.start_channel(self, latched) then break end
                remaining = math.max(0, remaining - spent)
                if remaining == 0 or cfg.channel.channel_time <= 0 then break end
            end
        end
    end
    if s.stepping then
        if not input.quick_use_held then s.stepping=false
        else
            local ticks, step_dt = Timers.combat_steps(s, "repeat_age", dt)
            for _ = 1, ticks do
                s.repeat_t = s.repeat_t - step_dt
                while s.repeat_t <= 1e-7 do
                    step(self)
                    s.repeat_t = s.repeat_t + cfg.quick.step_repeat_seconds
                end
            end
        end
    end
    publish(self)
end
function M.reset(self)
    cancel(self); local s=state(self)
    if s then s.stepping=false; s.signature=nil; s.last_health=self.health; s.hint_pending=false; s.suppress_toggle_tap=false end
end
-- Rests and respawns follow their healing.lua switches; any other named
-- caller (a developer cheat, for example) refills unconditionally.
function M.refill(reason)
    local flask=M.settings().flask
    if reason=="rest" and not flask.refill_at_save_points then return false end
    if (reason=="respawn" or reason=="load") and not flask.refill_on_respawn then return false end
    charges=maximum(); return true
end
function M.restore(self,message)
    if not state(self) or not valid(self) or type(message)~="table" then return end
    M.reset(self)
    if message.reason=="rest" then M.refill("rest")
    elseif message.respawn_pos and (message.reason=="respawn" or message.reason=="load") then M.refill(message.reason) end
end
function M.add_bonus_charges(n,source_key)
    if type(source_key)~="string" or source_key=="" or bonus_sources[source_key] then return false end
    n=tonumber(n) or M.settings().flask.upgrade_charges
    if n<=0 or n%1~=0 then return false end
    local before=current(); bonus_sources[source_key]=n; charges=before+n; return true
end
-- Compensate only a source newly added by a refused reward transaction.
function M.remove_bonus_charges(source_key)
    local amount = bonus_sources[source_key]
    if not amount then return false end
    local before = current()
    bonus_sources[source_key] = nil
    charges = math.max(0, math.min(maximum(), before - amount))
    return true
end
function M.defaults()
    bonus_sources={}; selected="heal"; charges=maximum()
end
function M.on_session_start()
    require("mvtk.ui.hud_bus").post("quick_item",{name="",count_text="",list_text="",stepping=false})
end
Util.register_checkpoint_provider("healing",{
    version=1,order=48,description="Healing flask and quick item",
    capture=function() return {charges=current(),bonus_sources=copy(bonus_sources),selected=selected} end,
    apply=function(data)
        data=type(data)=="table" and data or {}; bonus_sources={}
        if type(data.bonus_sources)=="table" then
            for key,n in pairs(data.bonus_sources) do
                if type(key)=="string" and type(n)=="number" and n>0 and n<math.huge and n%1==0 then bonus_sources[key]=n end
            end
        end
        charges=type(data.charges)=="number" and data.charges==data.charges and math.max(0,math.min(maximum(),math.floor(data.charges))) or maximum()
        selected=type(data.selected)=="string" and data.selected~="" and data.selected or "heal"
    end,
    defaults=M.defaults,
})
return M
