import QtQuick
import Quickshell.Io
import qs.singletons

// The version in singletons/Version.qml must have its CHANGELOG.md section, so a bump
// without a changelog entry (or the other way round) fails here
TestCase {
    suiteName: "Version"

    property var _changelog: FileView {
        path: Qt.resolvedUrl("../CHANGELOG.md")
        blockLoading: true
    }

    function run() {
        assert(/^\d+\.\d+\.\d+$/.test(Version.number), "the version is MAJOR.MINOR.PATCH");
        const text = _changelog.text();
        assert(text.includes("## [" + Version.number + "]"), "CHANGELOG.md has a section for " + Version.number);
        const released = text.match(/^## \[(\d+\.\d+\.\d+)\]/m);
        assertEqual(released?.[1], Version.number, "the newest released section is the current version");

        // What the settings sidebar shows, from `git describe`
        assertEqual(Version._parse("v1.0.0-0-g9d98c91"), "", "the release itself: the number alone");
        assertEqual(Version._parse("v1.0.0-3-g9d98c91"), "9d98c91", "commits since: the commit");
        assertEqual(Version._parse("v1.0.0-0-g9d98c91-dirty"), "9d98c91.dirty", "uncommitted changes say so");
        assertEqual(Version._parse("9d98c91"), "9d98c91", "no tag yet: the commit");
        assertEqual(Version._parse(""), "", "no git: the number alone");
    }
}
