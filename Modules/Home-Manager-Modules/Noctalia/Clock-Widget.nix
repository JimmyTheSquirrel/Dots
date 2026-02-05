{
  config,
  pkgs,
  ...
}: {
  # If you have Noctalia, you already have Quickshell
  # Just create a separate widget config

  home.file.".config/quickshell/datetime-widget/shell.qml".text = ''
    import Quickshell
    import Quickshell.Wayland
    import QtQuick
    import QtQuick.Layouts

    ShellRoot {
      FloatingWindow {
        id: dateTimeWidget

        width: 400
        height: 200
        color: "transparent"

        // Center on screen
        screen: Quickshell.screens[0]

        Rectangle {
          anchors.fill: parent
          color: "#40000000"
          opacity: 0.3

          ColumnLayout {
            anchors.centerIn: parent
            spacing: 8

            Text {
              id: dayText
              Layout.alignment: Qt.AlignHCenter
              color: "#E8E3D3"
              font.pixelSize: 48
              font.family: "JetBrains Mono"
              font.letterSpacing: 8
              font.weight: Font.Light
            }

            Text {
              id: dateText
              Layout.alignment: Qt.AlignHCenter
              color: "#A89F8F"
              font.pixelSize: 16
              font.family: "JetBrains Mono"
              font.letterSpacing: 2
            }

            Text {
              id: timeText
              Layout.alignment: Qt.AlignHCenter
              color: "#A89F8F"
              font.pixelSize: 16
              font.family: "JetBrains Mono"
              font.letterSpacing: 2
            }
          }
        }

        Timer {
          interval: 1000
          running: true
          repeat: true
          onTriggered: updateDateTime()
        }

        Component.onCompleted: updateDateTime()

        function updateDateTime() {
          var now = new Date();
          dayText.text = Qt.formatDate(now, "dddd").toUpperCase();
          dateText.text = Qt.formatDate(now, "dd MMM yyyy").toUpperCase();
          timeText.text = "- " + Qt.formatTime(now, "hh:mm AP").toUpperCase() + " -";
        }
      }
    }
  '';

  # Launch the datetime widget alongside Noctalia
  wayland.windowManager.hyprland.settings.exec-once = [
    "qs -c noctalia-shell" # Your main Noctalia shell
    "qs -c datetime-widget" # Your datetime widget
  ];
}
