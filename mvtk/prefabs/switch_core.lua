-- mvtk/prefabs/switch_core.lua
-- Toggle switch that emits messages via TriggerBus.

local Flags = require "mvtk.core.flags"
local TriggerBus = require "mvtk.world.trigger_bus"
local PU = require "mvtk.prefabs.prefab_utils"
local Util = require "mvtk.core.util"
local Presentation = require "mvtk.tiled.object_presentation"
local Art = require "developer.config.object_art"
local Elevators = require "mvtk.elevators.elevator_manager"

local DEFAULT_ON = "activate"
local DEFAULT_OFF = "deactivate"
local DEFAULT_LABEL_ON = "Switch On"
local DEFAULT_LABEL_OFF = "Switch Off"
local MSG_FORCE_OFF = hash("mvtk_force_off")

local SwitchState = require "mvtk.world.switch_state"
local M = {}

local function resolve_message_id(value, fallback)
    -- Authored message properties are text; hash them at the message boundary.
    -- Preserve engine hashes supplied by runtime callers without reverse lookup.
    if type(value) == "userdata" then
        return value == hash("") and hash(fallback) or value
    end
    local s = PU.normalize_hash_string(value)
    return hash(s or fallback)
end

local function update_label(self)
    if self.switch_options and self.switch_options.interaction == false then return end
    local label = self.state_on and (self.label_on_str or DEFAULT_LABEL_ON)
        or (self.label_off_str or DEFAULT_LABEL_OFF)
    PU.update_interaction_label(label)
end

local function update_sprite(self)
    Presentation.restore(self.state_on and "on" or "off")
    if self.switch_options and self.switch_options.kind == "strike" then return end
    if not Util.component_exists("#sprite") then
        return
    end
    local anim = self.state_on and (self.on_anim_str or "lever_on")
        or (self.off_anim_str or "lever_idle")
    if anim and anim ~= "" then
        pcall(sprite.play_flipbook, "#sprite", hash(anim))
    end
end

local function emit_trigger(self, msg_id, pulse_state)
    local payload = {
        lever_id = self.lever_id_key,
        kind = self.switch_options and self.switch_options.kind or "lever",
        persist = self.persist_state == true,
        state = pulse_state or (self.state_on and "on" or "off"),
    }
    if self.call_landing_key then payload.landing = self.call_landing_key end
    if self.target_id_key then
        TriggerBus.emit(self.target_id_key, msg_id, payload)
    else
        pcall(msg.post, msg.url("main:/main_go#script"), msg_id, payload)
    end
end

local function write_state(self, on)
    if not self.persist_state then return end
    SwitchState.write_own(Flags, self.persist_key, on)
    SwitchState.write_channel(Flags, self.target_id_key, on, on and self.msg_on_text or self.msg_off_text)
end

local function set_state(self, on, opts)
    if self.state_on == on and not (opts and opts.reemit) then return end
    opts = opts or {}
    local emit = opts.emit ~= false
    local play_sfx = opts.play_sound ~= false

    self.state_on = on and true or false
    if emit then write_state(self, self.state_on) end
    if self.state_on then
        if self.flag_on_str then Flags.set(self.flag_on_str, true) end
        if emit then
            emit_trigger(self, self.msg_on)
        end
        if play_sfx then
            PU.play_sound(self.sound_on, { room_id = self.room_id })
        end
    else
        if self.flag_off_str then Flags.set(self.flag_off_str, true) end
        if emit then
            emit_trigger(self, self.msg_off)
        end
        if play_sfx then
            PU.play_sound(self.sound_off, { room_id = self.room_id })
        end
    end
    if emit then Presentation.emit("interacted", self.state_on and "on" or "off")
    else Presentation.restore(self.state_on and "on" or "off") end
    update_sprite(self)
    update_label(self)
end

local function apply_props(self, props)
    props = props or {}
    if props.label_on ~= nil then self.label_on_str = tostring(props.label_on) end
    if props.label_off ~= nil then self.label_off_str = tostring(props.label_off) end
    if props.on_animation ~= nil then self.on_anim_str = tostring(props.on_animation) end
    if props.off_animation ~= nil then self.off_anim_str = tostring(props.off_animation) end
    update_label(self)
end

local function sync_call_switch(self)
    if not self.call_stop then return end
    local present, requested, failed, generation = Elevators.get_call_status(self.target_id_key, self.call_stop)
    if present == nil or present or requested or failed or generation ~= self.call_generation then
        self.call_pending = false
    end
    set_state(self, self.call_pending or present or requested or false, { emit = false, play_sound = false })
end

