{
  config,
  pkgs,
  ...
}: let
  # Create the datetime widget plugin following Noctalia's structure
  # DateTime widget plugin
  # DateTime widget plugin
  # DateTime widget plugin
  # DateTime widget plugin
  datetime-widget-plugin = pkgs.stdenv.mkDerivation {
    name = "noctalia-datetime-widget";

    dontUnpack = true;
    installPhase = ''
            mkdir -p $out

            # Create DesktopWidget.qml following Noctalia's structure
            cat > $out/DesktopWidget.qml << 'EOF'
      import QtQuick
      import QtQuick.Layouts
      import qs.Commons
      import qs.Modules.DesktopWidgets
      import qs.Widgets

      DraggableDesktopWidget {
        id: root

        // Required by Noctalia
        property var pluginApi: null

        // Scaled dimensions
        implicitWidth: Math.round(500 * widgetScale)
        implicitHeight: Math.round(220 * widgetScale)
        width: implicitWidth
        height: implicitHeight

        // No default background
        showBackground: false

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Math.round(12 * widgetScale)

          // Day of week - HUGE RED TEXT FOR TESTING
          NText {
            id: dayText
            Layout.alignment: Qt.AlignHCenter
            color: "#FF0000"  // BRIGHT RED
            pointSize: Math.round(100 * widgetScale)  // HUGE
            font.family: "JetBrains Mono"
            font.letterSpacing: Math.round(12 * widgetScale)
            font.weight: Font.Bold  // BOLD
          }

          // Date only - no time
          NText {
            id: dateText
            Layout.alignment: Qt.AlignHCenter
            color: "#00FF00"  // BRIGHT GREEN
            pointSize: Math.round(30 * widgetScale)  // BIGGER
            font.family: "JetBrains Mono"
            font.letterSpacing: Math.round(3 * widgetScale)
            font.weight: Font.Bold
          }

          // TIME REMOVED - SHOULD BE GONE
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
          // NO TIME UPDATE
        }
      }
      EOF

            # Create manifest.json with proper structure
            cat > $out/manifest.json << EOF
      {
        "id": "datetime-widget",
        "name": "DateTime Widget",
        "description": "Retro-styled date and time display",
        "version": "1.0.0",
        "minNoctaliaVersion": "3.6.0",
        "author": "rock",
        "license": "MIT",
        "tags": ["Desktop"],
        "entryPoints": {
          "desktopWidget": "DesktopWidget.qml"
        },
        "metadata": {
          "defaultSettings": {}
        }
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
