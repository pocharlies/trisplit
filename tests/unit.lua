-- tests/unit.lua — pure-logic tests, no side effects.
-- Run: hs -c "dofile('<repo>/tests/unit.lua')"

local T = trisplit._test
local pass, fail = 0, 0
local problems = {}

local function eq(name, got, want)
  if got == want then
    pass = pass + 1
  else
    fail = fail + 1
    problems[#problems + 1] = string.format("%s: got %s want %s", name, tostring(got), tostring(want))
  end
end

local function near(name, got, want, tol)
  tol = tol or 0.01
  if type(got) == "number" and math.abs(got - want) <= tol then
    pass = pass + 1
  else
    fail = fail + 1
    problems[#problems + 1] = string.format("%s: got %s want %s±%s", name, tostring(got), tostring(want), tol)
  end
end

-- ---------- parseSpec ----------
local n1, i1 = T.parseSpec("Safari")
eq("parseSpec plain name", n1, "Safari")
eq("parseSpec plain idx", i1, 1)
local n2, i2 = T.parseSpec("Google Chrome#3")
eq("parseSpec #N name", n2, "Google Chrome")
eq("parseSpec #N idx", i2, 3)
local n3, i3 = T.parseSpec("App#")
eq("parseSpec trailing # not an index", n3, "App#")
eq("parseSpec trailing # idx", i3, 1)
local n4, i4 = T.parseSpec("App#x")
eq("parseSpec non-numeric suffix", n4, "App#x")
eq("parseSpec non-numeric idx", i4, 1)
local n5, i5 = T.parseSpec("App#12")
eq("parseSpec two digits", i5, 12)

-- ---------- gridFrame (fake screen, 1000x500 at 0,0, GAP=4) ----------
local fake = setmetatable({}, { __index = { frame = function(self) return hs.geometry(0, 0, 1000, 500) end } })

local g11 = T.gridFrame(fake, 1, 1, 1)
near("gridFrame 1x1 x", g11.x, 0)
near("gridFrame 1x1 w", g11.w, 1000)
near("gridFrame 1x1 h", g11.h, 500)

local g31 = T.gridFrame(fake, 2, 3, 1)
local w3 = (1000 - 4 * 2) / 3
near("gridFrame 3x1 slot2 w", g31.w, w3)
near("gridFrame 3x1 slot2 x", g31.x, w3 + 4)

local g22 = T.gridFrame(fake, 3, 2, 2)
eq("gridFrame 2x2 slot3 col", g22.x, 0)
near("gridFrame 2x2 slot3 y", g22.y, (500 - 4) / 2 + 4)

local gwrap = T.gridFrame(fake, 4, 3, 2)
eq("gridFrame wrap slot4 col0", gwrap.x, 0)
near("gridFrame wrap slot4 row1", gwrap.y, (500 - 4) / 2 + 4)

local ggap = T.gridFrame(fake, 1, 2, 1)
local ggap2 = T.gridFrame(fake, 2, 2, 1)
near("gridFrame gap between slots", ggap2.x - (ggap.x + ggap.w), 4)

-- ---------- newMonitorGrid ----------
local g = T.newMonitorGrid(3, 2)
eq("newMonitorGrid cols", g.cols, 3)
eq("newMonitorGrid rows", g.rows, 2)
eq("newMonitorGrid slot count", #g.slots, 6)
local allEmpty = true
for _, s in ipairs(g.slots) do if s ~= "" then allEmpty = false end end
eq("newMonitorGrid slots empty", allEmpty, true)

-- ---------- migrate (v2 flat slots -> v3 monitors) ----------
local old = { name = "Old", slots = {
  { screen = "A", app = "X" }, { screen = "A", app = "" }, { screen = "B", app = "Y" },
} }
T.migrate(old)
eq("migrate removes slots", old.slots, nil)
eq("migrate monitors A app1", old.monitors.A.slots[1], "X")
eq("migrate monitors A app2", old.monitors.A.slots[2], "")
eq("migrate monitors B app1", old.monitors.B.slots[1], "Y")
eq("migrate grid default cols", old.monitors.A.cols, 3)
local modern = { name = "New", monitors = {} }
T.migrate(modern)
eq("migrate is no-op on v3", modern.monitors ~= nil and modern.slots == nil, true)

-- ---------- namesFor (aliases) ----------
eq("namesFor Code alias", T.namesFor("Code")[2], "Visual Studio Code")
eq("namesFor no alias", T.namesFor("Foo")[2], nil)

-- ---------- currentOffsets ----------
local offs = T.currentOffsets()
local screenCount = #hs.screen.allScreens()
local offCount = 0
for _, v in pairs(offs) do
  offCount = offCount + 1
  eq("currentOffsets dx integer", math.floor(v.dx), v.dx)
  eq("currentOffsets dy integer", math.floor(v.dy), v.dy)
end
eq("currentOffsets covers all screens", offCount, screenCount)

-- ---------- panelState contract ----------
local ps = trisplit.panelState()
eq("panelState has screens", type(ps.screens) == "table" and #ps.screens > 0, true)
eq("panelState has configs", type(ps.configs) == "table", true)
eq("panelState primary is a screen name", ps.primary ~= nil, true)
eq("panelState apps is array", type(ps.apps) == "table", true)

-- contract: empty arrange may serialize as [] (this hs.json build ignores
-- __hsjson_type); panel.html normalizes [] -> {} on receipt.
local json = hs.json.encode(ps)
eq("panelState arrange encodes as object or empty array",
  json:find('"arrange":%{%}') ~= nil or json:find('"arrange":%[%]') ~= nil, true)

-- regression: primary is the screen at origin (0,0)
local p = T.primaryScreen()
local pf = p:fullFrame()
eq("primaryScreen at x=0", math.floor(pf.x), 0)
eq("primaryScreen at y=0", math.floor(pf.y), 0)

-- ---------- flatSlots with explicit cfg ----------
local realScreens = T.sortedScreens()
local cfg = { name = "T", monitors = {} }
for _, s in ipairs(realScreens) do
  cfg.monitors[s:name()] = { cols = 2, rows = 1, slots = { "App1", "App2" } }
end
local flat = trisplit.flatSlots(cfg)
eq("flatSlots count = screens*2", #flat, #realScreens * 2)
eq("flatSlots first has screen name", flat[1].screen ~= nil, true)
eq("flatSlots idx restarts per screen", flat[3] == nil or flat[3].idx == 1, true)
eq("flatSlots carries cols/rows", flat[1].cols, 2)

-- ---------- slotFrame matches gridFrame ----------
local sf = trisplit.slotFrame(1)
eq("slotFrame returns geometry", sf ~= nil, true)

-- ---------- summary ----------
return string.format("unit: %d passed, %d failed%s", pass, fail,
  fail > 0 and ("\n  - " .. table.concat(problems, "\n  - ")) or "")
