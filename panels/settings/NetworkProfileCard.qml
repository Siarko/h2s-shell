import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// A saved connection profile on its kind's page (System → Network → Wi-Fi, Ethernet): its
// name and a line about it, connect or disconnect at once, and, opened, edit connection and
// forget (under that button), connect automatically and priority — plus what the page adds (its children, `pageRows`:
// the Wi-Fi password). Shared, so the pages stay alike. Connecting uses `useDevice`, the device the
// page offers ("" when there is none: out of range, no cable); disconnecting takes the
// device down, not only the profile (NetworkProfiles.disconnectDevice). A VPN provider's
// entry (VpnManager) uses it too, as `external`: the page connects it, no editor, no delete.
// Built on SettingsCard: the frame, the header, the notice line and the two regions are
// its; this card gives them a profile's buttons and rows — "Forget" as the last button, under
// what modules add to the card's `actions`.
SettingsCard {
    id: root

    // { uuid, name, active, autoconnect, priority, device } (NetworkProfiles.profiles)
    property var profile: ({ uuid: "", name: "", active: false, autoconnect: false, priority: 0, device: "" })
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
    // The page's own settings, under the shared ones
    default property alias pageRows: _extra.data
    signal forgotten()
    // Its addresses, DNS and the rest: the page opens NetworkConnectionEditor
    signal editRequested()
    signal useRequested()
    signal stopRequested()
    signal settingsRequested()

    title: profile.name ?? ""
    active: profile.active === true
    // The notice's button waits with the primary one
    noticeAvailable: !busy

    primary: [
        PrivilegedMark {
            anchors.verticalCenter: parent.verticalCenter
            need: root.need
        },
        // As in the network popup: connect in the confirm colour, disconnect in the delete
        // colour
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
        },
        DeleteButton {
            visible: !root.profile.active && root.usable && root.canUse && root.useQuestion !== ""
            kind: "save"
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
    ]

    // Shown while open (the card's), under the primary button
    buttons: [
        SmallButton {
            objectName: "profileSettings"
            visible: root.hasSettings
            label: "Settings…"
            tooltip: root.settingsTooltip
            onClicked: root.settingsRequested()
        },
        SmallButton {
            objectName: "profileEdit"
            visible: root.editable
            label: "Edit connection…"
            tooltip: root.editTooltip
            onClicked: root.editRequested()
        }
    ]

    // Last, under the modules' buttons (the card's `actions`)
    lastButtons: [
        DeleteButton {
            objectName: "profileForget"
            visible: root.deletable
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
    ]

    // ── Its settings: the card's own rows, then the page's ──
    content: [
        SwitchRow {
            visible: root.showAutoconnect
            label: root.autoconnectLabel
            hint: root.autoconnectHint
            checked: root.profile.autoconnect
            onToggled: NetworkProfiles.setAutoconnect(root.profile.uuid, !checked)
        },

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
        },

        // The page's rows. Shown with none too: its place keeps 6 under the card's own rows
        ColumnLayout {
            id: _extra
            Layout.fillWidth: true
            spacing: 6
        }
    ]
}
