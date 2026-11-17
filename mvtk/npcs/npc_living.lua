-- Living NPCs (WM12a-b): the new-dialogue marker, ambient lines (barks),
-- turning to the player and pacing a short stretch of floor.
-- npc.script calls init once for an NPC that opted into any of them, update
-- every frame only for such an NPC, and note_talk after every finished NPC
-- conversation. NPCs with a marker or barks use npc_living.go, whose `bubble`
-- label shows "!" (unheard lines), "?" (unheard lines that start or turn in a
-- quest) or a bark, from developer/config/npc_settings.lua. The marker has
-- priority: an NPC with something new does not bark. Talking clears it.
--
-- Every require is at call time, so loading this module costs nothing and the
-- scripts that load npc.script in tests need no new doubles. No go.animate,
-- timers or listeners: update returns while paused or outside the current
-- room. Wander steps every frame; a 0.1 s tick gates distance, marker and bark
-- work. The marker is recomputed only when Presence.revision() +
-- Quests.revision() moves, when settings change, or once after a
-- conversation; the shown text re-renders when the language changes.
-- Facing assumes art drawn facing right, as the NPC's Facing does.
local M = {}

M.TICK = 0.1
M.LABEL = "#bubble"

local settings_cache, settings_revision

-- npc_settings, merged with creator overrides once per settings revision.
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if settings_cache == nil or settings_revision ~= revision then
        settings_cache = Runtime.section("npc_settings", require "developer.config.npc_settings")
        settings_revision = revision
    end
    return settings_cache, settings_revision
end

local function markers_of(cfg)
    local markers = type(cfg) == "table" and type(cfg.markers) == "table" and cfg.markers or {}
    return markers
end

local function section_of(cfg, name)
    return type(cfg) == "table" and type(cfg[name]) == "table" and cfg[name] or {}
end

-- Pure marker rule. opts: enabled, signature (nil = no visible lines), stored,
-- vendor_active, needs_greeting, offers_task. Returns nil, "new" or "task".
function M.marker_state(opts)
    opts = type(opts) == "table" and opts or {}
    if opts.enabled == false then return nil end
    if opts.signature == nil then return nil end
    -- A vendor that opens its shop directly shows no dialogue to clear it.
    if opts.vendor_active and not opts.needs_greeting then return nil end
    if opts.stored ~= nil and opts.stored == opts.signature then return nil end
    return opts.offers_task and "task" or "new"
end

-- Pure bark helpers (WM12b). Lines are `|`-separated source text; blanks drop.
function M.parse_barks(text)
    local lines = {}
    if type(text) ~= "string" then return lines end
    for part in (text .. "|"):gmatch("([^|]*)|") do
        local line = part:match("^%s*(.-)%s*$")
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

-- A list of source lines from an npc_types.lua `barks` table.
local function list_barks(list)
    local lines = {}
    if type(list) ~= "table" then return lines end
    for _, value in ipairs(list) do
        local line = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end
M.list_barks = list_barks

-- Index of the next line. Never repeats the last one when there is a choice.
-- random(n) returns 1..n (math.random by default).
function M.pick_bark(lines, last, random)
    local count = type(lines) == "table" and #lines or 0
    if count == 0 then return nil end
    if count == 1 then return 1 end
    random = random or math.random
    if last == nil or last < 1 or last > count then return random(count) end
    local index = random(count - 1)
    if index >= last then index = index + 1 end
    return index
end

-- One wander step. state: x (offset from home), dir (1 or -1), wait (seconds
-- left at an end). opts: width, speed, pause_min, pause_max, random() in [0, 1).
-- Walks home +- width/2, stops at each end for pause_min..pause_max, then
-- turns. Returns the new offset and whether the character moved.
function M.wander_step(state, dt, opts)
    local half = math.max(0, tonumber(opts.width) or 0) / 2
    if half <= 0 then return state.x, false end
    dt = math.max(0, tonumber(dt) or 0)
    if (state.wait or 0) > 0 then
        state.wait = math.max(0, state.wait - dt)
        return state.x, false
    end
    local dir = state.dir == -1 and -1 or 1
    local x = state.x + dir * math.max(0, tonumber(opts.speed) or 0) * dt
    if x >= half or x <= -half then
        x = x >= half and half or -half
        state.dir = -dir
        local lo = math.max(0, tonumber(opts.pause_min) or 0)
        local hi = math.max(lo, tonumber(opts.pause_max) or lo)
        state.wait = lo + (hi - lo) * (opts.random or math.random)()
    end
    local moved = x ~= state.x
    state.x = x
    return x, moved
end

-- Which way to face: toward the player while near, otherwise `facing`.
function M.facing_for(npc_x, player_x, facing, near)
    facing = (tonumber(facing) or 1) < 0 and -1 or 1
    if not near or player_x == nil or npc_x == nil or player_x == npc_x then return facing end
    return player_x < npc_x and -1 or 1
end

local function number_or(value, default)
    local n = tonumber(value)
    if n == nil or n ~= n then return default end
    return n
