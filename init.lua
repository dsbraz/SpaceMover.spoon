local obj = {}
obj.__index = obj

obj.name = "SpaceMover"
obj.version = "0.3.0"
obj.author = "Daniel Braz"
obj.license = "MIT"
obj.logger = hs.logger.new("SpaceMover")
obj._hotkeys = {}
obj._tasks = {}
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

function obj:_fail(message)
  self.logger.w(message)
  hs.alert.show("SpaceMover: " .. message)
  return false, message
end

-- Without a screen, number ordinary desktops across all managed displays.
-- Never iterate allSpaces() with pairs: UUID hash order is not desktop order.
function obj:desktopSpaces(screen)
  if screen == nil then
    local displays, reason = hs.spaces.data_managedDisplaySpaces()
    if not displays then return nil, reason end
    local desktops, seen = {}, {}
    for _, display in ipairs(displays) do
      for _, space in ipairs(display.Spaces or {}) do
        local id = space.ManagedSpaceID or space.id64
        if id and not seen[id] and hs.spaces.spaceType(id) == "user" then
          desktops[#desktops + 1] = id
          seen[id] = true
        end
      end
    end
    return desktops
  end
  local spaces, reason = hs.spaces.spacesForScreen(screen)
  if not spaces then return nil, reason end
  local desktops = {}
  for _, id in ipairs(spaces) do
    if hs.spaces.spaceType(id) == "user" then
      desktops[#desktops + 1] = id
    end
  end
  return desktops
end

local function containsSpace(screen, target)
  for _, space in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
    if space == target then return true end
  end
  return false
end

-- Preserve size where possible and relative placement in the available travel
-- area. Screen origins can be negative or vertically offset.
function obj:destinationFrame(frame, source, destination)
  local w, h = math.min(frame.w, destination.w), math.min(frame.h, destination.h)
  local function position(value, origin, extent, size, nextOrigin, nextExtent, nextSize)
    local ratio = extent > size and (value - origin) / (extent - size) or 0.5
    return nextOrigin + math.max(0, math.min(1, ratio)) * (nextExtent - nextSize)
  end
  return {
    x = position(frame.x, source.x, source.w, frame.w, destination.x, destination.w, w),
    y = position(frame.y, source.y, source.h, frame.h, destination.y, destination.h, h),
    w = w, h = h,
  }
end

-- Space membership can settle before WindowServer finishes placing a window.
-- Keep the per-window lock until geometry has also settled; never poll forever.
function obj:_settle(window, id, target, targetUUID, original, sourceFrame)
  local attempts = 0
  local function finish(message)
    self._tasks[id] = nil
    if message then self:_fail(message) end
  end
  local step
  step = function()
    local ok, reason = pcall(function()
      if window:id() ~= id then return finish("A janela foi fechada durante o movimento.") end
      local actual = hs.spaces.windowSpaces(id)
      if not actual or #actual ~= 1 or actual[1] ~= target then
        return finish("O macOS não confirmou o desktop de destino.")
      end
      local destination
      for _, candidate in ipairs(hs.screen.allScreens()) do
        if candidate:getUUID() == targetUUID then destination = candidate; break end
      end
      if not destination or not containsSpace(destination, target) then
        return finish("O monitor de destino mudou durante o movimento.")
      end
      local wanted = self:destinationFrame(original, sourceFrame, destination:frame())
      local frame = window:frame()
      local matches = true
      for _, key in ipairs({ "x", "y", "w", "h" }) do
        if math.abs(frame[key] - wanted[key]) > 2 then matches = false end
      end
      if matches then return finish() end
      if attempts >= 3 then
        return finish("O aplicativo não confirmou a posição/tamanho no monitor de destino.")
      end
      attempts = attempts + 1
      window:setFrame(wanted, 0)
      self._tasks[id] = hs.timer.doAfter(0.15, step)
    end)
    if not ok then finish(tostring(reason)) end
  end
  self._tasks[id] = hs.timer.doAfter(0.15, step)
end

function obj:moveFocusedTo(index)
  -- Capture the exact focused window before querying Spaces or showing alerts.
  local window = hs.window.focusedWindow()
  local ok, result, reason = pcall(function()
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then
      return self:_fail("Número de desktop inválido.")
    end
    if not window or not window:isStandard() or window:isMinimized() then
      return self:_fail("Nenhuma janela comum em foco.")
    end
    if window:isFullScreen() then
      return self:_fail("Saia da tela cheia antes de mover a janela.")
    end
    local id, screen = window:id(), window:screen()
    if not id or not screen then
      return self:_fail("Não foi possível identificar a janela ou o monitor.")
    end
    local current = hs.spaces.windowSpaces(id)
    if not current or #current ~= 1 or hs.spaces.spaceType(current[1]) ~= "user" then
      return self:_fail("A janela precisa estar em um único desktop comum.")
    end
    local desktops, spaceError = self:desktopSpaces()
    if not desktops then return self:_fail(tostring(spaceError)) end
    local target = desktops[index]
    if not target then
      return self:_fail("Desktop " .. index .. " não existe nos monitores conectados.")
    end
    if current[1] == target then return true end
    if self._tasks[id] then return self:_fail("Esta janela já está sendo movida.") end
    local destination = containsSpace(screen, target) and screen or nil
    if not destination then
      for _, candidate in ipairs(hs.screen.allScreens()) do
        if containsSpace(candidate, target) then destination = candidate; break end
      end
    end
    if not destination then return self:_fail("Monitor de destino indisponível.") end
    local targetUUID = destination:getUUID()
    local original, sourceFrame = window:frame(), screen:frame()
    local helper = spoonPath .. "native/space-mover"
    if not hs.fs.attributes(helper) then
      return self:_fail("Execute make na pasta do SpaceMover.spoon antes de usar.")
    end
    local task = hs.task.new(helper, function(code, _, stderr)
      if code ~= 0 then
        self._tasks[id] = nil
        self:_fail("Falha no movimento: " .. tostring(stderr))
        return
      end
      local actual = hs.spaces.windowSpaces(id)
      if not actual or #actual ~= 1 or actual[1] ~= target then
        self._tasks[id] = nil
        self:_fail("O macOS não confirmou o movimento para o desktop " .. index .. ".")
        return
      end
      self:_settle(window, id, target, targetUUID, original, sourceFrame)
    end, { tostring(id), tostring(target) })
    if not task then return self:_fail("Não foi possível iniciar o suporte nativo.") end
    self._tasks[id] = task
    if not task:start() then
      self._tasks[id] = nil
      return self:_fail("Não foi possível executar o suporte nativo.")
    end
    return true
  end)
  if not ok then return self:_fail(tostring(result)) end
  return result, reason
end

-- Omit mapping for Hyper+1…9; pass {} to disable all bindings.
function obj:bindHotkeys(mapping)
  self:stop()
  if mapping == nil then
    mapping = {}
    for index = 1, 9 do mapping[index] = { { "cmd", "ctrl", "alt" }, tostring(index) } end
  end
  for index = 1, 9 do
    local binding = mapping[index]
    if binding then
      local hotkey = hs.hotkey.bind(binding[1], binding[2], function() self:moveFocusedTo(index) end)
      if hotkey then self._hotkeys[index] = hotkey end
    end
  end
  return self
end

function obj:stop()
  for _, hotkey in pairs(self._hotkeys) do hotkey:delete() end
  self._hotkeys = {}
  return self
end

function obj:status()
  local bindings = {}
  for index, hotkey in pairs(self._hotkeys) do bindings[index] = hotkey.enabled == true end
  return { version = self.version, bindings = bindings }
end

return obj
