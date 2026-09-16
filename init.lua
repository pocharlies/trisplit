-- trisplit: divide la pantalla principal en 3 columnas iguales y coloca apps.
-- Repo: ~/Documents/ClaudecodeTools/trisplit (este fichero es el que se enlaza en ~/.hammerspoon/init.lua)

require("hs.ipc")

local log = hs.logger.new("trisplit", "debug")

local GAP = 4
local ANIM = 0.2
local PREFERRED_SCREEN = "Odyssey G95C"

local function targetScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    if s:name() == PREFERRED_SCREEN then return s end
  end
  local best, bestArea = nil, 0
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:frame()
    if f.w * f.h > bestArea then best, bestArea = s, f.w * f.h end
  end
  return best or hs.screen.mainScreen()
end

local presets = {
  dev3 = {
    { "OpenChamber" },
    { "Code", "Visual Studio Code" },
    { "Claude" },
  },
}

local hotkeys = {
  dev3   = { mods = { "cmd", "alt" },         key = "3" },
  picker = { mods = { "cmd", "alt", "shift" }, key = "3" },
}

local function screenFrame()
  return targetScreen():frame()
end

local function columnFrames(n)
  local f = screenFrame()
  local w = (f.w - GAP * (n - 1)) / n
  local out = {}
  for i = 0, n - 1 do
    out[i + 1] = hs.geometry(f.x + i * (w + GAP), f.y, w, f.h)
  end
  return out
end

local function ensureRunning(names)
  for _, n in ipairs(names) do
    local app = hs.application.get(n)
    if app then return app end
  end
  hs.application.launchOrFocus(names[1])
  for _ = 1, 50 do
    hs.timer.usleep(100000)
    for _, n in ipairs(names) do
      local app = hs.application.get(n)
      if app then return app end
    end
  end
  return nil
end

local function findWindow(app)
  for _ = 1, 40 do
    for _, w in ipairs(app:allWindows()) do
      if w:isStandard() or w:isMinimized() then return w end
    end
    hs.timer.usleep(100000)
  end
  return nil
end

local function anyWindow(app)
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() or w:isMinimized() then return w end
  end
  return nil
end

local function placeApp(names, frame)
  local app = ensureRunning(names)
  if not app then
    log.e("app no encontrada: " .. table.concat(names, "/"))
    return false
  end
  local win = anyWindow(app)
  if not win then
    -- la ventana está en otro Space: activar la app para cambiar de Space
    app:activate(true)
    win = findWindow(app)
  end
  if not win then
    -- app corriendo sin ventana (ej. Claude minimizada a menu bar): relanzar
    hs.application.launchOrFocus(names[1])
    win = findWindow(app)
  end
  if not win then
    -- sigue sin ventana: reiniciar la app para forzarla a abrirla
    log.i("reiniciando " .. names[1] .. " para abrir ventana")
    os.execute("kill -9 " .. app:pid() .. " 2>/dev/null")
    for _ = 1, 50 do
      hs.timer.usleep(100000)
      if not hs.application.get(names[1]) then break end
    end
    hs.application.launchOrFocus(names[1])
    app = ensureRunning(names)
    win = app and findWindow(app)
  end
  if not win then
    log.e("sin ventana para: " .. names[1])
    return false
  end
  if win:isMinimized() then win:unminimize() end
  if win:isFullscreen() then
    win:toggleFullScreen()
    hs.timer.usleep(700000)
  end
  win:moveToScreen(targetScreen())
  hs.timer.usleep(100000)
  win:setFrame(frame, ANIM)
  return true
end

local function screenLocked()
  local f = hs.application.frontmostApplication()
  return f and f:bundleID() == "com.apple.loginwindow"
end

local function applyLayout(entries)
  if screenLocked() then
    log.w("pantalla bloqueada: layout cancelado")
    return false
  end
  local frames = columnFrames(#entries)
  local ok = true
  for i, entry in ipairs(entries) do
    local names = type(entry) == "table" and entry or { entry }
    if not placeApp(names, frames[i]) then ok = false end
  end
  return ok
end

-- Picker: elegir 3 apps instaladas una a una
local function installedApps()
  local out = {}
  for entry in hs.fs.dir("/Applications") do
    if entry:match("%.app$") then
      local name = entry:gsub("%.app$", "")
      table.insert(out, { text = name, id = name })
    end
  end
  table.sort(out, function(a, b) return a.text:lower() < b.text:lower() end)
  return out
end

local pickerSel = {}
local picker

local function pickerShow()
  local n = #pickerSel
  if n >= 3 then
    picker:hide()
    applyLayout(pickerSel)
    pickerSel = {}
    return
  end
  picker:placeholderText(("App %d de 3 — escribe para buscar (esc cancela)"):format(n + 1))
  picker:show()
  picker:search("")
end

picker = hs.chooser.new(function(row)
  if not row then
    pickerSel = {}
    return
  end
  table.insert(pickerSel, row.id)
  pickerShow()
end)

local function openPicker()
  picker:choices(installedApps)
  pickerSel = {}
  pickerShow()
end

-- Menu bar
local mb = hs.menubar.new()
mb:setTitle("◫3")

local function buildMenu()
  local items = {}
  for name, entries in pairs(presets) do
    local labels = {}
    for _, e in ipairs(entries) do table.insert(labels, type(e) == "table" and e[1] or e) end
    table.insert(items, {
      title = name .. "  (" .. table.concat(labels, " · ") .. ")",
      fn = function() applyLayout(entries) end,
    })
  end
  table.insert(items, { separator = true })
  table.insert(items, { title = "Elegir 3 apps…", fn = openPicker })
  table.insert(items, { separator = true })
  table.insert(items, { title = "Recargar config", fn = hs.reload })
  return items
end
mb:setMenu(buildMenu)

-- Hotkeys
hs.hotkey.bind(hotkeys.dev3.mods, hotkeys.dev3.key, function()
  applyLayout(presets.dev3)
end)
hs.hotkey.bind(hotkeys.picker.mods, hotkeys.picker.key, openPicker)

-- API para verificación/uso desde CLI: hs -c "trisplit.applyPreset('dev3')"
local api = {
  applyPreset = function(name) return applyLayout(presets[name]) end,
  applyLayout = applyLayout,
  openPicker = openPicker,
}
rawset(_G, "trisplit", api)

log.i("trisplit cargado")
