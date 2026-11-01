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
    // Emitted on every wheel event, with its movement in notches (fractional)
    signal scrolled(delta: real)
    // Emitted for each whole notch, 1 for up, -1 for down (ScrollNotches)
    signal scrollNotch(direction: int)
    // Emitted on middle mouse button click
    signal middleClicked

    Layout.fillHeight: true
    Layout.preferredHeight: 20
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    Layout.minimumWidth: 40
    // On a bar at a side the cell is as wide as the bar (its Loader sizes it) and as tall
    // as its content, the padding then above and below it
    readonly property bool vertical: BarLayout.vertical
    implicitWidth: vertical ? 0 : contentItem.childrenRect.width + horizontalPadding * 2
    implicitHeight: vertical ? contentItem.childrenRect.height + horizontalPadding * 2 : 0

    default property alias content: contentItem.data

    readonly property ScrollNotches _notches: ScrollNotches {}

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
            container.scrolled(container._notches.notches(event.angleDelta.y));
            const direction = container._notches.feed(event.angleDelta.y);
            if (direction !== 0)
                container.scrollNotch(direction);
        }
    }
}
