-- tests/panel_js.lua — drives panel_tests.js inside the Lua webview fallback.
-- Temporarily moves TrisplitPanel.app aside, opens the webview panel, injects
-- the JS assertions, writes the result to /tmp/trisplit_js_result.txt.
-- Run via tests/run.sh (async; poll the result file).

local T = trisplit._test
local REPO = "/Users/dibanez/Documents/ClaudecodeTools/trisplit"
local RESULT = "/tmp/trisplit_js_result.txt"
local BACKUP = "/tmp/trisplit_js_backup.json"

local function trace(msg)
  local f = io.open("/tmp/trisplit_js_trace.txt", "a")
  f:write(os.date("%H:%M:%S ") .. msg .. "\n")
  f:close()
end

os.remove(RESULT)
os.remove("/tmp/trisplit_js_trace.txt")
trace("driver start")
T.closePanel()
os.execute("cp '" .. T.store .. "' " .. BACKUP)

local function finish(result)
  local f = io.open(RESULT, "w")
  f:write(result)
  f:close()
  os.execute("cp " .. BACKUP .. " '" .. T.store .. "'")
  T.loadState()
  os.execute("mv '" .. REPO .. "/TrisplitPanel.app.off' '" .. REPO .. "/TrisplitPanel.app' 2>/dev/null")
  local p = trisplit.panelObj()
  if p then pcall(function() p:hide() end) end
end

-- Finder with 2 windows via Cmd+N (open <folder> hangs on Apple Events)
local finder = hs.application.get("Finder")
local knownIds = {}
for _, w in ipairs(finder:allWindows()) do
  if w:isStandard() then knownIds[w:id()] = true end
end
finder:activate(true)
_G.__tjs2 = hs.timer.doAfter(0.6, function() hs.eventtap.keyStroke({ "cmd" }, "n", 0) end)
_G.__tjs3 = hs.timer.doAfter(1.6, function() hs.eventtap.keyStroke({ "cmd" }, "n", 0) end)

-- deterministic config: every screen 2x1 with one window placed
local cfg = T.activeConfig()
cfg.name = "JSDRV"
cfg.monitors = {}
for _, s in ipairs(T.sortedScreens()) do
  cfg.monitors[s:name()] = { cols = 2, rows = 1, slots = { "Finder#1", "" } }
end
T.saveState()

-- webview fallback only: hide the native app
os.execute("mv '" .. REPO .. "/TrisplitPanel.app' '" .. REPO .. "/TrisplitPanel.app.off' 2>/dev/null")

_G.__tjs = hs.timer.doAfter(3.0, function()
  trace("openPanel")
  local okk, err = pcall(trisplit.openPanel)
  trace("openPanel done ok=" .. tostring(okk) .. " err=" .. tostring(err))
  _G.__tjs = hs.timer.doAfter(5.0, function()
    trace("evalJS")
    local f = io.open(REPO .. "/tests/panel_tests.js")
    local js = f:read("a")
    f:close()
    local started = trisplit.evalJS(js, function(res, err)
      trace("callback")
      local msg = tostring(res)
      if type(err) == "table" and (err.code or 0) ~= 0 then
        local parts = {}
        for k, v in pairs(err) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        msg = msg .. " | err: {" .. table.concat(parts, ", ") .. "}"
      elseif err and type(err) ~= "table" then
        msg = msg .. " | err: " .. tostring(err)
      end
      finish(msg)
    end)
    if not started then
      trace("not started")
      finish("panel-js: 0 passed, 1 failed\n  - webview not open")
    end
  end)
end)

return "panel-js: started"
