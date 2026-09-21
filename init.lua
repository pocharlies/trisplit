-- trisplit: panel nativo macOS (ventana titled de AppKit vía hs.webview),
-- grid configurable (cols×filas) por monitor, drag & drop que mueve ventanas
-- reales y hotkeys por slot.
-- Repo: ~/Documents/ClaudecodeTools/trisplit (enlazado en ~/.hammerspoon/init.lua)

require("hs.ipc")

-- solo el icono de trisplit: fuera el elefante de Hammerspoon (menu bar y Dock)
hs.menuIcon(false)
hs.dockIcon(false)

local log = hs.logger.new("trisplit", "debug")

local GAP, ANIM = 4, 0.2
local STORE = hs.configdir .. "/trisplit.json"

local ALIASES = { ["Code"] = "Visual Studio Code", ["Visual Studio Code"] = "Code" }

-- ---------- pantallas ----------

local function sortedScreens()
  local ss = hs.screen.allScreens()
  table.sort(ss, function(a, b)
    local fa, fb = a:frame(), b:frame()
    if fa.x ~= fb.x then return fa.x < fb.x end
    return fa.y < fb.y
  end)
  return ss
end

local function screenByName(name)
  for _, s in ipairs(hs.screen.allScreens()) do
    if s:name() == name then return s end
  end
  return nil
end

local function gridFrame(screen, i, cols, rows)
  cols, rows = math.max(cols or 1, 1), math.max(rows or 1, 1)
  local f = screen:frame()
  local w = (f.w - GAP * (cols - 1)) / cols
  local h = (f.h - GAP * (rows - 1)) / rows
  local col = (i - 1) % cols
  local row = math.floor((i - 1) / cols)
  return hs.geometry(f.x + col * (w + GAP), f.y + row * (h + GAP), w, h)
end

-- ---------- estado / configs ----------
-- state = { active = N, configs = [ { name, monitors = { [screenName] = {cols, rows, slots=[app,...]} } } ] }

