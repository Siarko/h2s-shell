import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.singletons

// A notification as a card — in the panel, and as a toast: its app, summary, body and
// image, its actions, an inline reply (NotificationReply) and the codes found in it
// (CodeChips); text in it can be selected and copied.
Rectangle {
    id: notifCard

    required property var notification
    property string timestamp: ""
    property bool compactDismiss: false
    property int imageMaxHeight: 120
    // From the theme: a card in the panel by default; a toast sets its own
    property int contentPadding: Theme.notificationCard.padding
    property real cornerRadius: Theme.notificationCard.radius
    // A border: none in the panel; a toast sets the theme's
    property int borderWidth: 0
    property color borderColor: Theme.outline
    property color replyBackground: Theme.surfaceSunken

    property bool timerVisible: false
    // Fraction of the auto-dismiss time left, 1 → 0; the owner runs the countdown
    property real timerProgress: 1.0

    signal dismissRequested()

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
        _defaultAction.invoke();
        dismissRequested();
    }
    // The header's dismiss control sits inside a tappable area: its press marks the tap
    // that follows as its own
    property bool _dismissPressed: false
    property real _selectionClearedAt: 0
    border.width: borderWidth
    border.color: borderColor
    clip: true

    // The image's square, cropped thumbnail beside the text
    property int thumbnailSize: 44

    // A notification carries up to two pictures: the app's icon (app_icon, or the icon of
    // its desktop entry — Quickshell fills that in) and an image (image-data or
    // image-path: an avatar, album art, a screenshot — or, from many apps, their logo).
    // The icon sits in the header; a square image is a thumbnail beside the text, anything
    // else a preview across the card.
    //
    // An icon name the theme lacks still loads, as Quickshell's purple checkerboard, so
    // names are looked up first and a missing one shows nothing. A path given as a name
    // (image-path without "file:") becomes a file URL.
    function _pictureSource(picture) {
        const value = (picture ?? "").toString();
        if (value === "")
            return "";
        const iconPrefix = "image://icon/";
        const name = value.startsWith(iconPrefix) ? value.slice(iconPrefix.length) : value;
        if (name.startsWith("/"))
            return "file://" + name;
        if (value.startsWith(iconPrefix) || !/^[a-z]+:/.test(value))
            return Quickshell.iconPath(name, true);
        return value;
    }

    // What the card shows, kept when the notification goes: running an action closes it
    // (unless it is resident), and the card must not empty while it slides away
    property string _appName
    property string _summary
    property string _body
    property string _appIcon
    property string _image
    Binding on _appName { when: notifCard.notification !== null; value: notifCard.notification?.appName ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _summary { when: notifCard.notification !== null; value: notifCard.notification?.summary ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _body { when: notifCard.notification !== null; value: notifCard.notification?.body ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _appIcon { when: notifCard.notification !== null; value: notifCard.notification?.appIcon ?? ""; restoreMode: Binding.RestoreNone }
    Binding on _image { when: notifCard.notification !== null; value: (notifCard.notification?.image ?? "").toString(); restoreMode: Binding.RestoreNone }

    readonly property string _appIconSource: _pictureSource(_appIcon)
    // The same picture as the icon is shown once, in the header
    readonly property string _imageSource: {
        const source = _pictureSource(_image);
        return source === _appIconSource ? "" : source;
    }
    // "thumbnail", "preview", or "" — known once the image has loaded and its shape is known
    readonly property string _imageKind: {
        if (_imageSource === "" || _imageProbe.status !== Image.Ready)
            return "";
        const width = _imageProbe.sourceSize.width, height = _imageProbe.sourceSize.height;
        if (width <= 0 || height <= 0)
            return "";
        const aspect = width / height;
        return aspect >= 0.8 && aspect <= 1.25 ? "thumbnail" : "preview";
    }

    // Loads the image at its own size, only to learn its shape
    Image {
        id: _imageProbe
        visible: false
        source: notifCard._imageSource
        asynchronous: true
    }

    property var _activeEdit: null
    readonly property string _selectedText: _activeEdit ? _activeEdit.selectedText : ""

    // "default" is clicking the notification itself: the card, not a button
    readonly property var _regularActions: (notification?.actions ?? []).filter(function(a) { return a.identifier !== "default"; })
    readonly property var _defaultAction: (notification?.actions ?? []).find(function(a) { return a.identifier === "default"; }) ?? null
    readonly property var _replyAction: (notification?.actions ?? []).find(function(a) { return a.id === "inline-reply"; }) ?? null

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
        RowLayout {
            TapHandler {
                enabled: notifCard._defaultAction !== null
                onTapped: notifCard._activateDefault()
            }
            Layout.fillWidth: true

            Image {
                visible: notifCard._appIconSource !== ""
                source: notifCard._appIconSource
                sourceSize: Qt.size(32, 32)
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                Layout.maximumWidth: 16
                Layout.maximumHeight: 16
                fillMode: Image.PreserveAspectFit
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: notifCard._appName
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.textSecondary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                visible: notifCard.timestamp !== ""
                text: notifCard.timestamp
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            Text {
                text: notifCard.compactDismiss ? "×" : "dismiss"
                font.family: Theme.fontFamily
                font.pixelSize: notifCard.compactDismiss ? Theme.fontSizeSection : Theme.fontSizeSmall
                color: notifCard.compactDismiss ? Theme.textSecondary : Theme.textMuted

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: notifCard._dismissPressed = true
                    // Whether or not the tap came, the mark ends with this click
                    onReleased: Qt.callLater(() => notifCard._dismissPressed = false)
                    onClicked: notifCard.dismissRequested()
                }
            }
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

                // Summary
                TextEdit {
                    id: _summaryEdit
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.selectedText
                    text: notifCard._summary
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

                // Body (optional — hidden when empty)
                TextEdit {
                    id: _bodyEdit
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.selectedText
                    text: notifCard._body
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                    wrapMode: TextEdit.WordWrap
                    readOnly: true
                    selectByMouse: true
                    visible: notifCard._body.length > 0
                    onSelectedTextChanged: {
                        if (selectedText !== "")
                            notifCard._activeEdit = _bodyEdit;
                        else if (notifCard._activeEdit === _bodyEdit)
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
                width * _imageProbe.sourceSize.height / Math.max(1, _imageProbe.sourceSize.width))
            Layout.topMargin: 4
            radius: Theme.notificationCard.controlRadius
            source: visible ? notifCard._imageSource : ""
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
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: _actionLabel.implicitWidth + 16
                    height: 24
                    radius: Theme.notificationCard.controlRadius
                    color: Theme.accent

                    Text {
                        id: _actionLabel
                        anchors.centerIn: parent
                        text: modelData.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            modelData.invoke();
                            notifCard.dismissRequested();
                        }
                    }
                }
            }
        }

        // Inline reply
        NotificationReply {
            visible: notifCard._replyAction !== null
            Layout.fillWidth: true
            Layout.topMargin: 4
            fieldColor: notifCard.replyBackground
            onSent: text => {
                notifCard._replyAction.invoke(text);
                notifCard.dismissRequested();
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
        color: _copyArea.containsMouse ? Theme.surfaceHover : Theme.accentDark
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            anchors.centerIn: parent
            text: "󰆏"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
        }

        MouseArea {
            id: _copyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (notifCard._activeEdit) {
                    notifCard._activeEdit.copy();
                    Notifier.send("Copied selected text", { urgency: "low", category: "x-qs-shell" });
                }
            }
        }
    }
}
