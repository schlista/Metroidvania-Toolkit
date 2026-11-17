-- Journal > People (WM12c): who the player has talked to. A person is an
-- npc_types.lua type with a journal block {title=, bio=, order=}; it is keyed
-- by type, not by placed npc_id, so a person a World state condition moves to
-- another room stays one entry. Met means NpcMemory holds that type, which it
-- does after the first finished conversation with any NPC of the type.
-- Titles, bios and last lines stay creator source text; only the displaying
-- list menu resolves them (T4, T5). Dependencies are lazy, so loading the
-- static menu registry registers no save state.
local M = {}
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end

function M.new(deps)
    deps = deps or {}
    local provider = {}
    local function types() return deps.npc_types or require "developer.config.npc_types" end
    local function memory() return deps.npc_memory or require "mvtk.npcs.npc_memory" end
    local function people_settings()
        local cfg = deps.settings and deps.settings() or require("mvtk.npcs.npc_living").settings()
        return type(cfg) == "table" and type(cfg.people) == "table" and cfg.people or {}
    end
    -- Every listed person, in journal order then title, then type id.
    local function people()
        local out = {}
        for id, def in pairs(types()) do
            if type(id) == "string" and type(def) == "table" and type(def.journal) == "table" then
                local journal = def.journal
                local title = nonblank(journal.title) and journal.title or (nonblank(def.name) and def.name or nil)
                out[#out + 1] = { id = id, title = title, bio = nonblank(journal.bio) and journal.bio or nil,
                    order = type(journal.order) == "number" and journal.order or 0 }
            end
        end
        table.sort(out, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            if (a.title or "") ~= (b.title or "") then return (a.title or "") < (b.title or "") end
            return a.id < b.id
        end)
        return out
    end
    local function title_of(person) return person.title and { text = person.title } or { key = "list.missing_name" } end
    local function body_of(person, last)
        local said = nonblank(last) and { key = "journal.people_last_said", params = { line = { text = last } } } or nil
        if said and person.bio then
            return { key = "journal.people_detail", params = { bio = { text = person.bio }, last = said } }
        end
        return said or (person.bio and { text = person.bio }) or ""
    end

    function provider.title() return { key = "journal.people" } end
    function provider.enabled()
        return people_settings().enabled == true and #people() > 0
    end
    function provider.header_right()
        local met, list = memory().snapshot().people, people()
        local count = 0
        for _, person in ipairs(list) do if met[person.id] then count = count + 1 end end
        return { key = "journal.people_progress", params = { met = count, total = #list } }
    end
    function provider.rows()
        local met, show_unmet, out = memory().snapshot().people, people_settings().show_unmet ~= false, {}
        for _, person in ipairs(people()) do
            local record = met[person.id]
            if record then
                local title = title_of(person)
                out[#out + 1] = { id = "person:" .. person.id, label = title, state = "available",
                    detail = { title = title, body = body_of(person, record.last) } }
            elseif show_unmet then
                out[#out + 1] = { id = "person:" .. person.id, label = { key = "journal.unknown" },
                    state = "unknown", selectable = false }
            end
        end
        return out
    end
    function provider.detail(_, row) return row.detail end
    return provider
end
local default = M.new()
default.new = M.new
return default
