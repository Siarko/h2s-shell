import QtQuick
import qs.singletons

// The theme as a module reads it (Api.theme): the tokens the core's own widgets use, every
// one read-only and following the theme in use (a profile switch, a theme edited live). The
// groups (capsule, popup, row, …) are deep frozen copies of the theme's values (curve() too): reading
// `Api.theme.row.radius` works, writing does nothing. Part of the module API 1.0 — a token
// added is a minor bump; the names are the core Theme's (singletons/Theme.qml).
QtObject {
    // ---- Colours ----
    readonly property color barBackground: Theme.barBackground
    readonly property color popupBackground: Theme.popupBackground
    readonly property color surface: Theme.surface
    readonly property color surfaceHover: Theme.surfaceHover
    readonly property color surfaceHoverClear: Theme.surfaceHoverClear
    readonly property color surfaceSunken: Theme.surfaceSunken
    readonly property color overlay: Theme.overlay
    readonly property color scrim: Theme.scrim
    readonly property color accent: Theme.accent
    readonly property color accentHover: Theme.accentHover
    readonly property color accentTint: Theme.accentTint
    readonly property color accentDark: Theme.accentDark
    readonly property color onAccent: Theme.onAccent
    readonly property color accentSecondary: Theme.accentSecondary
    readonly property color accentSecondaryTint: Theme.accentSecondaryTint
    readonly property color textPrimary: Theme.textPrimary
    readonly property color textSecondary: Theme.textSecondary
    readonly property color textMuted: Theme.textMuted
    readonly property color textDisabled: Theme.textDisabled
    readonly property color selection: Theme.selection
    readonly property color selectedText: Theme.selectedText
    readonly property color divider: Theme.divider
    readonly property color outline: Theme.outline
    readonly property color fill: Theme.fill
    readonly property color fillSubtle: Theme.fillSubtle
    readonly property color track: Theme.track
    readonly property color error: Theme.error
    readonly property color errorTint: Theme.errorTint
    readonly property color errorMuted: Theme.errorMuted
    readonly property color warning: Theme.warning
    readonly property color privileged: Theme.privileged
    readonly property color success: Theme.success
    readonly property color capsuleBorder: Theme.capsuleBorder
    readonly property color popupBorder: Theme.popupBorder

    // ---- Type ----
    readonly property string fontFamily: Theme.fontFamily
    readonly property int fontSizeTiny: Theme.fontSizeTiny
    readonly property int fontSizeXSmall: Theme.fontSizeXSmall
    readonly property int fontSizeSmall: Theme.fontSizeSmall
    readonly property int fontSizeBody: Theme.fontSizeBody
    readonly property int fontSizeBodyLarge: Theme.fontSizeBodyLarge
    readonly property int fontSizeMedium: Theme.fontSizeMedium
    readonly property int fontSizeSection: Theme.fontSizeSection
    readonly property int fontSizeHeading: Theme.fontSizeHeading
    readonly property int fontSizeTitle: Theme.fontSizeTitle
    readonly property int fontSizeDisplay: Theme.fontSizeDisplay
    // How much bigger the theme's text is than the built-in's
    readonly property real fontScale: Theme.fontScale

    // ---- Shapes and spacing (frozen copies of the theme's groups) ----
    readonly property var capsule: _frozen(Theme.capsule)
    readonly property var popup: _frozen(Theme.popup)
    readonly property var row: _frozen(Theme.row)
    readonly property var listItem: _frozen(Theme.listItem)
    readonly property var button: _frozen(Theme.button)
    readonly property var iconButton: _frozen(Theme.iconButton)
    readonly property var pill: _frozen(Theme.pill)
    readonly property var field: _frozen(Theme.field)
    readonly property var checkbox: _frozen(Theme.checkbox)
    readonly property var tooltip: _frozen(Theme.tooltip)
    readonly property var border: _frozen(Theme.border)
    // pageMargin, cardRadius, sidebarItemRadius, … of the settings window
    readonly property var settings: _frozen(Theme.settings)

    // ---- Motion ----
    readonly property bool reduceMotion: Theme.reduceMotion
    readonly property real animationSpeed: Theme.animationSpeed

    // A width designed at the built-in fonts, grown with the text
    function scaled(width) {
        return Theme.scaled(width);
    }

    // A popup panel's width: `base` at the built-in fonts, with the theme's multipliers
    // (`name`: a popupWidth token; a module's own name falls back to the general one)
    function popupWidth(name, base) {
        return Theme.popupWidth(name, base);
    }

    // How long an animation of `role` ("enter", "exit", "hover", "state", "slide", "fade", …)
    // takes, in ms, at the profile's speed and with reduced motion
    function duration(role) {
        return Theme.duration(role);
    }

    // The easing for a role's curve, for an animation's `easing`
    function curve(name) {
        return _deepFrozen(Theme.curve(name));
    }

    // A deep copy, frozen all the way down: nothing a module holds is the core's own object
    // (re-made whenever the theme's group changes, so it stays current)
    function _frozen(group) {
        const copy = _deepFrozen(Object.assign({}, group ?? {}));
        return copy !== null && typeof copy === "object" ? copy : Object.freeze({});
    }

    function _deepFrozen(value) {
        if (value === null || typeof value !== "object")
            return value;
        // Only plain objects and arrays are copied: a colour or another Qt value type is a
        // value already (a copy), and must stay what it is
        if (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype)
            return value;
        try {
            const copy = Array.isArray(value) ? value.map(item => _deepFrozen(item)) : {};
            if (!Array.isArray(value)) {
                for (const key of Object.keys(value))
                    copy[key] = _deepFrozen(value[key]);
            }
            return Object.freeze(copy);
        } catch (error) {
            return Object.freeze({});
        }
    }
}
