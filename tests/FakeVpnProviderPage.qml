import QtQuick
import QtQuick.Layouts

// The stand-in provider's own page (slot network.vpn.page; tests/FakeVpnProvider.qml's
// `withPage`): a plain column, as a module's page is — the frame (Back, title, scrolling)
// is the core's. Shows what its context says.
ColumnLayout {
    property var context: null

    Text {
        text: "Fake page for " + (context?.entryId ?? "?") + " of " + (context?.provider?.providerId ?? "?")
        color: "gray"
    }
}
