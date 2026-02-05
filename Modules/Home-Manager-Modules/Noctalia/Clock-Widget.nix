{
  config,
  pkgs,
  ...
}: let
  # Create the datetime widget plugin following Noctalia's structure
  datetime-widget = pkgs.stdenv.mkDerivation {
    name = "noctalia-datetime-widget";
    src = pkgs.writeTextFile {
      name = "widget.qml";
      text = ''
        import QtQuick
        import Quickshell
        import Quickshell.Wayland

        FloatingWindow {
          id: dateTimeWidget

          width: 400
          height: 200
          color: "transparent"

          Rectangle {
            anchors.fill: parent
            color: "#40000000"
            opacity: 0.3
            radius: 0

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
      '';
    };

    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp $src $out/widget.qml

      cat > $out/manifest.json << EOF
      {
        "id": "datetime-widget",
        "name": "DateTime Widget",
        "description": "Retro-styled date and time display",
        "version": "1.0.0",
        "author": "rock",
        "entry": "widget.qml"
      }
      EOF
    '';
  };
in {
  # Install the font
  home.packages = with pkgs; [
    jetbrains-mono
  ];

  # Install the plugin
  home.file.".config/noctalia/plugins/datetime-widget".source = datetime-widget;
}
