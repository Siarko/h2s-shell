import QtQuick
import qs.api

// The fixture's wide element on a Wi-Fi row's name line: wider than the place lets it be
Rectangle {
    property var module: null
    property var context: null

    objectName: "anchors-popup-rows:Wide"
    implicitWidth: 400
    implicitHeight: 10
    color: Api.theme.accent
}
