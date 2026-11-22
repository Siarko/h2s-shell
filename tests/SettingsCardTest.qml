import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.panels.settings
import qs.singletons

// components/SettingsCard.qml laid out in a window, beside NetworkProfileCard, the network
// pages' card built on it: the same height closed with an empty line under the name, its
// buttons on that line too; hidden buttons take no room; the buttons stand in one row on the
// name's line, 6 apart and centred on it, without each saying so — closed as open.
TestCase {
    id: suite
    suiteName: "SettingsCard"
    asynchronous: true

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 400
        implicitHeight: 600
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        ColumnLayout {
            width: 380
            spacing: 4

            // Closed, the line under the name empty: as tall as NetworkProfileCard
            SettingsCard {
                id: emptyLine
                Layout.fillWidth: true
                title: "Home"
            }
            SettingsCard {
                id: withLine
                Layout.fillWidth: true
                title: "Home"
                subtitle: "Connected"
            }
            NetworkProfileCard {
                id: profileCard
                Layout.fillWidth: true
                title: "Home"
                subtitle: ""
            }

            // Open with nothing inside and no gap under the header (spacing 0), its two
            // buttons hidden: as tall as closed
            SettingsCard {
                id: hiddenButtons
                Layout.fillWidth: true
                title: "Office"
                open: true
                spacing: 0
                buttons: [
                    SmallButton { label: "Edit…"; visible: false },
                    SmallButton { label: "Forget"; visible: false }
                ]
            }

            // Closed, two buttons of different widths, no alignment of their own
            SettingsCard {
                id: twoButtons
                Layout.fillWidth: true
                title: "Cafe"
                buttons: [
                    SmallButton { objectName: "short"; label: "Edit…" },
                    SmallButton { objectName: "long"; label: "Forget this network" }
                ]
            }
        }
    }

    property var _driver: WindowDriver {
        name: "SettingsCardDriver"
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            _driver.wait(10);
        return condition();
    }

    function _named(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children ?? []) {
            const found = _named(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function runAsync() {
        const cards = [emptyLine, withLine, profileCard, hiddenButtons, twoButtons];
        const shortButton = _named(twoButtons, "short");
        const longButton = _named(twoButtons, "long");
        // Laid out once shown: every card has its height, the buttons their widths
        assert(_until(() => _window.visible && cards.every(card => card.height > 0)
                      && shortButton.width > 0 && longButton.width > shortButton.width),
               "the window is shown and the cards laid out");
        _driver.wait(50);

        assertEqual(emptyLine.height, withLine.height, "closed, an empty line under the name keeps its height");
        assertEqual(emptyLine.height, profileCard.height, "… as tall as NetworkProfileCard closed");
        assertEqual(hiddenButtons.height, emptyLine.height, "open, hidden buttons take no room (nothing else inside: as tall as closed)");
        assertEqual(hiddenButtons.buttonGroup.implicitWidth + " " + hiddenButtons.buttonRow.implicitWidth, "0 0", "… their row is empty");
        const profileForget = _named(profileCard, "profileForget");
        assert(profileForget !== null && profileForget.visible && _named(profileCard, "profileEdit").visible,
               "NetworkProfileCard closed: Edit and Forget shown on the name's line");
        const at = button => button.mapToItem(twoButtons, 0, 0);
        assertEqual(Math.round(at(longButton).x - (at(shortButton).x + shortButton.width)), 6, "closed: the buttons side by side, 6 apart");
        assertEqual(Math.round(at(shortButton).y + shortButton.height / 2), Math.round(at(longButton).y + longButton.height / 2), "… centred on one line");
        assertEqual(Math.round(at(shortButton).y + shortButton.height / 2), Math.round(twoButtons.titleText.mapToItem(twoButtons, 0, 0).y + twoButtons.buttonRow.height / 2),
                    "… the name's line");
        const closedAt = [at(shortButton).x, at(shortButton).y, at(longButton).x, at(longButton).y].map(Math.round).join(",");
        twoButtons.open = true;
        assert(_until(() => twoButtons.settingsRegion.visible), "opened");
        _driver.wait(50);
        assertEqual([at(shortButton).x, at(shortButton).y, at(longButton).x, at(longButton).y].map(Math.round).join(","), closedAt,
                    "opened: the buttons where they stood closed");
        finish();
    }
}
