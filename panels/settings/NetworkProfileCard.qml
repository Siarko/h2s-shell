import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// A saved connection profile on its kind's page (System → Network → Wi-Fi, Ethernet): its
// name and a line about it, and on its line connect or disconnect, edit connection and forget,
// in one row; opened, connect automatically and priority — plus what the page adds (its
// children, the card's `content` after its own rows: the Wi-Fi password). The page's rows are
// the card's rows, not a column of their own: with none, or none shown, nothing is left under
// the card's own. Shared, so the pages stay alike. It does nothing itself: each button
// emits a request and the page acts on it (NetworkProfiles.use, stop, forget, setAutoconnect,
// setPriority; a VPN's through VpnManager). Connecting is offered with `useDevice`, the
// device the page offers ("" when there is none: out of range, no cable); disconnecting
// takes the device down, not only the profile, unless `stopsProfile`. A VPN provider's entry
// (VpnManager) uses it too: no editor, no delete (`editable`, `deletable`).
// Built on SettingsCard: the frame, the header, the notice line and the two regions are
// its; this card gives them a profile's buttons and rows — "Forget" as the last button, after
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
    // An editor and a delete (not for a VPN provider's entry)
    property bool editable: true
    property bool deletable: true
    // Its own settings elsewhere (a VPN provider's page): "Settings…" after the primary
    // button, emitting settingsRequested
    property bool hasSettings: false
    property string settingsTooltip: ""
    // An operation runs: the button waits
    property bool busy: NetworkProfiles.connecting
    // polkit's answer for connecting it, for PrivilegedMark ("" nothing marked)
    property string need: ""
    // Offer to connect at all (false: something else must be done first — `noticeAction`)
    property bool canUse: true
    // The requests, acted on by the page. `what` names the change in a failure's message
    // ("Forgetting Home", "Disconnecting Home")
    signal forgetRequested(string what)
    // Its addresses, DNS and the rest: the page opens NetworkConnectionEditor
    signal editRequested()
    // Connect, on `useDevice`
    signal useRequested()
    // Disconnect: the profile down when `stopsProfile`, else its device
    signal stopRequested(string what)
    signal autoconnectRequested(bool on)
    signal priorityRequested(int priority)
    signal settingsRequested()

    title: profile.name ?? ""
    active: profile.active === true
    // The notice's button waits with the primary one
    noticeAvailable: !busy

    primary: [
        PrivilegedMark {
            id: _mark
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
                if (!root.profile.active)
                    root.useRequested();
                else
                    root.stopRequested(root.stopsProfile ? root.stopLabel + " " + root.title : "Disconnecting " + root.title);
            }
        },
        DeleteButton {
            visible: !root.profile.active && root.usable && root.canUse && root.useQuestion !== ""
            kind: "save"
            label: root.useLabel
            fontSize: Theme.fontSizeBody
            confirmLabel: root.useQuestion
            cancelTip: "Cancel"
            // A question longer than a line goes on to more lines: the row moves under the
            // name, the question on a line of its own if need be (SettingsCard's buttonPlace).
            // Whole pixels: the lock is placed at its width rounded up
            maximumWidth: Math.floor(root.primaryRoom - (_mark.visible ? Math.ceil(_mark.implicitWidth) + 10 : 0))
            wraps: true
            available: !root.busy
            onConfirmed: root.useRequested()
        }
    ]

    // After the primary button, in the same row
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
            label: "Edit"
            tooltip: root.editTooltip
            onClicked: root.editRequested()
        }
    ]

    // Last, after the modules' buttons (the card's `actions`)
    lastButtons: [
        DeleteButton {
            objectName: "profileForget"
            visible: root.deletable
            // The row's size: as tall as the buttons beside it
            fontSize: Theme.fontSizeBody
            label: root.forgetLabel
            confirmLabel: root.forgetLabel + "?"
            cancelTip: "Keep it"
            onConfirmed: root.forgetRequested(root.forgetAction + " " + root.title)
        }
    ]

    // ── Its settings: the card's own rows, then the page's ──
    content: [
        SwitchRow {
            id: _autoconnect
            // Its 6 below only with a row under it: last, the card ends 8 under it, as its
            // first line is 8 under the top
            Layout.bottomMargin: parent && parent.visibleChildren[parent.visibleChildren.length - 1] === _autoconnect ? 0 : 6
            visible: root.showAutoconnect
            label: root.autoconnectLabel
            hint: root.autoconnectHint
            checked: root.profile.autoconnect
            onToggled: root.autoconnectRequested(!checked)
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
                onClicked: root.priorityRequested(root.profile.priority - 1)
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
                onClicked: root.priorityRequested(root.profile.priority + 1)
            }
        }
    ]
}
