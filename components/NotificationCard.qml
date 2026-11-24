import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.components.notification
import qs.singletons

// A notification as a card — in the panel, and as a toast: its app, summary, body and
// image, its actions, an inline reply (NotificationReply) and the codes found in it
// (CodeChips); text in it can be selected and copied.
Rectangle {
    id: notifCard

    required property var notification
    property string timestamp: ""
    property bool compactDismiss: false
    // A pin in the header (the centre's entries): pinned, the notification stays on screen as
    // a modal (Toasts.pinToast) until unpinned or dismissed
    property bool pinnable: false
    // The screen a pin puts the notification on: the card's own (the centre's), "" unknown
    property string screenName: QsWindow.window?.screen?.name ?? ""
    // The pin's glyph, tooltip and effect, from whether it is a modal now (ToastRules.pinLook)
    readonly property var pinLook: ToastRules.pinLook(notification !== null && Toasts.isModal(notification.id))
    property int imageMaxHeight: 120
    // From the theme: a card in the panel by default; a toast sets its own
    property int contentPadding: Theme.notificationCard.padding
    property real cornerRadius: Theme.notificationCard.radius
    // A border: none in the panel; a toast sets the theme's
    property int borderWidth: 0
    property color borderColor: Theme.outline
    property color replyBackground: Theme.surfaceSunken

    // At most this many lines of the body show, the rest cut under a fade (a toast); 0: the
    // whole body (the notification centre)
    property int bodyMaxLines: 0
    // The body has more lines than it may show, and is cut; the height it shows
    readonly property bool bodyCut: _body.length > 0 && bodyMaxLines > 0 && _bodyBox.edit.lineCount > bodyMaxLines
    readonly property real bodyShownHeight: _bodyBox.implicitHeight

    // Tab stays inside the card while it has the keyboard (a toast: the HUD's other controls
    // are not the card's)
    property bool keepsTab: false

    property bool timerVisible: false
    // Fraction of the auto-dismiss time left, 1 → 0; the owner runs the countdown
    property real timerProgress: 1.0

    signal dismissRequested()
    // The user's "×" or swipe, just before its dismissRequested — not an action's: a toast
    // dismisses the notification on it, and only leaves after an action
    signal closeClicked()
    // An action ran on a notification that stays after it (resident): its entry stays, so
    // no dismissal is asked — a toast still leaves
    signal actionInvoked()

    // ---- Swiped away with a finger, as on Android (NotificationSwipe) ----
    // Let go far enough, the card goes on out and asks to be dismissed, `swipedAway` set so
    // the owner skips its own slide out
    readonly property bool swiping: _swipeLayer.active
    property bool swipedAway: false

    FocusTrap {
        scope: notifCard
        active: notifCard.keepsTab
    }

    implicitHeight: _contentCol.implicitHeight + contentPadding * 2
    radius: cornerRadius
    // A card that does something when clicked shows it as rows and menu items do: a
    // lighter background under the pointer, and a hand over it — over the text too
    color: _defaultAction && _cardHover.hovered ? Theme.surfaceHover : Theme.surface
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    HoverHandler {
        id: _cardHover
        cursorShape: notifCard._defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // Clicking the header, the text or the image runs the default action. Not the
    // buttons, the reply field or the codes below them: those have their own clicks. A
    // drag across the text selects it instead (it is no tap).
    function _activateDefault() {
        if (!_defaultAction || _dismissPressed)
            return;
        // A click that cleared a selection only clears it — the text took the press first
        if (Date.now() - _selectionClearedAt < 400)
            return;
        Notifications.invokeAction(notification, _defaultAction);
        _afterAction();
    }
    // A resident notification keeps its entry after an action (NotificationRules)
    function _afterAction() {
        if (NotificationRules.dismissAfterAction(notification))
            dismissRequested();
        else
            actionInvoked();
    }
    // The pin's click, as its look says: pinned on screen, or unpinned
    function togglePin() {
        if (!notification)
            return;
        if (pinLook.action === "pin")
            Toasts.pinToast(notification, screenName);
        else
            Toasts.unpinToast(notification.id);
    }

    // The header's dismiss control sits inside a tappable area: its press marks the tap
    // that follows as its own
    property bool _dismissPressed: false
    property real _selectionClearedAt: 0
    // A critical notification is outlined in the error colour, wherever the card is (a
    // toast, the panel, the lock screen) — the toast of one also stays (Toasts)
    readonly property bool _critical: Notifications.isCritical(notification)
    border.width: _critical ? Math.max(borderWidth, Theme.border.selectedWidth) : borderWidth
    border.color: _critical ? Theme.error : borderColor
    clip: true

    // The image's square, cropped thumbnail beside the text
    property int thumbnailSize: 44

    // What the card shows, kept when the notification goes: running an action closes it
    // (unless it is resident), and the card must not empty while it slides away
    property string _appName
    property string _summary
    property string _body
    property string _appIcon
    property string _image
    property var _hints: ({})
    Binding on _appName { when: notifCard.notification !== null; value: notifCard.notification?.appName ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _summary { when: notifCard.notification !== null; value: notifCard.notification?.summary ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _body { when: notifCard.notification !== null; value: notifCard.notification?.body ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _appIcon { when: notifCard.notification !== null; value: notifCard.notification?.appIcon ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _hints { when: notifCard.notification !== null; value: notifCard.notification?.hints ?? {}; restoreMode: Binding.RestoreNone }
    Binding on _image { when: notifCard.notification !== null; value: (notifCard.notification?.image ?? "").toString(); restoreMode: Binding.RestoreNone }

    // How far the sender's job has gone, from its hints: a bar under the text
    readonly property var progress: NotificationRules.progress(_hints)
    // What of it shows: a job that ended has a mark beside the summary, and on a card that
    // counts down no bar of its own — the countdown is the only bar (NotificationRules.progressView)
    readonly property var progressView: NotificationRules.progressView(progress, timerVisible)

    // The bar's wave: while the job runs and its value grew lately (NotificationProgress)
    property int progressWaveMs: NotificationRules.progressWaveMs
    readonly property bool progressWave: _progressBar.grewLately

    // The app's icon in the header, the image as a thumbnail or a preview (NotificationPicture)
    readonly property string _appIconSource: _picture.appIconSource
    readonly property string _imageSource: _picture.imageSource
    readonly property string _imageKind: _picture.imageKind

    NotificationPicture {
        id: _picture
        appIcon: notifCard._appIcon
        image: notifCard._image
    }

    // A link clicked in the body: a web or mail one opens; any other waits for a yes
    property string _pendingLink: ""
    // A new notification in the card: no question about the last one's link, an empty
    // reply; and, after a swipe (a toast's next one), back in place
    onNotificationChanged: {
        // Its first value is no growth, whichever of this and its hints comes first
        _progressBar.startAgain();
        _pendingLink = "";
        _reply.clear();
        _swipeLayer.stop();
        x = 0;
        opacity = 1;
        swipedAway = false;
    }
    function _openLink(link) {
        if (NotificationMarkup.linkKind(link) === "standard")
            Qt.openUrlExternally(link);
        else
            _pendingLink = link;
    }

    property var _activeEdit: null
    readonly property string _selectedText: _activeEdit ? _activeEdit.selectedText : ""

    // "default" is clicking the notification itself: the card, not a button
    // "inline-reply" is the reply field's own, should a sender also list it as an action
    readonly property var _regularActions: (notification?.actions ?? []).filter(function(a) { return a.identifier !== "default" && a.identifier !== "inline-reply"; })
    readonly property var _defaultAction: (notification?.actions ?? []).find(function(a) { return a.identifier === "default"; }) ?? null
    // A reply typed on the card goes back to the sender (Quickshell's inline reply)
    readonly property bool _hasReply: notification?.hasInlineReply ?? false
    // While a reply is hovered or written the card's window needs the keyboard, and a
    // toast holds its countdown
    readonly property bool wantsKeyboard: _hasReply && _reply.wantsKeyboard
    readonly property bool replying: _hasReply && _reply.engaged

    ColumnLayout {
        id: _contentCol
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: notifCard.contentPadding
        }
        spacing: 4

        // Header: app icon + app name + [timestamp] + dismiss control
        NotificationHeader {
            card: notifCard
        }

        // Thumbnail (a square image) beside the summary and body
        RowLayout {
            TapHandler {
                enabled: notifCard._defaultAction !== null
                onTapped: notifCard._activateDefault()
            }
            Layout.fillWidth: true
            spacing: 8

            RoundedImage {
                visible: notifCard._imageKind === "thumbnail"
                Layout.preferredWidth: notifCard.thumbnailSize
                Layout.preferredHeight: notifCard.thumbnailSize
                Layout.alignment: Qt.AlignTop
                radius: Theme.notificationCard.controlRadius
                source: visible ? notifCard._imageSource : ""
                sourceSize: Qt.size(notifCard.thumbnailSize * 2, notifCard.thumbnailSize * 2)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 4

                // Summary, after a finished job's mark
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        objectName: "progressMark"
                        visible: notifCard.progressView.mark !== ""
                        Layout.alignment: Qt.AlignTop
                        text: notifCard.progressView.mark
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        color: notifCard.progressView.tone !== "" ? Theme[notifCard.progressView.tone] : Theme.textPrimary
                    }

                    TextEdit {
                        id: _summaryEdit
                        selectionColor: Theme.selection
                        selectedTextColor: Theme.selectedText
                        text: notifCard._summary
                        textFormat: TextEdit.PlainText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                        wrapMode: TextEdit.WordWrap
                        readOnly: true
                        selectByMouse: true
                        onSelectedTextChanged: {
                            if (selectedText !== "")
                                notifCard._activeEdit = _summaryEdit;
                            else if (notifCard._activeEdit === _summaryEdit)
                                notifCard._selectionClearedAt = Date.now();
                        }

                        // Text stays selectable by dragging, but on a card that is clicked
                        // the pointer is the card's hand, not a text cursor
                        MouseArea {
                            anchors.fill: parent
                            enabled: notifCard._defaultAction !== null
                            acceptedButtons: Qt.NoButton
                            cursorShape: Qt.PointingHandCursor
                        }

                        // On the text itself: the text takes the press for selecting, so a
                        // handler further up never sees the click. A handler of the same item
                        // sees it first, and a drag (a selection) is no tap.
                        TapHandler {
                            enabled: notifCard._defaultAction !== null
                            onTapped: notifCard._activateDefault()
                        }
                    }
                }

                // Body (optional — hidden when empty), in a box that cuts it at
                // bodyMaxLines lines (a toast)
                NotificationBody {
                    id: _bodyBox
                    card: notifCard
                }

                // The sender's progress (NotificationRules.progress); the bar's own
                // animation smooths a sender that updates fast
                NotificationProgress {
                    id: _progressBar
                    card: notifCard
                }
            }
        }

        // Preview (a wide or tall image) under the text, across the card
        RoundedImage {
            TapHandler {
                enabled: notifCard._defaultAction !== null
                onTapped: notifCard._activateDefault()
            }
            visible: notifCard._imageKind === "preview"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(notifCard.imageMaxHeight,
                width * _picture.sourceSize.height / Math.max(1, _picture.sourceSize.width))
            Layout.topMargin: 4
            radius: Theme.notificationCard.controlRadius
            source: visible ? notifCard._imageSource : ""
        }

        // An unusual link clicked (not http, https or mailto: a file, an app's own scheme):
        // asked about before it is opened, as it may open something other than a page
        ColumnLayout {
            visible: notifCard._pendingLink !== ""
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: "Not a web or mail link — open it?"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.warning
            }

            Text {
                Layout.fillWidth: true
                text: notifCard._pendingLink
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
                elide: Text.ElideMiddle
            }

            Row {
                spacing: 6

                SmallButton {
                    label: "Open"
                    onClicked: {
                        Qt.openUrlExternally(notifCard._pendingLink);
                        notifCard._pendingLink = "";
                    }
                }
                SmallButton {
                    label: "Copy"
                    onClicked: {
                        _linkClip.text = notifCard._pendingLink;
                        _linkClip.selectAll();
                        _linkClip.copy();
                        Notifier.send("Copied: " + notifCard._pendingLink, { urgency: "low", category: "x-qs-shell" });
                        notifCard._pendingLink = "";
                    }
                }
                SmallButton {
                    label: "Cancel"
                    kind: "cancel"
                    onClicked: notifCard._pendingLink = ""
                }
            }

            // A hidden TextEdit, the way to put text on the clipboard (as CodeChips)
            TextEdit {
                id: _linkClip
                visible: false
                Layout.preferredWidth: 0
                Layout.preferredHeight: 0
            }
        }

        // Action buttons
        Flow {
            spacing: 6
            visible: notifCard._regularActions.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 4

            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash" in
                // docs/ARCHITECTURE.md. The card is reused for the next notification, so
                // this array is replaced while the card lives.
                model: ScriptModel {
                    values: notifCard._regularActions
                }
                delegate: SmallButton {
                    required property var modelData
                    kind: "action"
                    // The app's label, plain and on one line; one wider than the card ends in "…"
                    label: modelData.text
                    width: Math.min(implicitWidth, parent ? parent.width : implicitWidth)
                    fontSize: Theme.fontSizeSmall
                    onClicked: {
                        Notifications.invokeAction(notifCard.notification, modelData);
                        notifCard._afterAction();
                    }
                }
            }
        }

        // Inline reply
        NotificationReply {
            id: _reply
            visible: notifCard._hasReply
            Layout.fillWidth: true
            Layout.topMargin: 4
            fieldColor: notifCard.replyBackground
            placeholder: notifCard.notification?.inlineReplyPlaceholder ?? ""
            onSent: text => {
                notifCard.notification?.sendInlineReply(text);
                notifCard._afterAction();
            }
        }

        // Codes Notifications found in this notification, to copy
        CodeChips {
            Layout.fillWidth: true
            Layout.topMargin: 4
            codes: Notifications.extractedCodes[notifCard.notification?.id ?? -1] ?? []
            visible: codes.length > 0
        }
    }

    // Timer bar — pinned to bottom edge, shrinks as auto-close timer counts down
    Rectangle {
        visible: notifCard.timerVisible
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        height: Theme.notifTimerHeight
        width: parent.width * notifCard.timerProgress
        color: Theme.accent
        z: 1
    }

    // Copy overlay — appears in bottom-right corner when text is manually selected
    Rectangle {
        visible: notifCard._selectedText !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 28
        height: 28
        radius: Theme.notificationCard.controlRadius
        z: 1
        color: _copyArea.lit ? Theme.surfaceHover : Theme.accentDark
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            anchors.centerIn: parent
            text: "󰆏"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
        }

        PointerArea {
            id: _copyArea
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (notifCard._activeEdit) {
                    notifCard._activeEdit.copy();
                    Notifier.send("Copied selected text", { urgency: "low", category: "x-qs-shell" });
                }
            }
        }
    }

    // Swiped away with a finger (NotificationSwipe): over the content, above everything
    NotificationSwipe {
        id: _swipeLayer
        card: notifCard
    }
}
