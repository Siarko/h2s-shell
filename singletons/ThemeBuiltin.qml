pragma Singleton

import Quickshell

// The built-in theme: today's look, and every token a theme file may set. A theme file
// lays its values over these (Theme, ThemeRules.resolve); a token missing here cannot be
// set by a theme at all.
Singleton {
    readonly property var values: ({
        "colors": {
            // Backgrounds
            "barBackground": "#4b4b4b",      // the bar
            "popupBackground": "#4d4d4d",    // popups and their curved corners
            "surface": "#3b3b3b",            // an element: bar cell, card, field, row
            "surfaceHover": "#5a5a5a",       // an element under the pointer, or whose popup is open
            "scrim": "#000000",              // behind the screensaver and lock screen
            // Accent
            "accent": "#44d47a",             // selection, active state, progress, graphs
            "accentHover": "#92db7a",        // accent under the pointer
            "accentDark": "#008000",         // filled accent: focused workspace, code buttons
            "onAccent": "#ffffff",           // text and icons on the accent
            "accentSecondary": "#5aa9e6",    // a second series or highlight: upload, sidebar selection
            // Text, brightest to dimmest
            "textPrimary": "#ffffff",        // labels, headings, the clock
            "textSecondary": "#aaaaaa",      // secondary labels, body text
            "textMuted": "#888888",          // timestamps, links, empty states
            "textDisabled": "#777777",       // disabled, other-month days, faint icons
            "selection": "#008000",          // behind selected text
            "selectedText": "#ffffff",       // selected text
            // Status
            "error": "#e05555",              // errors, destructive actions
            "warning": "#e8a854",            // warnings, volume above 100%
            "success": "#44d47a",            // connected, done
            // Workspaces
            "workspaceActive": "#4a6a4a",    // active but not focused
            "workspaceSpecial": "#7a1a2a",   // a shown special (scratchpad) workspace
            // Calendar
            "calendarToday": "#666666",      // the circle behind today's date
            // Filled buttons
            "confirm": "#1e5c1e",            // confirming: add an event
            "confirmHover": "#2d6a2d",
            "confirmSecondary": "#1e3a5f",   // confirming a change: save an edited event
            "confirmSecondaryHover": "#2d4a6d",
            // Borders, drawn where their width is above 0
            "barBorder": "#777777",
            "capsuleBorder": "#777777",
            "popupBorder": "#777777",
            "osdToastBorder": "#777777",
            "osdVolumeBorder": "#777777",
            "osdMessageBorder": "#777777",
            // Music: empty follows the accent (ThemeRules.colorFollows) until a theme sets it
            "visualizer": ""                 // the music visualiser
        },
        "fonts": {
            "family": "JetBrainsMono Nerd Font",
            "sizeTiny": 9,                   // smallest form labels
            "sizeXSmall": 10,                // very small secondary labels
            "sizeSmall": 11,                 // metadata, timestamps, captions
            "sizeBody": 12,                  // default body text
            "sizeBodyLarge": 13,             // slightly larger body/labels
            "sizeMedium": 14,                // subheadings, medium text
            "sizeSection": 16,               // panel section icons, calendar headers
            "sizeHeading": 18,               // settings section headers, widget text
            "sizeTitle": 20,                 // widget/panel titles, large icons
            "sizeDisplay": 22,               // calendar event display
            "sizeLargeDisplay": 24,          // music panel headers
            "sizeXXLargeDisplay": 32,        // music track name
            "sizeHero": 52                   // notification empty-state icon
        },
        // The bar's geometry (ThemeRules.barTokens): pixels, and corner radii in percent
        // of half the bar's height
        "bar": {
            "barHeight": 36,                 // the bar itself
            "reservedSpace": 40,             // space kept free for it at its screen edge
            "topOffset": 2,                  // between the bar and its screen edge
            "leftMargin": 0,                 // between the screen edges and the bar
            "rightMargin": 0,
            "leftPadding": 5,                // between the bar's ends and its widgets
            "rightPadding": 5,
            "radiusTopLeft": 0,
            "radiusTopRight": 0,
            "radiusBottomLeft": 20,
            "radiusBottomRight": 20,
            "cellVerticalMargin": 5,         // above and below each widget's cell
            "widgetSpacing": 5,              // between the widgets of a section
            "borderWidth": 0                 // along the edge facing the desktop (colour barBorder); 0: none
        },
        // Radii, borders and spacing by kind of element (docs/plans/themes-stage7.md). Radii
        // and sizes in pixels.
        "capsule": { "radius": 5, "horizontalPadding": 8, "borderWidth": 0 },   // a widget's cell on the bar
        "workspace": { "pillRadius": 4, "pillHorizontalPadding": 4, "pillHeight": 22, "pillSpacing": 4 },
        "tray": { "pillRadius": 5, "pillWidth": 24, "iconSize": 18, "pillSpacing": 4 },  // the tray's icons
        "popup": { "radius": 20, "contentPadding": 10, "borderWidth": 0 },
        "row": { "radius": 6, "horizontalPadding": 8 },                       // rows and cards in popups
        "listItem": { "radius": 4 },                                          // menu and list items
        "dropdown": { "radius": 6 },
        "powerMenu": { "buttonRadius": 8, "buttonHeight": 44 },
        "button": { "radius": 6, "horizontalPadding": 7, "verticalPadding": 4, "minHeight": 24 },
        "saveButton": { "radius": 6 },
        "cancelButton": { "radius": 6 },
        "deleteButton": { "radius": 6 },
        "iconButton": { "radius": 4 },
        "pill": { "radius": 6, "horizontalPadding": 7, "minHeight": 22 },
        "field": { "radius": 6, "horizontalPadding": 8 },
        "notificationCard": { "radius": 8, "padding": 8, "controlRadius": 5 },  // in the panel
        "osdToast": { "radius": 8, "padding": 10, "width": 360, "screenGap": 16, "spacing": 8, "badgeWidth": 36, "borderWidth": 0 },
        "osdVolume": { "radius": 6, "padding": 10, "borderWidth": 0 },
        // The shell's message pill; a radius of -1 rounds its ends fully
        "osdMessage": { "radius": -1, "borderWidth": 0 },
        "tooltip": { "radius": 4, "horizontalPadding": 8, "verticalPadding": 6 },
        "settings": { "pageMargin": 14, "sidebarItemRadius": 6, "tabRadius": 6, "tabHorizontalPadding": 12, "cardRadius": 6 },
        "calendar": { "dayRadius": 4 },
        "checkbox": { "radius": 3 },
        "lock": { "cardRadius": 16, "controlRadius": 8, "controlHeight": 40 },
        "border": { "width": 1, "selectedWidth": 2 },  // ordinary outlines; selection rings
        // Popups' widths, in percent of their width at the built-in fonts: `all` for every
        // popup, then each one's own, multiplied (popupWidth())
        "popupWidth": { "all": 100, "network": 100, "bluetooth": 100, "hardware": 100, "sound": 100,
                        "music": 100, "notifications": 100, "tray": 100, "power": 100, "calendar": 100, "battery": 100 },
        // Animations by role — the kind of motion, not where it happens (docs/plans/themes.md)
        "durations": {
            "hover": 100,                    // colour under the pointer
            "state": 150,                    // a switch, a focused workspace, a field's state
            "expand": 150,                   // something growing or shrinking in place
            "popup": 100,                    // a popup opening or closing
            "popupResize": 100,              // a popup moving to another widget's size
            "enter": 250,                    // a toast, an OSD or a card arriving
            "exit": 200,                     // and leaving
            "move": 200,                     // a small shift: toasts restacking
            "slide": 300,                    // a larger slide: menus, pages
            "fade": 150,                     // appearing or disappearing in place
            "value": 400,                    // a value bar following its data
            "heartbeat": 350,                // the wave on graphs when a sample arrives
            "pop": 380,                      // a mark popping in; "Clear all" is timed from it
            "pulse": 1000,                   // one breath of a pulsing indicator
            "spin": 800,                     // one turn of a spinner
            "themeChange": 400               // colours moving to a new theme
        },
        "curves": {
            "hover": "OutQuad",
            "state": "OutQuad",
            "expand": "OutQuad",
            "popupOpen": "OutQuad",
            "popupClose": "InQuad",
            "popupResize": "OutQuad",
            "enter": "OutCubic",
            "exit": "InCubic",
            "move": "OutCubic",
            "slide": "OutCubic",
            "fade": "OutQuad",
            "value": "Linear",
            "heartbeat": "OutQuad",
            "pop": "OutBack",
            "pulse": "InOutQuad",
            "spin": "Linear",
            "themeChange": "OutQuad"
        }
    })
}
