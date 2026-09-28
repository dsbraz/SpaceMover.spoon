local obj = {}
obj.__index = obj

obj.name = "SpaceMover"
obj.version = "0.1.0"
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

-- Number only ordinary desktops, in Mission Control order, on this screen.
function obj:desktopSpaces(screen)
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
    local desktops, spaceError = self:desktopSpaces(screen)
    if not desktops then return self:_fail(tostring(spaceError)) end
    local target = desktops[index]
    if not target then
      return self:_fail("Desktop " .. index .. " não existe neste monitor.")
    end
    if current[1] == target then return true end
    if self._tasks[id] then return self:_fail("Esta janela já está sendo movida.") end
    local helper = spoonPath .. "native/space-mover"
    if not hs.fs.attributes(helper) then
      return self:_fail("Execute make na pasta do SpaceMover.spoon antes de usar.")
    end
    local task = hs.task.new(helper, function(code, _, stderr)
      self._tasks[id] = nil
      if code ~= 0 then
        self:_fail("Falha no movimento: " .. tostring(stderr))
        return
      end
      local actual = hs.spaces.windowSpaces(id)
      if not actual or #actual ~= 1 or actual[1] ~= target then
        self:_fail("O macOS não confirmou o movimento para o desktop " .. index .. ".")
      end
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