end

local function wanders(self)
    return number_or(self and self.wander_width, 0) > 0
end

-- Bark lines: the object's Barks, else its npc_types.lua type's `barks`.
local function bark_lines(self)
    local lines = M.parse_barks(self.barks)
    if #lines > 0 then return lines end
    local npc_type = self.npc_type_str
    if npc_type == nil or npc_type == "" then return lines end
    local types = require "developer.config.npc_types"
    local entry = type(types) == "table" and types[npc_type] or nil
    return list_barks(type(entry) == "table" and entry.barks or nil)
end

-- Any living behaviour opted in on this NPC. Type barks count, as they do
-- for the bake (hooks/core/npc_behavior_bake.lua has_barks).
function M.wants(self)
    if self == nil then return false end
    return self.show_new_dialogue_marker == true or self.face_player == true or wanders(self)
        or (type(self.barks) == "string" and self.barks:match("%S") ~= nil)
        or #bark_lines(self) > 0
end

-- The rows this NPC's conversation would show now.
local function preview_rows(self)
    local id = self.dialogue_id_str
    if id == nil or id == "" then return {} end
    local Registry = require "mvtk.dialogue.dialogue_registry"
    local Logic = require "mvtk.dialogue.dialogue_logic"
    return require("mvtk.dialogue.dialogue_preview").lines(id, Registry.get, Logic.eval_condition)
end

function M.compute(self)
    local cfg = M.settings()
    local markers = markers_of(cfg)
    local Preview = require "mvtk.dialogue.dialogue_preview"
    local rows = preview_rows(self)
    local Flags = require "mvtk.core.flags"
    local Vendor = require "mvtk.economy.vendor"
    local vendor_active = Vendor.is_active(self, self._vendor_preset, Flags) and true or false
    return M.marker_state({
        enabled = markers.enabled ~= false,
        signature = Preview.signature(rows),
        stored = require("mvtk.npcs.npc_memory").seen(self.npc_id_str),
        vendor_active = vendor_active,
        needs_greeting = vendor_active and Vendor.needs_greeting(self.vendor_greeting, self.npc_id_str,
            self.dialogue_id_str ~= nil and self.dialogue_id_str ~= "", Flags) or false,
        offers_task = Preview.offers_task(rows),
    })
end

-- The marker's source text for a state (nil hides it).
local function marker_source(state, cfg)
    if state == nil then return nil end
    local markers = markers_of(cfg)
    local source = state == "task" and markers.task_text or markers.new_text
    if source == nil then source = state == "task" and "?" or "!" end
    source = tostring(source)
    if source == "" then return nil end
    return source
end

-- The text the label shows for a marker state ("" hides it).
function M.marker_text(state, cfg)
    local source = marker_source(state, cfg)
    if source == nil then return "" end
    return require("mvtk.ui.display_text").render(source)
end

local function show(self, value)
    if self._living_text == value then return end
    self._living_text = value
    go.set(self._living_label, "text", value)
end

-- The marker is one character and a bark a sentence, so each has its own size.
local function set_scale(self, cfg, marker)
    local scale = tonumber(section_of(cfg, marker and "markers" or "barks").scale) or 1
    if self._living_scale == scale then return end
    self._living_scale = scale
    go.set(self._living_label, "scale", vmath.vector3(scale, scale, 1))
end

local function set_facing(self, facing)
    if self._living_face == facing then return end
    self._living_face = facing
    require("mvtk.tiled.object_presentation").restore(facing < 0 and "flipped" or "default")
end

function M.init(self)
    if not M.wants(self) then return false end
    local has_label = require("mvtk.core.util").component_exists(M.LABEL, "text")
    self._living_marker = self.show_new_dialogue_marker == true and has_label or nil
    self._living_barks = nil
    if has_label then
        local lines = bark_lines(self)
        if #lines > 0 then self._living_barks = lines end
    end
    self._living_face_player = self.face_player == true or nil
    self._living_wander = wanders(self) and { x = 0, dir = number_or(self.facing, 1) < 0 and -1 or 1, wait = 0 } or nil
    if not (self._living_marker or self._living_barks or self._living_face_player or self._living_wander) then
        return false
    end
    if has_label then
        self._living_label = msg.url(M.LABEL)
        self._living_scale = nil
        set_scale(self, M.settings(), self._living_marker ~= nil)
    end
    if self._living_face_player or self._living_wander then
        -- Turning flips the owned art's default image (D-WM12-4's fallback).
        require("mvtk.tiled.object_presentation").set_state_fallbacks({ flipped = { flip_horizontal = true } })
        self._living_face = number_or(self.facing, 1) < 0 and -1 or 1
    end
    self._living_acc = M.TICK
    self._living_rev, self._living_settings, self._living_display = nil, nil, nil
    self._living_state, self._living_source = nil, nil
    self._living_near, self._bark_source, self._bark_timer, self._bark_cool, self._bark_last = false, nil, 0, 0, nil
    if self._living_label then show(self, "") end
    return true
