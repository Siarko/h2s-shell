import QtQuick
import qs.api

// The fixture's element that takes clicks, on a Wi-Fi row's name line: a public PointerArea
// over it, each click told to its main by the row's SSID — the click is the element's, the
// row stays as it was
Rectangle {
    id: clicker

    property var module: null
    property var context: null

    objectName: "anchors-popup-rows:Clicker"
    implicitWidth: 16
    implicitHeight: 10
    color: area.lit ? Api.theme.surfaceHover : Api.theme.surface

    PointerArea {
        id: area
        centred: false
        anchors.fill: parent
        onClicked: clicker.module?.main?.clicked(clicker.context?.ssid ?? "")
    }
}
