import QtQuick
import qs.singletons

// A migration for tests/MigrationsTest.qml only, never registered: renames testonly.old to
// testonly.new in every profile and the globals
QtObject {
    readonly property string migrationId: "2026-11-25-testonly-rename"
    readonly property string since: "2.2.0"
    readonly property string summary: "A test setting renamed"
    readonly property var scope: ["setting:testonly.*"]

    function migrate(document, context) {
        return MigrationHelpers.renameKey(document, "testonly.old", "testonly.new");
    }
}