function M.init(self, options)
    self.switch_options = options
    Presentation.set_state_fallbacks(options and options.state_fallbacks or Art.lever_state_fallbacks)
    self.lever_id_key = PU.resolve_id(self.lever_id) or tostring(go.get_id())
    self.target_id_key = PU.resolve_id(self.target_id)
    self.msg_on_text = PU.normalize_hash_string(self.message_on) or DEFAULT_ON
    self.msg_off_text = PU.normalize_hash_string(self.message_off) or DEFAULT_OFF
    self.msg_on = resolve_message_id(self.message_on, DEFAULT_ON)
    self.msg_off = resolve_message_id(self.message_off, DEFAULT_OFF)
    self.call_landing_key = self.msg_on == hash("elevator_call") and PU.resolve_id(self.call_landing) or nil
    if self.msg_on == hash("elevator_call_bottom") then self.call_stop = "bottom"
    elseif self.msg_on == hash("elevator_call_top") then self.call_stop = "top"
    else self.call_stop = self.call_landing_key end
    self.flag_on_str = PU.normalize_hash_string(self.set_flag_on)
    self.flag_off_str = PU.normalize_hash_string(self.set_flag_off)
    self.requires_flag_str = PU.normalize_hash_string(self.requires_flag)
    self.label_on_str = PU.normalize_hash_string(self.label_on)
    self.label_off_str = PU.normalize_hash_string(self.label_off)
    self.on_anim_str = PU.normalize_hash_string(self.on_animation)
    self.off_anim_str = PU.normalize_hash_string(self.off_animation)

    local state = self.starts_on == true
    if self.toggle and self.flag_on_str and Flags.has(self.flag_on_str)
        and (not options or options.restore_on_flag ~= false) then
        state = true
    end
    self.persist_state = self.persist_state == true and self.toggle == true and not self.call_stop
    if self.persist_state then
        local saved = SwitchState.read_own(Flags, self.persist_key)
        if saved ~= nil then state = saved end
    end
    self.state_on = state
    self.cooldown_t = 0

    local label = self.state_on and (self.label_on_str or DEFAULT_LABEL_ON)
        or (self.label_off_str or DEFAULT_LABEL_OFF)
    if not options or options.interaction ~= false then
        PU.register_interaction(label, self.range, 5, nil, true)
    end

    update_sprite(self)
    sync_call_switch(self)
end

function M.final(self)
    if not self.switch_options or self.switch_options.interaction ~= false then
        PU.unregister_interaction()
    end
end

-- Hit-operated switches share the same persistence, flags and signal boundary.
function M.set_state(self, on, opts)
    set_state(self, on, opts)
end

function M.call(self)
    local _, _, _, generation = Elevators.get_call_status(self.target_id_key, self.call_stop)
    self.call_generation = generation
    self.call_pending = true
    set_state(self, true, { emit = false, play_sound = false })
    emit_trigger(self, self.msg_on)
    PU.play_sound(self.sound_on, { room_id = self.room_id })
end

function M.update(self, dt)
    if self.cooldown_t and self.cooldown_t > 0 then
        self.cooldown_t = math.max(0, self.cooldown_t - dt)
    end
    sync_call_switch(self)
end

function M.on_message(self, message_id, message, sender)
    if message_id == hash("apply_tiled_props") and message and message.properties then
        apply_props(self, message.properties)
        return
    end

    if message_id == MSG_FORCE_OFF then
        local msg_door_id = PU.normalize_hash_string(message and message.door_id)
        if msg_door_id and self.target_id_key and msg_door_id ~= tostring(self.target_id_key) then
            return
        end
        -- Keep visual/logical lever state in sync with timed targets that auto-close.
        write_state(self, false)
        set_state(self, false, { emit = false, play_sound = false })
        return
    end

    if message_id ~= hash("mvtk_interact") then
        return
    end

    if self.requires_flag_str and not Flags.has(self.requires_flag_str) then
        return
    end

    if self.cooldown_t and self.cooldown_t > 0 then
        return
    end

    if self.call_stop then
        M.call(self)
    elseif self.toggle then
        set_state(self, not self.state_on)
    else
        if self.flag_on_str then Flags.set(self.flag_on_str, true) end
        emit_trigger(self, self.msg_on, "on")
        PU.play_sound(self.sound_on, { room_id = self.room_id })
        if self.reset_delay and self.reset_delay > 0 then
            -- Pause.delay: menu pause keeps engine timers running (mvtk/core/pause.lua),
            -- and paused receivers must not see the reset arrive mid-menu.
            require("mvtk.core.pause").delay(self.reset_delay, function()
                emit_trigger(self, self.msg_off, "off")
                PU.play_sound(self.sound_off, { room_id = self.room_id })
            end)
        end
    end

    self.cooldown_t = tonumber(self.cooldown) or 0
    return true
end

local receive_message = M.on_message
function M.on_message(self, message_id, message, sender)
    local accepted = receive_message(self, message_id, message, sender)
    if message_id == hash("mvtk_interact") and message and message.interaction_result then
        require("mvtk.game.interaction_result").report(message, accepted)
    end
    return accepted
end

return M
