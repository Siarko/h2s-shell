pragma Singleton

import QtQuick

QtObject {
    // Typography
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // Font sizes
    readonly property int fontSizeTiny: 9           // smallest form labels
    readonly property int fontSizeXSmall: 10        // very small secondary labels
    readonly property int fontSizeSmall: 11         // metadata, timestamps, captions
    readonly property int fontSizeBody: 12          // default body text
    readonly property int fontSizeBodyLarge: 13     // slightly larger body/labels
    readonly property int fontSizeMedium: 14        // subheadings, medium text
    readonly property int fontSizeSection: 16       // panel section icons, calendar headers
    readonly property int fontSizeHeading: 18       // settings section headers, widget text
    readonly property int fontSizeTitle: 20         // widget/panel titles, large icons
    readonly property int fontSizeDisplay: 22       // calendar event display
    readonly property int fontSizeLargeDisplay: 24  // music panel headers
    readonly property int fontSizeXXLargeDisplay: 32 // music track name
    readonly property int fontSizeHero: 52          // notification empty-state icon

    // Colours, by role rather than by where they were first used, so a theme — or a
    // palette generated from a wallpaper (matugen) — can set each one meaningfully. See
    // docs/plans/themes.md. Variants with transparency are derived here with Qt.alpha, not
    // written as numbers at the call sites.

    // Backgrounds
    readonly property color barBackground: "#4b4b4b"     // the bar
    readonly property color popupBackground: "#4d4d4d"   // popups and their curved corners
    readonly property color surface: "#3b3b3b"           // an element: bar cell, card, field, row
    readonly property color surfaceHover: "#5a5a5a"      // an element under the pointer, or whose popup is open
    readonly property color surfaceSunken: Qt.alpha("black", 0.2)  // lists and containers set into a page
    readonly property color overlay: Qt.alpha("black", 0.65)       // a pill or card over arbitrary content
    readonly property color scrim: "black"                          // behind the screensaver and lock screen

    // Accent
    readonly property color accent: "#44d47a"            // selection, active state, progress, graphs
    readonly property color accentHover: "#92db7a"       // accent under the pointer
    readonly property color accentTint: Qt.alpha(accent, 0.2)   // a faint accent background: selected row, day
    readonly property color accentDark: "green"          // filled accent: focused workspace, code buttons
    readonly property color onAccent: textPrimary        // text and icons on the accent
    readonly property color accentSecondary: "#5aa9e6"   // a second series or highlight: upload, sidebar selection
    readonly property color accentSecondaryTint: Qt.alpha(accentSecondary, 0.15)

    // Text, brightest to dimmest
    readonly property color textPrimary: "white"         // labels, headings, the clock
    readonly property color textSecondary: "#aaaaaa"     // secondary labels, body text
    readonly property color textMuted: "#888888"         // timestamps, links, empty states
    readonly property color textDisabled: "#777777"     // disabled, other-month days, faint icons

    // Lines and faint fills
    readonly property color divider: Qt.alpha(textDisabled, 0.3)   // separators, container borders
    readonly property color outline: Qt.alpha(textSecondary, 0.4)  // borders of pills and outlined buttons
    readonly property color fill: Qt.alpha(textDisabled, 0.15)     // an unselected pill, a dragged row
    readonly property color fillSubtle: Qt.alpha(textDisabled, 0.08)  // a row under the pointer in a list
    readonly property color track: Qt.alpha(textDisabled, 0.25)    // the empty part of a progress bar

    // Status
    readonly property color error: "#e05555"             // errors, destructive actions
    readonly property color errorTint: Qt.alpha(error, 0.12)   // behind an error message
    readonly property color errorMuted: Qt.alpha(error, 0.6)   // a destructive button at rest
    readonly property color warning: "#e8a854"           // warnings, volume above 100%
    readonly property color success: accent              // connected, done

    // Workspaces
    readonly property color workspaceFocused: accentDark
    readonly property color workspaceActive: "#4a6a4a"   // active but not focused
    readonly property color workspaceSpecial: "#7a1a2a"  // a shown special (scratchpad) workspace

    // Calendar
    readonly property color calendarToday: "#666666"     // the circle behind today's date

    // Filled buttons
    readonly property color confirm: "#1e5c1e"           // confirming: add an event
    readonly property color confirmHover: "#2d6a2d"
    readonly property color confirmSecondary: "#1e3a5f"  // confirming a change: save an edited event
    readonly property color confirmSecondaryHover: "#2d4a6d"

    // Lock screen and screensaver: light "glass" cards over the scrim
    readonly property color glass: Qt.alpha("white", 0.08)          // a card or field
    readonly property color glassRaised: Qt.alpha("white", 0.14)    // a button
    readonly property color glassHover: Qt.alpha("white", 0.22)     // a button under the pointer
    readonly property color glassBorder: Qt.alpha("white", 0.12)
    readonly property color glassBorderFocus: Qt.alpha("white", 0.45)  // a focused field
    readonly property color glassTextMuted: Qt.alpha("white", 0.38)    // placeholder, disabled text

    // HUD notification timer bar
    readonly property int notifTimerHeight: 3
}
