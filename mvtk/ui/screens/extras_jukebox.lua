-- Extras Jukebox tab: plays tracks unlocked on this profile through the Extras
-- world's own audio controller. Pure provider: the static registry loads it
-- without runtime state, and labels stay keys or creator source text until the
-- list menu draws them. Track ids are never shown (T8).
local M = {}
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end

function M.new(deps)
  deps = deps or {}
  local provider = {}
  local function extras() return deps.extras or require "mvtk.game.extras" end
  local function audio() return deps.audio or require "mvtk.audio.audio" end
  function provider.title() return { key = "extras.jukebox" } end
  -- Rows already drop a switched-off section and, with show_locked off, locked tracks.
  function provider.enabled()
    return extras().settings().enabled == true and #extras().rows("jukebox") > 0
  end
  function provider.rows()
    local playing = audio().current_music_request()
    local out = { { id = "stop", label = { key = "extras.stop_music" } } }
    for index, track in ipairs(extras().rows("jukebox")) do
      if track.unlocked then
        out[#out + 1] = { id = "track:" .. track.track, track = track.track, state = "available",
          label = nonblank(track.title) and track.title or { key = "extras.untitled_track", params = { number = index } },
          value = playing == track.track and { key = "extras.playing" } or nil }
      else
        out[#out + 1] = { id = "locked:" .. index, label = { key = "journal.unknown" }, state = "unknown",
          enabled = false, disabled_reason = { key = "extras.locked_detail" },
          detail = { title = { key = "journal.unknown" }, body = { key = "extras.locked_detail" } } }
      end
    end
    return out
  end
  function provider.detail(_, row) return row.detail end
  function provider.on_confirm(_, row)
    if row.track then audio().music(row.track, { t = 0.3 })
    else audio().music("none", { silence = true }) end
    return { refresh = true }
  end
  return provider
end

local default = M.new()
default.new = M.new
return default
