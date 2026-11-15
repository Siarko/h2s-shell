import QtQuick
import QtQuick.Layouts
import qs.api

// The fixture's settings page (System tab): laid out at the page's width, scrolled by the
// window — the core's building blocks, through qs.api
ColumnLayout {
    id: page
    objectName: "goodSettingsPage"

    property var module: null
    // The profile picked in the settings window
    property int editIndex: -1

    spacing: 4

    Heading {
        text: "Good fixture"
    }
    Hint {
        Layout.fillWidth: true
        text: "Version " + (page.module?.version ?? "?")
    }
    SectionTitle {
        text: "Settings"
    }
    SettingEditor {
        Layout.fillWidth: true
        key: "mod.good.greeting"
        editIndex: page.editIndex
    }
    SwitchRow {
        label: "Loud"
        hint: "A global setting of the module"
        checked: page.module?.value("loud") === true
        onToggled: page.module.setValue("loud", !checked)
    }
    DetailRow {
        label: "Started"
        value: String(page.module?.store.get("starts", 0) ?? 0)
    }
}
