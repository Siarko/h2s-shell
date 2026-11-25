import QtQuick
import qs.singletons
import qs.mockups.kit

// A fixture view that reaches what touches the session — the module host, the notification
// server, Notifier and the helper — and prints what it finds: in a mockup none of them may
// reach it, whatever the process inherited (H2S_SHELL_MODULES, H2S_SHELL_HELPER)
MockupWindow {
    id: root
    contentWidth: 100
    contentHeight: 50

    Component.onCompleted: {
        Notifier.send("Fixture notification");
        console.info("MOCKUP-FACTS modules=" + Modules.host.directories.length + " testMode=" + Modules.host.testMode
                     + " notifications=" + Notifications.count + " recorded=" + Notifier.recorded.length
                     + " helper='" + Helper.path + "'");
    }
}
