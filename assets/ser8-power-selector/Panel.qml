import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"

  // D-Bus updates keep the icon current without background polling.
  readonly property string activeProfile: PowerProfiles.profile === PowerProfile.PowerSaver
    ? "power-saver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
  readonly property var profiles: PowerProfiles.hasPerformanceProfile
    ? ["power-saver", "balanced", "performance"] : ["power-saver", "balanced"]
  property int profileIndex: 0
  property bool cursorActive: false
  property string errorMessage: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function profileLabel(profile) {
    return profile === "power-saver" ? "Power Saver" : profile === "performance" ? "Performance" : "Balanced"
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    errorMessage = ""
    // Use Omarchy's setter so the selection is restored at boot.
    actionProc.command = ["omarchy-powerprofiles-set", "ac", profile]
    actionProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      profileIndex = Math.max(0, profiles.indexOf(activeProfile))
      cursorActive = false
      errorMessage = ""
    }
  }

  Process {
    id: actionProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0)
        root.errorMessage = "Could not change power mode. Please try again."
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.profileIcon(root.activeProfile)
    tooltipText: "Power mode: " + root.profileLabel(root.activeProfile)
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(410))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        root.profileIndex = Model.selectProfileIndex(root.profileIndex, dx !== 0 ? dx : dy, root.profiles)
      }
      onActivateRequested: root.setProfile(root.profiles[root.profileIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelSectionHeader {
          text: "POWER MODE"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Row {
          id: profileRow
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.profiles
            Button {
              required property var modelData
              required property int index
              width: (profileRow.width - profileRow.spacing * (root.profiles.length - 1)) / root.profiles.length
              iconText: Model.profileIcon(String(modelData))
              iconSize: Style.font.title
              text: root.profileLabel(String(modelData))
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.activeProfile === modelData
              enabled: !actionProc.running
              hasCursor: root.cursorActive && root.profileIndex === index
              onClicked: root.setProfile(String(modelData))
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.profileIndex = index
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.errorMessage || "Your choice is remembered after restarting."
          wrapMode: Text.WordWrap
          color: root.bar.foreground
          opacity: root.errorMessage ? 1 : 0.65
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
