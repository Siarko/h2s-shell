import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.components
import qs.singletons

// Lazily-loaded popup panel that appears below a triggering element.
// Matches the width and horizontal position of the element that triggered it.
LazyLoader {
    id: popupLoader
    active: false

    // Horizontal offset and width inherited from the triggering element
    required property int popupPosition
    required property int popupWidth
    // Emitted when the popup becomes visible, used for cross-screen coordination
    signal opened

    // True while the close animation is running; prevents immediate destruction
    property bool closing: false
    // When true, the popup stays open until explicitly toggled (click-to-close)
    property bool persistent: false
    // Which content to display in the popup ("calendar" or "power")
    property string contentType: "calendar"

    // The panel on screen, reported to Profiles for its "panel.open" fact. Closed from the
    // moment the close animation starts.
    readonly property string _shownPanel: active && !closing ? contentType : ""
    property string _reportedPanel: ""

    on_ShownPanelChanged: {
        if (_reportedPanel !== "")
            Profiles.panelClosed(_reportedPanel);
        _reportedPanel = _shownPanel;
        if (_shownPanel !== "")
            Profiles.panelOpened(_shownPanel);
    }

    Component.onDestruction: {
        if (_reportedPanel !== "")
            Profiles.panelClosed(_reportedPanel);
    }

    // Start the close animation instead of immediately deactivating
    function close() {
        if (popupLoader.active && !popupLoader.closing) {
            popupLoader.closing = true;
        }
    }

    // Open the popup aligned to the given element
    function open(element, persistent = false, contentType = "calendar") {
        popupLoader.persistent = persistent;
        popupLoader.contentType = contentType;
        const mapped = element.mapToItem(null, 0, 0);
        popupLoader.popupPosition = mapped.x;
        popupLoader.popupWidth = element.width;
        popupLoader.closing = false;
        popupLoader.active = true;
        popupLoader.opened();
    }

    // Popup window positioned at the top-left, offset by popupPosition
    PanelWindow {
        id: popup

        anchors {
            top: true
            left: true
        }

        property int panelRadius: 20
        property int paddingSide: 10
        property int paddingTop: 10
        property int paddingBottom: 10
        property int contentWidth: contentLoader.item ? contentLoader.item.implicitWidth : 0
        property int contentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
        property int popupHeight: contentHeight + paddingTop + paddingBottom
        property int totalWidth: contentWidth + (paddingSide * 2) + panelRadius * 2
        // The width on screen: follows totalWidth with an animation when switching
        // between popups of different widths, so it does not jump
        property real shownWidth: totalWidth
        Behavior on shownWidth {
            enabled: popup.showPopup
            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
        }
        // The bar's own extent and bottom corners: it need not reach the screen edges
        function _layout(name) {
            return Profiles.value("bar.layout." + name) ?? 0
        }
        readonly property real barLeft: _layout("leftMargin")
        readonly property real barRight: popup.screen.width - _layout("rightMargin")
        readonly property real barCornerLeft: _layout("radiusBottomLeft") / 100 * (_layout("barHeight") / 2)
        readonly property real barCornerRight: _layout("radiusBottomRight") / 100 * (_layout("barHeight") / 2)

        // A popup at the very end of the bar drops its curve there, its straight edge
        // continuing the bar's end; anywhere else it curves into the bar
        property bool roundingLeft: clipWrapper.x > popup.barLeft
        property bool roundingRight: clipWrapper.x + popup.shownWidth < popup.barRight

        implicitWidth: popup.screen.width
        implicitHeight: popup.screen.height

        property bool showPopup: false
        // Deferred so the panel and its Repeaters are created on the main event loop, after
        // this window's incubation — see "The Repeater crash" in docs/ARCHITECTURE.md
        Component.onCompleted: Qt.callLater(() => {
            content.loadContent()
            popup.showPopup = true
        })

        focusable: hoverHandler.hovered

        // Align to the bar's visual bottom, not the full reserved space
        margins.top: (Profiles.value("bar.layout.topOffset") ?? 0) + (Profiles.value("bar.layout.barHeight") ?? 0)
            - (Profiles.value("bar.layout.reservedSpace") ?? 0)
        margins.left: 0
        color: "transparent"

        mask: Region {
            item: clipWrapper
        }

        // Clip wrapper — animates height; the window itself never resizes
        Item {
            id: clipWrapper
            // Centred under its widget, but kept under the bar — not the screen, which the
            // bar may not reach. Where the bar's corner is rounded the popup stops short of
            // it, keeping its curve; under a square corner it may run to the end.
            readonly property real _minX: popup.barLeft + popup.barCornerLeft
            readonly property real _maxX: popup.barRight - popup.barCornerRight - popup.shownWidth
            readonly property real _targetX: {
                var raw = popupLoader.popupPosition + (popupLoader.popupWidth / 2) - (popup.totalWidth / 2);
                return Math.max(_minX, Math.min(raw, _maxX));
            }

            // Moving between popups of different widths, the edge that stays put is the one
            // the popup is held against: the right edge at the bar's right end, the left at
            // its left end, else the middle. All three are animated; x follows the one that
            // applies to the new target, so a narrower popup at the right end keeps its
            // right edge instead of opening at the old left edge and sliding over. The bar's
            // limits apply to every frame, since the width changes at once.
            readonly property string _anchor: _targetX >= _maxX - 0.5 ? "right"
                : _targetX <= _minX + 0.5 ? "left" : "centre"
            property real _left: _targetX
            property real _right: _targetX + popup.totalWidth
            property real _centre: _targetX + popup.totalWidth / 2
            // With the width animating too, the held edge stays put while the other moves
            readonly property real _anchoredX: _anchor === "right" ? _right - popup.shownWidth
                : _anchor === "left" ? _left : _centre - popup.shownWidth / 2
            x: Math.max(_minX, Math.min(_anchoredX, _maxX))
            width: popup.shownWidth
            height: popup.showPopup && !popupLoader.closing ? popup.popupHeight : 0
            clip: true

            Behavior on _left {
                enabled: popup.showPopup
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }
            Behavior on _right {
                enabled: popup.showPopup
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }
            Behavior on _centre {
                enabled: popup.showPopup
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }

            Behavior on height {
                enabled: true
                NumberAnimation {
                    duration: 100
                    easing.type: popupLoader.closing ? Easing.InQuad : Easing.OutQuad
                    onRunningChanged: {
                        if (!running && popupLoader.closing) {
                            popupLoader.closing = false;
                            popupLoader.active = false;
                        }
                    }
                }
            }

            Rectangle {
                id: rect
                width: popup.shownWidth
                height: popup.popupHeight
                color: "transparent"

                PopupCurve {
                    id: leftCurve
                    side: "left"
                    radius: popup.panelRadius
                    anchors.top: parent.top
                    anchors.left: parent.left
                    visible: popup.roundingLeft
                }

                PopupCurve {
                    id: rightCurve
                    side: "right"
                    radius: popup.panelRadius
                    anchors.top: parent.top
                    anchors.right: parent.right
                    visible: popup.roundingRight
                }

                Rectangle {
                    id: content
                    anchors.top: parent.top
                    anchors.left: popup.roundingLeft ? leftCurve.right : parent.left
                    anchors.right: popup.roundingRight ? rightCurve.left : parent.right
                    implicitHeight: popup.popupHeight

                    bottomLeftRadius: popup.roundingLeft ? popup.panelRadius : 0
                    bottomRightRadius: popup.roundingRight ? popup.panelRadius : 0

                    color: Theme.popupBackground

                    // Contents that need wiring to this popup. Every other content type is a
                    // plain widget panel, loaded from the URL WidgetRegistry gives for it.
                    readonly property var _componentMap: ({
                            "tray-menu": trayMenuComponent,
                            "notifications": notificationsComponent
                        })

                    function loadContent() {
                        const wired = _componentMap[popupLoader.contentType];
                        // Clear both, since the loader is switched between the two kinds
                        contentLoader.sourceComponent = null;
                        contentLoader.source = "";
                        if (wired)
                            contentLoader.sourceComponent = wired;
                        else
                            contentLoader.source = WidgetRegistry.popupPanelUrl(popupLoader.contentType)
                                || WidgetRegistry.popupPanelUrl("calendar");
                    }

                    Loader {
                        id: contentLoader
                        anchors.centerIn: parent
                    }

                    Connections {
                        target: popupLoader
                        function onContentTypeChanged() {
                            content.loadContent()
                        }
                    }

                    Component {
                        id: trayMenuComponent
                        TrayMenu {
                            onCloseRequested: popupLoader.close()
                        }
                    }

                    Component {
                        id: notificationsComponent
                        NotificationPanel {
                            screenHeight: popup.screen.height
                            onCloseRequested: popupLoader.close()
                        }
                    }
                }
            }

            // Close the popup when the mouse leaves the visible area
            HoverHandler {
                id: hoverHandler
                onHoveredChanged: {
                    if (!hovered && !popupLoader.persistent)
                        popupLoader.close();
                }
            }
        }
    }
}
