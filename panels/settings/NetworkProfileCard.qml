import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// A saved connection profile on its kind's page (System → Network → Wi-Fi, Ethernet): its
// name and a line about it, connect or disconnect at once, and, opened, edit connection and
// forget (under that button), connect automatically and priority — plus what the page adds (`data`:
// the Wi-Fi password). Shared, so the pages stay alike. Connecting uses `useDevice`, the device the
// page offers ("" when there is none: out of range, no cable); disconnecting takes the
// device down, not only the profile (NetworkProfiles.disconnectDevice). A VPN provider's
// entry (VpnManager) uses it too, as `external`: the page connects it, no editor, no delete.
Rectangle {
    id: root

    // { uuid, name, active, autoconnect, priority, device } (NetworkProfiles.profiles)
    property var profile: ({ uuid: "", name: "", active: false, autoconnect: false, priority: 0, device: "" })
    property string title: profile.name
    property string subtitle: ""
    property bool open: false
    property string useDevice: ""
    // Whether it can be connected now: a device to use it on, by default; a VPN needs none
    property bool usable: useDevice !== ""
    property string forgetLabel: "Forget"
    // The same as it is being done, for a failure's message ("Forgetting Home failed")
    property string forgetAction: "Forgetting"
    property string useLabel: "Connect"
    property string stopLabel: "Disconnect"
    // A question before connecting ("" none): the second click connects (DeleteButton)
    property string useQuestion: ""
    // Stopping takes the profile down rather than the device (a hotspot: the saved network
    // comes back on the Wi-Fi after it)
    property bool stopsProfile: false
    property bool showAutoconnect: true
    property string autoconnectLabel: "Connect automatically"
    property string autoconnectHint: ""
    property bool showPriority: true
    property string priorityHint: "Higher wins when several could connect"
    property string editTooltip: "Addresses, DNS, and the rest"
    // Not a NetworkManager profile (a VPN provider's, VpnManager): connecting and
    // disconnecting are the page's — useRequested / stopRequested — and there is no editor
    // and no delete unless the page says so
    property bool external: false
    property bool editable: !external
    property bool deletable: !external
    // Its own settings elsewhere (a VPN provider's page): "Settings…" under the primary
    // button, opened, emitting settingsRequested
    property bool hasSettings: false
    property string settingsTooltip: ""
    // An operation runs: the button waits
    property bool busy: NetworkProfiles.connecting
    // polkit's answer for connecting it, for PrivilegedMark ("" nothing marked)
    property string need: ""
    // Offer to connect at all (false: something else must be done first — `noticeAction`)
    property bool canUse: true
    // A lasting line under the header, in the warning colour ("" none), with a button
    // (`noticeAction`, "" none) that emits noticeActionRequested
    property string notice: ""
    property string noticeAction: ""
    // The page's own settings, under the shared ones
    default property alias content: _extra.data
    signal toggleRequested()
    signal forgotten()
    // Its addresses, DNS and the rest: the page opens NetworkConnectionEditor
    signal editRequested()
    signal useRequested()
    signal stopRequested()
    signal settingsRequested()
    signal noticeActionRequested()

    implicitHeight: _column.implicitHeight + 16
    radius: Theme.settings.cardRadius
    // Opened, a tint over the page's background, not Theme.surface: the buttons inside are
    // Theme.surface at rest, and on a card of the same colour they read as plain text
    color: open || _headerArea.lit ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
    border.width: Theme.border.width
    border.color: profile.active ? Theme.accent : Theme.outline
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    ColumnLayout {
        id: _column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 6

        // The profile — click for its settings. The click area goes under the row, so the
        // button takes its own clicks.
        Item {
            Layout.fillWidth: true
            implicitHeight: _header.implicitHeight

            PointerArea {
                id: _headerArea
                centred: false
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleRequested()
            }

            RowLayout {
                id: _header
                width: parent.width
                spacing: 10

                ColumnLayout {
                    id: _titleBlock
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.title
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: root.profile.active
                        color: Theme.textPrimary
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.subtitle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.profile.active ? Theme.success : Theme.textMuted
                    }
                }
                // The actions, on the right: the primary one (connect or disconnect) and,
                // opened, the secondary ones stacked under it, all on one right edge — so
                // the text keeps the left and elides instead of running under them
                ColumnLayout {
                    id: _actions
                    Layout.alignment: Qt.AlignTop
                    spacing: 4

                    // At least as tall as the name and its line, the primary button
                    // centred in it: closed, the card looks as it did; and the secondary
                    // buttons start at the same place whether or not the primary shows
                    Item {
                        id: _primarySlot
                        Layout.alignment: Qt.AlignRight
                        implicitWidth: _primaryRow.implicitWidth
                        implicitHeight: Math.max(_primaryRow.implicitHeight, _titleBlock.implicitHeight)

                        Row {
                            id: _primaryRow
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 10

                            PrivilegedMark {
                                anchors.verticalCenter: parent.verticalCenter
                                need: root.need
                            }
                            // As in the network popup: connect in the confirm colour, disconnect
                            // in the delete colour
                            SmallButton {
                                objectName: "profilePrimary"
                                visible: root.profile.active || (root.usable && root.canUse && root.useQuestion === "")
                                label: root.profile.active ? root.stopLabel : root.useLabel
                                kind: root.profile.active ? "delete" : "save"
                                available: !root.busy
                                onClicked: {
                                    if (root.external && root.profile.active)
                                        root.stopRequested();
                                    else if (root.external)
                                        root.useRequested();
                                    else if (!root.profile.active)
                                        NetworkProfiles.activate(root.profile.uuid, root.useDevice);
                                    else if (root.stopsProfile)
                                        NetworkProfiles.deactivate(root.profile.uuid, root.stopLabel + " " + root.title);
                                    else
                                        NetworkProfiles.disconnectDevice(root.profile.device, "Disconnecting " + root.title);
                                }
                            }
                            DeleteButton {
                                visible: !root.profile.active && root.usable && root.canUse && root.useQuestion !== ""
                                label: root.useLabel
                                fontSize: Theme.fontSizeBody
                                confirmLabel: root.useQuestion
                                cancelTip: "Cancel"
                                available: !root.busy
                                onConfirmed: {
                                    if (root.external)
                                        root.useRequested();
                                    else
                                        NetworkProfiles.activate(root.profile.uuid, root.useDevice);
                                }
                            }
                        }
                    }

                    SmallButton {
                        objectName: "profileSettings"
                        visible: root.open && root.hasSettings
                        Layout.alignment: Qt.AlignRight
                        label: "Settings…"
                        tooltip: root.settingsTooltip
                        onClicked: root.settingsRequested()
                    }
                    SmallButton {
                        objectName: "profileEdit"
                        visible: root.open && root.editable
                        Layout.alignment: Qt.AlignRight
                        label: "Edit connection…"
                        tooltip: root.editTooltip
                        onClicked: root.editRequested()
                    }
                    DeleteButton {
                        objectName: "profileForget"
                        visible: root.open && root.deletable
                        Layout.alignment: Qt.AlignRight
                        // The stack's size: as tall as the buttons above it
                        fontSize: Theme.fontSizeBody
                        label: root.forgetLabel
                        confirmLabel: root.forgetLabel + "?"
                        cancelTip: "Keep it"
                        onConfirmed: {
                            root.forgotten();
                            NetworkProfiles.forget([root.profile.uuid], root.forgetAction + " " + root.title);
                        }
                    }
                }
                // Level with the primary button, not with the whole stack
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredHeight: _primarySlot.implicitHeight
                    verticalAlignment: Text.AlignVCenter
                    text: root.open ? "▾" : "▸"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }
            }
        }

        // A lasting line: what needs the user, with its action
        RowLayout {
            visible: root.notice !== ""
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.notice
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            SmallButton {
                visible: root.noticeAction !== ""
                label: root.noticeAction
                available: !root.busy
                onClicked: root.noticeActionRequested()
            }
        }

        // ── Its settings ──
        ColumnLayout {
            visible: root.open
            Layout.fillWidth: true
            spacing: 6

            SwitchRow {
                visible: root.showAutoconnect
                label: root.autoconnectLabel
                hint: root.autoconnectHint
                checked: root.profile.autoconnect
                onToggled: NetworkProfiles.setAutoconnect(root.profile.uuid, !checked)
            }

            // Which profile wins when several could connect
            RowLayout {
                visible: root.showPriority
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: "Priority"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.priorityHint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textMuted
                    }
                }
                SmallButton {
                    label: "−"
                    available: !NetworkProfiles.busy && root.profile.priority > -999
                    onClicked: NetworkProfiles.setPriority(root.profile.uuid, root.profile.priority - 1)
                }
                Text {
                    Layout.preferredWidth: 32
                    horizontalAlignment: Text.AlignHCenter
                    text: String(root.profile.priority)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
                SmallButton {
                    label: "+"
                    available: !NetworkProfiles.busy && root.profile.priority < 999
                    onClicked: NetworkProfiles.setPriority(root.profile.uuid, root.profile.priority + 1)
                }
            }

            ColumnLayout {
                id: _extra
                Layout.fillWidth: true
                spacing: 6
            }
        }
    }
}
