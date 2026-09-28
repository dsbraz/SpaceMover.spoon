-- Run in Hammerspoon: dofile(hs.configdir .. "/Spoons/SpaceMover.spoon/tests.lua")
-- Isolated fixtures: never touches real windows, Spaces, or bindings.
local source = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local screen, focused, lastMove, pending, alert = {}, nil, nil, nil, nil
local membership = { [42] = { 10 }, [43] = { 10 } }
local fullscreen, moveOK, silentFailure, helperExists = false, true, false, true
local window = {
  id = function() return 42 end,
  screen = function() return screen end,
  isStandard = function() return true end,
  isMinimized = function() return false end,
  isFullScreen = function() return fullscreen end,
}
local fake = {
  logger = { new = function() return { w = function() end } end },
  alert = { show = function(message) alert = message end },
  window = { focusedWindow = function() return focused end, get = function() return window end },
  spaces = {
    data_managedDisplaySpaces = function() return {
      { Spaces = { { ManagedSpaceID = 10 }, { ManagedSpaceID = 99 }, { ManagedSpaceID = 20 } } },
      { Spaces = { { ManagedSpaceID = 30 } } },
      { Spaces = { { ManagedSpaceID = 40 }, { ManagedSpaceID = 10 } } },
    } end,
    spacesForScreen = function(s) assert(s == screen); return { 10, 99, 20 } end,
    spaceType = function(id) return id == 99 and "fullscreen" or "user" end,
    windowSpaces = function(id) return membership[id] end,
  },
  fs = { attributes = function() return helperExists end },
  task = { new = function(_, callback, args)
    local id, target = tonumber(args[1]), tonumber(args[2])
    return { start = function(self)
      lastMove = { id, target }
      pending = function()
        if moveOK and not silentFailure then membership[id] = { target } end
        callback(moveOK and 0 or 6, "", moveOK and "" or "API failure")
      end
      return self
    end }
  end },
  hotkey = { bind = function(_, _, callback)
    return { callback = callback, enabled = true, delete = function(self) self.enabled = false end }
  end },
}
local mover = assert(loadfile(source .. "init.lua", "t", setmetatable({ hs = fake }, { __index = _G })))()
assert(not mover:moveFocusedTo(1) and not lastMove, "no focused window")
focused = window
assert(not mover:moveFocusedTo(0) and not lastMove, "invalid number")
assert(not mover:moveFocusedTo(5) and not lastMove, "missing desktop")
local desktops = mover:desktopSpaces()
assert(table.concat(desktops, ",") == "10,20,30,40", "global display order, skip fullscreen, deduplicate shared Spaces")
assert(table.concat(mover:desktopSpaces(screen), ",") == "10,20", "explicit screen query remains supported")
fullscreen = true
assert(not mover:moveFocusedTo(2) and not lastMove, "fullscreen guard")
fullscreen = false
membership[42] = { 10, 20 }
assert(not mover:moveFocusedTo(2) and not lastMove, "sticky window guard")
membership[42] = { 10 }
assert(mover:moveFocusedTo(1) and not lastMove, "same desktop is a no-op")
helperExists = false
assert(not mover:moveFocusedTo(2) and not lastMove, "missing native helper")
helperExists = true
assert(mover:moveFocusedTo(2), "valid move")
assert(lastMove[1] == 42 and lastMove[2] == 20, "exact window ID; skip fullscreen desktop")
assert(not mover:moveFocusedTo(2), "reject concurrent movement of same window")
assert(membership[43][1] == 10, "other application window stays put")
alert = nil
pending()
assert(not alert, "confirmed move")
moveOK = false
assert(mover:moveFocusedTo(1))
pending()
assert(alert and alert:find("API failure"), "report asynchronous failure")
moveOK, silentFailure, alert = true, true, nil
assert(mover:moveFocusedTo(1))
pending()
assert(alert, "detect false-positive API success")
moveOK, silentFailure, alert = true, false, nil
assert(mover:moveFocusedTo(3), "cross-monitor destination is accepted")
assert(lastMove[1] == 42 and lastMove[2] == 30, "exact window sent to second display")
pending()
assert(membership[42][1] == 30 and not alert, "cross-monitor membership confirmed")
assert(membership[43][1] == 10, "other windows remain untouched")
mover:bindHotkeys()
local old = mover._hotkeys[1]
assert(#mover:status().bindings == 9, "nine default bindings")
for index = 1, 2 do
  membership[42], silentFailure = { index == 1 and 20 or 10 }, false
  mover._hotkeys[index].callback()
  assert(lastMove[2] == (index == 1 and 10 or 20), "binding captures its own index")
  pending()
end
mover:bindHotkeys({})
assert(not old.enabled and next(mover._hotkeys) == nil, "cleanup on rebind")
return "SpaceMover tests passed"
