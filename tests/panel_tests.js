(function () {
 try {
  let pass = 0;
  const fails = [];
  const A = (name, cond) => { if (cond) pass++; else fails.push(name); };

  const firstScreen = S.screens[0].name;
  const slotsOf = () => groups().get(firstScreen).slots;

  const slotEls = () => Array.from(document.querySelectorAll("#desk .slot"));
  const drag = (srcEl, dstEl, dt) => {
    srcEl.dispatchEvent(new DragEvent("dragstart", { dataTransfer: dt, bubbles: true }));
    dstEl.dispatchEvent(new DragEvent("dragover", { dataTransfer: dt, bubbles: true }));
    dstEl.dispatchEvent(new DragEvent("drop", { dataTransfer: dt, bubbles: true }));
    srcEl.dispatchEvent(new DragEvent("dragend", { dataTransfer: dt, bubbles: true }));
  };

  // ---- T1: chip drag swaps slots ----
  A("T1 setup slots[0]=Finder#1", slotsOf()[0] === "Finder#1");
  const chip = slotEls()[0].querySelector(".chip");
  A("T1 chip rendered", chip !== null);
  drag(chip, slotEls()[1], new DataTransfer());
  A("T1 target filled", slotsOf()[1] === "Finder#1");
  A("T1 source emptied", slotsOf()[0] === "");

  // ---- T2: X removes chip ----
  slotEls()[1].querySelector(".x").click();
  A("T2 slot emptied by X", slotsOf()[1] === "");

  // ---- T3: tray drag fills empty slot ----
  const trayChip = Array.from(document.querySelectorAll("#chips .tchip"))
    .find((c) => c.textContent.indexOf("Finder") === 0);
  A("T3 Finder in tray", trayChip !== undefined);
  const dt3 = new DataTransfer();
  dt3.setData("text/plain", JSON.stringify({ app: "Finder", tray: true }));
  drag(trayChip, slotEls()[0], dt3);
  A("T3 tray drop fills slot", slotsOf()[0] === "Finder");

  // ---- T4: cols stepper grows grid ----
  const box = document.querySelector("#desk .mon");
  const before = groups().get(firstScreen).cols;
  box.querySelector('[data-dc="1"]').click();
  A("T4 cols incremented", groups().get(firstScreen).cols === before + 1);
  A("T4 slots grew", groups().get(firstScreen).slots.length === (before + 1) * groups().get(firstScreen).rows);

  // ---- T5: + creates a new config ----
  const nCfgs = S.configs.length;
  document.getElementById("new").click();
  const inp = document.getElementById("newname");
  A("T5 input visible", inp.offsetParent !== null);
  inp.value = "JSTest";
  inp.onkeydown({ key: "Enter" });
  A("T5 config added", S.configs.length === nCfgs + 1);
  A("T5 config active", S.configs[S.active - 1].name === "JSTest");
  A("T5 input hidden", document.getElementById("newname").offsetParent === null);

  // ---- T6: arrange [] from Lua normalizes to {} ----
  trisplitSetState({
    screens: S.screens, configs: S.configs, active: S.active,
    apps: S.apps, primary: S.primary, arrange: [], hasDisplayplacer: S.hasDisplayplacer,
  });
  A("T6 [] normalized to object", typeof S.arrange === "object" && !Array.isArray(S.arrange));

  // ---- T7: monitor box drag records offset ----
  const mon = document.querySelector("#desk .mon:not(.primary)") || document.querySelector("#desk .mon");
  const monName = mon.querySelector(".monhead .nm").textContent;
  const r = mon.getBoundingClientRect();
  const pid = 1;
  mon.dispatchEvent(new PointerEvent("pointerdown", { clientX: r.x + r.width / 2, clientY: r.y + 8, pointerId: pid, bubbles: true }));
  mon.dispatchEvent(new PointerEvent("pointermove", { clientX: r.x + r.width / 2 + 80, clientY: r.y + 8, pointerId: pid, bubbles: true }));
  mon.dispatchEvent(new PointerEvent("pointerup", { clientX: r.x + r.width / 2 + 80, clientY: r.y + 8, pointerId: pid, bubbles: true }));
  const off = S.arrange[monName];
  A("T7 arrange offset recorded", off && (off.dx !== 0 || off.dy !== 0));

  return "panel-js: " + pass + " passed, " + fails.length + " failed" + (fails.length ? "\n  - " + fails.join("\n  - ") : "");
 } catch (e) {
  return "JS-EXCEPTION: " + e.message + " @" + (e.stack || "").split("\n")[1];
 }
})()
