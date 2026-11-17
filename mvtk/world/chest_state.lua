-- Read-only chest persistence; writers use the same key without changing saves.
local Util=require "mvtk.core.util"
local Flags=require "mvtk.core.flags"
local M={}
function M.key(id) return "chest_opened_"..(Util.hash_key_hex(id) or "") end
function M.is_opened(id) return Flags.has(M.key(id)) end
return M
