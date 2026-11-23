import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// The pills' three sizes as they are drawn (Pill: "s", "m", "l", the theme's three
// heights), and the tree's own pills: none sets its height itself, and each names the
// size written here (tests/pill-sizes.sh reads the sources). The rule alone:
// ThemeTest, ThemeRules.pillHeight.
TestCase {
    id: suite
    suiteName: "PillSizes"
    asynchronous: true

    property var _small: Pill { size: "s"; label: "x" }
    property var _medium: Pill { size: "m"; label: "x" }
    property var _large: Pill { size: "l"; label: "x" }
    property var _unsized: Pill { label: "x" }
    property var _unknown: Pill { size: "huge"; label: "x" }

    // The sizes the shell's pills name, per file, sorted ("-": none, the default).
    // 22 px: "s" and "-"; 26 px: "m"; 30 px: "l".
    readonly property var expected: ({
        "panels/BatteryPanel.qml": "-,l",
        "panels/WidgetSettingsPane.qml": "s",
        "panels/calendar/RecurrenceEditor.qml": "-,-",
        "panels/settings/AnimationsSettings.qml": "-,m",
        "panels/settings/CommandEntryCard.qml": "m,m",
        "panels/settings/ConditionEditor.qml": "s,s,s,s,s,s,s,s",
        "panels/settings/CurvesSettings.qml": "-,-,-,-",
        "panels/settings/MonitorTimesCard.qml": "m,m,m",
        "panels/settings/NetworkConnectionEditor.qml": "m,m,m",
        "panels/settings/NetworkVpnSettings.qml": "m",
        "panels/settings/PamRuleList.qml": "-,m,m",
        "panels/settings/SchemaSettingEditor.qml": "m",
        "panels/settings/ThemesSettings.qml": "-",
        "panels/settings/WallpaperSettings.qml": "m",
        "panels/widget_settings/BatteryWidgetSettings.qml": "m",
        "panels/widget_settings/NotificationsWidgetSettings.qml": "m"
    })

    property Process _scan: Process {
        property var lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") suite._scan.lines.push(line.trim()); }
        }
        onExited: suite._scanned(lines)
    }

    function runAsync() {
        assertEqual(_small.height, 22, "a small pill is 22 px");
        assertEqual(_medium.height, 26, "a medium pill is 26 px");
        assertEqual(_large.height, 30, "a large pill is 30 px");
        assertEqual(_small.height, Theme.pill.minHeight, "a small pill has the theme's small height");
        assertEqual(_medium.height, Theme.pill.mediumHeight, "a medium pill the medium one");
        assertEqual(_large.height, Theme.pill.largeHeight, "a large pill the large one");
        assertEqual(_unsized.height, _small.height, "a pill that names no size is small");
        assertEqual(_unknown.height, _small.height, "and so is one with a size that does not exist");
        _medium.size = "l";
        assertEqual(_medium.height, _large.height, "a pill follows its size when that changes");

        _scan.command = ["bash", Quickshell.shellDir + "/tests/pill-sizes.sh", Quickshell.shellDir];
        _scan.running = true;
    }

    function _scanned(lines) {
        const files = Number((lines.find(line => line.startsWith("FILES:")) ?? "FILES:0").slice(6));
        assert(files > 100, "the tree's QML files were read (" + files + ")");
        const numbers = lines.filter(line => line.startsWith("NUMBER:")).map(line => line.slice(7));
        assertEqual(numbers.join(", "), "", "no file sets a pill's height itself");
        const found = {};
        for (const line of lines.filter(line => line.startsWith("PILL:"))) {
            const parts = line.slice(5).split(":");
            found[parts[0]] = (found[parts[0]] ?? []).concat([parts[1]]);
        }
        const names = Object.keys(found).concat(Object.keys(expected)).filter((name, index, all) => all.indexOf(name) === index).sort();
        for (const name of names)
            assertEqual((found[name] ?? []).sort().join(","), expected[name] ?? "", "the pills of " + name + " have the sizes written here");
        finish();
    }
}
