import QtQuick
import qs.singletons

// A bar widget that opens a popup panel, by click or by hover as configured per widget
// type. The seven popup widgets each used to carry their own copy of this wiring, with
// their own default mode; input handling for the popup now changes in one place.
BarWidget {
    id: root

    property var popup: null
    // Key into Config.widgetProfiles, where the user's popup mode is stored
    property string widgetType: ""
    // Which panel the popup shows, as registered in WidgetRegistry (the clock's is
    // "calendar")
    readonly property string popupContent: WidgetRegistry.popupContent(widgetType)

    readonly property string popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data[widgetType]?.["_popupMode"] ?? WidgetRegistry.defaultPopupMode;
    }

    readonly property bool popupOpen: !!popup?.active && popup?.contentType === popupContent

    active: popupOpen

    // Opened by click it stays until clicked again; opened by hover it closes when the
    // pointer leaves the popup
    function togglePopup() {
        if (!popup)
            return;
        if (popupOpen)
            popup.close();
        else
            popup.open(root, true, popupContent);
    }

    onClicked: {
        if (popupMode === "click")
            togglePopup();
    }
    onHover: state => {
        if (popupMode === "hover" && state && popup)
            popup.open(root, false, popupContent);
    }
}
