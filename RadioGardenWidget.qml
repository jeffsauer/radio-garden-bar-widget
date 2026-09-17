import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Radio Garden web app bar toggle. Clicking launches the web app and shows it
// on the special:radiogarden scratchpad (a dropdown); click again to hide it.
// Modeled on the TMOG bar widget.
//
// Chrome-family web apps set their window class (brave-radio.garden__-Default
// here) only after the window maps, so the widget cannot rely on a static
// window rule matching at map time. It therefore moves the window onto the
// scratchpad itself once the app is up. A best-effort window rule in
// hypr/looknfeel.lua helps for the brief first frame, but the move here is the
// source of truth.
BarWidget {
  id: root
  moduleName: "com.darkhorse-studios.radio-garden-bar-widget"

  readonly property string special: "radiogarden"
  readonly property string appTitle: "Radio Garden"
  readonly property string appClass: "brave-radio.garden__-Default"
  readonly property string appUrl: root.setting("url", "https://radio.garden")

  // Facts about the current state. hasClient = a Radio Garden window exists
  // (3s refresh poll); shown = the special:radiogarden scratchpad is the
  // active special workspace (tracked from Hyprland's `activespecial` event so
  // it cannot be fooled by focus: a window parked on a closed scratchpad still
  // reports as the active window). launching = a launch is in progress.
  // `shown` seeds false; the first activespecial corrects it.
  property bool hasClient: false
  property bool shown: false
  property bool launching: false

  readonly property bool running: root.hasClient || root.launching

  // Brave web apps all belong to the browser profile, so identify the window
  // by title prefix ("Radio Garden", "Radio Garden – <location>", ...).
  function isRadioGarden(win) {
    if (!win) return false
    var title = String(win.title || "")
    return title.indexOf(root.appTitle) === 0
  }

  function getRadioGardenClient(clients) {
    for (var i = 0; i < clients.length; i++) {
      if (root.isRadioGarden(clients[i])) return clients[i]
    }
    return null
  }

  // ------------- scratchpad visibility (source of truth for `shown`) -------------

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name || "") !== "activespecial") return
      // data is "<specialName>,<monitor>" when a special workspace is active,
      // or ",<monitor>" when none is.
      var parts = String(event.data || "").split(",")
      root.shown = parts[0] === "special:" + root.special
    }
  }

  // ------------- hyprctl plumbing -------------

  property var pendingClients: null
  property var pendingMonitors: null

  Process {
    id: clientsProcess
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var clients = []
        try { clients = JSON.parse(String(text || "")) } catch (e) {}
        var cb = root.pendingClients
        root.pendingClients = null
        if (cb) cb(clients)
        else root.applyClients(clients)
      }
    }
  }

  Process {
    id: monitorsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var monitors = []
        try { monitors = JSON.parse(String(text || "")) } catch (e) {}
        var cb = root.pendingMonitors
        root.pendingMonitors = null
        if (cb) cb(monitors)
      }
    }
  }

  // Dispatches run one at a time: the compositor only accepts them against a
  // settled state, and two hyprctl calls racing each other is how windows end
  // up on the wrong workspace. Queue rather than stack.
  property var dispatchQueue: []

  Process {
    id: dispatchProcess
    stdout: StdioCollector {
      waitForEnd: true
      // Defer the drain by one event-loop turn: `running` can still report true
      // while onStreamFinished runs, which would otherwise deadlock the queue.
      onStreamFinished: function() {
        Qt.callLater(root.pumpDispatch)
      }
    }
  }

  function runDispatch(command) {
    root.dispatchQueue.push(command)
    root.pumpDispatch()
  }

  function pumpDispatch() {
    if (dispatchProcess.running) return
    if (root.dispatchQueue.length === 0) {
      root.refreshState()
      return
    }
    dispatchProcess.command = root.dispatchQueue.shift()
    dispatchProcess.running = true
  }

  function queryClients(cb) {
    root.pendingClients = cb
    if (!clientsProcess.running) clientsProcess.running = true
  }

  function queryMonitors(cb) {
    root.pendingMonitors = cb
    if (!monitorsProcess.running) monitorsProcess.running = true
  }

  function refreshState() {
    root.queryClients(null)
  }

  function workspaceName(win) {
    var ws = win ? win.workspace : null
    return ws ? String(ws.name || "") : ""
  }

  // Move the Radio Garden window onto the scratchpad unless it is already
  // there. Chrome resolves its app class after the window maps, so the static
  // window rule only gets the first frames; this is the reliable landing.
  function moveToScratchpad(win) {
    if (!win || !win.address) return
    if (workspaceName(win) === "special:" + root.special) return
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.move({ window = "address:' + win.address + '", workspace = "special:' + root.special + '" })'])
  }

  function toggleSpecial() {
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.workspace.toggle_special("' + root.special + '")'])
  }

  // ------------- runtime auto-sizing to 40% x 40% of the active monitor -------------

  function focusedMonitor(monitors) {
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i] && monitors[i].focused) return monitors[i]
    }
    return monitors.length ? monitors[0] : null
  }

  // hyprctl monitors reports physical pixels; window sizes are logical, so the
  // fraction applies to width/scale (rotation-aware like the webcam overlay).
  function logicalMonitorSize(monitor) {
    var scale = Math.max(1, (monitor.scale || 1))
    var rotated = ((monitor.transform || 0) % 2) === 1
    var width = rotated ? monitor.height : monitor.width
    var height = rotated ? monitor.width : monitor.height
    return { width: width / scale, height: height / scale }
  }

  function resizeToClean(win, monitors) {
    if (!win || !win.address) return
    var monitor = root.focusedMonitor(monitors)
    if (!monitor) return
    // A tiled window cannot be resized, so float it first (window rules only
    // apply at map time; this also catches a window that was un-floated).
    if (!win.floating) {
      root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.float({ window = "address:' + win.address + '", action = "on" })'])
    }
    var size = root.logicalMonitorSize(monitor)
    var w = Math.max(200, Math.round(size.width * 0.4))
    var h = Math.max(150, Math.round(size.height * 0.4))
    var address = "address:" + win.address
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.resize({ window = "' + address + '", x = ' + w + ', y = ' + h + ' })'])
    // Center on the bar's monitor, just under the bar. The bar hugs the top or
    // bottom edge of the monitor where the scratchpad opens (the focused one).
    var position = root.bar ? String(root.bar.position || "top") : "top"
    var barThickness = (position === "left" || position === "right") ? 0 : root.barSize
    var monitorLeft = Math.round(monitor.x)
    var monitorTop = Math.round(monitor.y)
    var monitorRight = monitorLeft + size.width
    var monitorBottom = monitorTop + size.height
    var barBottom = (position === "bottom")
      ? monitorBottom
      : monitorTop + barThickness
    var x = Util.clamp(monitorLeft + Math.round((size.width - w) / 2), monitorLeft, Math.max(monitorLeft, monitorRight - w))
    var y = Util.clamp(barBottom + 10, monitorTop, Math.max(monitorTop, monitorBottom - h))
    root.runDispatch(["hyprctl", "dispatch", 'hl.dsp.window.move({ window = "' + address + '", x = ' + x + ', y = ' + y + ' })'])
  }

  // Size the Radio Garden window to 40% x 40% of the current monitor the
  // moment it shows, instead of remembering whatever size it had before.
  function autoSizeWindow(win) {
    if (!win || !win.address) return
    root.queryMonitors(function(monitors) {
      root.resizeToClean(win, monitors)
    })
  }

  function applyClients(clients) {
    root.hasClient = root.getRadioGardenClient(clients) !== null
    if (root.hasClient) root.launching = false
  }

  // ------------- click: launch if needed, then flip the scratchpad -------------

  function onToggle() {
    if (root.launching) return
    root.queryClients(function(clients) {
      var win = root.getRadioGardenClient(clients)
      if (win) {
        // Window exists -> park it on the scratchpad and flip it open/closed.
        // Toggling always flips, and the activespecial event keeps `shown` in
        // step with reality.
        root.moveToScratchpad(win)
        root.autoSizeWindow(win)
        root.toggleSpecial()
      } else {
        root.launchApp()
      }
    })
  }

  // ------------- launch -------------

  Timer {
    id: launchPoll
    interval: 350
    repeat: true
    running: false
    property int attempts: 0
    onTriggered: root.pollLaunch()
  }

  function launchApp() {
    root.launching = true
    launchPoll.attempts = 0
    launchPoll.running = true
    Util.execArgv(["omarchy-launch-webapp", root.appUrl])
    root.pollLaunch()
  }

  function pollLaunch() {
    root.queryClients(function(clients) {
      var win = root.getRadioGardenClient(clients)
      if (win) {
        launchPoll.running = false
        launchPoll.attempts = 0
        root.launching = false
        // Park the fresh window on the scratchpad, then open it. If the
        // scratchpad somehow was already showing, `shown` is true and the
        // toggle is skipped.
        root.moveToScratchpad(win)
        root.autoSizeWindow(win)
        if (!root.shown) root.toggleSpecial()
      } else if (++launchPoll.attempts >= 40) {
        // ~14s without a window: give up so the icon is not stuck "launching".
        launchPoll.running = false
        launchPoll.attempts = 0
        root.launching = false
      }
    })
  }

  Timer {
    id: stateRefresh
    interval: 3000
    repeat: true
    running: true
    onTriggered: root.refreshState()
  }

  Component.onCompleted: Qt.callLater(root.refreshState)

  // ------------- IPC (keybinding) -------------
  // Add `omarchy-shell -q com.darkhorse-studios.radio-garden-bar-widget toggle`
  // to a binding in ~/.config/hypr/bindings.lua if you want a shortcut.

  IpcHandler {
    target: "com.darkhorse-studios.radio-garden-bar-widget"

    function toggle(): void { root.onToggle() }
    function show(): void { if (!root.shown) root.onToggle() }
    function hide(): void { if (root.shown) root.onToggle() }
  }

  // ------------- bar button -------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uDB81\uDC3B" // nf-md-radio_tower (U+F043B)
    active: root.shown
    dimmed: !root.running
    tooltipText: root.shown ? "Hide Radio Garden" : "Open Radio Garden"
    onPressed: function(buttonId) {
      if (buttonId === Qt.LeftButton) root.onToggle()
    }
  }
}