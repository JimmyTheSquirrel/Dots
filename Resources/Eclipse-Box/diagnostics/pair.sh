#!/bin/bash
export ADDON_PROFILE_PATH=/storage/.kodi/userdata/addon_data/plugin.program.moonlight-qt
M="$ADDON_PROFILE_PATH/moonlight-qt"
export HOME="$ADDON_PROFILE_PATH/moonlight-home"
export LD_LIBRARY_PATH="/usr/lib/:$M/lib"
export XDG_RUNTIME_DIR=/var/run
export QT_QPA_PLATFORM=offscreen
export QT_PLUGIN_PATH="$M/lib/qt6/plugins"
export QML_IMPORT_PATH="$M/lib/qt6/qml/"
export QML2_IMPORT_PATH="$M/lib/qt6/qml/"
cd "$M/bin" || exit 1
exec ./moonlight-qt "$@"