end

-- A conversation, a shop or a cutscene holds barks and wander.
local function busy(self)
    if self._talk_open or self._vendor_pending or self._station_menu then return true end
    return require("mvtk.rooms.input_controller").get_blocked() == true
end

local function hide_bark(self, cooldown)
    if self._bark_source == nil then return end
    self._bark_source, self._bark_timer = nil, 0
    self._bark_cool = math.max(0, number_or(cooldown, 0))
end

local function step_wander(self, dt)
    local state = self._living_wander
    if self._living_near or self._living_busy then return end
    local cfg = section_of(settings_cache, "wander")
    local before = state.x
    local x, moved = M.wander_step(state, dt, {
        width = self.wander_width, speed = number_or(self.wander_speed, 30),
        pause_min = number_or(cfg.pause_min, 1.5), pause_max = number_or(cfg.pause_max, 4),
    })
    if not moved then return end
    -- Move by the step only, so any other placement of the NPC is kept.
    local p = go.get_position()
    go.set_position(vmath.vector3(p.x + (x - before), p.y, p.z))
    self._living_walk = x > before and 1 or -1
end

-- Distance work for barks, turning and wander (0.1 s tick).
local function sense(self, elapsed, cfg)
    local player = rawget(_G, "PLAYER_WORLD_POS")
    local here = go.get_world_position()
    local dx, dy = 0, 0
    local known = player ~= nil
    if known then dx, dy = player.x - here.x, player.y - here.y end
    local distance = known and math.sqrt(dx * dx + dy * dy) or math.huge
    self._living_busy = busy(self)
    self._living_near = distance <= number_or(self.interaction_range, 48)
    if self._living_face_player or self._living_wander then
        local base = self._living_wander and (self._living_walk or self._living_wander.dir) or self.facing
        local near = self._living_face_player and self._living_near
        set_facing(self, M.facing_for(here.x, known and player.x or nil, base, near))
    end
    if not self._living_barks then return end
    local barks = section_of(cfg, "barks")
    local cooldown = number_or(self.bark_cooldown, 8)
    local in_range = distance <= number_or(self.bark_range, 96)
    self._bark_cool = math.max(0, (self._bark_cool or 0) - elapsed)
    if self._bark_source ~= nil then
        self._bark_timer = self._bark_timer - elapsed
        if self._bark_timer <= 0 or not in_range or self._living_busy or barks.enabled == false
            or self._living_state ~= nil then
            hide_bark(self, cooldown)
        end
        return
    end
    if barks.enabled == false or not in_range or self._living_busy or self._living_state ~= nil then return end
    if self._bark_cool > 0 then return end
    local index = M.pick_bark(self._living_barks, self._bark_last)
    self._bark_last = index
    self._bark_source = self._living_barks[index]
    self._bark_timer = math.max(0.1, number_or(barks.show_seconds, 3))
end

function M.update(self, dt)
    if require("mvtk.core.pause").get() then return end
    if not require("mvtk.prefabs.prefab_utils").is_current_room(self.room_id) then
        -- A hidden cached room keeps running scripts; its label must not show.
        self._living_rev = nil
        self._bark_source, self._bark_timer = nil, 0
        if self._living_label then
            self._living_source = nil
            show(self, "")
        end
        return
    end
    dt = tonumber(dt) or 0
    if self._living_wander and settings_cache ~= nil then step_wander(self, dt) end
    self._living_acc = (self._living_acc or 0) + dt
    if self._living_acc < M.TICK then return end
    local elapsed = self._living_acc
    self._living_acc = 0
    local cfg, settings_rev = M.settings()
    if self._living_marker then
        local revision = require("mvtk.world.presence").revision() + require("mvtk.game.quests.quests").revision()
        if revision ~= self._living_rev or settings_rev ~= self._living_settings then
            self._living_rev, self._living_settings = revision, settings_rev
            self._living_state = M.compute(self)
        end
    end
    if self._living_barks or self._living_face_player or self._living_wander then sense(self, elapsed, cfg) end
    if not self._living_label then return end
    local marker = marker_source(self._living_state, cfg)
    local source = marker or self._bark_source
    local display = require("mvtk.ui.display_text").revision()
    if source ~= self._living_source or display ~= self._living_display then
        self._living_source, self._living_display = source, display
        if source then set_scale(self, cfg, marker ~= nil) end
        show(self, source and require("mvtk.ui.display_text").render(source) or "")
    end
end

-- After an NPC's own conversation closed: remember what it would say now
-- (its set_flag lines have run, so the marker does not come straight back).
function M.note_talk(self)
    local Preview = require "mvtk.dialogue.dialogue_preview"
    local signature = Preview.signature(preview_rows(self))
    local last = require("mvtk.dialogue.dialogue_logic").take_last_line()
    require("mvtk.npcs.npc_memory").note_talk(self.npc_id_str, self.npc_type_str, self.room_id_str, signature, last)
    self._living_rev = nil
    self._living_acc = M.TICK
end

return M
