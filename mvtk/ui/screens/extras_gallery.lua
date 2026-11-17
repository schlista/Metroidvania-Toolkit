-- Extras Gallery tab: images unlocked on this profile. Choosing an unlocked row
-- asks the Extras host to show it full screen (delegate; the host owns the
-- viewer). Pure provider: image ids are never shown (T8), and titles and
-- captions stay creator source text until the list menu draws them.
-- Image sizes come from developer/config/extras_gallery_generated.lua, which
-- Prepare & Check writes from developer/assets/extras/.
local M = {}
local PREFIX = "gallery:"
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end

M.PREFIX = PREFIX
-- The entry id of a gallery row id, or nil for any other row.
function M.entry_id(row_id)
  if type(row_id) ~= "string" or row_id:sub(1, #PREFIX) ~= PREFIX then return nil end
  local id = row_id:sub(#PREFIX + 1)
  return id ~= "" and id or nil
end

local function generated_images()
  local data = require("mvtk.core.util").require_config("developer.config.extras_gallery_generated", { images = {} })
  return type(data.images) == "table" and data.images or {}
end

function M.new(deps)
  deps = deps or {}
  local provider = { PREFIX = PREFIX, entry_id = M.entry_id }
  local function extras() return deps.extras or require "mvtk.game.extras" end
  local function images() return deps.images or generated_images() end
  function provider.title() return { key = "extras.gallery" } end
  function provider.enabled()
    return extras().settings().enabled == true and #extras().rows("gallery") > 0
  end
  function provider.rows()
    local out = {}
    for index, entry in ipairs(extras().rows("gallery")) do
      if entry.unlocked then
        local label = nonblank(entry.title) and entry.title or { key = "list.missing_name" }
        out[#out + 1] = { id = PREFIX .. entry.id, label = label, state = "available",
          detail = nonblank(entry.caption) and { title = label, body = entry.caption } or nil }
      else
        out[#out + 1] = { id = "locked:" .. index, label = { key = "journal.unknown" }, state = "unknown",
          enabled = false, disabled_reason = { key = "extras.locked_detail" },
          detail = { title = { key = "journal.unknown" }, body = { key = "extras.locked_detail" } } }
      end
    end
    return out
  end
  function provider.detail(_, row) return row.detail end
  function provider.on_confirm() return { delegate = true } end
  -- Unlocked entries whose image Prepare & Check found, in authored order:
  -- {id, image, title, caption, width, height}. The viewer pages through these.
  function provider.viewable()
    local sizes, out = images(), {}
    for _, entry in ipairs(extras().rows("gallery")) do
      local size = entry.unlocked and nonblank(entry.image) and sizes[entry.image]
      if type(size) == "table" and tonumber(size.width) and tonumber(size.height) then
        out[#out + 1] = { id = entry.id, image = entry.image, title = entry.title, caption = entry.caption,
          width = tonumber(size.width), height = tonumber(size.height) }
      end
    end
    return out
  end
  return provider
end

local default = M.new()
default.new = M.new
default.PREFIX = PREFIX
default.entry_id = M.entry_id
return default
