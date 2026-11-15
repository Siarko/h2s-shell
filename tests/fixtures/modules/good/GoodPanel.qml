import QtQuick
import QtQuick.Layouts
import qs.api

// The fixture's popup panel
ColumnLayout {
    property var module: null
    implicitWidth: Api.theme.popupWidth("good", 200)

    SectionTitle {
        text: "Good: " + (parent.module?.value("greeting") ?? "")
    }
    DetailRow {
        label: "Level"
        value: String(parent.module?.facts["good.level"] ?? "unknown")
    }
}
