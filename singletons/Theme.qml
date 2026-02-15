pragma Singleton

import QtQuick

QtObject {
    // Typography
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // Bar & cells
    readonly property color barBackground: "#4b4b4b"   // top panel background
    readonly property color cellDefault: "#3b3b3b"      // default cell / notification card background
    readonly property color cellAccent: "green"         // highlighted interactive cell
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

    // Calendar
    readonly property color todayHighlight: "#666666"   // background circle on today's date
}
