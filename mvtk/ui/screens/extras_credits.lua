-- Extras Credits tab: one row per ending seen on this profile. Choosing a row
-- asks the Extras host to replay that ending's title, text and credits pages
-- (delegate; the host owns the completion screen). Pure provider: ending ids
-- are never shown (T8), and titles stay creator source text until drawn.
local M = {}
local PREFIX = "credits:"
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end

M.PREFIX = PREFIX
-- The ending id of a credits row id, or nil for any other row.
function M.ending_id(row_id)
  if type(row_id) ~= "string" or row_id:sub(1, #PREFIX) ~= PREFIX then return nil end
  local id = row_id:sub(#PREFIX + 1)
  return id ~= "" and id or nil
end

function M.new(deps)
  deps = deps or {}
  local provider = { PREFIX = PREFIX, ending_id = M.ending_id }
  local function extras() return deps.extras or require "mvtk.game.extras" end
  function provider.title() return { key = "extras.credits" } end
  function provider.enabled()
    return extras().settings().enabled == true and #extras().rows("credits") > 0
  end
  function provider.rows()
    local out = {}
    for _, ending in ipairs(extras().rows("credits")) do
      local label = nonblank(ending.title) and ending.title or { key = "list.missing_name" }
      out[#out + 1] = { id = PREFIX .. ending.id, label = label, state = "available" }
    end
    return out
  end
  function provider.on_confirm() return { delegate = true } end
  return provider
end

local default = M.new()
default.new = M.new
default.PREFIX = PREFIX
default.ending_id = M.ending_id
return default
