#!/usr/bin/env bash
# trisplit test runner: unit + integration + panel JS.
# Requires a running Hammerspoon with trisplit loaded.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
FAIL=0

clean() { grep -v -- "-- Loading extension" | grep -v "^ok$" | grep -v "^started$"; }

run_sync() {
  local name="$1" file="$2"
  local out
  out=$(hs -c "dofile('$file')" 2>&1 | clean)
  echo "▸ $name"
  echo "  $out"
  echo "$out" | grep -q "0 failed" || FAIL=1
}

run_async() {
  local name="$1" file="$2" result="$3" timeout="$4"
  rm -f "$result"
  hs -c "
hs.timer.doAfter(0.2, function()
  local okk, r = pcall(dofile, '$file')
  if not okk then
    local f = io.open('$result', 'w')
    f:write('ERROR: ' .. tostring(r)); f:close()
  end
end)
return 'started'" >/dev/null 2>&1
  local waited=0
  while [ ! -f "$result" ] && [ "$waited" -lt "$timeout" ]; do sleep 2; waited=$((waited + 2)); done
  echo "▸ $name"
  if [ ! -f "$result" ]; then
    echo "  TIMEOUT after ${timeout}s"
    FAIL=1
  else
    sed 's/^/  /' "$result"
    grep -q "0 failed" "$result" || FAIL=1
  fi
}

echo "trisplit test suite — $(date)"
run_sync    "unit"        "$DIR/unit.lua"
run_async   "integration" "$DIR/integration.lua" /tmp/trisplit_it_result.txt 120
run_async   "panel-js"    "$DIR/panel_js.lua"    /tmp/trisplit_js_result.txt 90

echo
if [ "$FAIL" -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "FAILURES DETECTED"; fi
exit "$FAIL"
