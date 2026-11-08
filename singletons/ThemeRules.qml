pragma Singleton

import Quickshell
import QtQuick

// Pure functions behind Theme: resolving a theme file's `extends` chain and layering the
// result over the built-in theme. No I/O — the caller passes a function that reads a theme
// by name — so tests/ThemeTest.qml exercises them with made-up themes.
// See docs/plans/themes.md.
//
// A theme file:
//   {
//     "extends":    "<theme name>",          optional; the built-in theme otherwise
//     "colorsFrom": "<path>",                 optional; a palette file, e.g. from matugen
//     "colors":     { "<token>": "#rrggbb" }, optional
//     "fonts":      { "<token>": … },         optional
//     "bar":        { "<token>": <number> },  optional; geometry, see barTokens
//     "durations":  { "<role>": <ms> },       optional; animation roles, see Theme
//     "curves":     { "<role>": "<curve>" }   optional; a Qt easing name ("OutQuad", …) or
//                                             the name of a curve in the curves library
//   }
//
// The curves library, ~/.config/h2s_shell/curves.json, shared by every theme:
//   { "<name>": [x1, y1, x2, y2] }            a cubic Bézier from (0,0) to (1,1)
// or, for several segments, Qt's own form: [c1x, c1y, c2x, c2y, endX, endY, …], the last
// end being (1,1).
// Every group is partial: what a theme leaves out comes from what it extends.
Singleton {
    id: root

    // Groups of tokens a theme file may set
    readonly property var groups: ["colors", "fonts", "bar", "durations", "curves"].concat(shapeGroups)

    // The groups of radii, borders and spacing by kind of element (themes stage 7)
    readonly property var shapeGroups: ["capsule", "workspace", "tray", "popup", "row", "listItem", "dropdown",
        "powerMenu", "button", "saveButton", "cancelButton", "deleteButton", "iconButton", "pill", "field",
        "notificationCard", "osdToast", "osdVolume", "osdMessage", "tooltip", "settings", "calendar",
        "checkbox", "lock", "border", "target", "popupWidth"]

    // The bar's geometry: sizes in pixels, corner radii in percent of half the bar's height
    readonly property var barTokens: ["barHeight", "reservedSpace", "topOffset", "leftMargin", "rightMargin",
        "leftPadding", "rightPadding", "radiusTopLeft", "radiusTopRight", "radiusBottomLeft", "radiusBottomRight",
        "cellVerticalMargin", "widgetSpacing", "borderWidth"]

    // The chain for `name`, the theme itself first and its ancestors after it, each
    // { name, theme }. `readTheme(name)` returns the parsed file or null when there is
    // none. Stops at a missing theme (reported, the rest of the chain still applies) and
    // at a cycle (reported, the theme seen again is not applied twice).
    // Returns { chain: [{ name, theme }], errors: [string] }.
    function chainFor(name, readTheme, maxDepth) {
        const chain = [];
        const errors = [];
        const seen = [];
        let current = name;
        const limit = maxDepth ?? 16;
        while (current && current !== "") {
            if (seen.includes(current)) {
                errors.push("Theme \"" + current + "\" extends itself through " + seen.join(" → "));
                break;
            }
            if (seen.length >= limit) {
                errors.push("Theme chain longer than " + limit + ": " + seen.join(" → "));
                break;
            }
            seen.push(current);
            const theme = readTheme(current);
            if (theme === null || theme === undefined) {
                // The default theme may simply not exist: that is the built-in theme
                if (current !== "default")
                    errors.push("Theme \"" + current + "\" not found");
                break;
            }
            chain.push({ name: current, theme: theme });
            current = typeof theme.extends === "string" ? theme.extends : "";
        }
        return { chain: chain, errors: errors };
    }

    // The built-in values overlaid by the chain, ancestors first, so the theme itself has
    // the last word. Within one theme, its palette file (`colorsFrom`, passed in
    // `palettes[name]`) comes before its own colours, so a theme can adjust a generated
    // palette. Tokens the built-in theme does not know are ignored. Inputs are not
    // modified. Returns { group: { token: value } } for every group.
    // Colours that take another's value until a theme sets them — built in as "" — so a
    // theme that changes the accent changes them too
    readonly property var colorFollows: ({ visualizer: "accent" })

    function resolve(builtin, chain, palettes) {
        const result = {};
        for (const group of groups) {
            if (builtin[group] !== undefined)
                result[group] = Object.assign({}, builtin[group]);
        }
        for (let i = chain.length - 1; i >= 0; i--) {
            const entry = chain[i];
            const layers = [];
            if (palettes?.[entry.name])
                layers.push({ group: "colors", values: palettes[entry.name] });
            for (const group of groups)
                layers.push({ group: group, values: entry.theme[group] });
            for (const layer of layers) {
                for (const token in layer.values ?? {}) {
                    if (result[layer.group] && token in result[layer.group])
                        result[layer.group][token] = layer.values[token];
                }
            }
        }
        // Followers left unset take their leader's value
        for (const token in colorFollows) {
            if (result.colors && token in result.colors && !result.colors[token])
                result.colors[token] = result.colors[colorFollows[token]];
        }
        return result;
    }

    // ---- What the Appearance pages show ----

    // The base colours a theme sets, by group, with what each is for (the transparent
    // variants are derived in Theme, not set)
    readonly property var colorTokens: [
        { group: "Backgrounds", token: "barBackground", label: "Bar", hint: "The bar" },
        { group: "Backgrounds", token: "popupBackground", label: "Popup", hint: "Popups and their curved corners" },
        { group: "Backgrounds", token: "surface", label: "Surface", hint: "An element: bar cell, card, field, row" },
        { group: "Backgrounds", token: "surfaceHover", label: "Surface, hovered", hint: "An element under the pointer, or whose popup is open" },
        { group: "Backgrounds", token: "scrim", label: "Scrim", hint: "Behind the screensaver and the lock screen" },
        { group: "Accent", token: "accent", label: "Accent", hint: "Selection, active state, progress, graphs" },
        { group: "Accent", token: "accentHover", label: "Accent, hovered", hint: "The accent under the pointer" },
        { group: "Accent", token: "accentDark", label: "Accent, dark", hint: "Filled accent: focused workspace, code buttons" },
        { group: "Accent", token: "onAccent", label: "On accent", hint: "Text and icons on the accent" },
        { group: "Accent", token: "accentSecondary", label: "Second accent", hint: "A second series or highlight: upload, sidebar selection" },
        { group: "Text", token: "textPrimary", label: "Primary", hint: "Labels, headings, the clock" },
        { group: "Text", token: "textSecondary", label: "Secondary", hint: "Secondary labels, body text" },
        { group: "Text", token: "textMuted", label: "Muted", hint: "Timestamps, links, empty states" },
        { group: "Text", token: "selection", label: "Selection", hint: "Behind selected text: fields, notifications' text, the lock screen" },
        { group: "Text", token: "selectedText", label: "Selected text", hint: "Text that is selected" },
        { group: "Text", token: "textDisabled", label: "Disabled", hint: "Disabled, other-month days, faint icons; dividers and faint fills derive from it" },
        { group: "Status", token: "error", label: "Error", hint: "Errors, destructive actions" },
        { group: "Status", token: "warning", label: "Warning", hint: "Warnings, volume above 100%" },
        { group: "Status", token: "success", label: "Success", hint: "Connected, done" },
        { group: "Workspaces", token: "workspaceActive", label: "Active", hint: "A workspace that is active but not focused (focused uses the dark accent)" },
        { group: "Workspaces", token: "workspaceSpecial", label: "Special", hint: "A shown special (scratchpad) workspace" },
        { group: "Calendar", token: "calendarToday", label: "Today", hint: "The circle behind today's date" },
        { group: "Buttons", token: "confirm", label: "Confirm", hint: "Confirming: add an event" },
        { group: "Buttons", token: "confirmHover", label: "Confirm, hovered", hint: "A confirm button under the pointer" },
        { group: "Buttons", token: "confirmSecondary", label: "Confirm a change", hint: "Confirming a change: save an edited event" },
        { group: "Buttons", token: "confirmSecondaryHover", label: "Confirm a change, hovered", hint: "A confirm-a-change button under the pointer" },
        { group: "Borders", token: "barBorder", label: "Bar", hint: "Along the bar's edge facing the desktop, when its border width is above 0" },
        { group: "Borders", token: "capsuleBorder", label: "Bar cells", hint: "Around the widgets' cells on the bar, when their border width is above 0" },
        { group: "Borders", token: "popupBorder", label: "Popups", hint: "Around popups, when their border width is above 0" },
        { group: "Borders", token: "osdToastBorder", label: "Notification toasts", hint: "Around toasts, when their border width is above 0" },
        { group: "Borders", token: "osdVolumeBorder", label: "Volume OSD", hint: "Around the volume OSD, when its border width is above 0" },
        { group: "Borders", token: "osdMessageBorder", label: "Shell messages", hint: "Around the shell's message pill, when its border width is above 0" },
        { group: "Music", token: "visualizer", label: "Visualiser", hint: "The music visualiser; follows the accent until set" }
    ]

    // The bar's geometry tokens (barTokens) as the Bar shape page shows them: label, use,
    // slider range and unit. Named for a bar at the top, they apply relative to the bar's
    // edge (BarGeometry): the "top" ones are at the screen's edge, the "bottom" ones face
    // the desktop.
    readonly property var barTokenInfo: [
        { token: "barHeight", group: "Size", label: "Bar height", hint: "Its thickness — its width at a side — excluding the reserved space and edge offset", from: 10, to: 80, suffix: " px" },
        { token: "reservedSpace", group: "Size", label: "Reserved space", hint: "Kept free for the bar at its screen edge: its height and offset", from: 10, to: 80, suffix: " px" },
        { token: "topOffset", group: "Size", label: "Edge offset", hint: "Between the bar and its screen edge", from: 0, to: 80, suffix: " px" },
        { token: "leftMargin", group: "Size", label: "Left margin", hint: "Between the bar's start and the screen's edge: its left end, or its top at a side", from: 0, to: 300, suffix: " px" },
        { token: "rightMargin", group: "Size", label: "Right margin", hint: "Between the bar's end and the screen's edge: its right end, or its bottom at a side", from: 0, to: 300, suffix: " px" },
        { token: "leftPadding", group: "Size", label: "Left padding", hint: "Inside the bar, before its first widget (above it at a side)", from: 0, to: 300, suffix: " px" },
        { token: "rightPadding", group: "Size", label: "Right padding", hint: "Inside the bar, after its last widget (below it at a side)", from: 0, to: 300, suffix: " px" },
        { token: "radiusTopLeft", group: "Corners", label: "Screen edge, left", hint: "At the screen's edge, at the bar's start (top at a side); in percent of half the bar's thickness", from: 0, to: 100, suffix: "%" },
        { token: "radiusTopRight", group: "Corners", label: "Screen edge, right", hint: "At the screen's edge, at the bar's end (bottom at a side); in percent of half the bar's thickness", from: 0, to: 100, suffix: "%" },
        { token: "radiusBottomLeft", group: "Corners", label: "Desktop side, left", hint: "Facing the desktop, at the bar's start (top at a side); in percent of half the bar's thickness", from: 0, to: 100, suffix: "%" },
        { token: "radiusBottomRight", group: "Corners", label: "Desktop side, right", hint: "Facing the desktop, at the bar's end (bottom at a side); in percent of half the bar's thickness", from: 0, to: 100, suffix: "%" },
        { token: "cellVerticalMargin", group: "Widgets", label: "Cell margin", hint: "Across the bar, on each side of a widget's cell", from: 0, to: 20, suffix: " px" },
        { token: "widgetSpacing", group: "Widgets", label: "Widget spacing", hint: "Between the widgets of a section", from: 0, to: 30, suffix: " px" },
        { token: "borderWidth", group: "Border", label: "Border width", hint: "Along the edge facing the desktop, in the colour Bar border (Colors); 0: none", from: 0, to: 10, suffix: " px" }
    ]

    // The animation roles as the Animations page shows them: what each moves, the range of
    // its duration's slider (ms), and its curve tokens — one per role, but a popup has one
    // for opening and one for closing
    readonly property var animationRoles: [
        { role: "hover", label: "Hover", hint: "Colour under the pointer", to: 1000, curves: ["hover"] },
        { role: "state", label: "State", hint: "A switch, a focused workspace, a field's state", to: 1000, curves: ["state"] },
        { role: "expand", label: "Expand", hint: "Something growing or shrinking in place", to: 1000, curves: ["expand"] },
        { role: "popup", label: "Popup", hint: "A popup opening or closing", to: 1000, curves: ["popupOpen", "popupClose"] },
        { role: "popupResize", label: "Popup resize", hint: "A popup moving to another widget's size", to: 1000, curves: ["popupResize"] },
        { role: "enter", label: "Enter", hint: "A toast, an OSD or a card arriving", to: 1500, curves: ["enter"] },
        { role: "exit", label: "Exit", hint: "A toast, an OSD or a card leaving", to: 1500, curves: ["exit"] },
        { role: "move", label: "Move", hint: "A small shift: toasts restacking, the selected week", to: 1500, curves: ["move"] },
        { role: "slide", label: "Slide", hint: "A larger slide: pages, months, the bar's shape", to: 1500, curves: ["slide"] },
        { role: "fade", label: "Fade", hint: "Appearing or disappearing in place", to: 1500, curves: ["fade"] },
        { role: "value", label: "Value", hint: "A bar or slider following its value", to: 2000, curves: ["value"] },
        { role: "heartbeat", label: "Heartbeat", hint: "The wave on graphs when a sample arrives", to: 2000, curves: ["heartbeat"] },
        { role: "pop", label: "Pop", hint: "A mark popping in, the bell; \"Clear all\" is timed from it", to: 2000, curves: ["pop"] },
        { role: "pulse", label: "Pulse", hint: "One breath of a pulsing indicator", to: 4000, curves: ["pulse"] },
        { role: "spin", label: "Spin", hint: "One turn of a spinner", to: 4000, curves: ["spin"] },
        { role: "themeChange", label: "Theme change", hint: "Colours moving to a new theme", to: 2000, curves: ["themeChange"] }
    ]

    // Qt's curves by name, for picking one: each kind in, out, in-out and out-in
    readonly property var qtCurveNames: {
        const names = ["Linear"];
        for (const kind of ["Quad", "Cubic", "Quart", "Quint", "Sine", "Expo", "Circ", "Back", "Elastic", "Bounce"]) {
            for (const way of ["In", "Out", "InOut", "OutIn"])
                names.push(way + kind);
        }
        return names;
    }

    // The shape groups' tokens as the Appearance pages show them, by group: label, use,
    // slider range and unit. A page lists groups from here (ShapeSettings).
    readonly property var shapeTokenInfo: {
        const px = " px";
        const radius = (hint, to) => ({ token: "radius", label: "Corner radius", hint: hint, from: 0, to: to ?? 30, suffix: px });
        const border = hint => ({ token: "borderWidth", label: "Border width", hint: hint, from: 0, to: 10, suffix: px });
        return {
            capsule: [radius("A widget's cell on the bar", 20),
                { token: "horizontalPadding", label: "Padding", hint: "Between a cell's edge and its content", from: 0, to: 30, suffix: px },
                border("Around each cell, in the colour Bar cells (Colors → Borders); 0: none")],
            workspace: [
                { token: "pillRadius", label: "Corner radius", hint: "A workspace's pill", from: 0, to: 20, suffix: px },
                { token: "pillHorizontalPadding", label: "Padding", hint: "Between a pill's edge and its name", from: 0, to: 20, suffix: px },
                { token: "pillHeight", label: "Height", hint: "And the narrowest a pill gets", from: 10, to: 40, suffix: px },
                { token: "pillSpacing", label: "Spacing", hint: "Between the pills", from: 0, to: 20, suffix: px }],
            tray: [
                { token: "pillRadius", label: "Corner radius", hint: "An icon's highlight, under the pointer or with its menu open", from: 0, to: 20, suffix: px },
                { token: "pillWidth", label: "Width", hint: "Each icon's place", from: 12, to: 48, suffix: px },
                { token: "iconSize", label: "Icon size", hint: "The icons", from: 8, to: 40, suffix: px },
                { token: "pillSpacing", label: "Spacing", hint: "Between the icons", from: 0, to: 20, suffix: px }],
            popup: [radius("The curves joining a popup to the bar, and its bottom corners", 60),
                { token: "contentPadding", label: "Padding", hint: "Around a popup's content", from: 0, to: 40, suffix: px },
                border("Around a popup, open where it joins the bar, in the colour Popups (Colors → Borders); 0: none")],
            row: [radius("Rows and cards in popups: networks, devices, events"),
                { token: "horizontalPadding", label: "Padding", hint: "Between a row's edge and its content", from: 0, to: 30, suffix: px }],
            listItem: [radius("Menu and list items: the tray menu, audio devices, a dropdown's options", 20)],
            dropdown: [radius("A dropdown's button and its list", 20)],
            powerMenu: [
                { token: "buttonRadius", label: "Corner radius", hint: "The power menu's buttons", from: 0, to: 30, suffix: px },
                { token: "buttonHeight", label: "Height", hint: "The power menu's buttons", from: 24, to: 80, suffix: px }],
            button: [radius("General buttons", 20),
                { token: "horizontalPadding", label: "Padding across", hint: "Every button: between its edge and its label", from: 0, to: 30, suffix: px },
                { token: "verticalPadding", label: "Padding down", hint: "Every button: above and below its label", from: 0, to: 20, suffix: px },
                { token: "minHeight", label: "Height", hint: "Every button's least height", from: 14, to: 48, suffix: px }],
            saveButton: [radius("Buttons that save or confirm: Save, Connect", 20)],
            cancelButton: [radius("Buttons that cancel", 20)],
            deleteButton: [radius("Buttons that delete or disconnect, which ask first", 20)],
            iconButton: [radius("Small buttons with an icon: pin, reset, remove", 20)],
            pill: [radius("Choices: presets, options, days", 20),
                { token: "horizontalPadding", label: "Padding", hint: "Between a pill's edge and its label", from: 0, to: 30, suffix: px },
                { token: "minHeight", label: "Height", hint: "A pill's least height", from: 14, to: 48, suffix: px }],
            field: [radius("Text fields", 20),
                { token: "horizontalPadding", label: "Padding", hint: "Between a field's edge and its text", from: 0, to: 30, suffix: px }],
            checkbox: [radius("Check boxes", 10)],
            target: [
                { token: "minSize", label: "Least target", hint: "Every control takes a click or a tap this far around it at least, though it looks smaller: room for a finger", from: 0, to: 60, suffix: px }],
            tooltip: [radius("Tooltips", 20),
                { token: "horizontalPadding", label: "Padding across", hint: "Between a tooltip's edge and its text", from: 0, to: 30, suffix: px },
                { token: "verticalPadding", label: "Padding down", hint: "Above and below a tooltip's text", from: 0, to: 30, suffix: px }],
            border: [
                { token: "width", label: "Outline width", hint: "Ordinary outlines: fields, lists, pills, tooltips", from: 0, to: 6, suffix: px },
                { token: "selectedWidth", label: "Selection width", hint: "Selection rings: colour swatches, curve handles, an event's colour edge", from: 0, to: 8, suffix: px }],
            osdToast: [radius("A notification toast, and the queue count beside it"),
                { token: "padding", label: "Padding", hint: "Around a toast's content", from: 0, to: 40, suffix: px },
                { token: "width", label: "Width", hint: "A toast's width", from: 200, to: 700, suffix: px },
                { token: "screenGap", label: "Gap to the edge", hint: "Between toasts and the screen's edge, and below the bar", from: 0, to: 80, suffix: px },
                { token: "spacing", label: "Spacing", hint: "Between toasts", from: 0, to: 40, suffix: px },
                { token: "badgeWidth", label: "Queue count width", hint: "The count of waiting notifications", from: 20, to: 80, suffix: px },
                border("Around toasts and the queue count, in the colour Notification toasts (Colors → Borders); 0: none")],
            notificationCard: [radius("A notification in the notifications panel, and on the lock screen"),
                { token: "padding", label: "Padding", hint: "Around a card's content in the panel", from: 0, to: 40, suffix: px },
                { token: "controlRadius", label: "Controls' radius", hint: "A notification's buttons, reply field and chips, here and in toasts", from: 0, to: 20, suffix: px }],
            osdVolume: [radius("The volume OSD at the screen's edge"),
                { token: "padding", label: "Padding", hint: "Around the volume OSD's content", from: 0, to: 30, suffix: px },
                border("Around the volume OSD, in the colour Volume OSD (Colors → Borders); 0: none")],
            osdMessage: [{ token: "radius", label: "Corner radius", hint: "The shell's message pill (\"Settings saved\"); -1: fully round", from: -1, to: 30, suffix: px },
                border("Around the message pill, in the colour Shell messages (Colors → Borders); 0: none")],
            popupWidth: [
                { token: "all", label: "Every popup", hint: "Multiplies each popup's own width below", from: 50, to: 200, suffix: "%" },
                { token: "network", label: "Network", hint: "", from: 50, to: 200, suffix: "%", base: 280 },
                { token: "bluetooth", label: "Bluetooth", hint: "", from: 50, to: 200, suffix: "%", base: 280 },
                { token: "hardware", label: "Hardware", hint: "", from: 50, to: 200, suffix: "%", base: 280 },
                { token: "sound", label: "Sound", hint: "", from: 50, to: 200, suffix: "%", base: 300 },
                { token: "music", label: "Music", hint: "", from: 50, to: 200, suffix: "%", base: 320 },
                { token: "notifications", label: "Notifications", hint: "", from: 50, to: 200, suffix: "%", base: 350 },
                { token: "tray", label: "Tray menu", hint: "", from: 50, to: 200, suffix: "%", base: 220 },
                { token: "power", label: "Power menu", hint: "", from: 50, to: 200, suffix: "%", base: 200 },
                { token: "calendar", label: "Calendar", hint: "Both columns, and its height", from: 50, to: 200, suffix: "%", base: 551 },
                { token: "battery", label: "Battery", hint: "", from: 50, to: 200, suffix: "%", base: 320 }],
            settings: [
                { token: "pageMargin", label: "Page margin", hint: "Around a settings page", from: 0, to: 40, suffix: px },
                { token: "sidebarItemRadius", label: "Sidebar radius", hint: "The sidebar's pages and the selection mark", from: 0, to: 20, suffix: px },
                { token: "tabRadius", label: "Tab radius", hint: "The Behaviour and Appearance tabs", from: 0, to: 20, suffix: px },
                { token: "tabHorizontalPadding", label: "Tab padding", hint: "Between a tab's edge and its label", from: 0, to: 40, suffix: px },
                { token: "cardRadius", label: "Card radius", hint: "Cards and boxes on settings pages", from: 0, to: 20, suffix: px }],
            calendar: [{ token: "dayRadius", label: "Day radius", hint: "A day in the month, and the week's frame", from: 0, to: 20, suffix: px }],
            lock: [
                { token: "cardRadius", label: "Card radius", hint: "The lock screen's password card", from: 0, to: 40, suffix: px },
                { token: "controlRadius", label: "Controls' radius", hint: "Its password field and button", from: 0, to: 30, suffix: px },
                { token: "controlHeight", label: "Controls' height", hint: "Its password field and button", from: 24, to: 80, suffix: px }]
        };
    }

    // The font tokens: the family, and the sizes in pixels with what each is for and the
    // range its slider offers
    readonly property var fontTokens: [
        { token: "sizeTiny", label: "Tiny", hint: "The smallest form labels", from: 6, to: 30 },
        { token: "sizeXSmall", label: "Extra small", hint: "Very small secondary labels", from: 6, to: 30 },
        { token: "sizeSmall", label: "Small", hint: "Metadata, times, captions, hints", from: 6, to: 30 },
        { token: "sizeBody", label: "Body", hint: "Most text: rows, fields, buttons", from: 6, to: 30 },
        { token: "sizeBodyLarge", label: "Body, large", hint: "Larger labels: settings names, volume", from: 6, to: 30 },
        { token: "sizeMedium", label: "Medium", hint: "Subheadings, small icons", from: 6, to: 36 },
        { token: "sizeSection", label: "Section", hint: "Section icons, calendar headers, the bell", from: 8, to: 40 },
        { token: "sizeHeading", label: "Heading", hint: "Settings headings, most bar icons", from: 8, to: 40 },
        { token: "sizeTitle", label: "Title", hint: "Panel titles, large bar icons (clock, power, settings)", from: 8, to: 48 },
        { token: "sizeDisplay", label: "Display", hint: "Calendar events", from: 8, to: 48 },
        { token: "sizeLargeDisplay", label: "Large display", hint: "Music panel headers", from: 8, to: 60 },
        { token: "sizeXXLargeDisplay", label: "Extra large display", hint: "The music track's name", from: 10, to: 72 },
        { token: "sizeHero", label: "Hero", hint: "The empty notifications icon", from: 16, to: 96 }
    ]

    // Where each resolved value comes from: { group: { token: { theme, palette } } } for
    // what the chain sets — `theme` the name of the theme that has the last word, `palette`
    // true when it comes from that theme's palette file. A token absent here is built in.
    function origins(chain, palettes) {
        const result = {};
        for (const group of groups)
            result[group] = {};
        for (let i = chain.length - 1; i >= 0; i--) {
            const entry = chain[i];
            for (const token in palettes?.[entry.name] ?? {})
                result.colors[token] = { theme: entry.name, palette: true };
            for (const group of groups) {
                for (const token in entry.theme[group] ?? {})
                    result[group][token] = { theme: entry.name, palette: false };
            }
        }
        // A follower nothing sets: its leader's value
        for (const token in colorFollows) {
            if (!(token in result.colors))
                result.colors[token] = { follows: colorFollows[token] };
        }
        return result;
    }

    // ---- Drafts: changes made in the settings, not saved yet ----
    // A draft is part of a theme file, { group: { token: value } }, kept in a file of its
    // own; null as a value means the token is removed from the theme (a reset). It is laid
    // over the theme file, so what the draft does not touch follows the file.

    // The theme file `theme` with `draft` laid over it. Inputs are not modified.
    function applyDraft(theme, draft) {
        const result = JSON.parse(JSON.stringify(theme ?? {}));
        for (const group in draft ?? {}) {
            const values = Object.assign({}, result[group] ?? {});
            for (const token in draft[group]) {
                if (draft[group][token] === null)
                    delete values[token];
                else
                    values[token] = draft[group][token];
            }
            if (Object.keys(values).length > 0)
                result[group] = values;
            else
                delete result[group];
        }
        return result;
    }

    // `draft` with one token changed to `value`, or, with `value` null, reset: removed from
    // the theme if `theme` sets it, else dropped from the draft. Empty groups go.
    function draftWith(draft, theme, group, token, value) {
        const result = JSON.parse(JSON.stringify(draft ?? {}));
        result[group] = result[group] ?? {};
        if (value === null && !(token in (theme?.[group] ?? {})))
            delete result[group][token];
        else
            result[group][token] = value;
        if (Object.keys(result[group]).length === 0)
            delete result[group];
        return result;
    }

    // `draft` without its change to one token: back to what the theme file has
    function draftWithout(draft, group, token) {
        const result = JSON.parse(JSON.stringify(draft ?? {}));
        if (result[group]) {
            delete result[group][token];
            if (Object.keys(result[group]).length === 0)
                delete result[group];
        }
        return result;
    }

    // The part of `draft` in `groups` (all when not given), and the rest:
    // { taken, rest } — each a draft, possibly empty
    function splitDraft(draft, groups) {
        const taken = {};
        const rest = {};
        for (const group in draft ?? {}) {
            if (!groups || groups.includes(group))
                taken[group] = draft[group];
            else
                rest[group] = draft[group];
        }
        return { taken: taken, rest: rest };
    }

    // ---- Managing themes ----

    // Whether `name` may name a theme file: not empty, no spaces at its ends, no slash,
    // not hidden
    function validThemeName(name) {
        return typeof name === "string" && name.trim() !== "" && name === name.trim()
            && !name.includes("/") && !name.startsWith(".");
    }

    // The themes (`{ name: parsed file }`) that extend `oldName`, pointed at `newName`:
    // only those that changed. Inputs are not modified.
    function renameExtends(themes, oldName, newName) {
        const changed = {};
        for (const name in themes ?? {}) {
            if (themes[name]?.extends === oldName)
                changed[name] = Object.assign({}, themes[name], { extends: newName });
        }
        return changed;
    }

    // The themes that extend `removed`, extending what it extended instead (the default
    // theme when it extended nothing): only those that changed
    function withoutExtends(themes, removed) {
        const parent = typeof themes?.[removed]?.extends === "string" ? themes[removed].extends : "default";
        return renameExtends(themes, removed, parent);
    }

    // Profiles and pinned globals with `appearance.theme` set to `oldName` set to
    // `newName` instead. Inputs are not modified.
    // Returns { profiles, globals, changed: [profile names, "global" for the pin] }.
    function retargetTheme(profiles, globals, oldName, newName) {
        const newProfiles = JSON.parse(JSON.stringify(profiles ?? []));
        const newGlobals = Object.assign({}, globals ?? {});
        const changed = [];
        for (const profile of newProfiles) {
            if (profile.set?.["appearance.theme"] === oldName) {
                profile.set["appearance.theme"] = newName;
                changed.push(profile.name);
            }
        }
        if (newGlobals["appearance.theme"] === oldName) {
            newGlobals["appearance.theme"] = newName;
            changed.push("global");
        }
        return { profiles: newProfiles, globals: newGlobals, changed: changed };
    }

    // Whether `name` extending `base` would make a cycle: `base`'s chain reaches `name`
    function extendsCycle(name, base, readTheme) {
        if (name === base)
            return true;
        return chainFor(base, readTheme).chain.some(entry => entry.name === name);
    }

    // ---- Curves ----

    // The easing to fall back on for a curve that cannot be found
    readonly property string fallbackCurve: "OutQuad"

    // Whether `name` is one of Qt's easing curves ("OutQuad", "Linear", …)
    function isQtCurve(name) {
        return typeof name === "string" && /^[A-Z]/.test(name) && typeof Easing[name] === "number"
            && name !== "BezierSpline" && name !== "Bezier";
    }

    // A library curve's points in Qt's form (6 numbers per segment, ending at 1,1), or
    // null when they are not a curve: 4 numbers are one segment, its end added
    function curvePoints(points) {
        if (!Array.isArray(points) || points.some(value => typeof value !== "number" || !isFinite(value)))
            return null;
        const full = points.length === 4 ? points.concat([1, 1]) : points;
        if (full.length === 0 || full.length % 6 !== 0)
            return null;
        if (full[full.length - 2] !== 1 || full[full.length - 1] !== 1)
            return null;
        // Time only moves forward: every control point's x within 0–1
        for (let i = 0; i < full.length; i += 2) {
            if (full[i] < 0 || full[i] > 1)
                return null;
        }
        return full;
    }

    // The easing for a curve name, as a value an animation's `easing` takes: a Qt curve,
    // or a library curve as a Bézier spline. Unknown names and broken curves fall back.
    // Returns { easing, error } — error is "" when the name resolved.
    function curveEasing(name, library) {
        if (isQtCurve(name))
            return { easing: { type: Easing[name] }, error: "" };
        const points = library && Object.prototype.hasOwnProperty.call(library, name) ? curvePoints(library[name]) : null;
        if (points !== null)
            return { easing: { type: Easing.BezierSpline, bezierCurve: points }, error: "" };
        const why = library && Object.prototype.hasOwnProperty.call(library, name)
            ? "Curve \"" + name + "\" is not a valid curve"
            : "Curve \"" + name + "\" not found";
        return { easing: { type: Easing[fallbackCurve] }, error: why };
    }

    // Qt's curves as one cubic Bézier each, to start a library curve from: close
    // approximations (easings.net), not exact. Bounce and elastic curves have none.
    readonly property var qtCurveApproximations: ({
        Linear: [0, 0, 1, 1],
        InSine: [0.12, 0, 0.39, 0], OutSine: [0.61, 1, 0.88, 1], InOutSine: [0.37, 0, 0.63, 1],
        InQuad: [0.11, 0, 0.5, 0], OutQuad: [0.5, 1, 0.89, 1], InOutQuad: [0.45, 0, 0.55, 1],
        InCubic: [0.32, 0, 0.67, 0], OutCubic: [0.33, 1, 0.68, 1], InOutCubic: [0.65, 0, 0.35, 1],
        InQuart: [0.5, 0, 0.75, 0], OutQuart: [0.25, 1, 0.5, 1], InOutQuart: [0.76, 0, 0.24, 1],
        InQuint: [0.64, 0, 0.78, 0], OutQuint: [0.22, 1, 0.36, 1], InOutQuint: [0.83, 0, 0.17, 1],
        InExpo: [0.7, 0, 0.84, 0], OutExpo: [0.16, 1, 0.3, 1], InOutExpo: [0.87, 0, 0.13, 1],
        InCirc: [0.55, 0, 1, 0.45], OutCirc: [0, 0.55, 0.45, 1], InOutCirc: [0.85, 0, 0.15, 1],
        InBack: [0.36, 0, 0.66, -0.56], OutBack: [0.34, 1.56, 0.64, 1], InOutBack: [0.68, -0.6, 0.32, 1.6]
    })

    // Where the curve `name` is used: [{ theme, role }] over `themes` ({ name: parsed
    // theme file }), by each theme's own `curves` (what it inherits is counted where it
    // is set)
    function curveUsages(themes, name) {
        const usages = [];
        for (const theme of Object.keys(themes ?? {}).sort()) {
            const curves = themes[theme]?.curves ?? {};
            for (const role in curves) {
                if (curves[role] === name)
                    usages.push({ theme: theme, role: role });
            }
        }
        return usages;
    }

    // `themes` with every reference to the curve `oldName` pointing at `newName`: only
    // the themes that changed, { name: new theme }. Inputs are not modified.
    function renameCurveIn(themes, oldName, newName) {
        const changed = {};
        for (const theme in themes ?? {}) {
            const curves = themes[theme]?.curves;
            if (!curves || !Object.values(curves).includes(oldName))
                continue;
            const copy = JSON.parse(JSON.stringify(themes[theme]));
            for (const role in copy.curves) {
                if (copy.curves[role] === oldName)
                    copy.curves[role] = newName;
            }
            changed[theme] = copy;
        }
        return changed;
    }

    // Whether `name` may name a library curve: not empty, not a Qt curve's name
    function validCurveName(name) {
        return typeof name === "string" && name.trim() !== "" && name === name.trim()
            && !isQtCurve(name) && name !== "BezierSpline" && name !== "Bezier";
    }

    // A file name for a theme named after `wanted` that `exists(name)` does not report
    // taken: the name itself, else "<name> 2", "<name> 3", …
    function freeName(wanted, exists) {
        const base = wanted.replace(/[\/]/g, "-").trim() || "Theme";
        let name = base;
        for (let i = 2; exists(name); i++)
            name = base + " " + i;
        return name;
    }

    // Moves the bar geometry from profiles into themes, once (docs/plans/themes.md, stage
    // 3), so the bar looks the same in every profile afterwards. Each profile that sets
    // any `bar.layout.*` gets a theme named after it holding those values, extending the
    // theme of the nearest profile before it that got one ("default" for the first), and
    // picks it with `appearance.theme` — the same layering profiles had. Geometry pinned
    // as global goes into every such theme (and gives the first profile one if none has
    // its own). `legacyLayout`: the `bar.layout` section of a config from before profiles
    // whose values never reached a profile, or undefined; it counts as the first profile's.
    // Inputs are not modified.
    // Returns { profiles, globals, themes: [{ name, theme }] }.
    function themesFromBarLayout(profiles, globals, legacyLayout, exists) {
        const newProfiles = JSON.parse(JSON.stringify(profiles ?? []));
        const newGlobals = Object.assign({}, globals ?? {});
        const take = set => {
            const values = {};
            for (const token of barTokens) {
                if (set && ("bar.layout." + token) in set) {
                    values[token] = set["bar.layout." + token];
                    delete set["bar.layout." + token];
                }
            }
            return values;
        };
        const pinned = take(newGlobals);
        const themes = [];
        const taken = name => exists(name) || themes.some(entry => entry.name === name);
        let parent = "default";
        newProfiles.forEach((profile, index) => {
            profile.set = profile.set ?? {};
            const own = take(profile.set);
            if (index === 0 && legacyLayout) {
                for (const token of barTokens) {
                    if (!(token in own) && legacyLayout[token] !== undefined)
                        own[token] = legacyLayout[token];
                }
            }
            const needed = Object.keys(own).length > 0 || (index === 0 && Object.keys(pinned).length > 0);
            if (!needed)
                return;
            const name = freeName(profile.name ?? "Theme", taken);
            themes.push({ name: name, theme: { extends: parent, bar: Object.assign(own, pinned) } });
            profile.set["appearance.theme"] = name;
            parent = name;
        });
        return { profiles: newProfiles, globals: newGlobals, themes: themes };
    }
}
