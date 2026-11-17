-- Content-addressed generated room resources (CP05, docs/metroidvania/
-- STAGE_7_WORLD_SCALE_PLAN.md slice f "2.2"). The content determines the
-- resource path, so many objects and rooms can share one file, and rebuilding
-- one room can never change what another room's file holds. The pattern
-- follows mvtk/editor/shared_atlas.lua.
--
-- Only generated prototypes and hulls go here. Every Tiled object stays a
-- gameobject instance in its room collection, with its id; per-object values
-- live on that instance as overrides.
--
-- Editor (LuaJ) and headless safe: no frontier patterns, no %.Nf formats, no
-- engine or editor API calls. The caller's context supplies the I/O.
local Adler = require "mvtk.core.adler32"
local R = require "mvtk.editor.resource_text"
local P = require "mvtk.editor.proto_utils"
local M = {}
local function quote(s) return '"' .. P.proto_escape(s) .. '"' end

M.GENERATED_DIR = "/developer/rooms/generated"
M.DIR = M.GENERATED_DIR .. "/shared"

-- The editor resolves stream_settings once and passes its resource directory.
-- Standalone tools/tests without an editor context retain the shipped default.
function M.generated_dir(c)
    local dir = (c and c.GENERATED_ROOMS_RESOURCE_DIR) or M.GENERATED_DIR
    return (dir:gsub("/+$", ""))
end

-- Texts written in this editor session, by absolute path. A queued write may
-- not be readable from disk yet, so this catches two different texts with
-- the same fingerprint inside one write batch. It never skips a write: at
-- worst a stale entry moves a text to the next suffix, which is still exact.
local written = {}

-- store(c, text, ext) -> "/developer/rooms/generated/shared/<fingerprint>.<ext>"
-- c: ROOT, join(a, b), read_text(absolute) -> text or nil,
-- write_if_changed(absolute, text). Identical text always returns the same
-- path; different text never shares one (full-text compare, then a suffix).
function M.store(c, text, ext)
    text = tostring(text):gsub("\r\n", "\n")
    ext = tostring(ext):gsub("^%.", "")
    local stem = M.generated_dir(c) .. "/shared/" .. Adler.fingerprint(text):gsub(":", "_")
    local suffix = 0
    while true do
        local path = stem .. (suffix == 0 and "" or "_" .. suffix) .. "." .. ext
        local absolute = c.join(c.ROOT, path:sub(2))
        local existing = c.read_text(absolute)
        if existing then existing = existing:gsub("\r\n", "\n") else existing = written[absolute] end
        if existing == nil or existing == text then
            -- write_if_changed is a no-op for the same text on disk or queued.
            c.write_if_changed(absolute, text)
            written[absolute] = text
            return path
        end
        suffix = suffix + 1
        -- A reader that returns other text for every name would loop forever.
        assert(suffix <= 64, "shared store: no free name for " .. stem .. "." .. ext)
    end
end

-- CP05d: per-object values live on the instance, so a shared prototype holds
-- only what its instances have in common.
--
-- Script properties of a prototype text or a parsed collection instance, as
-- {component_id = {property_id = {value=, type=}}}. Only `components` take
-- properties (gameobject_ddf.proto ComponentDesc); an instance holds them as
-- `component_properties` (InstanceDesc).
local function property_sets(entries)
    local result = {}
    for _, entry in ipairs(entries) do
        local id = R.value(entry.node, "id")
        local set = result[id] or {}
        for _, field in ipairs(R.all(entry.node, "properties")) do
            set[R.value(field.node, "id")] = {value = R.value(field.node, "value"), type = R.value(field.node, "type")}
        end
        result[id] = set
    end
    return result
end

function M.instance_overrides(node)
    return property_sets(R.all(node, "component_properties"))
end

function M.prototype_properties(text)
    return property_sets(R.all(R.parse(text).root, "components"))
end

-- The prototype text minus every property its instance overrides. The
-- instance's value wins over the prototype's in Defold, so the merged value
-- each script reads is unchanged.
function M.without_overridden(text, overrides)
    local doc = R.parse(text)
    for _, component in ipairs(R.all(doc.root, "components")) do
        local set = overrides[R.value(component.node, "id")]
        if set then
            for _, field in ipairs(R.all(component.node, "properties")) do
                if set[R.value(field.node, "id")] then R.remove(doc, field) end
            end
        end
    end
    return R.tidy(R.render(doc))
end

-- Moves every property of the named components out of the prototype text.
-- Returns the lean text, the instance's component_properties text (InstanceDesc
-- field order puts it after position and rotation) and the moved values.
function M.lift(text, component_ids)
    local wanted = {}
    for _, id in ipairs(component_ids) do wanted[id] = true end
    local doc = R.parse(text)
    local rows, moved = {}, {}
    for _, component in ipairs(R.all(doc.root, "components")) do
        local id = R.value(component.node, "id")
        local fields = wanted[id] and R.all(component.node, "properties") or {}
        if #fields > 0 then
            local parts, set = {}, moved[id] or {}
            for _, field in ipairs(fields) do
                local pid, value, kind = R.value(field.node, "id"), R.value(field.node, "value"), R.value(field.node, "type")
                parts[#parts + 1] = "properties { id: " .. quote(pid) .. " value: " .. quote(value) .. " type: " .. tostring(kind) .. " }"
                set[pid] = {value = value, type = kind}
                R.remove(doc, field)
            end
            moved[id] = set
            rows[#rows + 1] = "component_properties { id: " .. quote(id) .. " " .. table.concat(parts, " ") .. " }"
        end
    end
    return R.tidy(R.render(doc)), (#rows > 0 and table.concat(rows, " ") or nil), moved
end

-- Bake-time guard (slice f "2.3 Rows" CP05d step 2): every script property
-- the per-object text held is either overridden on this instance or held,
-- with the same value and type, by the shared file it now uses. A go-only
-- value that differs between instances therefore gets its own store file,
-- and a later change that strips more than its instance overrides fails
-- Create Rooms instead of losing the value.
function M.check_kept(path, owner, before, stored, overrides)
    local held = M.prototype_properties(stored)
    for cid, set in pairs(M.prototype_properties(before)) do
        for pid, property in pairs(set) do
            if not (overrides[cid] and overrides[cid][pid]) then
                local kept = held[cid] and held[cid][pid]
                assert(kept and tostring(kept.value) == tostring(property.value) and kept.type == property.type,
                    "Shared prototype " .. path .. " lost " .. cid .. "." .. pid .. " of " .. tostring(owner) ..
                    ": a value only the prototype holds must stay in it, or move to an instance override")
            end
        end
    end
end

-- store, then check_kept. Returns the stored path.
function M.store_checked(c, owner, before, lean, overrides)
    local path = M.store(c, lean, "go")
    M.check_kept(path, owner, before, lean, overrides)
    return path
end

-- Tests only: forget the session's written texts.
function M._reset()
    written = {}
end

return M
