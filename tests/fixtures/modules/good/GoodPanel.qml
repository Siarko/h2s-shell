import QtQuick
import QtQuick.Layouts
import qs.api

// The fixture's popup panel; it declares every input a popup panel can be given (module
// API 1.15) and tells GoodState what it got
ColumnLayout {
    id: panel
    property var module: null
    // The bar widget that opened it: { widgetType, preset, edge, byTouch }
    property var opener: null
    // The most height before it must scroll, kept current
    property real availableHeight: 0
    // Sized to the height shown while the popup animates
    readonly property bool fitsShownHeight: true
    // The popup moving or resizing
    property bool popupAnimating: false
    onPopupAnimatingChanged: if (popupAnimating) GoodState.panelSawAnimating = true
    implicitWidth: Api.theme.popupWidth("good", 200)

    Component.onCompleted: {
        GoodState.panelOpenerAtStart = opener;
        GoodState.panelsBuilt += 1;
        GoodState.panel = panel;
    }
    Component.onDestruction: {
        GoodState.panelsGone += 1;
        if (GoodState.panel === panel)
            GoodState.panel = null;
    }

    SectionTitle {
        text: "Good: " + (panel.module?.value("greeting") ?? "")
    }
    DetailRow {
        label: "Level"
        value: String(panel.module?.facts["good.level"] ?? "unknown")
    }
    DetailRow {
        label: "Opened from"
        value: panel.opener ? panel.opener.preset : ""
    }
}
