import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  property var pluginApi: null

  readonly property var now: Time.now
  readonly property real widgetOpacity: widgetData.opacity !== undefined ? widgetData.opacity : 1.0

  // Font sizes scaled by widgetScale
  readonly property real dayFontSize: Math.round(72 * widgetScale)
  readonly property real dateFontSize: Math.round(14 * widgetScale)
  readonly property real timeFontSize: Math.round(12 * widgetScale)

  // Padding
  readonly property real contentPadding: Math.round(Style.marginXL * 1.5 * widgetScale)

  // Implicit size based on content
  implicitWidth: Math.round(contentLayout.implicitWidth + contentPadding * 2)
  implicitHeight: Math.round(contentLayout.implicitHeight + contentPadding * 2)
  width: implicitWidth
  height: implicitHeight

  // Center on screen by default
  defaultX: screen ? (screen.width - implicitWidth) / 2 : 100
  defaultY: screen ? (screen.height - implicitHeight) / 2 : 100

  ColumnLayout {
    id: contentLayout
    anchors.centerIn: parent
    spacing: Math.round(4 * root.widgetScale)
    opacity: root.widgetOpacity

    // Day name (e.g., "MONDAY")
    Text {
      id: dayText
      Layout.alignment: Qt.AlignHCenter
      text: Qt.formatDate(root.now, "dddd").toUpperCase()
      font.family: "Michroma"
      font.pixelSize: root.dayFontSize
      font.weight: Font.Medium
      font.letterSpacing: Math.round(6 * root.widgetScale)
      color: Color.mOnSurface
    }

    // Date (e.g., "20 APR 2025")
    Text {
      id: dateText
      Layout.alignment: Qt.AlignHCenter
      text: Qt.formatDate(root.now, "dd MMM yyyy").toUpperCase()
      font.family: "Michroma"
      font.pixelSize: root.dateFontSize
      font.weight: Font.Normal
      font.letterSpacing: Math.round(4 * root.widgetScale)
      color: Color.mOnSurfaceVariant
      opacity: 0.85
    }

    // Time (e.g., "- 05:30 AM -")
    Text {
      id: timeText
      Layout.alignment: Qt.AlignHCenter
      text: "- " + Qt.formatTime(root.now, "hh:mm AP") + " -"
      font.family: "Michroma"
      font.pixelSize: root.timeFontSize
      font.weight: Font.Normal
      font.letterSpacing: Math.round(4 * root.widgetScale)
      color: Color.mOnSurfaceVariant
      opacity: 0.7
    }
  }
}
