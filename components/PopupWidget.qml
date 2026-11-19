import QtQuick
import qs.singletons

// A bar widget that opens a popup panel, by click or by hover as configured per widget
// type. The seven popup widgets each used to carry their own copy of this wiring, with
// their own default mode; input handling for the popup now changes in one place.
BarWidget {
    id: root

    property var popup: null
    // Which panel the popup shows, as registered in WidgetRegistry (the clock's is
    // "calendar")
    readonly property string popupContent: WidgetRegistry.popupContent(widgetType)

    // A setting of the active shell profile, per widget type (writable for tests only)
    property string popupMode: Profiles.value("widgets." + widgetType + ".popupMode") ?? WidgetRegistry.defaultPopupMode

    // Open from this entry: another entry of the same widget type showing it does not count
    readonly property bool popupOpen: !!popup?.active && popup?.contentType === popupContent && popup?.openedBy === root

    active: popupOpen

    // What the popup is told of the widget that opened it (Popup.open's contentData; a
    // module's panel gets it as `opener`, API 1.15): its type and its bar entry's preset —
    // "" for a widget that declares no `preset` (the bar sets it on those that do)
    function _openerData() {
        return { widgetType: widgetType, preset: typeof root.preset === "string" ? root.preset : "" };
    }

    // Opened by click it stays until clicked again; opened by hover it closes when the
    // pointer leaves the popup. Opened by a tap it stays too, and a tap outside closes it
    // (Popup, touchOpened). A click on another entry of the same type switches it there.
    function togglePopup(byTouch) {
        if (!popup)
            return;
        if (PointerRules.popupClick(!!popup.active, popup.contentType === popupContent, popup.openedBy === root) === "close")
            popup.close();
        else
            popup.open(root, true, popupContent, _openerData(), byTouch);
    }

    // A tap opens even a hover-mode popup: a finger cannot hover, so it is a click there
    onClicked: {
        if (PointerRules.tapTogglesPopup(popupMode, lastPressByTouch))
            togglePopup(lastPressByTouch);
    }
    onHover: state => {
        if (popupMode === "hover" && state && popup)
            popup.open(root, false, popupContent, _openerData(), false);
    }
}
