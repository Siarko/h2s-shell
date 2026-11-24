import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.network

// A VPN provider's own page (slot network.vpn.page, VpnManager.pageOf) in the settings
// pages' frame — the core's, so a module need not make one: "‹ Back", the title (the
// provider's type · the entry's name), and scrolling, as the connection editor is framed.
// The provider's root item is laid out at the frame's width and scrolled by its
// implicitHeight (it must not scroll itself); it gets `context` (VpnManager.contextFor:
// { slot, vpnId, entryId, vpn, provider, close }) when it declares the property, again only
// when that changes. Back and `close()` emit `closed`. The VPN gone from the list (its
// provider away, the entry missing from a read) emits `closed` too: the owner clears
// `vpnId`, so the page never reopens by itself when the id comes back.
// A page that fails to load shows nothing (`shown` false): the page under it stays.
Flickable {
    id: root

    // The VPN's id ("" none)
    property string vpnId: ""
    signal closed()

    readonly property var vpn: vpnId === "" ? null : (VpnManager.vpns.find(entry => entry.uuid === vpnId) ?? null)
    readonly property bool shown: _loader.status === Loader.Ready
    readonly property string title: vpn === null ? ""
        : [VpnManager.typeName(vpn), vpn.name].filter((part, index, parts) => part !== "" && parts.indexOf(part) === index).join(" · ")
    // The provider's page, for the tests
    readonly property var page: _loader.item

    // After the change has settled: the owner clearing vpnId from inside this notification
    // would re-evaluate `vpn` within its own change (a binding loop)
    onVpnChanged: {
        if (vpnId !== "" && vpn === null)
            Qt.callLater(_closeIfGone);
    }
    function _closeIfGone() {
        if (vpnId !== "" && vpn === null)
            closed();
    }

    function close() {
        closed();
    }

    visible: shown
    contentWidth: width
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    flickableDirection: Flickable.VerticalFlick

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SmallButton {
                label: "‹ Back"
                onClicked: root.close()
            }
            Heading {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.title
                textFormat: Text.PlainText
            }
        }

        Loader {
            id: _loader
            Layout.fillWidth: true
            readonly property string _url: root.vpn !== null ? VpnManager.pageOf(root.vpn) : ""
            active: _url !== ""
            readonly property var context: VpnManager.contextFor(VpnManager.slots.page, root.vpn, { close: () => root.close() })
            // A module's page (slot network.vpn.page) is given its module's handle as `module`
            // when it declares the property, as the core gives it to everything it builds from
            // a manifest (Modules.initialProperties: {} for a file of no module, the stand-in's)
            on_UrlChanged: _setSource()
            Component.onCompleted: _setSource()
            function _setSource() {
                if (_url === "") {
                    source = "";
                    return;
                }
                setSource(_url, Modules.initialProperties(_url, { shown: _shown }));
            }
            // On screen (module API 1.2: a module page that declares `property bool shown`
            // gets it, kept current, as ModuleContribution gives it)
            readonly property bool _shown: visible && (Window.window?.visible ?? false)
            on_ShownChanged: {
                try {
                    if (item !== null && "shown" in item)
                        item.shown = _shown;
                } catch (error) {
                    // Not writable there
                }
            }
            property var _passed: null
            onLoaded: {
                _passed = null;
                _pass();
            }
            onContextChanged: _pass()
            function _pass() {
                if (item === null || VpnProviderRules.sameVpnContext(_passed, context))
                    return;
                try {
                    if ("context" in item) {
                        // Its own frozen copy: its plain data a new copy at each read, the
                        // provider and close() as they are (ReadOnlyRules.context)
                        item.context = ReadOnlyRules.context(context);
                        _passed = context;
                    }
                } catch (error) {
                    // No such property: it takes no context
                }
            }
        }
    }
}
