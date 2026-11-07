import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Modes.js" as Modes

Panel {
  id: root
  moduleName: "shawn.dabber"
  ipcTarget: "shawn.dabber"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showBattery: setting("showBattery", true) !== false

  readonly property string glyphFlame: "\u{F0238}"
  readonly property string glyphBluetooth: "\u{F00AF}"
  readonly property string glyphBroom: "\u{F00E2}"

  function tempText(v) {
    return isNaN(v) ? "–" : Math.round(v) + "°" + dabber.unit
  }

  function heroMeta() {
    if (!dabber.usable) return dabber.statusText + (dabber.lastError !== "" && !dabber.wsUp ? " · " + dabber.lastError : "")
    var parts = []
    if (dabber.preset > 0) parts.push("Preset " + dabber.preset)
    parts.push(root.tempText(dabber.temperature) + " now")
    if (dabber.battery >= 0) parts.push(dabber.battery + "%" + (dabber.charging ? " ⚡" : ""))
    return parts.join(" · ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: dabber
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function preset(n: int): string { dabber.setPreset(n); return dabber.statusText }
    function heat(action: string): string {
      // Starting needs an explicit "start"; stopping is always allowed.
      if (action === "start") dabber.startHeat()
      else if (action === "stop") dabber.stopHeat()
      return dabber.heating ? "heating" : "idle"
    }
    function brightness(n: int): string { dabber.setBrightness(n); return String(n) }
    function led(n: int): string { dabber.setLedMode(n); return String(n) }
    function clean(action: string): string {
      if (action === "start") dabber.startCleaning()
      else if (action === "stop") dabber.stopCleaning()
      return "ok"
    }
    function status(): string {
      return dabber.statusText + " | preset " + dabber.preset + " | " + root.tempText(dabber.temperature)
        + " | battery " + dabber.battery + "% | led " + dabber.ledMode + " @ " + dabber.brightness + "%"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: dabber.heating
    dimmed: !dabber.usable
    text: root.glyphFlame + (dabber.heating && !isNaN(dabber.temperature) && !(root.bar && root.bar.vertical)
        ? " " + Math.round(dabber.temperature) + "°"
        : (root.showBattery && dabber.usable && dabber.battery >= 0 && !(root.bar && root.bar.vertical) ? " " + dabber.battery + "%" : ""))
    tooltipText: "Dr.Dabber: " + dabber.statusText
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) dabber.stopHeat()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t >= "1" && t <= "5") dabber.setPreset(parseInt(t))
        else if (t === "x" || t === "X") dabber.stopHeat()
        else if (t === "[") dabber.stepLedMode(-1)
        else if (t === "]") dabber.stepLedMode(1)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Dr.Dabber"
          meta: root.heroMeta()
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: root.glyphFlame
              color: dabber.heating ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: root.glyphBluetooth
              tooltipText: dabber.holding ? "Release Bluetooth for the phone app" : "Reconnect Bluetooth"
              foreground: dabber.holding ? root.foreground : root.urgent
              fontFamily: root.fontFamily
              onClicked: dabber.setHolding(!dabber.holding)
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: dabber.lastError !== "" && dabber.wsUp
          width: parent.width
          text: dabber.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ---- Heat -----------------------------------------------------------
        Button {
          width: parent.width
          enabled: dabber.usable
          bordered: true
          selected: dabber.heating
          foreground: dabber.heating ? root.urgent : root.foreground
          fontFamily: root.fontFamily
          iconText: root.glyphFlame
          text: dabber.heating
            ? "Stop heat   " + root.tempText(dabber.temperature) + (dabber.sessionLeft > 0 ? "  ·  " + dabber.sessionLeft + "s" : "")
            : "Start heat"
          onClicked: dabber.toggleHeat()
        }

        // ---- Presets --------------------------------------------------------
        PanelSectionHeader { text: "PRESET"; foreground: root.foreground; fontFamily: root.fontFamily }
        Row {
          id: presetRow
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: 5
            Button {
              required property int index
              width: (presetRow.width - presetRow.spacing * 4) / 5
              enabled: dabber.usable
              bordered: true
              selected: dabber.preset === index + 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              text: (index + 1) + (dabber.presetTemp(index + 1) > 0 ? "\n" + Math.round(dabber.presetTemp(index + 1)) + "°" : "")
              onClicked: dabber.setPreset(index + 1)
            }
          }
        }

        // ---- LEDs -----------------------------------------------------------
        PanelSectionHeader { text: "LED BRIGHTNESS  " + dabber.brightness + "%"; foreground: root.foreground; fontFamily: root.fontFamily }
        PanelSlider {
          id: brightnessSlider
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: 100
          step: 1
          integer: true
          enabled: dabber.usable
          value: dabber.brightness
          property int pending: -1
          onMoved: function(v) { pending = Math.round(v); throttle.start() }
          onReleased: function(v) { throttle.stop(); pending = -1; dabber.setBrightness(v) }
          // While dragging, send about 4 updates a second (the Switch needs ~250 ms between writes).
          Timer {
            id: throttle
            interval: 250
            repeat: true
            onTriggered: if (brightnessSlider.pending >= 0) { dabber.setBrightness(brightnessSlider.pending); brightnessSlider.pending = -1 }
          }
        }

        PanelSectionHeader {
          text: "LED MODE  " + (dabber.ledInfo ? dabber.ledInfo.name : "–")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        ModeGroup { width: parent.width; modes: Modes.inGroup("off");   cols: 2 }
        PanelSectionHeader { text: "SOLID COLORS"; foreground: root.foreground; fontFamily: root.fontFamily }
        ModeGroup { width: parent.width; modes: Modes.inGroup("solid"); cols: 4 }
        PanelSectionHeader { text: "THEMES"; foreground: root.foreground; fontFamily: root.fontFamily }
        ModeGroup { width: parent.width; modes: Modes.inGroup("theme"); cols: 2 }

        // ---- Extras ---------------------------------------------------------
        PanelSeparator { width: parent.width; foreground: root.foreground }
        Toggle {
          width: parent.width
          label: "Haptic feedback"
          checked: dabber.haptics
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: dabber.usable
          onClicked: dabber.setHaptics(!dabber.haptics)
        }
        Button {
          width: parent.width
          enabled: dabber.usable && !dabber.heating
          bordered: true
          selected: dabber.cleaning
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconText: root.glyphBroom
          text: dabber.cleaning ? "Stop cleaning assist" : "Cleaning assist (200° for 30 s)"
          onClicked: dabber.cleaning ? dabber.stopCleaning() : dabber.startCleaning()
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "1–5 preset · [ ] LED mode · x stop heat · middle-click the bar icon stops heat"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
      }
    }
  }

  component ModeGroup: Grid {
    id: group
    property var modes: []
    property int cols: 3
    columns: cols
    spacing: Style.space(4)
    Repeater {
      model: group.modes
      ModeTile {
        required property var modelData
        mode: modelData
        width: (group.width - group.spacing * (group.cols - 1)) / group.cols
      }
    }
  }

  // Quiet tile: neutral base, the mode's colors as a soft tint that brightens when selected or hovered.
  component ModeTile: Rectangle {
    id: tile
    property var mode: null
    readonly property bool current: mode && dabber.ledMode === mode.n
    readonly property bool usable: mode && dabber.usable && dabber.ledSupports(mode.n)
    readonly property var cols: mode && mode.colors.length > 0 ? mode.colors : []
    readonly property bool hot: hover.hovered && usable
    height: Style.space(30)
    radius: Style.cornerRadius > 0 ? Style.space(6) : 0
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, current ? 0.14 : 0.06)
    border.width: current ? 1 : 0
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    opacity: usable ? 1 : 0.4

    Rectangle {
      visible: tile.cols.length > 0
      anchors.fill: parent
      radius: tile.radius
      opacity: tile.current ? 0.65 : (tile.hot ? 0.45 : 0.26)
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: tile.cols.length > 0 ? tile.cols[0] : "transparent" }
        GradientStop { position: 0.5; color: tile.cols.length > 2 ? tile.cols[1] : (tile.cols.length > 0 ? tile.cols[0] : "transparent") }
        GradientStop { position: 1.0; color: tile.cols.length > 0 ? tile.cols[tile.cols.length - 1] : "transparent" }
      }
    }
    // Small solid chip on the left keeps the real hue readable despite the soft tint.
    Rectangle {
      visible: tile.cols.length > 0
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(7)
      width: Style.space(8); height: Style.space(8); radius: width / 2
      color: tile.cols.length > 0 ? tile.cols[tile.cols.length - 1] : "transparent"
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: tile.cols.length > 0 ? Style.space(21) : Style.space(8)
      anchors.rightMargin: Style.space(6)
      horizontalAlignment: tile.cols.length > 0 ? Text.AlignLeft : Text.AlignHCenter
      textFormat: Text.PlainText
      text: tile.mode ? tile.mode.name + (tile.mode.hint ? " · " + tile.mode.hint : "") : ""
      elide: Text.ElideRight
      color: tile.current ? root.foreground : Qt.darker(root.foreground, 1.15)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: tile.current
    }
    HoverHandler { id: hover; cursorShape: tile.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: tile.usable; onTapped: dabber.setLedMode(tile.mode.n) }
  }
}
