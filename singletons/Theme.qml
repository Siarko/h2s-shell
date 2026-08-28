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
    readonly property int fontSizeXLargeDisplay: 30 // settings widget icon
    readonly property int fontSizeXXLargeDisplay: 32 // music track name
    readonly property int fontSizeHero: 52          // notification empty-state icon

    // Bar & cells
    readonly property color barBackground: "#4b4b4b"   // top panel background
    readonly property color cellDefault: "#3b3b3b"      // default cell / notification card background
    readonly property color cellHover: "#5a5a5a"        // cell background on hover or while popup is open
    readonly property color cellAccent: "green"         // highlighted interactive cell
    readonly property color cellAccentSecondary: "#4a6a4a"  // active but unfocused workspace
    readonly property color cellAccentSpecial: "#7a1a2a"    // focused special (scratchpad) workspace
    readonly property color cellMuted: "gray"           // de-emphasized cell (e.g. notification bell)

    // Popup & buttons
    readonly property color popupBackground: "#4d4d4d"  // popup panel and curved corners
    readonly property color buttonHover: "#5a5a5a"      // power menu button hover state

    // Text hierarchy (brightest → dimmest)
    readonly property color textPrimary: "white"        // main labels, headings, clock
    readonly property color textSecondary: "#aaaaaa"    // day-of-week headers, arrow buttons, "Clear all"
    readonly property color textSubtle: "#bbbbbb"       // notification app name
    readonly property color textBody: "#cccccc"         // notification body text
    readonly property color textTertiary: "#888888"     // "dismiss" link, timestamp, empty-state text
    readonly property color textWarning: "#e8a854"       // volume above 100%
    readonly property color textDim: "#777777"          // previous/next month day numbers

    // Sliders
    readonly property color sliderAccent: "#44d47a"      // active track fill
    readonly property color sliderAccentHover: "#92db7a"   // active track fill on hover

    // Calendar
    readonly property color todayHighlight: "#666666"   // background circle on today's date

    // HUD notification timer bar
    readonly property int   notifTimerHeight: 3
    readonly property color notifTimerColor:  sliderAccent
}
