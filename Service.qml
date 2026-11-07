import QtQuick
import Quickshell
import Quickshell.Io
import "Modes.js" as Modes

// Live state for the Switch 2. A small Python bridge (bin/dabber-bridge) keeps one Home Assistant
// WebSocket open and pushes every entity change as NDJSON, so the bar and panel update the instant
// the device does. Commands go back the same way. Taps are shown optimistically for ~2.5 s so the
// UI feels instant; HA's real state replaces them, or they roll back if nothing confirms.
Item {
  id: root

  property var settings: ({})

  property var real: ({})       // key -> {id, state, attrs}, straight from HA
  property var overlay: ({})    // key -> state shown optimistically
  property bool wsUp: false
  property bool synced: false
  property string lastError: ""

  readonly property string haUrl: String(setting("haUrl", "http://homeassistant.local:8123"))
  readonly property string tokenFile: String(setting("tokenFile", "~/.config/homeassistant/token"))
  readonly property string bridgePath: Qt.resolvedUrl("bin/dabber-bridge").toString().replace(/^file:\/\//, "")

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function st(key, fallback) {
    if (overlay[key] !== undefined) return overlay[key]
    var e = real[key]
    return e === undefined ? fallback : e.state
  }
  function num(key, fallback) {
    var v = parseFloat(st(key, ""))
    return isNaN(v) ? fallback : v
  }

  // ---- derived state -------------------------------------------------------
  readonly property bool linked: synced && real["connected"] !== undefined && real["connected"].state === "on"
  readonly property bool holding: st("connection", "off") === "on"
  readonly property bool usable: linked && st("temperature", "unavailable") !== "unavailable"
  readonly property bool heating: st("heat", "off") === "on"
  readonly property bool cleaning: st("cleaning", "off") === "on"
  readonly property int preset: Math.round(num("preset", 0))
  readonly property real temperature: num("temperature", NaN)
  readonly property string unit: st("unit", "F") === "C" ? "C" : "F"
  readonly property int battery: Math.round(num("battery", -1))
  readonly property bool charging: st("charging", "off") === "on"
  readonly property int brightness: Math.round(num("brightness", 0))
  // The HA select exposes either numbers (integration 0.1.x) or names (0.2+); handle both.
  readonly property var ledOptions: real["led_mode"] && real["led_mode"].attrs && real["led_mode"].attrs.options ? real["led_mode"].attrs.options : []
  readonly property bool ledNamed: ledOptions.length > 0 && isNaN(parseInt(ledOptions[0]))
  readonly property int ledMode: {
    var s = st("led_mode", "")
    var m = ledNamed ? Modes.byName(s) : Modes.byNumber(parseInt(s))
    return m ? m.n : -1
  }
  readonly property var ledInfo: Modes.byNumber(ledMode)
  function ledSupports(n) {
    var m = Modes.byNumber(n)
    if (!m) return false
    return ledNamed || (n >= 1 && n <= 28)   // old integration only knows 1..28
  }
  readonly property bool haptics: st("haptics", "off") === "on"
  readonly property int sessionLeft: Math.round(num("session_left", 0))
  function presetTemp(n) { return num("preset_" + n + "_temp", -1) }

  readonly property string statusText: !wsUp ? "Home Assistant offline"
    : !synced ? "Connecting…"
    : !holding ? "Released for the phone app"
    : !linked ? "Switch not connected"
    : heating ? "Heating"
    : cleaning ? "Cleaning"
    : "Ready"

  // ---- commands ------------------------------------------------------------
  function send(obj) {
    if (proc.running) proc.write(JSON.stringify(obj) + "\n")
  }
  function call(domain, service, key, data) {
    send({ cmd: "call", domain: domain, service: service, key: key, data: data || {} })
  }
  function show(key, state) {
    var o = Object.assign({}, overlay)
    o[key] = state
    overlay = o
    overlayTimer.restart()
  }

  function setPreset(n) {
    if (n < 1 || n > 5 || !usable) return
    show("preset", String(n))
    call("select", "select_option", "preset", { option: String(n) })
  }
  function startHeat() {
    if (!usable || heating) return
    show("heat", "on")
    call("switch", "turn_on", "heat")
  }
  function stopHeat() {
    // Always allowed, even if the UI thinks nothing is heating.
    show("heat", "off")
    call("switch", "turn_off", "heat")
  }
  function toggleHeat() { heating ? stopHeat() : startHeat() }
  function setBrightness(v) {
    v = Math.max(0, Math.min(100, Math.round(v)))
    show("brightness", String(v))
    call("number", "set_value", "brightness", { value: v })
  }
  function setLedMode(n) {
    if (!usable || !ledSupports(n)) return
    var m = Modes.byNumber(n)
    var option = ledNamed ? m.name : String(n)
    show("led_mode", option)
    call("select", "select_option", "led_mode", { option: option })
  }
  function stepLedMode(dir) {
    var n = ledMode < 0 ? Modes.modes[0].n : ledMode
    for (var i = 0; i < Modes.modes.length; i++) {
      n = Modes.step(n, dir)
      if (ledSupports(n)) { setLedMode(n); return }
    }
  }
  function setHaptics(on) {
    show("haptics", on ? "on" : "off")
    call("switch", on ? "turn_on" : "turn_off", "haptics")
  }
  function startCleaning() { if (usable && !heating) call("button", "press", "clean_start") }
  function stopCleaning() { call("button", "press", "clean_stop") }
  function setHolding(on) {
    show("connection", on ? "on" : "off")
    call("switch", on ? "turn_on" : "turn_off", "connection")
  }

  Timer {
    id: overlayTimer
    interval: 2500
    onTriggered: root.overlay = ({})
  }

  // ---- bridge process ------------------------------------------------------
  function handle(line) {
    var m
    try { m = JSON.parse(line) } catch (e) { return }
    if (m.t === "conn") {
      wsUp = m.ok === true
      if (!wsUp) { synced = false; lastError = m.err || "" } else lastError = ""
    } else if (m.t === "snapshot") {
      real = m.entities || {}
      overlay = ({})
      synced = true
    } else if (m.t === "update") {
      var r = Object.assign({}, real)
      r[m.key] = { id: (real[m.key] ? real[m.key].id : ""), state: m.state, attrs: m.attrs || {} }
      real = r
      if (overlay[m.key] !== undefined) {
        var o = Object.assign({}, overlay)
        delete o[m.key]
        overlay = o
      }
    } else if (m.t === "error") {
      lastError = m.msg || ""
    }
  }

  Process {
    id: proc
    command: [root.bridgePath, "--url", root.haUrl, "--token-file", root.tokenFile]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handle(line) } }
    onExited: {
      root.wsUp = false
      root.synced = false
      restartTimer.start()
    }
  }
  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: proc.running = true
  }
}
