import QtQuick
import qs.singletons

// The frame a module's settings page is shown in (the settings window's, and the test kit's
// pageFrame): the page's margins and scrolling are the frame's — the page, its child (a
// ColumnLayout), is laid out at the frame's inner width and scrolled by its implicitHeight —
// and over it, outside the scrolling, the layer its public SidePanels show in
// (SidePanelHost). The frame is known to ApiElements by identity while it exists, which is
// how a SidePanel inside finds the layer.
//
//   ModulePageFrame { anchors.fill: parent; ModuleContribution { … } }
Item {
    id: root

    // The page, written inside (or created with `body` as its parent)
    default property alias page: _body.data
    readonly property Item body: _body
    readonly property alias sidePanelHost: _host
    // A modal host of its own over the frame, the place of the page's questions (module.ask):
    // for a frame in no Settings window (the test kit's), whose window's host is the place
    property bool ownQuestions: false
    readonly property var modalHost: _questions.item

    clip: true

    Flickable {
        id: _scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: _body.implicitHeight + 2 * Theme.settings.pageMargin
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: _body
            x: Theme.settings.pageMargin
            y: Theme.settings.pageMargin
            width: _scroller.width - 2 * Theme.settings.pageMargin
            implicitHeight: {
                let tallest = 0;
                for (const child of children)
                    tallest = Math.max(tallest, child.implicitHeight);
                return tallest;
            }
            // Each page as wide as the frame's inside
            onChildrenChanged: {
                for (const child of children)
                    child.width = Qt.binding(() => _body.width);
            }
        }
    }

    SidePanelHost {
        id: _host
        anchors.fill: parent
    }

    Loader {
        id: _questions
        anchors.fill: parent
        active: root.ownQuestions
        sourceComponent: SettingsModalHost {
            placeRoot: root
        }
    }

    Component.onCompleted: ApiElements.addFrame(root, _host)
    Component.onDestruction: ApiElements.removeFrame(root)
}
