// SPDX-License-Identifier: MIT
// Copyright (c) 2026 DGBooth
// Helpers for the Fanatec wheel widget. Ids up to 0x0c are from the driver's
// hid-ftec.h; 0x33 was confirmed by hand. To add another: attach the rim, read
// /sys/bus/hid/drivers/fanatec/*/wheel_id, and add "0xNN": "Name" below.
const wheelNames = {
  "0x04": "CSL Elite WRC",
  "0x06": "Podium Button Module Endurance",
  "0x08": "CSL P1 V2",
  "0x0a": "ClubSport Formula V2",
  "0x0b": "McLaren GT3 V2",
  "0x0c": "Podium Porsche 911 GT3 R",
  "0x33": "CSL Steering Wheel GT3"
}

// Wheelbase names by USB product id (from hid-ftec.h). 0x0020 is shared by the
// CSL DD, GT DD Pro and ClubSport DD, so it can't be told apart from the id
// alone, so it gets the family name.
const baseNames = {
  0x0001: "ClubSport Wheel Base V2",
  0x0004: "ClubSport Wheel Base V2.5",
  0x0005: "CSL Elite Wheel Base (PS4)",
  0x0006: "Podium Wheel Base DD1",
  0x0007: "Podium Wheel Base DD2",
  0x0011: "CSR Elite Wheel Base",
  0x0020: "Fanatec DD Family",
  0x0197: "Porsche 911 Wheel Base",
  0x0e03: "CSL Elite Wheel Base"
}

function baseName(hidId, fallback) {
  var pid = parseInt(String(hidId || "").split(":").pop(), 16)
  return baseNames[pid] || fallback || "Fanatec wheelbase"
}

// Tuning-menu sliders. Ranges are from the Fanatec help article for the
// Podium/CSL DD family: `min` is the advanced-mode minimum, `stdMin` the
// standard-mode one. `off` is the raw value the wheel shows as "OFF"; `dflt` is
// Fanatec's default (used for right-click reset; "max" = AUTO for SEN).
const tuningDefs = [
  { key: "SEN", label: "Sensitivity (rotation)", min: 90, stdMin: 180, max: 2520, step: 10, unit: "°", dflt: "max",
    help: "Degrees of wheel rotation, split evenly left and right of centre. At the top of the scale it shows AUTO, and the PC driver or the game controls it. Standard mode allows 180 to 1080, advanced mode 90 to 2520." },
  { key: "FF", label: "Force feedback", min: 1, stdMin: 5, max: 100, step: 1, off: 0, dflt: 100,
    help: "Maximum motor strength for game FFB. OFF disables FFB from the motor. For stronger feel, raise this rather than the in-game strength, which can cause clipping." },
  { key: "FUL", label: "FullForce strength", min: 1, stdMin: 1, max: 100, step: 1, off: 0, dflt: 100,
    help: "Adds high-fidelity vibration to the FFB signal in games that support it. OFF removes it. Podium DD, CS DD and CS DD+ only." },
  { key: "NDP", label: "Natural damper", min: 1, stdMin: 25, max: 100, step: 1, off: 0, dflt: 50,
    help: "Extra damping that reacts to steering acceleration and angle. Higher values calm oversteer snaps and oscillation. OFF makes the wheel easier to turn." },
  { key: "NFR", label: "Natural friction", min: 1, stdMin: 1, max: 100, step: 1, off: 0, dflt: 0,
    help: "Simulates the mechanical resistance of steering components. Higher means more resistance, and it can also help prevent oscillation." },
  { key: "NIN", label: "Natural inertia", min: 1, stdMin: 1, max: 100, step: 1, off: 0, dflt: 0,
    help: "Simulates extra steering weight. Useful with lighter rims such as the CSL range." },
  { key: "INT", label: "FFB interpolation", min: 1, stdMin: 1, max: 20, step: 1, off: 0, dflt: 11,
    help: "Smooths the game's FFB output without losing detail. OFF is unfiltered, 1 is the lightest filter and 20 the strongest." },
  { key: "FEI", label: "Force effect intensity", min: 0, stdMin: 0, max: 100, step: 10, dflt: 100,
    help: "0 is the smoothest, 100 the sharpest and most direct. Lowering it can tame harsh or spiky FFB." },
  { key: "FOR", label: "Force effect", min: 10, stdMin: 10, max: 120, step: 10, off: 0, dflt: 100,
    help: "Scales the game's constant-force signal. Above 100 raises motor load and heat, so only use it if effects feel weak." },
  { key: "SPR", label: "Spring effect", min: 10, stdMin: 10, max: 120, step: 10, off: 0, dflt: 100,
    help: "Scales the game's centring-spring signal. If this is low or OFF, the wheel can't return to centre after a centre calibration. Games also use spring to centre the wheel in menus and on pause." },
  { key: "DPR", label: "Damper effect", min: 10, stdMin: 10, max: 120, step: 10, off: 0, dflt: 100,
    help: "Scales the game's damper (friction) signal. Above 100 raises motor load and heat." },
  { key: "BLI", label: "Brake level indicator", min: 1, stdMin: 1, max: 101, step: 1, off: 101, dflt: 101,
    help: "Brake pedal level at which the pedal vibrates, for learning threshold braking (needs ClubSport Pedals V3/V3i). OFF lets the game control it." },
  { key: "brF", label: "Brake force (load cell)", min: 10, stdMin: 10, max: 100, step: 10, dflt: 50,
    help: "Pedal force needed for 100% brake, from Lo to Hi. Needs a load-cell brake connected via RJ12 and USB." },
  { key: "DRI", label: "Drift mode", min: -5, stdMin: -5, max: 3, step: 1, dflt: 0,
    help: "CSL Elite only. Not covered by the Fanatec article." }
]
// The driver's SLOT value is 1..5, and the wheel's display shows it shifted by
// one: 1 = "A SET" (Auto Setup, games may adjust it), 2..5 = "SET 1" .. "SET 4".
const slotOptions = [
  { value: "1", label: "Auto", tooltip: "A SET: Auto Setup profile, parameters may be set by games" },
  { value: "2", label: "S1", tooltip: "SET 1: custom profile" },
  { value: "3", label: "S2", tooltip: "SET 2: custom profile" },
  { value: "4", label: "S3", tooltip: "SET 3: custom profile" },
  { value: "5", label: "S4", tooltip: "SET 4: custom profile" }
]
const analogPaddleModes = [
  { value: "1", label: "CbP", tooltip: "Clutch bite point" },
  { value: "2", label: "CH", tooltip: "Left paddle clutch, right paddle handbrake" },
  { value: "3", label: "BT", tooltip: "Left paddle brake, right paddle throttle" },
  { value: "4", label: "AnA", tooltip: "Mappable axes" }
]

