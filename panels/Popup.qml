import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.components
import qs.singletons

// Lazily-loaded popup panel that opens from the bar by a triggering element, away from
// the bar's edge — down, up, or sideways from a bar at a side — centred on it.
//
// Laid out in the bar's frame (BarGeometry): along the bar, and across it from its desktop
// side, as for a bar at the top; put on screen at the end. The background's shapes are
// drawn in the frame and transformed; the panel inside is placed, never turned.
LazyLoader {
    id: popupLoader
    active: false

    // The bar's screen: the popup's window is put on it. Left to the compositor, it went
    // to the screen with the focus, which need not be the bar's
    property ShellScreen barScreen: null
    // The screen edge the bar stands at: the popup opens away from it
    property string barEdge: "top"
    readonly property bool _vertical: BarGeometry.isVertical(barEdge)
    // The bar moving to another edge with the popup open: the popup goes at once. Its window
    // and panel were laid out for the old edge, and turned in place they came apart — the
    // panel scrambled, and no popup opened on that screen after. The next one is made anew.
    // Just after: the edge changes while Profiles resolves, and the popup closing reports
    // its panel closed to Profiles (a binding loop, done at once).
    onBarEdgeChanged: Qt.callLater(() => {
        popupLoader.closing = false;
        popupLoader.active = false;
    })

    // Where the triggering element is along the bar, and its length that way
    required property int popupPosition
    required property int popupLength
    // Emitted when the popup becomes visible, used for cross-screen coordination
    signal opened

    // True while the close animation is running; prevents immediate destruction
    property bool closing: false
    // When true, the popup stays open until explicitly toggled (click-to-close)
    property bool persistent: false
    // Opened by a tap on a touch screen. Such a popup closes on a tap outside it and the
    // bar (OutsideTapCatcher), and takes the keyboard only after a tap on a text field
    // (TouchTextFocus). One opened by the mouse does neither: it may stay open while you
    // work elsewhere, and takes the keyboard while the mouse is over it.
    property bool touchOpened: false
    // Whether the last tap in a popup opened by touch was on a text field: the popup
    // holds the keyboard exclusively until a tap anywhere else
    property bool _typing: false
    // The bar's window: a tap on it does not close a popup opened by touch, so another
    // cell can be tapped
    property var barWindow: null
    // Which content the popup shows: a widget type, whose panel WidgetRegistry gives, or
    // one of the contents wired here ("tray-menu", "notifications" — see _componentMap)
    property string contentType: "calendar"
    // What the content needs to know beyond its type, given to open(): the tray menu's
    // { menu, direction }. Kept per popup, so each screen's bar has its own.
    property var contentData: null

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

    // A hover popup closes a moment after the pointer leaves it, and opening it again in
    // that moment keeps it: the pointer going back from the popup onto its cell reopens it
    // (the cell passes hover on after 60 ms — BarWidget), which used to happen in the same
    // instant as the leave, before the close could start
    property Timer _hoverClose: Timer {
        interval: 120
        onTriggered: popupLoader.close()
    }

    // Start the close animation instead of immediately deactivating
    function close() {
        if (!popupLoader.active || popupLoader.closing)
            return;
        // Not shown yet (its first frame still being rendered): nothing to slide away, and
        // its slide, still at rest, would never run and end it — it stayed open for good,
        // its cell lit and deaf to clicks
        if (!popupLoader.item || !popupLoader.item.showPopup) {
            popupLoader.active = false;
            return;
        }
        popupLoader.closing = true;
    }

    // Open the popup aligned to the given element
    function open(element, persistent = false, contentType = "calendar", contentData = null, byTouch = false) {
        _hoverClose.stop();
        popupLoader.persistent = persistent;
        popupLoader.touchOpened = byTouch;
        popupLoader._typing = false;
        popupLoader.contentType = contentType;
        popupLoader.contentData = contentData;
        const mapped = element.mapToItem(null, 0, 0);
        popupLoader.popupPosition = _vertical ? mapped.y : mapped.x;
        popupLoader.popupLength = _vertical ? element.height : element.width;
        popupLoader.closing = false;
        // New content in an open popup too (another tray icon's menu): its size settling
        // is the popup's to animate, not the panel animating (_contentResized)
        if (popupLoader.item)
            popupLoader.item._contentArrived = Date.now();
        popupLoader.active = true;
        popupLoader.opened();
    }

    // Popup window over the whole screen from the bar's edge; the popup is placed in it
    PanelWindow {
        id: popup
        screen: popupLoader.barScreen

        anchors {
            top: popupLoader.barEdge !== "bottom"
            bottom: popupLoader.barEdge === "bottom"
            left: popupLoader.barEdge !== "right"
            right: popupLoader.barEdge === "right"
        }

        property int panelRadius: Theme.popup.radius
        property int paddingSide: Theme.popup.contentPadding
        property int paddingTop: Theme.popup.contentPadding
        property int paddingBottom: Theme.popup.contentPadding
        // Switching to another panel, the popup keeps the old one's size until the new one
        // has rendered once (see _switchContent)
        property bool _holding: false
        property int _heldWidth: 0
        property int _heldHeight: 0
        property int contentWidth: _holding ? _heldWidth : contentLoader.item ? contentLoader.item.implicitWidth : 0
        property int contentHeight: _holding ? _heldHeight
            : contentLoader.item ? Math.min(contentLoader.item.implicitHeight, _keyboardLimit) : 0

        // ---- Keeping clear of an on-screen keyboard ----
        // While one is up on this screen, a popup by a bar at the top is cut to end above it
        // (ScreenKeyboard), its content moved within it: by itself to keep the focused field
        // in sight, or dragged / wheeled. A bar at the bottom is under the keyboard itself,
        // and popups by a bar at a side are not cut yet (docs/plans/touch.md).
        readonly property real _keyboardLimit: {
            if (!ScreenKeyboard.visible || edge !== "top" || ScreenKeyboard.screenName !== popup.screen?.name)
                return Infinity;
            const keyboardTop = ScreenKeyboard.top - (popup.screen?.y ?? 0);
            return Math.max(80, keyboardTop - _screenOffset.y - paddingTop - paddingBottom - _screenGap);
        }
        readonly property real _overflow: contentLoader.item && isFinite(_keyboardLimit)
            ? Math.max(0, contentLoader.item.implicitHeight - _keyboardLimit) : 0
        property real _keyboardScroll: 0
        on_OverflowChanged: {
            _keyboardScroll = Math.min(_keyboardScroll, _overflow);
            Qt.callLater(_revealFocus);
        }

        // The focused field in sight within the part shown, with a little room around it
        function _revealFocus() {
            if (_overflow <= 0 || !contentLoader.item)
                return;
            const focused = contentLoader.Window.activeFocusItem;
            if (!focused || focused.cursorPosition === undefined)
                return;
            const inContent = focused.mapToItem(contentLoader, 0, 0);
            const room = 12;
            let scroll = _keyboardScroll;
            if (inContent.y - room < scroll)
                scroll = inContent.y - room;
            else if (inContent.y + focused.height + room > scroll + _keyboardLimit)
                scroll = inContent.y + focused.height + room - _keyboardLimit;
            _keyboardScroll = Math.max(0, Math.min(_overflow, scroll));
        }
        readonly property Item _focusedItem: contentLoader.Window.activeFocusItem
        on_FocusedItemChanged: Qt.callLater(_revealFocus)
        readonly property string edge: popupLoader.barEdge
        // The content's size along the bar and across it
        readonly property int _contentAlong: popupLoader._vertical ? contentHeight : contentWidth
        readonly property int _contentAcross: popupLoader._vertical ? contentWidth : contentHeight
        // How far the popup reaches from the bar, with its paddings
        property int popupAcross: _contentAcross + paddingTop + paddingBottom
        // The most height content can take. Below or above the bar: still ending a gap
        // short of the screen's far edge, the popup opening at the bar's desktop side and
        // adding its paddings. Beside a bar at a side: the bar's length between its
        // desktop-side corners, less the popup's ears. Given to the panel as its
        // `availableHeight`, if it has one.
        readonly property int _screenGap: 16
        readonly property real availableContentHeight: popupLoader._vertical
            ? (barEnd - barCornerEnd) - (barStart + barCornerStart) - 2 * panelRadius - 2 * paddingSide
            : BarGeometry.popupContentLength(popup.screen.height, Theme.bar, paddingTop + paddingBottom, _screenGap)
        // The content's height as shown: following the popup's size as it moves to another
        // panel's, where the panel's own height is already the new one. A panel that sets
        // `fitsShownHeight` is given this as its height, so what it holds to its edges stays
        // in sight while the popup resizes (the music panel), instead of being cut.
        readonly property real shownContentHeight: popupLoader._vertical
            ? shownLength - 2 * paddingSide - 2 * panelRadius
            : clipWrapper.across - paddingTop - paddingBottom
        // The popup animates its size to a panel's — another panel's, or this one's after a
        // jump — but not while the panel animates its own size (an expander opening): then
        // it takes the panel's size as it comes, at the panel's own speed. Chasing a moving
        // size with an animation of its own restarted it at every frame, and the popup came
        // in late. The animated sizes go on in the background meanwhile (an animation in a
        // Behavior cannot be stopped), and have caught up when the panel stops.
        property bool _contentAnimating: false
        property real _lastContentResize: 0
        // Quick size changes in a row; one or two are a panel rebuilding (a tray menu goes
        // to nothing and back as another icon's replaces it), not animating
        property int _quickResizes: 0
        // Since opening or a switch to another panel: the new panel settling into its size
        // then is part of the popup's own animation, not the panel animating
        property real _contentArrived: 0
        function _contentResized() {
            const now = Date.now();
            const settling = now - _contentArrived < Theme.duration("popup") + Theme.duration("popupResize");
            // Nothing at all is a panel being rebuilt, not a step of an animation
            const rebuilding = contentWidth === 0 || contentHeight === 0;
            _quickResizes = !rebuilding && now - _lastContentResize < 50 ? _quickResizes + 1 : 0;
            _lastContentResize = now;
            // Sizes coming frame after frame: the panel is animating
            if (showPopup && !_holding && !settling && _quickResizes >= 2) {
                _contentAnimating = true;
                _contentStill.restart();
            }
        }
        // Once for a change of both at once, as one resize
        onContentWidthChanged: Qt.callLater(_contentResized)
        onContentHeightChanged: Qt.callLater(_contentResized)
        Timer {
            id: _contentStill
            // As long as the animated sizes take to catch up behind it (they restart at
            // each resize): then they are where the panel is, and nothing jumps back
            interval: Math.max(Theme.duration("popup"), Theme.duration("popupResize")) + 50
            onTriggered: popup._contentAnimating = false
        }

        // Opening, closing, or moving to another panel's size: given to the panel as its
        // `popupAnimating`, if it has one (the music panel cuts its middle meanwhile)
        readonly property bool animating: clipWrapper.reveal < 1 || _holding
            || Math.abs(clipWrapper.across - popupAcross) >= 0.5 || Math.abs(shownLength - totalLength) >= 0.5
        // Its length along the bar: the content, its paddings and an ear at each end
        property int totalLength: _contentAlong + (paddingSide * 2) + panelRadius * 2
        // The length on screen: follows totalLength with an animation when switching
        // between popups of different sizes, so it does not jump
        readonly property real shownLength: _contentAnimating ? totalLength : _animatedLength
        property real _animatedLength: totalLength
        Behavior on _animatedLength {
            enabled: popup.showPopup
            NumberAnimation { duration: Theme.duration("popupResize"); easing: Theme.curve("popupResize") }
        }
        // The bar's own extent along the screen and the corners on its desktop side (the
        // theme's bottom ones, at any edge): it need not reach the screen's ends
        function _layout(name) {
            return Theme.bar[name] ?? 0
        }
        readonly property real barStart: _layout("leftMargin")
        readonly property real barEnd: (popupLoader._vertical ? popup.screen.height : popup.screen.width) - _layout("rightMargin")
        readonly property real barCornerStart: BarGeometry.radius(_layout("radiusBottomLeft"), _layout("barHeight"))
        readonly property real barCornerEnd: BarGeometry.radius(_layout("radiusBottomRight"), _layout("barHeight"))

        // A popup at the very end of the bar drops its curve there, its straight edge
        // continuing the bar's end; anywhere else it curves into the bar
        property bool roundingStart: clipWrapper.position > popup.barStart
        property bool roundingEnd: clipWrapper.position + popup.shownLength < popup.barEnd

        implicitWidth: popup.screen.width
        implicitHeight: popup.screen.height

        property bool showPopup: false
        // Deferred so the panel and its Repeaters are created on the main event loop, after
        // this window's incubation — see "The Repeater crash" in docs/ARCHITECTURE.md
        Component.onCompleted: Qt.callLater(() => {
            content.loadContent()
            popup._whenRendered(() => {
                popup._contentArrived = Date.now()
                popup.showPopup = true
            })
        })

        // The first frame with new content is slow — text is laid out and its glyphs
        // prepared — and took 30 ms for the calendar, a third of the opening animation.
        // So new content is rendered once first, hidden, and animations start on the
        // frame after: opening at zero height, switching under the old panel's size.
        function _whenRendered(action) {
            _firstRender.action = action
            _firstRender.ticks = 0
            _firstRender.running = true
        }

        FrameAnimation {
            id: _firstRender
            property var action: null
            property int ticks: 0
            onTriggered: {
                // The first tick comes before the content's first frame, the second after it
                if (++ticks < 2)
                    return
                running = false
                const action = _firstRender.action
                _firstRender.action = null
                action()
            }
        }

        // Another widget's popup while this one is open: the new panel appears as the
        // popup moves to its size, rather than first jumping in and then being resized
        function _switchContent() {
            // Called as the content type changes, before open() moves popupPosition
            _heldWidth = contentWidth
            _heldHeight = contentHeight
            clipWrapper._heldTarget = clipWrapper._target
            _holding = true
            contentLoader.opacity = 0
            content.loadContent()
            _whenRendered(() => {
                popup._contentArrived = Date.now()
                popup._holding = false
                _contentFadeIn.restart()
            })
        }

        // The keyboard: under the mouse on demand, as before. Opened by touch: none, and
        // exclusive from a tap on a text field to a tap anywhere else (TouchTextFocus).
        WlrLayershell.keyboardFocus: popupLoader.touchOpened
            ? (popupLoader._typing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None)
            : hoverHandler.hovered ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

        // Where this window lies on the screen: as large as the screen, put by the
        // compositor beyond the bar's reserved space (the window keeps clear of exclusive
        // zones) plus its margin there — measured on the Framework, a top bar: y = 37
        readonly property int _fromEdge: Theme.bar.reservedSpace
        readonly property point _screenOffset: Qt.point(
            edge === "left" ? _fromEdge + margins.left : edge === "right" ? -(_fromEdge + margins.right) : 0,
            edge === "top" ? _fromEdge + margins.top : edge === "bottom" ? -(_fromEdge + margins.bottom) : 0)

        // A tap outside the popup and the bar closes one opened by touch
        OutsideTapCatcher {
            visible: popupLoader.touchOpened && !popupLoader.closing
            screen: popupLoader.barScreen
            popupHole: Qt.rect(clipWrapper.x + popup._screenOffset.x, clipWrapper.y + popup._screenOffset.y,
                               clipWrapper.width, clipWrapper.height)
            barHole: {
                const bar = popupLoader.barWindow;
                if (!bar)
                    return Qt.rect(0, 0, 0, 0);
                const screenWidth = popupLoader.barScreen?.width ?? 0;
                const screenHeight = popupLoader.barScreen?.height ?? 0;
                switch (popup.edge) {
                case "bottom": return Qt.rect(0, screenHeight - bar.height, screenWidth, bar.height);
                case "left": return Qt.rect(0, 0, bar.width, screenHeight);
                case "right": return Qt.rect(screenWidth - bar.width, 0, bar.width, screenHeight);
                default: return Qt.rect(0, 0, screenWidth, bar.height);
                }
            }
            onTapped: popupLoader.close()
        }

        // Align to the bar's desktop side, not the edge of its reserved space
        margins.top: edge === "top" ? BarGeometry.popupMargin(Theme.bar) : 0
        margins.bottom: edge === "bottom" ? BarGeometry.popupMargin(Theme.bar) : 0
        margins.left: edge === "left" ? BarGeometry.popupMargin(Theme.bar) : 0
        margins.right: edge === "right" ? BarGeometry.popupMargin(Theme.bar) : 0
        color: "transparent"

        mask: Region {
            item: clipWrapper
        }

        // Clip wrapper — what of the popup is out from under the bar, cut at the bar's edge;
        // the window itself never resizes
        Item {
            id: clipWrapper
            objectName: "popupBody"
            // Centred on its widget along the bar, but kept by the bar — not the screen,
            // which the bar may not reach. Where the bar's corner is rounded the popup stops
            // short of it, keeping its curve; by a square corner it may run to the end.
            readonly property real _min: popup.barStart + popup.barCornerStart
            readonly property real _max: popup.barEnd - popup.barCornerEnd - popup.shownLength
            // The target is limited by the length the popup is going to have, not the one it
            // has mid-animation: a target that moved every frame restarted the position's
            // animation every frame, and the popup crawled after its size
            readonly property real _maxTarget: popup.barEnd - popup.barCornerEnd - popup.totalLength
            property real _heldTarget: 0
            readonly property real _target: {
                if (popup._holding)
                    return _heldTarget;
                var raw = popupLoader.popupPosition + (popupLoader.popupLength / 2) - (popup.totalLength / 2);
                return Math.max(_min, Math.min(raw, _maxTarget));
            }

            // Moving between popups of different sizes, the end that stays put is the one
            // the popup is held against: the far end at the bar's end, the near one at its
            // start, else the middle. All three are animated; the position follows the one
            // that applies to the new target, so a shorter popup at the bar's end keeps its
            // far end instead of opening at the old near end and sliding over. The bar's
            // limits apply to every frame, since the length changes at once.
            readonly property string _anchor: _target >= _maxTarget - 0.5 ? "end"
                : _target <= _min + 0.5 ? "start" : "centre"
            property real _start: _target
            property real _end: _target + popup.totalLength
            property real _centre: _target + popup.totalLength / 2
            // With the length animating too, the held end stays put while the other moves
            readonly property real _anchored: popup._contentAnimating ? _target
                : _anchor === "end" ? _end - popup.shownLength
                : _anchor === "start" ? _start : _centre - popup.shownLength / 2
            // On whole pixels at rest: at half a pixel (an odd width centred, e.g. the
            // calendar's 551) the curved corners and the panel met mid-pixel, and smoothing
            // left a faint seam between them. Not while moving: rounding every frame moved
            // the popup in steps, and at the bar's end changed when it reached the end and
            // its ear went, so it jumped.
            readonly property real _exact: Math.max(_min, Math.min(_anchored, _max))
            // Along the bar: set here rather than bound, since a binding that read both the
            // position and whether it had settled was changed by its own evaluation (the
            // change handler below runs inside it), a binding loop
            property real position: 0
            Component.onCompleted: position = Math.round(_exact)
            on_ExactChanged: {
                position = _exact;
                _settle.restart();
            }
            Timer {
                id: _settle
                interval: 60
                onTriggered: clipWrapper.position = Math.round(clipWrapper._exact)
            }
            // How far the open popup reaches from the bar: following a new panel's size when
            // switching, the content held against the bar and the far side moving
            readonly property real across: popup._contentAnimating ? popup.popupAcross : _animatedAcross
            property real _animatedAcross: popup.popupAcross
            Behavior on _animatedAcross {
                enabled: popup.showPopup
                NumberAnimation { duration: Theme.duration("popup"); easing: Theme.curve("popupOpen") }
            }
            // Opening and closing: the whole popup slides out from under the bar, and back
            // under it — 0 hidden, 1 out
            property real reveal: popup.showPopup && !popupLoader.closing ? 1 : 0
            Behavior on reveal {
                NumberAnimation {
                    duration: Theme.duration("popup")
                    easing: Theme.curve(popupLoader.closing ? "popupClose" : "popupOpen")
                    onRunningChanged: {
                        if (!running && popupLoader.closing) {
                            popupLoader.closing = false;
                            popupLoader.active = false;
                        }
                    }
                }
            }
            // How much of it is out: what is on screen, cut at the bar's edge
            readonly property real visibleAcross: reveal * across
            // The ears stay by the bar until only the popup's rounded far end is out, then go
            // under it with that end: negative, how far they are pushed under
            readonly property real earShift: Math.min(0, visibleAcross - popup.panelRadius)

            readonly property var _placed: BarGeometry.fromBarFrame(popup.edge,
                { along: position, across: 0, alongLength: popup.shownLength, acrossLength: visibleAcross },
                popup.width, popup.height)
            x: _placed.x
            y: _placed.y
            width: _placed.width
            height: _placed.height
            clip: true

            Behavior on _start {
                enabled: popup.showPopup
                NumberAnimation { duration: Theme.duration("popupResize"); easing: Theme.curve("popupResize") }
            }
            Behavior on _end {
                enabled: popup.showPopup
                NumberAnimation { duration: Theme.duration("popupResize"); easing: Theme.curve("popupResize") }
            }
            Behavior on _centre {
                enabled: popup.showPopup
                NumberAnimation { duration: Theme.duration("popupResize"); easing: Theme.curve("popupResize") }
            }

            // The popup's body: the panel and its background, sliding as one
            Item {
                id: rect
                // At least as far across as the open popup while that animates: shrinking to
                // a smaller panel, the background staying at the old size until the clip has
                // closed over it is what makes the shrink visible (it jumped before). Open,
                // held against the bar; opening and closing, pushed under it by what is not
                // out yet.
                readonly property real across: Math.max(popup.popupAcross, clipWrapper.across)
                readonly property real _shift: -(1 - clipWrapper.reveal) * clipWrapper.across
                readonly property var _placed: BarGeometry.fromBarFrame(popup.edge,
                    { along: 0, across: _shift, alongLength: popup.shownLength, acrossLength: across },
                    clipWrapper.width, clipWrapper.height)
                x: _placed.x
                y: _placed.y
                width: _placed.width
                height: _placed.height

                Rectangle {
                    id: content
                    // Floating lists (FloatingList) open over the panel here, inside the
                    // popup, where clicks reach them
                    objectName: "overlayHost"
                    // Between the ears, as far across as the background
                    readonly property real _startInset: popup.roundingStart ? popup.panelRadius : 0
                    readonly property real _endInset: popup.roundingEnd ? popup.panelRadius : 0
                    readonly property var _placed: BarGeometry.fromBarFrame(popup.edge,
                        { along: _startInset, across: 0, alongLength: popup.shownLength - _startInset - _endInset,
                          acrossLength: rect.across },
                        rect.width, rect.height)
                    x: _placed.x
                    y: _placed.y
                    width: _placed.width
                    height: _placed.height

                    // Rounded on the side away from the bar, at the ends that curve into it
                    readonly property var _corners: BarGeometry.popupCorners(popup.edge, popup.roundingStart,
                        popup.roundingEnd, popup.panelRadius)
                    topLeftRadius: _corners.topLeft
                    topRightRadius: _corners.topRight
                    bottomLeftRadius: _corners.bottomLeft
                    bottomRightRadius: _corners.bottomRight

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

                    // Held against the bar, centred along it: the background may reach
                    // further than the content while it shrinks
                    Loader {
                        id: contentLoader
                        anchors.horizontalCenter: popupLoader._vertical ? undefined : parent.horizontalCenter
                        anchors.verticalCenter: popupLoader._vertical ? parent.verticalCenter : undefined
                        anchors.top: popup.edge === "top" ? parent.top : undefined
                        // Moved up within the popup while it is cut short by an on-screen keyboard
                        anchors.topMargin: popup.paddingTop - popup._keyboardScroll
                        anchors.bottom: popup.edge === "bottom" ? parent.bottom : undefined
                        anchors.bottomMargin: popup.paddingBottom
                        // The padding by the bar across it, as popupAcross counts it
                        anchors.left: popup.edge === "left" ? parent.left : undefined
                        anchors.leftMargin: popup.paddingTop
                        anchors.right: popup.edge === "right" ? parent.right : undefined
                        anchors.rightMargin: popup.paddingTop
                        onLoaded: {
                            // Its own height, or the shown one (shownContentHeight)
                            contentLoader.height = item.fitsShownHeight === true
                                ? Qt.binding(() => Math.max(0, popup.shownContentHeight))
                                : Qt.binding(() => contentLoader.item ? contentLoader.item.implicitHeight : 0)
                            if (typeof item.availableHeight !== "undefined")
                                item.availableHeight = Qt.binding(() => popup.availableContentHeight)
                            if (typeof item.popupAnimating !== "undefined")
                                item.popupAnimating = Qt.binding(() => popup.animating)
                        }
                    }

                    // A click anywhere in the popup takes the focus from a field
                    FocusReleaser {}

                    // Cut short by an on-screen keyboard: its content moved by a drag or the wheel
                    DragHandler {
                        target: null
                        enabled: popup._overflow > 0
                        xAxis.enabled: false
                        property real _scrollAtStart: 0
                        onActiveChanged: if (active) _scrollAtStart = popup._keyboardScroll
                        onTranslationChanged: popup._keyboardScroll = Math.max(0, Math.min(popup._overflow, _scrollAtStart - translation.y))
                    }
                    WheelHandler {
                        enabled: popup._overflow > 0
                        onWheel: event => {
                            popup._keyboardScroll = Math.max(0, Math.min(popup._overflow, popup._keyboardScroll - event.angleDelta.y / 2));
                        }
                    }

                    NumberAnimation {
                        id: _contentFadeIn
                        target: contentLoader
                        property: "opacity"
                        to: 1
                        duration: Theme.duration("fade")
                        easing: Theme.curve("fade")
                    }

                    Connections {
                        target: popupLoader
                        function onContentTypeChanged() {
                            popup._switchContent()
                        }
                    }

                    Component {
                        id: trayMenuComponent
                        TrayMenu {
                            request: popupLoader.contentData
                            onCloseRequested: popupLoader.close()
                        }
                    }

                    Component {
                        id: notificationsComponent
                        NotificationPanel {
                            onCloseRequested: popupLoader.close()
                        }
                    }
                }
            }

            // The ears and the border, drawn as for a popup below a bar — x along it, y away
            // from it, as far as the popup is out — and put on screen by the frame's
            // transform. Apart from the body: the ears keep their place by the bar while
            // the body slides (earShift).
            Item {
                id: _frame
                width: popup.shownLength
                height: clipWrapper.visibleAcross
                transform: Matrix4x4 {
                    matrix: {
                        const matrix = BarGeometry.frameMatrix(popup.edge, clipWrapper.width, clipWrapper.height);
                        return Qt.matrix4x4(...matrix);
                    }
                }

                PopupCurve {
                    id: leftCurve
                    side: "left"
                    radius: popup.panelRadius
                    x: 0
                    y: clipWrapper.earShift
                    visible: popup.roundingStart
                }

                PopupCurve {
                    id: rightCurve
                    side: "right"
                    radius: popup.panelRadius
                    x: parent.width - width
                    y: clipWrapper.earShift
                    visible: popup.roundingEnd
                }

                // The popup's border (popup.borderWidth, popupBorder): one line around its
                // shape, open where it joins the bar — down the curve of each ear, the side,
                // the rounded far end — so it carries on from the bar's border, which the
                // popup covers there. Drawn half a line inside the edge, so all of it shows;
                // the ears where they are, the far end where the body has got to.
                Shape {
                    id: _outline
                    readonly property real lineWidth: Theme.popup.borderWidth
                    visible: lineWidth > 0
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    readonly property string _path: {
                        const d = lineWidth / 2;
                        const radius = popup.panelRadius;
                        const width = _frame.width;
                        const height = Math.max(clipWrapper.visibleAcross, lineWidth);
                        const shift = clipWrapper.earShift;
                        const left = popup.roundingStart;
                        const right = popup.roundingEnd;
                        // The ear's curve, offset inwards: a circle centred on the bar's edge
                        // beside the popup, its radius grown by half the line
                        const earRadius = radius + d;
                        // With a border on the bar, the line starts along the middle of the
                        // bar's border, from the popup's edge, and turns into the ear: the
                        // popup covers that piece of the bar's border, and this carries it on
                        // into its own. Without one, it starts at the bar's edge.
                        const joinY = Math.min(Theme.bar.borderWidth / 2, radius);
                        const earTop = Math.sqrt(Math.max(0, earRadius * earRadius - (radius - joinY) * (radius - joinY)));
                        const corner = Math.max(0, radius - d);
                        const sideLeft = left ? radius + d : d;
                        const sideRight = right ? width - radius - d : width - d;
                        const bottom = height - d;
                        let path = left ? (joinY > 0 ? `M 0 ${joinY + shift} L ${earTop} ${joinY + shift}` : `M ${earTop} ${shift}`)
                                + ` A ${earRadius} ${earRadius} 0 0 1 ${sideLeft} ${radius + shift}`
                                        : `M ${sideLeft} 0`;
                        if (left)
                            path += ` L ${sideLeft} ${bottom - corner} A ${corner} ${corner} 0 0 0 ${sideLeft + corner} ${bottom}`;
                        else
                            path += ` L ${sideLeft} ${bottom}`;
                        if (right)
                            path += ` L ${sideRight - corner} ${bottom} A ${corner} ${corner} 0 0 0 ${sideRight} ${bottom - corner}`
                                + ` L ${sideRight} ${radius + shift} A ${earRadius} ${earRadius} 0 0 1 ${width - earTop} ${joinY + shift}`
                                + (joinY > 0 ? ` L ${width} ${joinY + shift}` : "");
                        else
                            path += ` L ${sideRight} ${bottom} L ${sideRight} 0`;
                        return path;
                    }

                    ShapePath {
                        strokeColor: Theme.popupBorder
                        strokeWidth: _outline.lineWidth
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: _outline._path }
                    }
                }
            }

            // Text fields under touch: the keyboard for a field, none after (the window's
            // keyboardFocus above)
            TouchTextFocus {
                watching: popupLoader.touchOpened
                onFieldTapped: onField => { popupLoader._typing = onField; }
            }

            // Close the popup when the mouse leaves the visible area
            HoverHandler {
                id: hoverHandler
                onHoveredChanged: {
                    if (hovered)
                        popupLoader._hoverClose.stop();
                    else if (!popupLoader.persistent)
                        popupLoader._hoverClose.restart();
                }
            }
        }
    }
}
