import QtQuick

MouseArea {
    id: root

    signal scrollY(real amount)
    signal scrollNotchY(int direction)

    property real scrollBufferY: 0
    property real lastScrollAmountY: 0

    property real scrollBufferX: 0
    property real lastScrollAmountX: 0

    onWheel: event => {
        let amount = event.angleDelta.y * (1 / 8) / 14;
        let direction = root.scrollBufferY > 0 ? 1 : -1;
        if (root.lastScrollAmountY != 0 && root.lastScrollAmountY * amount < 0) {
            root.scrollBufferY = 0;
        }
        root.scrollBufferY += amount;
        root.lastScrollAmountY = amount;
        if (Math.abs(root.scrollBufferY) >= 1) {
            root.scrollNotchY(direction);
            root.scrollBufferY -= direction;
        }
    }
}
