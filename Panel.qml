// SPDX-License-Identifier: MIT
// Copyright (c) 2026 DGBooth
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Fanatec wheel status bar widget, fed by the hid-fanatecff sysfs attributes.
Panel {
  id: root
  moduleName: "io.github.dgbooth.fanatec-tuning-menu"
  ipcTarget: "io.github.dgbooth.fanatec-tuning-menu"

  implicitWidth: barRow.implicitWidth
  implicitHeight: barRow.implicitHeight

  readonly property int pollingInterval: Math.max(0, parseInt(setting("pollingInterval", 10)) || 0)
  readonly property bool showProfile: setting("barShowProfile", true) === true

  property bool isConnected: false
  property string deviceName: ""
  property int range: -1
  property string wheelName: ""
  property string fw: ""
  property var tuning: ({})
  property bool tuningWritable: false
  property int maxRange: 1090
  property bool tuningOpen: false
  property string writeError: ""
  property var pendingWrite: null

  readonly property string glyph: "󰓔"
  readonly property string statusScript: decodeURIComponent(Qt.resolvedUrl("status.sh").toString().replace("file://", ""))

  // Active tuning profile as the wheel shows it: raw slot 1 is "A SET", 2..5 are "SET 1".."SET 4".
  function profileName() {
    var s = tuning.SLOT
    if (s === undefined) return ""
    return s === 1 ? "A" : "S" + (s - 1)
  }

  // ---- profile nicknames ----
  // Stored as nickS1..nickS4 on this widget's entry in shell.json. The bar
  // label deliberately stays "A"/"S1".."S4"; nicknames only appear in the panel
  // and tooltip. Raw slot 2..5 = S1..S4 (slot 1 is Auto, which has no nickname).
  function nickFor(slot) {
    if (slot === undefined || slot < 2) return ""
    return Model.plain(setting("nickS" + (slot - 1), ""))
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var vk in values) entry[vk] = values[vk]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setNick(slot, text) {
    if (slot === undefined || slot < 2) return
    var values = {}
    values["nickS" + (slot - 1)] = String(text).trim()
    persistSettings(values)
  }

  // "Auto", "S1".."S4" - the preset the settings list currently edits.
  function presetLabel() {
    var n = profileName()
    return n === "A" ? "Auto" : (n !== "" ? n : "preset")
  }

  function barLabel() {
    return (isConnected && showProfile && profileName() !== "" && !button.vertical) ? profileName() : ""
  }

  function barTooltip() {
    if (!isConnected) return "No Fanatec wheelbase detected"
    var prof = profileName()
    return deviceName + "\n" + wheelName + (prof !== "" ? " · profile " + (prof === "A" ? "Auto" : prof) + (nickFor(tuning.SLOT) !== "" ? " (" + nickFor(tuning.SLOT) + ")" : "") : "")
  }

  Process {
    id: proc
    command: ["bash", root.statusScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(Model.parseState(text))
    }
  }

  function refresh() { if (!proc.running) proc.running = true }

  function apply(s) {
    isConnected = s.connected
    deviceName = s.name
    range = s.range
    wheelName = s.wheelName
    fw = s.fw
    tuning = s.tuning
    tuningWritable = s.writable
    maxRange = s.maxRange
  }

  // ---- tuning writes ----
  // Writes go through the driver's sysfs files (/sys/class/ftec_tuning/*/KEY);
  // the key is checked against a whitelist so nothing else is ever written.
  function setTuning(key, value) {
    if (Model.tuningKeys.indexOf(key) < 0) return
    value = Math.round(value)
    if (!isFinite(value)) return
    if (writeProc.running) { pendingWrite = { key: key, value: value }; return }
    writeError = ""
    writeProc.command = ["bash", "-c",
      'for d in /sys/class/ftec_tuning/*/; do echo "$2" > "${d}$1"; exit $?; done; exit 1',
      "_", key, String(value)]
    writeProc.running = true
  }

  Process {
    id: writeProc
    stderr: StdioCollector { id: writeErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0)
        root.writeError = root.tuningWritable
          ? "The wheel rejected that value."
          : "No write access. Add your user to the 'games' group, then log out and in."
      if (root.pendingWrite) {
        var w = root.pendingWrite
        root.pendingWrite = null
        root.setTuning(w.key, w.value)
      } else {
        settleTimer.restart()
      }
    }
  }

  // The wheel needs a moment to report back its new values (especially after
  // a slot change), so re-read shortly after the last write.
  Timer { id: settleTimer; interval: 500; onTriggered: root.refresh() }

  Timer {
    interval: Math.max(2, root.pollingInterval) * 1000
    running: root.pollingInterval > 0
    repeat: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: if (opened) refresh()
  Component.onCompleted: Qt.callLater(root.refresh)

  Row {
    id: barRow
    anchors.fill: parent
    spacing: 0

    BarIconButton {
      id: button
      bar: root.bar
      text: root.glyph
      dimmed: !root.isConnected
      tooltipText: root.barTooltip()
      onPressed: function(b) { if (b === Qt.RightButton) root.refresh(); else root.toggle() }
    }

    WidgetButton {
      bar: root.bar
      visible: root.barLabel() !== ""
      text: root.barLabel()
      tooltipText: root.barTooltip()
      horizontalMargin: 2
      onPressed: function(b) { if (b === Qt.RightButton) root.refresh(); else root.toggle() }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Text {

          textFormat: Text.PlainText
          text: "Fanatec Tuning Menu"
          color: root.barForeground
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: root.isConnected ? "Connected" : "No wheelbase detected"
          color: root.isConnected ? Color.accent : Qt.darker(root.barForeground, 1.4)
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          textFormat: Text.PlainText
          visible: !root.isConnected
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Plug in the wheelbase and make sure the hid-fanatecff driver is loaded (lsmod | grep fanatec)."
          color: Qt.darker(root.barForeground, 1.4)
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.isConnected ? [
            { k: "Base", v: root.deviceName },
            { k: "Wheel rim", v: root.wheelName },
            { k: "Rotation range", v: root.range > 0 ? root.range + "°" : "—" },
            { k: "Firmware", v: root.fw !== "" ? root.fw : "—" }
          ] : []
          delegate: Row {
            width: column.width
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              width: Style.space(110)
              text: modelData.k
              color: Qt.darker(root.barForeground, 1.4)
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width - Style.space(118)
              text: modelData.v
              color: root.barForeground
              elide: Text.ElideRight
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---------- Tuning menu ----------
        PanelSeparator { width: parent.width; visible: root.isConnected }
        // Preset selector, always visible. Switching presets reloads every
        // value in the settings list from the wheel.
        Column {
          visible: root.isConnected && root.tuning.SLOT !== undefined
          width: parent.width
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Preset" + (root.nickFor(root.tuning.SLOT) !== "" ? "  ·  " + root.nickFor(root.tuning.SLOT) : "")
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
          ButtonGroup {
            width: parent.width
            enabled: root.tuningWritable
            options: Model.slotOptions.map(function(o) {
              var n = root.nickFor(parseInt(o.value))
              return { value: o.value, label: o.label, tooltip: n !== "" ? n + " · " + o.tooltip : o.tooltip }
            })
            value: String(root.tuning.SLOT)
            fontSize: Style.font.caption
            onChanged: function(v) { root.setTuning("SLOT", parseInt(v)) }
          }
          TextField {
            id: nickField
            visible: root.tuning.SLOT >= 2
            width: parent.width
            placeholderText: "Nickname for " + root.profileName() + " (optional)"
            maximumLength: 24
            font.pixelSize: Style.font.caption
            text: root.nickFor(root.tuning.SLOT)
            onEditingFinished: root.setNick(root.tuning.SLOT, text)
            Connections {
              target: root
              function onTuningChanged() { if (!nickField.activeFocus) nickField.text = root.nickFor(root.tuning.SLOT) }
            }
          }
        }
        Button {
          visible: root.isConnected && Object.keys(root.tuning).length > 0
          width: parent.width
          text: (root.tuningOpen ? "Hide " : "Edit ") + root.presetLabel() + " settings"
          onClicked: root.tuningOpen = !root.tuningOpen
        }
        Text {
          textFormat: Text.PlainText
          visible: root.isConnected && !root.tuningWritable
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Read-only: your user can't write the tuning files. Add yourself to the 'games' group (sudo usermod -aG games $USER), then log out and back in."
          color: Qt.darker(root.barForeground, 1.4)
          font.pixelSize: Style.font.caption
        }
        Text {
          textFormat: Text.PlainText
          visible: root.writeError !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.writeError
          color: Color.accent
          font.pixelSize: Style.font.caption
        }
        Flickable {
          id: tuneFlick
          visible: root.isConnected && root.tuningOpen
          width: parent.width
          height: Math.min(tuneColumn.implicitHeight, Style.space(340))
          contentHeight: tuneColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          // Sliders swallow the mouse wheel to change their own value, so
          // they forward it here to scroll the list instead.
          function scrollBy(dy) {
            contentY = Math.max(0, Math.min(contentHeight - height, contentY - dy * 0.5))
          }

          // Scrollbar indicator: parented to the Flickable itself (not its
          // scrolling content) so it stays fixed on the right edge.
          Rectangle {
            parent: tuneFlick
            visible: tuneFlick.contentHeight > tuneFlick.height + 1
            readonly property real barH: Math.max(Style.space(24), tuneFlick.height * tuneFlick.height / Math.max(1, tuneFlick.contentHeight))
            readonly property real travel: tuneFlick.height - barH
            readonly property real scrollRange: Math.max(1, tuneFlick.contentHeight - tuneFlick.height)
            width: Style.space(4)
            radius: width / 2
            height: barH
            x: tuneFlick.width - width - Style.space(2)
            y: travel * Math.max(0, Math.min(1, tuneFlick.contentY / scrollRange))
            color: root.barForeground
            opacity: 0.35
          }

          Column {
            id: tuneColumn
            width: parent.width - Style.space(12)
            spacing: Style.space(6)
            opacity: root.tuningWritable ? 1 : 0.5

            Repeater {
              model: Model.tuningDefs.filter(function(d) { return root.tuning[d.key] !== undefined })
              delegate: Column {
                id: tRow
                width: tuneColumn.width
                spacing: Style.space(2)
                readonly property var def: modelData
                readonly property bool adv: root.tuning.advanced_mode === 1
                readonly property int minV: adv ? def.min : def.stdMin
                readonly property int maxV: def.key === "SEN" ? root.maxRange : def.max
                property int shown: root.tuning[def.key]
                property bool helpOpen: false
                Connections { target: root; function onTuningChanged() { tRow.shown = root.tuning[tRow.def.key] } }
                function snap(v) { return Math.round(v / def.step) * def.step }

                Row {
                  width: parent.width
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width - valueText.implicitWidth
                    text: tRow.def.label + (tRow.helpOpen ? "" : "  ⓘ")
                    color: Qt.darker(root.barForeground, 1.4)
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    MouseArea { anchors.fill: parent; onClicked: tRow.helpOpen = !tRow.helpOpen }
                  }
                  Text {
                    textFormat: Text.PlainText
                    id: valueText
                    text: Model.formatValue(tRow.def, tRow.shown, tRow.maxV)
                    color: root.barForeground
                    font.pixelSize: Style.font.caption
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  visible: tRow.helpOpen
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: tRow.def.help + "  Default: " + Model.formatValue(tRow.def, Model.defaultFor(tRow.def, tRow.maxV), tRow.maxV) + ". Right-click the slider to reset."
                  color: Qt.darker(root.barForeground, 1.4)
                  font.pixelSize: Style.font.caption
                }
                PanelSlider {
                  width: parent.width
                  enabled: root.tuningWritable
                  minimum: tRow.def.off !== undefined && tRow.def.off < tRow.minV ? tRow.def.off : tRow.minV
                  maximum: tRow.maxV
                  step: tRow.def.step
                  integer: true
                  value: tRow.shown
                  onMoved: function(v) { tRow.shown = tRow.snap(v) }
                  onReleased: function(v) { root.setTuning(tRow.def.key, tRow.snap(v)) }
                  onRightClicked: { if (root.tuningWritable) root.setTuning(tRow.def.key, Model.defaultFor(tRow.def, tRow.maxV)) }

                  // Wheel-only layer above the slider's own wheel handler:
                  // takes no clicks or drags, so the slider still works.
                  MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) { tuneFlick.scrollBy(wheel.angleDelta.y) }
                  }
                }
              }
            }

            Row {
              visible: root.tuning.SHO !== undefined
              width: parent.width
              Text {
                textFormat: Text.PlainText
                width: parent.width - shoSwitch.width
                anchors.verticalCenter: parent.verticalCenter
                text: "Wheel vibration (shock)"
                color: Qt.darker(root.barForeground, 1.4)
                font.pixelSize: Style.font.caption
              }
              ToggleSwitch {
                id: shoSwitch
                enabled: root.tuningWritable
                checked: root.tuning.SHO > 0
                onToggled: root.setTuning("SHO", root.tuning.SHO > 0 ? 0 : 100)
              }
            }
            Text {
              textFormat: Text.PlainText
              visible: root.tuning.ACP !== undefined
              text: "Analogue paddles"
              color: Qt.darker(root.barForeground, 1.4)
              font.pixelSize: Style.font.caption
            }
            ButtonGroup {
              visible: root.tuning.ACP !== undefined
              enabled: root.tuningWritable
              options: Model.analogPaddleModes
              value: String(root.tuning.ACP)
              fontSize: Style.font.caption
              onChanged: function(v) { root.setTuning("ACP", parseInt(v)) }
            }
            Row {
              visible: root.tuning.FFS !== undefined
              width: parent.width
              Text {
                textFormat: Text.PlainText
                width: parent.width - ffsSwitch.width
                anchors.verticalCenter: parent.verticalCenter
                text: "Force feedback scaling (undocumented)"
                color: Qt.darker(root.barForeground, 1.4)
                font.pixelSize: Style.font.caption
              }
              ToggleSwitch {
                id: ffsSwitch
                enabled: root.tuningWritable
                checked: root.tuning.FFS === 1
                onToggled: root.setTuning("FFS", root.tuning.FFS === 1 ? 0 : 1)
              }
            }
            Row {
              visible: root.tuning.advanced_mode !== undefined
              width: parent.width
              Text {
                textFormat: Text.PlainText
                width: parent.width - advSwitch.width
                anchors.verticalCenter: parent.verticalCenter
                text: "Advanced mode"
                color: Qt.darker(root.barForeground, 1.4)
                font.pixelSize: Style.font.caption
              }
              ToggleSwitch {
                id: advSwitch
                enabled: root.tuningWritable
                checked: root.tuning.advanced_mode === 1
                onToggled: root.setTuning("advanced_mode", root.tuning.advanced_mode === 1 ? 0 : 1)
              }
            }
          }
        }
      }
    }
  }
}
