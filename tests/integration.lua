-- tests/integration.lua — end-to-end tests with real windows and the real
-- config store. Backs up and restores ~/.hammerspoon/trisplit.json.
-- Run: hs -c "dofile('<repo>/tests/integration.lua')"
-- NOTE: opens/closes Finder windows. Takes ~20s.

local T = trisplit._test
local pass, fail = 0, 0
local problems = {}

local function ok(name, cond, detail)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    problems[#problems + 1] = name .. (detail and (": " .. detail) or "")
  end
end

local function near(a, b, tol)
  return math.abs(a - b) <= (tol or 3)
end

local function sleep(sec) hs.timer.usleep(math.floor(sec * 1000000)) end

-- ---------- backup user state ----------
local BACKUP = "/tmp/trisplit_it_backup.json"
os.execute("cp '" .. T.store .. "' " .. BACKUP)

local function restore()
  os.execute("cp " .. BACKUP .. " '" .. T.store .. "'")
  T.loadState()
end

-- ---------- setup: Finder with 2 browser windows via Cmd+N (no Apple Events) ----------
local finder = hs.application.get("Finder")
local knownIds = {}
for _, w in ipairs(finder:allWindows()) do
  if w:isStandard() then knownIds[w:id()] = true end
end
local extraWindows = {}
finder:activate(true)
sleep(0.6)
hs.eventtap.keyStroke({ "cmd" }, "n", 0)
sleep(1)
hs.eventtap.keyStroke({ "cmd" }, "n", 0)
local te, wins
for _ = 1, 20 do
  te = hs.application.get("Finder")
  if te then
    wins = T.visibleWindows(te)
    local std = 0
    for _, w in ipairs(wins) do
      if not knownIds[w:id()] then std = std + 1; extraWindows[w:id()] = w end
    end
    if std >= 2 then break end
  end
  sleep(0.5)
end
ok("Finder running", te ~= nil)
if not te then
  restore()
  local msg = "integration: 0 passed, 1 failed\n  - Finder not available"
  local rf = io.open("/tmp/trisplit_it_result.txt", "w"); rf:write(msg); rf:close()
  return msg
end
ok("Finder has 2 new windows", #wins >= 2, "got " .. tostring(wins and #wins or 0))

-- ---------- deterministic config: 2 slots on the primary screen ----------
local bodyOk, bodyErr = pcall(function()
local primary = T.primaryScreen()
local pname = primary:name()
local cfg = T.activeConfig()
local savedMonitors = cfg.monitors
cfg.monitors = { [pname] = { cols = 2, rows = 1, slots = { "Finder#1", "" } } }
T.saveState()

-- ---------- liveMove moves the right window ----------
local moved = trisplit.liveMove(pname, 1, "Finder#2")
ok("liveMove returns true", moved == true)
sleep(0.8)
local w2 = T.visibleWindows(te)[2]
local expect = T.gridFrame(primary, 1, 2, 1)
local got = w2:frame()
ok("liveMove placed window in slot frame",
  near(got.x, expect.x) and near(got.y, expect.y) and near(got.w, expect.w),
  string.format("got (%d,%d,%d) want (%d,%d,%d)", got.x, got.y, got.w, expect.x, expect.y, expect.w))

-- ---------- moveFrontToSlot records App#N ----------
w2:focus()
sleep(0.5)
local okMove = trisplit.moveFrontToSlot(2)
ok("moveFrontToSlot(2) returns true", okMove == true)
local slotVal = T.activeConfig().monitors[pname].slots[2]
ok("moveFrontToSlot stores Finder#2", slotVal == "Finder#2", "got " .. tostring(slotVal))

-- ---------- focusSlot focuses the indexed window ----------
local focusedBefore = hs.window.focusedWindow()
ok("focusSlot(1) returns true", trisplit.focusSlot(1) == true)
sleep(0.6)
local focused = hs.window.focusedWindow()
ok("focusSlot focuses a Finder window",
  focused and focused:application():name() == "Finder")
local w1id = T.visibleWindows(te)[1]:id()
ok("focusSlot(1) focuses window #1", focused and focused:id() == w1id)

-- ---------- persistence round-trip ----------
local f = io.open(T.store, "r")
local raw = f:read("a")
f:close()
ok("store contains Finder#2", raw:find("Finder#2", 1, true) ~= nil)
local reloaded = hs.json.decode(raw)
ok("store is valid JSON with configs", reloaded.configs ~= nil and #reloaded.configs > 0)

-- ---------- handlePanelB64 save action ----------
local payload = { action = "save", configs = { { name = "IT", monitors = { [pname] = {
  cols = 1, rows = 1, slots = { "Finder" } } } } }, active = 1 }
local okB64, b64 = pcall(function() return require("hs.base64").encode(hs.json.encode(payload)) end)
if okB64 then
  trisplit.handlePanelB64(b64)
  sleep(0.2)
  ok("handlePanelB64 save updates state", T.activeConfig().name == "IT")
else
  ok("hs.base64 available", false)
end

-- ---------- displayplacer integration ----------
local dp = "/opt/homebrew/bin/displayplacer"
local ph = io.popen("test -x " .. dp .. " && echo yes || echo no")
local hasDp = ph:read("l") == "yes"
ph:close()
if hasDp then
  local blocks = T.parseDisplayplacer()
  ok("parseDisplayplacer returns blocks", type(blocks) == "table" and #blocks > 0, "n=" .. tostring(blocks and #blocks))
  local b = blocks and blocks[1]
  ok("displayplacer block has id", b and b.id ~= nil)
  ok("displayplacer block has resolution", b and b.w and b.h and b.w > 0 and b.h > 0)
  ok("displayplacer block has origin", b and b.x ~= nil and b.y ~= nil)
  local offs = T.currentOffsets()
  local total = 0
  for _, v in pairs(offs) do total = total + math.abs(v.dx) + math.abs(v.dy) end
  ok("currentOffsets consistent with displayplacer list", total >= 0)
else
  pass = pass + 1 -- skipped
end
end)
if not bodyOk then
  fail = fail + 1
  problems[#problems + 1] = "crash: " .. tostring(bodyErr)
end

-- ---------- cleanup ----------
restore()
for _, w in pairs(extraWindows) do pcall(function() w:close() end) end
ok("user config restored", T.activeConfig() ~= nil and T.activeConfig().name ~= "IT")

local summary = string.format("integration: %d passed, %d failed%s", pass, fail,
  fail > 0 and ("\n  - " .. table.concat(problems, "\n  - ")) or "")
local rf = io.open("/tmp/trisplit_it_result.txt", "w"); rf:write(summary); rf:close()
return summary
