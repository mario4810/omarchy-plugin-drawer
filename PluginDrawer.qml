import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The drawer: a small card that drops out from the bar button and holds live
// copies of the widgets that were moved out of the bar.
//
// Why two windows rather than one popup. The widgets in the card open popups of
// their own (a calendar, a device list), and those position themselves from the
// height of whatever window they sit in, expecting it to be the bar. So the
// card lives in a window that reaches from the screen edge to the card's far
// edge, letting those popups land just beyond it, with input limited to the
// card so the bar underneath stays clickable. A second, screen-sized window
// behind it catches clicks elsewhere to dismiss the drawer.
Scope {
  id: root

  required property Item anchorItem
  required property QtObject bar
  // Directory holding plugin-drawer-ctl.sh.
  property string scriptDir: ""
  // What the drawer holds (PluginDrawerModel.drawerItems) and what could join it
  // (PluginDrawerModel.movable).
  property var items: []
  property var movable: []

  property bool open: false
  property bool manage: false

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"
  readonly property bool vertical: barPos === "left" || barPos === "right"
  readonly property int gap: Style.gapsOut
  readonly property int margin: Style.gapsOut

  // An empty drawer has nothing to show, so open it on the edit view.
  onOpenChanged: if (open && items.length === 0) manage = true

  function show() { open = true }
  function hide() { open = false }
  function toggle() { open = !open }

  // The hosted widgets see the bar through this: same bar, popup colours.
  BarProxy {
    id: hostBar
    source: root.bar
  }

  // True when `item` lives inside the card, i.e. is one of the hosted widgets
  // or something they own.
  function owns(item) {
    for (var p = item; p; p = p.parent) if (p === card) return true
    return false
  }

  // Opening another bar popup, say the audio one, should not leave the drawer
  // hanging open beside it. Popups opened by the hosted widgets are ours.
  Connections {
    target: root.bar
    function onActivePopoutChanged() {
      var popout = root.bar ? root.bar.activePopout : null
      if (root.open && popout && !root.owns(popout)) root.hide()
    }
  }

  // Moves a widget in or out. Both end in a layout change, which makes the bar
  // rebuild itself, this drawer included; plugin-drawer-ctl leaves a flag so the new
  // instance reopens where this one left off.
  Process {
    id: ctl
    property string busyId: ""
    property string errorText: ""
    stderr: StdioCollector { id: ctlErr }
    onExited: function(code) {
      busyId = ""
      errorText = code === 0 ? "" : ctlErr.text.trim() || "Could not update the bar layout."
    }
  }

  function runCtl(args, id) {
    if (ctl.running) return
    ctl.errorText = ""
    ctl.busyId = id
    ctl.command = ["bash", scriptDir + "/plugin-drawer-ctl.sh"].concat(args)
    ctl.running = true
  }

  // Catches clicks anywhere but the bar band, so the bar's own buttons keep
  // working while the drawer is open.
  PanelWindow {
    id: dismissWindow
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    visible: root.open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-plugin-drawer-dismiss"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    mask: Region {
      width: dismissWindow.width
      height: dismissWindow.height
      Region {
        x: root.barPos === "right" ? dismissWindow.width - cardWindow.barW : 0
        y: root.barPos === "bottom" ? dismissWindow.height - cardWindow.barH : 0
        width: root.vertical ? cardWindow.barW : dismissWindow.width
        height: root.vertical ? dismissWindow.height : cardWindow.barH
        intersection: Intersection.Subtract
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onPressed: root.hide()
    }
  }

  PanelWindow {
    id: cardWindow

    readonly property real barW: root.anchorWindow ? root.anchorWindow.width : 0
    readonly property real barH: root.anchorWindow ? root.anchorWindow.height : 0

    screen: root.anchorWindow ? root.anchorWindow.screen : null
    // Closing unmaps at once instead of fading out. Animations run on frame
    // callbacks, which stall while the shell is busy opening another popup,
    // and a half-closed card would sit there eating clicks.
    visible: root.open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-plugin-drawer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: root.vertical || root.barPos === "top"
      bottom: root.vertical || root.barPos === "bottom"
      left: !root.vertical || root.barPos === "left"
      right: !root.vertical || root.barPos === "right"
    }
    // Reach from the bar's screen edge to just past the card.
    implicitWidth: root.vertical ? barW + root.gap + card.width : 0
    implicitHeight: root.vertical ? 0 : barH + root.gap + card.height

    // Only the card takes input; everything else falls through to the bar and
    // the dismiss window.
    mask: Region { item: card }

    TransformWatcher {
      id: anchorWatcher
      a: root.anchorWindow ? root.anchorWindow.contentItem : null
      b: root.anchorItem
    }
    readonly property point anchorPos: {
      anchorWatcher.transform
      if (!root.anchorItem || !root.anchorWindow) return Qt.point(0, 0)
      return root.anchorItem.mapToItem(root.anchorWindow.contentItem, 0, 0)
    }

    function clamp(value, size, limit) {
      return Math.round(Math.max(root.margin, Math.min(value, limit - size - root.margin)))
    }

    BorderSurface {
      id: card
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: Style.space(6)
      width: Math.max(strip.implicitWidth, manageList.visible ? manageList.implicitWidth : 0) + contentLeftInset + contentRightInset
      height: content.implicitHeight + contentTopInset + contentBottomInset

      x: root.vertical
        ? (root.barPos === "left" ? cardWindow.barW + root.gap : cardWindow.width - cardWindow.barW - root.gap - width)
        : cardWindow.clamp(cardWindow.anchorPos.x + root.anchorItem.width / 2 - width / 2, width, cardWindow.width)
      y: root.vertical
        ? cardWindow.clamp(cardWindow.anchorPos.y + root.anchorItem.height / 2 - height / 2, height, cardWindow.height)
        : (root.barPos === "bottom" ? cardWindow.height - cardWindow.barH - root.gap - height : cardWindow.barH + root.gap)

      // Swallow clicks so they never reach the dismiss window.
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

      Column {
        id: content
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(6)

        Grid {
          id: strip
          // One row on a horizontal bar, one column on a vertical one; the
          // extra columns cover the empty hint and the edit button.
          columns: root.vertical ? 1 : root.items.length + 2
          spacing: Style.space(2)

          Repeater {
            model: root.items
            delegate: HostedWidget {
              required property var modelData
              entry: modelData
              bar: hostBar
              active: root.open
            }
          }

          Text {
            visible: root.items.length === 0 && !root.manage
            height: hostBar.barSize
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(6)
            rightPadding: Style.space(6)
            text: "Nothing in the drawer"
            color: hostBar.barForeground
            font.family: hostBar.fontFamily
            font.pixelSize: Style.font.body
          }

          // Edit toggle, always last.
          Item {
            width: hostBar.barSize
            height: width

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              radius: Style.cornerRadius
              color: editMouse.containsMouse || root.manage
                ? Util.alpha(hostBar.barForeground, 0.14) : "transparent"
            }
            Text {
              anchors.centerIn: parent
              text: root.manage ? "󰅖" : "󰏫"
              color: hostBar.barForeground
              font.family: hostBar.fontFamily
              font.pixelSize: Style.font.icon
            }
            MouseArea {
              id: editMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.manage = !root.manage
            }
          }
        }

        Rectangle {
          visible: manageList.visible
          width: parent.width
          height: 1
          color: Util.alpha(hostBar.barForeground, 0.2)
        }

        ManageList {
          id: manageList
          visible: root.manage
          // Everything the screen has room for below the bar and the strip.
          maxHeight: Math.max(Style.space(160),
            (cardWindow.screen ? cardWindow.screen.height : 0) - cardWindow.barH - root.gap - 2 * root.margin - Style.space(90))
          width: parent.width
          bar: hostBar
          stashed: root.items
          movable: root.movable
          busyId: ctl.busyId
          errorText: ctl.errorText
          onStash: function(id, keepEnabled) {
            root.runCtl(keepEnabled ? ["stash", id, "--keep-enabled"] : ["stash", id], id)
          }
          onRestore: function(id) { root.runCtl(["restore", id], id) }
        }
      }
    }
  }
}
