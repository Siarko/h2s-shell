import QtQuick
import QtQuick.Shapes
import qs.singletons

Rectangle {
    id: root

    property string side: "left"
    property int radius: Theme.popup.radius
    property color curveColor: Theme.popupBackground

    implicitWidth: radius
    implicitHeight: radius
    color: "transparent"

    Shape {
        width: parent.width
        height: parent.height
        preferredRendererType: Shape.CurveRenderer
        visible: root.side === "left"

        ShapePath {
            strokeWidth: 0
            fillColor: root.curveColor

            startX: 0
            startY: 0

            PathArc {
                x: root.radius
                y: root.radius
                radiusX: root.radius
                radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.radius
                y: 0
            }
        }
    }

    Shape {
        width: parent.width
        height: parent.height
        preferredRendererType: Shape.CurveRenderer
        visible: root.side === "right"

        ShapePath {
            strokeWidth: 0
            fillColor: root.curveColor

            startX: 0
            startY: root.radius

            PathArc {
                x: root.radius
                y: 0
                radiusX: root.radius
                radiusY: root.radius
                direction: PathArc.Clockwise
            }
            PathLine {
                x: 0
                y: 0
            }
            PathLine {
                x: 0
                y: root.radius
            }
        }
    }
}
