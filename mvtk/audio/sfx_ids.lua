-- mvtk/audio/sfx_ids.lua
-- Resolves developer/config/sound_bank.lua sfx ids to the sound components on
-- developer/game/audio/audio_controller.go. An id plays the component named by
-- its `component` field, or "sfx_<id>" when that field is absent. The audio
-- controller builds its play table from this, so the bank is the one list of
-- sound ids: every id a creator can choose is an id the controller can play.
-- Plain Lua with no engine calls, so tests and the editor can load it.

local M = {}

-- Component id (without "#") that plays one sound-bank entry.
function M.component_for(id, entry)
  if type(entry) == "table" and type(entry.component) == "string" and entry.component ~= "" then
    return entry.component
  end
  return "sfx_" .. tostring(id)
end

-- { [sfx id] = component id } for every string id in bank.sfx.
function M.components(bank)
  local out = {}
  local sfx = type(bank) == "table" and bank.sfx or nil
  if type(sfx) ~= "table" then return out end
  for id, entry in pairs(sfx) do
    if type(id) == "string" and id ~= "" then
      out[id] = M.component_for(id, entry)
    end
  end
  return out
end

return M
