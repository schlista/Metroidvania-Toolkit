-- One engine listener, shared by runtime subscribers in the installing script's context.
local M = {}
local installed, next_token = false, 0
local subscribers = {}

function M.subscribe(fn)
  assert(type(fn) == "function", "window subscriber must be a function")
  next_token = next_token + 1
  subscribers[next_token] = { fn = fn }
  return next_token
end

function M.unsubscribe(token) subscribers[token] = nil end

function M.dispatch(event, data)
  -- Additions during a dispatch wait for the next event; removals take effect now.
  local last = next_token
  for token = 1, last do
    local entry = subscribers[token]
    if entry then
      local ok, err = pcall(entry.fn, event, data)
      if not ok and not entry.failed then
        entry.failed = true
        print("[WINDOW] subscriber " .. token .. ": " .. tostring(err))
      end
    end
  end
end

function M.install()
  if installed then return end
  window.set_listener(function(self, event, data) M.dispatch(event, data) end)
  installed = true
end

function M.uninstall()
  if installed then window.set_listener(nil) end
  installed = false
  -- Subscribers survive Quit to Menu and the next gameplay collection load.
end

return M
