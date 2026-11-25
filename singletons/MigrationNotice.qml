pragma Singleton

import Quickshell
import QtQuick
import qs.components

// The shell's notice of a failed settings update at start, and its answers
// (components/MigrationFailureNotice.qml on the real Config, Notifier and launcher). The
// Settings window shows its entry; IPC `settings migrations` and `settings
// restoreMigrationBackup` reach the same without the notification. `backups`: the config
// backups for the Settings list and IPC (`settings backups`, `settings restoreBackup`),
// applied through the notice's restore.
Singleton {
    id: root

    readonly property MigrationFailureNotice notice: MigrationFailureNotice {
        reports: Config.migrationReports
        saveBlocked: Config.saveBlocked
        testRunner: Config.readOnly
        registry: Migrations.all()
        configPath: Config.path
        holdSaves: () => Config.holdSaves()
        releaseSaves: () => Config.releaseSaves()
        restartShell: () => Modules.restartShell()
        canRestart: () => Modules.canRestartShell()
        busy: Config.migrationBusy
        openSettings: () => Shell.showSettings()
    }

    readonly property ConfigBackupList backups: ConfigBackupList {
        configPath: Config.path
        registry: Migrations.all()
        notice: root.notice
    }

    // The last runs as JSON (MigrationNoticeRules.reportText)
    function reportText() {
        return MigrationNoticeRules.reportText(notice.current, Config.migrationReports);
    }
}
