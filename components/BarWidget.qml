import QtQuick
import QtQuick.Layouts
import qs.singletons

// Reusable interactive bar widget with click and hover signals
Item {
    id: container
    // Key into WidgetRegistry and the widget preset library
    property string widgetType: ""
    property color cellColor: Theme.surface
    // When true, keeps the cell highlighted regardless of hover (e.g. while its popup is open)
    property bool active: false
    // Optional outline around the cell — off by default, so existing widgets are unaffected
    property color borderColor: Theme.capsuleBorder
    property int borderWidth: Theme.capsule.borderWidth
    // False for widgets with several click targets of their own (tray icons, workspace
    // buttons): the cell keeps its size and background but stops taking input, which
    // otherwise lands on its full-size MouseArea above the content
    property bool interactive: true
    // Space between the content and the cell edge, on each side
    property int horizontalPadding: Theme.capsule.horizontalPadding
    // Emitted on click, carries the cell's color
    signal clicked(cellColor: color)
    // Emitted on mouse enter (true) and exit (false)
    signal hover(status: bool)
    // Emitted on scroll wheel
    signal scrolled(delta: real)
    // Emitted on scroll wheen notch change (only on full scroll clicks)
    signal scrollNotch(direction: int)
    // Emitted on middle mouse button click
    signal middleClicked

    Layout.fillHeight: true
    Layout.preferredHeight: 20
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    Layout.minimumWidth: 40
    implicitWidth: contentItem.childrenRect.width + horizontalPadding * 2

    default property alias content: contentItem.data

    property real scrollBuffer: 0
    property real lastScrollAmount: 0

    Rectangle {
        id: rectangle
        radius: Theme.capsule.radius
        anchors.fill: parent
        color: (mouseArea.containsMouse || container.active) ? Theme.surfaceHover : container.cellColor
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        border.color: container.borderColor
        border.width: container.borderWidth
    }

    // Free-standing item for measuring content size without anchoring loops
    Item {
        id: contentItem
        anchors.centerIn: parent
    }

    // Extends 5px below the cell to prevent hover gaps between bar and popup
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: container.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                container.middleClicked();
            else
                container.clicked(container.cellColor);
        }
        onEntered: container.hover(true)
        onExited: container.hover(false)
        onWheel: event => {
            let amount = event.angleDelta.y * (1 / 8) / 14;
            let direction = container.scrollBuffer > 0 ? 1 : -1;
            container.scrolled(amount);
            if (container.lastScrollAmount != 0 && container.lastScrollAmount * amount < 0) {
                container.scrollBuffer = 0;
            }
            container.scrollBuffer += amount;
            container.lastScrollAmount = amount;
            if (Math.abs(container.scrollBuffer) >= 1) {
                container.scrollNotch(direction);
                container.scrollBuffer -= direction;
            }
        }
    }
}
