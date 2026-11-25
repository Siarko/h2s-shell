pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.migrations

// The core's settings migrations, in the order they run: one object per file under
// singletons/migrations/ (migrationId, since, summary, scope, migrate), each added at the end
// of `_registered`. MigrationRules decides which are pending and runs them;
// tests/MigrationsTest.qml checks each against its fixture (tests/fixtures/migrations/<id>/).
Singleton {
    id: root

    readonly property list<QtObject> _registered: [
        PreProfilesSettings {},
        WidgetPresetsFromProfiles {},
        BarLayoutIntoThemes {},
        LockNotificationDetailDefault {}
    ]

    // The registry, a new list at each call (a shared list could be changed by a reader)
    function all() {
        const list = [];
        for (let i = 0; i < _registered.length; i++)
            list.push(_registered[i]);
        return list;
    }
}
