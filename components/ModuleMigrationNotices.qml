import QtQuick
import Quickshell
import qs.singletons

// One ModuleMigrationNotice for each module whose settings migrations ran (its report in
// ModuleHost.migrationReports), each told and answered on its own: a module's run, backup
// and records are its own. A module stays listed once its report is in (a later run replaces
// the report, never removes it), so a notice withdraws what it sent itself rather than going
// with it.
QtObject {
    id: root

    // ModuleHost.migrationReports: id → the last run's report
    property var reports: ({})
    // id → display name (Modules.displayNames(): the modules installed)
    property var names: ({})
    property bool testRunner: false
    property var notifier: Notifier
    property var installer: null
    property var openSettings: () => {}
    property bool logging: true

    // The notices, in the modules' id order
    readonly property var notices: _notices

    property var _notices: []

    readonly property var _ids: Object.keys(reports ?? {}).filter(id => typeof id === "string" && id !== "").sort()

    property Instantiator _made: Instantiator {
        model: ScriptModel { values: root._ids }
        delegate: ModuleMigrationNotice {
            required property string modelData
            moduleId: modelData
            moduleName: Object.prototype.hasOwnProperty.call(root.names ?? {}, modelData) ? String(root.names[modelData]) : ""
            present: Object.prototype.hasOwnProperty.call(root.names ?? {}, modelData)
            report: root.reports?.[modelData] ?? null
            testRunner: root.testRunner
            notifier: root.notifier
            installer: root.installer
            openSettings: root.openSettings
            logging: root.logging
        }
        onObjectAdded: (index, object) => root._notices = root._notices.concat([object]).sort((first, second) => first.moduleId < second.moduleId ? -1 : 1)
        onObjectRemoved: (index, object) => root._notices = root._notices.filter(each => each !== object)
    }
}
