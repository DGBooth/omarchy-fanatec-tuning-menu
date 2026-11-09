// SPDX-License-Identifier: MIT
// Copyright (c) 2026 DGBooth
// Run with: node --test tests/
// Loads Model.js (a QML JS library) into a plain VM context and checks that
// markup-shaped input from the device or a nickname is neutralised.
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const ctx = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  + "\nthis.api = { plain, parseState, formatValue, tuningDefs, defaultFor, baseName }", ctx)
const api = ctx.api

test("plain() strips angle brackets and control characters", () => {
  assert.strictEqual(api.plain('<img src="https://example.invalid/t">AMS2'), 'img src="https://example.invalid/t"AMS2')
  assert.strictEqual(api.plain("a\u0000b\nc"), "abc")
  assert.strictEqual(api.plain(undefined), "")
})

test("device-supplied names cannot carry markup", () => {
  const s = api.parseState([
    "connected=1", "name=<b>Evil</b>", "hid_id=0003:00000EB7:00000999",
    "wheel_id=<i>0x99", "range=900"].join("\n"))
  assert.ok(!/[<>]/.test(s.name), s.name)
  assert.ok(!/[<>]/.test(s.wheelName), s.wheelName)
})

test("known base and rim ids resolve to names", () => {
  const s = api.parseState("connected=1\nhid_id=0003:00000EB7:00000020\nwheel_id=0x33\nrange=900")
  assert.strictEqual(s.name, "Fanatec DD Family")
  assert.strictEqual(s.wheelName, "CSL Steering Wheel GT3")
})

test("disconnected state parses", () => {
  assert.strictEqual(api.parseState("connected=0").connected, false)
  assert.strictEqual(api.parseState("").connected, false)
})

test("OFF and AUTO labels", () => {
  const def = k => api.tuningDefs.find(d => d.key === k)
  assert.strictEqual(api.formatValue(def("SEN"), 2530, 2530), "AUTO")
  assert.strictEqual(api.formatValue(def("NFR"), 0, 100), "OFF")
  assert.strictEqual(api.formatValue(def("BLI"), 101, 101), "OFF")
  assert.strictEqual(api.formatValue(def("FF"), 75, 100), "75")
})