local function newMonitorGrid(cols, rows)
  local slots = {}
  for _ = 1, cols * rows do slots[#slots + 1] = "" end
  return { cols = cols, rows = rows, slots = slots }
end

local function defaultConfig()
  local monitors = {}
  local defaults = { ["Odyssey G95C"] = { "OpenChamber", "Code", "Claude" } }
  for _, s in ipairs(sortedScreens()) do
    local g = newMonitorGrid(3, 1)
    local apps = defaults[s:name()] or {}
    for i, a in ipairs(apps) do g.slots[i] = a end
    monitors[s:name()] = g
  end
  return { name = "Dev", monitors = monitors }
end

local state = { active = 1, configs = {} }

local function saveState()
  local f = io.open(STORE, "w")
  if f then f:write(hs.json.encode(state)); f:close() end
end

local function migrate(cfg)
  if cfg.slots and not cfg.monitors then
    local monitors = {}
    for _, sl in ipairs(cfg.slots) do
      local g = monitors[sl.screen]
      if not g then g = { cols = 3, rows = 1, slots = {} }; monitors[sl.screen] = g end
      g.slots[#g.slots + 1] = sl.app or ""
    end
    cfg.slots = nil
    cfg.monitors = monitors
  end
  return cfg
end

local function loadState()
  local f = io.open(STORE, "r")
  if not f then return false end
  local ok, decoded = pcall(hs.json.decode, f:read("a"))
  f:close()
  if ok and decoded and decoded.configs and #decoded.configs > 0 then
    for _, c in ipairs(decoded.configs) do migrate(c) end
    state = decoded
    if not state.active or state.active < 1 or state.active > #state.configs then state.active = 1 end
    return true
  end
  return false
end

if not loadState() then
  state = { active = 1, configs = { defaultConfig() } }
  saveState()
end

local function activeConfig() return state.configs[state.active] end

local function flatSlots(cfg)
  cfg = cfg or activeConfig()
  local out = {}
  if not cfg then return out end
  for _, s in ipairs(sortedScreens()) do
    local m = cfg.monitors[s:name()]
    if m then
      for i, app in ipairs(m.slots) do
        out[#out + 1] = { screen = s:name(), idx = i, cols = m.cols, rows = m.rows, app = app }
      end
    end
  end
  return out
end

-- ---------- colocación ----------

local function screenLocked()
  local f = hs.application.frontmostApplication()
  return f and f:bundleID() == "com.apple.loginwindow"
end

local function namesFor(app)
  local out = { app }
  if ALIASES[app] then out[2] = ALIASES[app] end
  return out
end

local function ensureRunning(names)
  for _, n in ipairs(names) do
    local app = hs.application.get(n)
    if app then return app end
  end
  for _, n in ipairs(names) do
    hs.application.launchOrFocus(n)
    for _ = 1, 30 do
      hs.timer.usleep(100000)
      for _, cand in ipairs(names) do
        local app = hs.application.get(cand)
        if app then return app end
      end
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

local function visibleWindows(app)
  local out = {}
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() and not w:isMinimized() then out[#out + 1] = w end
  end
  table.sort(out, function(a, b) return a:id() < b:id() end)
  return out
end

-- "App#N" = N-ésima ventana de la app (por defecto 1)
local function parseSpec(spec)
  local name, idx = spec:match("^(.-)#(%d+)$")
  if name then return name, tonumber(idx) end
  return spec, 1
end

local function placeWindow(win, frame, screen)
  if win:isMinimized() then win:unminimize() end
  if win:isFullscreen() then
    win:toggleFullScreen()
    hs.timer.usleep(700000)
  end
  if screen and win:screen() and win:screen():name() ~= screen:name() then
    win:moveToScreen(screen)
    hs.timer.usleep(100000)
  end
  win:setFrame(frame, ANIM)
end

local function placeApp(spec, frame, screen)
  local app, idx = parseSpec(spec)
  local names = namesFor(app)
  local a = ensureRunning(names)
  if not a then
    log.e("app no encontrada: " .. app)
    return false
  end
  local wins = visibleWindows(a)
  local win = wins[math.min(idx, #wins)]
  if not win then
    a:activate(true)
    win = findWindow(a)
  end
  if not win then
    hs.application.launchOrFocus(names[1])
    win = findWindow(a)
  end
  if not win then
    log.i("reiniciando " .. app .. " para abrir ventana")
    os.execute("kill -9 " .. a:pid() .. " 2>/dev/null")
    for _ = 1, 50 do
      hs.timer.usleep(100000)
      if not hs.application.get(names[1]) then break end
    end
    hs.application.launchOrFocus(names[1])
    a = ensureRunning(names)
    win = a and findWindow(a)
  end
  if not win then
    log.e("sin ventana para: " .. app)
    return false
  end
  placeWindow(win, frame, screen)
  return true
end

local function applyConfig(cfg)
  cfg = cfg or activeConfig()
  if not cfg then return false end
  if screenLocked() then
    log.w("pantalla bloqueada: layout cancelado")
    return false
  end
  local ok = true
  for _, s in ipairs(sortedScreens()) do
    local m = cfg.monitors[s:name()]
    if m then
      for i, app in ipairs(m.slots) do
        if app ~= "" then
          if not placeApp(app, gridFrame(s, i, m.cols, m.rows), s) then ok = false end
        end
      end
    end
  end
  return ok
end

-- ---------- hotkeys por slot ----------

local function moveFrontToSlot(n)
  local slot = flatSlots()[n]
  if not slot then return false end
  local s = screenByName(slot.screen)
  if not s then log.w("sin pantalla " .. slot.screen); return false end
  local win = hs.window.focusedWindow()
  if not win then return false end
  placeWindow(win, gridFrame(s, slot.idx, slot.cols, slot.rows), s)
  win:focus()
  win:raise()
  local app = win:application():name()
  local wins = visibleWindows(win:application())
  local idx = 1
  for i, w in ipairs(wins) do
    if w:id() == win:id() then idx = i break end
  end
  activeConfig().monitors[slot.screen].slots[slot.idx] = app .. (idx > 1 and ("#" .. idx) or "")
  saveState()
  return true
end

local function focusSlot(n)
  local slot = flatSlots()[n]
  if not slot or slot.app == "" then return false end
  local app, idx = parseSpec(slot.app)
  local a = hs.application.get(namesFor(app)[1]) or hs.application.get(app)
  if a then
    local wins = visibleWindows(a)
    local w = wins[math.min(idx, #wins)]
    if w then
      w:focus()
      return true
    end
  end
  hs.application.launchOrFocus(namesFor(app)[1])
  return true
end

local function liveMove(screenName, idx, app)
  local s = screenByName(screenName)
  if not s or app == "" then return false end
  local m = activeConfig().monitors[screenName]
  if not m then return false end
  return placeApp(app, gridFrame(s, idx, m.cols, m.rows), s)
end

-- ---------- panel (webview en ventana nativa de AppKit) ----------

local panel = nil

local function assetPath(name)
  local candidates = {
    (debug.getinfo(1, "S").source:match("@?(.*/)") or "") .. name,
    os.getenv("HOME") .. "/Documents/ClaudecodeTools/trisplit/" .. name,
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then f:close(); return p end
  end
  return nil
end

local function visibleApps()
  local out = {}
  for _, a in ipairs(hs.application.runningApplications()) do
    if a:kind() == 1 and a:name() then
      local hidden = false
      local ok, hid = pcall(function() return a:isHidden() end)
      if ok then hidden = hid end
      if not hidden then
        local wins = visibleWindows(a)
        if #wins > 0 then
          local titles = {}
          for i, w in ipairs(wins) do titles[i] = w:title() or "" end
          out[#out + 1] = { name = a:name(), count = #wins, titles = titles }
        end
      end
    end
  end
  table.sort(out, function(x, y) return x.name:lower() < y.name:lower() end)
  return out
end

local DISPLAYPLACER = "/opt/homebrew/bin/displayplacer"

local function primaryScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    if f.x == 0 and f.y == 0 then return s end
  end
  return hs.screen.mainScreen()
end

local function parseDisplayplacer()
  local p = io.popen(DISPLAYPLACER .. " list 2>/dev/null")
  if not p then return nil end
  local txt = p:read("a"); p:close()
  local blocks, cur = {}, nil
  for line in txt:gmatch("[^\n]+") do
    local id = line:match("^Persistent screen id: ([%w%-]+)")
    if id then cur = { id = id }; blocks[#blocks + 1] = cur end
    if cur then
      local w, h = line:match("^Resolution: (%d+)x(%d+)")
      if w then cur.w, cur.h = tonumber(w), tonumber(h) end
      local hz = line:match("^Hertz: ([%d%.]+)")
      if hz then cur.hertz = hz end
      local ox, oy = line:match("^Origin: %((%-?%d+),(%-?%d+)%)")
      if ox then cur.x, cur.y = tonumber(ox), tonumber(oy) end
      if line:match("main display") then cur.main = true end
      local rot = line:match("^Rotation: (%d+)")
      if rot then cur.rot = rot end
      local sc = line:match("^Scaling: (%a+)")
      if sc then cur.scaling = sc end
      local cd = line:match("^Color Depth: (%d+)")
      if cd then cur.depth = cd end
    end
  end
  return blocks
end

local function currentOffsets()
  local offs = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    offs[s:name()] = { dx = math.floor(f.x), dy = math.floor(f.y) }
  end
  return offs
end

local function applyArrangement(offsets)
  if not hs.fs.attributes(DISPLAYPLACER) then return false, "displayplacer no instalado" end
  local blocks = parseDisplayplacer()
  if not blocks or #blocks == 0 then return false, "displayplacer no devolvió pantallas" end
  local function arg(b, ox, oy)
    return "id:" .. b.id .. " res:" .. b.w .. "x" .. b.h .. " hz:" .. b.hertz
      .. " color_depth:" .. (b.depth or "8") .. " enabled:true scaling:" .. (b.scaling or "off")
      .. " origin:(" .. ox .. "," .. oy .. ") degree:" .. (b.rot or "0")
  end
  -- rects efectivas: offsets relativos a la pantalla con origen (0,0) actual
  local rects = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    local off = offsets and offsets[s:name()]
    rects[#rects + 1] = {
      name = s:name(),
      x = off and math.floor(off.dx) or math.floor(f.x),
      y = off and math.floor(off.dy) or math.floor(f.y),
      w = math.floor(f.w), h = math.floor(f.h),
    }
  end
  -- la nueva principal es la que queda en el origen (0,0); si ninguna, la más arriba-izquierda
  local newMain = nil
  for _, r in ipairs(rects) do
    if r.x == 0 and r.y == 0 then newMain = r break end
  end
  if not newMain then
    table.sort(rects, function(a, b)
      if a.x ~= b.x then return a.x < b.x end
      return a.y < b.y
    end)
    newMain = rects[1]
  end
  local args = {}
  for _, r in ipairs(rects) do
    local curX, curY, match
    for _, s in ipairs(hs.screen.allScreens()) do
      if s:name() == r.name then
        local f = s:fullFrame()
        curX, curY = math.floor(f.x), math.floor(f.y)
      end
    end
    for _, b in ipairs(blocks) do
      if b.w == r.w and b.h == r.h and b.x == curX and b.y == curY then match = b break end
    end
    if not match then return false, "no se encontró " .. r.name .. " en displayplacer" end
    args[#args + 1] = arg(match, r.x - newMain.x, r.y - newMain.y)
  end
  local cmd = DISPLAYPLACER
  for _, a in ipairs(args) do cmd = cmd .. " '" .. a .. "'" end
  local ok = os.execute(cmd)
  return ok == true or ok == 0, cmd
end

local function panelState()
  local screens = {}
  for _, s in ipairs(sortedScreens()) do
    local f = s:fullFrame()
    screens[#screens + 1] = { name = s:name(), x = f.x, y = f.y, w = f.w, h = f.h }
  end
  local arrange = state.arrange or {}
  if next(arrange) == nil then arrange = setmetatable({}, { __hsjson_type = "o" }) end
  return { screens = screens, configs = state.configs, active = state.active,
           apps = visibleApps(), primary = primaryScreen():name(), arrange = arrange,
           hasDisplayplacer = hs.fs.attributes(DISPLAYPLACER) ~= nil }
end

local function pushPanel()
  if panel then
    panel:evaluateJavaScript("trisplitSetState(" .. hs.json.encode(panelState()) .. ")")
  end
end

local function handlePanel(msg)
  local raw = msg
  if type(raw) == "table" then raw = raw.body end
  local m = raw
  if type(m) == "string" then
    local ok, decoded = pcall(hs.json.decode, m)
    m = ok and decoded or nil
  end
  if type(m) ~= "table" then return end
  local action = m.action
  if action == "ready" then
    hs.timer.doAfter(0.3, pushPanel)
  elseif action == "save" then
    state.configs = m.configs
    state.active = m.active
    saveState()
    pushPanel()
  elseif action == "liveMove" then
    liveMove(m.screen, m.idx, m.app or "")
  elseif action == "arrange" then
    if next(state.arrange or {}) == nil and next(m.offsets or {}) ~= nil then
      state.arrangeOriginal = currentOffsets()
    end
    state.arrange = m.offsets or {}
    saveState()
  elseif action == "resetArrange" then
    if state.arrangeOriginal and next(state.arrange or {}) == nil then
      applyArrangement(state.arrangeOriginal)
      hs.alert.show("Disposición original restaurada")
    end
    state.arrange = {}
    state.arrangeOriginal = nil
    saveState()
    hs.timer.doAfter(1.2, pushPanel)
  elseif action == "applyArrange" then
    local ok, err = applyArrangement(state.arrange)
    if ok then
      state.arrange = {}
      saveState()
      hs.alert.show("Disposición aplicada a macOS")
      hs.timer.doAfter(1.2, pushPanel)
    else
      log.e("arrange falló: " .. tostring(err))
      hs.alert.show("No se pudo aplicar la disposición")
      pushPanel()
    end
  elseif action == "apply" then
    applyConfig()
  elseif action == "applyAndClose" then
    applyConfig()
    if panel then panel:hide() end
  elseif action == "close" then
    if panel then panel:hide() end
  else
    log.e("acción de panel desconocida: " .. tostring(action))
  end
end

local function appPanelPath()
  return assetPath("TrisplitPanel.app")
end

local function openPanel()
  local appPath = appPanelPath()
  if appPath then
    os.execute('open "' .. appPath .. '"')
    return
  end
  if panel then
    panel:show()
    panel:bringToFront()
    pushPanel()
    return
  end
  for _, w in ipairs(hs.window.allWindows()) do
    if w:title() == "Trisplit" then w:close() end
  end
  local path = assetPath("panel.html")
  if not path then log.e("no existe panel.html"); return end
  local f = io.open(path, "r")
  local html = f:read("a")
  f:close()
  local uc = hs.webview.usercontent.new("trisplit")
  uc:setCallback(function(msg) handlePanel(msg) end)
  panel = hs.webview.new({ x = 0, y = 0, w = 1100, h = 680 }, {}, uc)
  panel:windowStyle({ "titled", "closable", "miniaturizable", "resizable" })
  panel:windowTitle("Trisplit")
  panel:titleVisibility("visible")
  panel:darkMode(true)
  panel:setLevel(0)
  panel:closeOnEscape(true)
  panel:html(html, "trisplit.local")
  panel:show()
  panel:bringToFront()
  local w = panel:hswindow()
  if w then w:center() end
  hs.timer.doAfter(1.0, pushPanel)
end

-- ---------- hotkeys ----------
-- ⌘⌥0 aplicar · ⌘⌥⇧0 siguiente config · ⌘⌥P panel
-- ⌘⌥1..9 mover ventana frontal al slot N · ⌘⌥⇧1..9 enfocar app del slot N

hs.hotkey.bind({ "cmd", "alt" }, "0", function() applyConfig() end)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "0", function()
  if #state.configs > 0 then
    state.active = state.active % #state.configs + 1
    saveState()
    applyConfig()
    pushPanel()
  end
end)
hs.hotkey.bind({ "cmd", "alt" }, "p", openPanel)

for i = 1, 9 do
  hs.hotkey.bind({ "cmd", "alt" }, tostring(i), (function(n)
    return function() moveFrontToSlot(n) end
  end)(i))
  hs.hotkey.bind({ "cmd", "alt", "shift" }, tostring(i), (function(n)
    return function() focusSlot(n) end
  end)(i))
end

-- ---------- menu bar (icono template monocromo) ----------

local mb = hs.menubar.new()

local iconPath = assetPath("icon.png")
local icon = iconPath and hs.image.imageFromPath(iconPath) or nil
if icon then
  icon:setSize({ w = 22, h = 12 })
  icon:template(true)
  mb:setIcon(icon)
else
  mb:setTitle("▥")
end

mb:setClickCallback(openPanel)

-- ---------- API ----------

rawset(_G, "trisplit", {
  apply = applyConfig,
  applyConfig = applyConfig,
  openPanel = openPanel,
  state = function() return state end,
  panelState = panelState,
  applyArrangement = applyArrangement,
  flatSlots = flatSlots,
  moveFrontToSlot = moveFrontToSlot,
  focusSlot = focusSlot,
  liveMove = liveMove,
  slotFrame = function(n)
    local slot = flatSlots()[n]
    if not slot then return nil end
    local s = screenByName(slot.screen)
    if not s then return nil end
    return gridFrame(s, slot.idx, slot.cols, slot.rows)
  end,
  handlePanelB64 = function(b64)
    local ok, dec = pcall(function() return require("hs.base64").decode(b64) end)
    if ok and dec then handlePanel(dec) end
  end,
  menubar = function() return mb end,
  evalJS = function(js, cb)
    if not panel then return false end
    panel:evaluateJavaScript(js, cb)
    return true
  end,
  panelObj = function() return panel end,
})

log.i("trisplit v3 cargado")