function defaultFor(def, maxV) {
  return def.dflt === "max" ? maxV : def.dflt
}

function formatValue(def, v, maxV) {
  if (def.key === "SEN" && v >= maxV) return "AUTO"
  if (def.off !== undefined && v === def.off) return "OFF"
  return v + (def.unit || "")
}

// FFS is a 0/1 switch and advanced_mode a toggle, handled separately.
const tuningKeys = tuningDefs.map(function(d) { return d.key }).concat(["SLOT", "FFS", "SHO", "ACP", "advanced_mode"])

// Highest rotation range per base (hid product id), for the SEN slider.
function maxRange(hidId) {
  var pid = parseInt(String(hidId || "").split(":").pop(), 16)
  // The wheel reports 10 above the advanced-mode maximum (2520 -> 2530) when SEN is AUTO.
  return (pid === 0x0020 || pid === 0x0006 || pid === 0x0007) ? 2530 : 1090
}

function disconnectedState() {
  return { connected: false, name: "", range: -1, wheelId: "", wheelName: "", fw: "", tuning: {}, writable: false, maxRange: 1090 }
}

function parseState(text) {
  var s = disconnectedState()
  var kv = {}
  String(text || "").split("\n").forEach(function(line) {
    var i = line.indexOf("=")
    if (i > 0) kv[line.slice(0, i)] = line.slice(i + 1).trim()
  })
  if (kv.connected !== "1") return s
  s.connected = true
  s.name = baseName(kv.hid_id, kv.name)
  var r = parseInt(kv.range)
  s.range = isNaN(r) ? -1 : r
  s.wheelId = (kv.wheel_id || "").toLowerCase()
  s.wheelName = wheelNames[s.wheelId] || (s.wheelId ? "Unknown rim (" + s.wheelId + ")" : "No rim detected")
  s.fw = kv.fw || ""
  s.maxRange = maxRange(kv.hid_id)
  s.writable = kv.tun_writable === "1"
  tuningKeys.forEach(function(k) {
    var v = parseInt(kv["tun_" + k])
    if (!isNaN(v)) s.tuning[k] = v
  })
  return s
}
