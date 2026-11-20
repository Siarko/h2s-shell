pragma Singleton

import Quickshell
import QtQuick

// What the words on a public element (qs.api) stand for inside the shell. A module picks
// a meaning, `kind`, and a `size`; the element asks here for the internal value. A word
// an element does not know stands for the element's default, and `known` says so. Pure.
Singleton {
    // A public button's kind → SmallButton's and DeleteButton's internal kind
    readonly property var buttonKinds: ({ primary: "save", secondary: "normal", danger: "delete", warning: "warning", success: "success" })
    readonly property string buttonKindDefault: "secondary"

    // The size of an element with a text → the theme's type size, by its name in Theme
    readonly property var textSizes: ({ xs: "fontSizeXSmall", s: "fontSizeSmall", m: "fontSizeBody" })
    readonly property string sizeDefault: "m"

    // A public pill's size → Pill's internal size (the theme's three pill heights)
    readonly property var pillSizes: ({ s: "s", m: "m", l: "l" })
    // (1.32) A public pill's text size → the theme's type size, by its name in Theme: always
    // one of the theme's sizes, never pixels
    readonly property var pillTextSizes: ({ small: "fontSizeSmall", body: "fontSizeBody" })
    readonly property string pillTextSizeDefault: "small"

    // What a public mark is told (polkit's answer) → PrivilegedMark's internal need. One
    // it does not know is the lock: a control that may ask is never shown as one that
    // does not.
    readonly property var markNeeds: ({ "": "", yes: "yes", auth: "auth", no: "no" })
    readonly property string markNeedDefault: "auth"

    // A public notice's kind → the colour of its line, by its name in Theme
    readonly property var noticeKinds: ({ warning: "warning", danger: "error", success: "success" })
    readonly property string noticeKindDefault: "warning"

    // (1.31) A public progress bar's kind → the colour of its fill, by its name in Theme
    readonly property var progressKinds: ({ normal: "accent", success: "success", warning: "warning", danger: "error" })
    readonly property string progressKindDefault: "normal"

    // (1.34) A side panel's sizes → its width at the built-in fonts, by its name in
    // Theme.sidePanelWidths; never wider than `sidePanelShare` of the page area
    readonly property var sidePanelSizes: ({ s: "s", m: "m", l: "l" })
    readonly property real sidePanelShare: 0.9
    // Why a side panel closed, by what happened (sidePanelEvent): its Close button, a click
    // on the dimmed page, Escape, another one opening, the page or window going, a lock
    readonly property var sidePanelReasons: ({ closeButton: "close", outsideClick: "outside", escape: "escape",
        otherOpened: "replaced", pageGone: "page", locked: "lock" })

    // The longest a text a module hands a public element for one line may be, in
    // characters, before it is cut
    readonly property int textCap: 80
    // (1.31) The longest a public tooltip's text may be; it wraps at the tooltip's width
    readonly property int tipCap: 200

    // A text from a module as a public element shows it on one line: line breaks and
    // tabs folded into spaces, and longer than `cap` (`textCap` unless given) cut, "…" at the end. Anything not
    // a string or a number is "". Characters are counted as code points, so a cut never
    // splits one.
    function oneLine(text, cap) {
        if (typeof text !== "string" && typeof text !== "number")
            return "";
        const longest = cap ?? textCap;
        const folded = String(text).replace(/[\r\n\t\v\f\u0085\u2028\u2029]+/g, " ");
        const characters = PrivilegedRules.characters(folded);
        return characters.length > longest ? characters.slice(0, longest - 1).join("") + "…" : folded;
    }

    // A public tooltip's text: as oneLine, cut at `tipCap` (the tooltip wraps it)
    function tipText(text) {
        return oneLine(text, tipCap);
    }

    // A public dropdown's options as the internal one is given them: { value, label } of
    // each, the label on one line. Every other field is left out — the internal dropdown
    // draws a `color` as a dot, and a module puts no colour of its own on screen. Not an
    // array: none.
    function dropdownOptions(options) {
        if (!Array.isArray(options))
            return [];
        return options.map(option => ({ value: option?.value, label: oneLine(option?.label) }));
    }

    // `word` looked up in `table`, else `fallback`'s entry: { value, known }
    function pick(table, word, fallback) {
        const known = typeof word === "string" && Object.prototype.hasOwnProperty.call(table, word);
        return { value: table[known ? word : fallback], known: known };
    }

    function buttonKind(kind) {
        return pick(buttonKinds, kind, buttonKindDefault);
    }

    function textSize(size) {
        return pick(textSizes, size, sizeDefault);
    }

    function pillSize(size) {
        return pick(pillSizes, size, sizeDefault);
    }

    function pillTextSize(size) {
        return pick(pillTextSizes, size, pillTextSizeDefault);
    }

    function markNeed(need) {
        return pick(markNeeds, need, markNeedDefault);
    }

    function noticeKind(kind) {
        return pick(noticeKinds, kind, noticeKindDefault);
    }

    function progressKind(kind) {
        return pick(progressKinds, kind, progressKindDefault);
    }

    function sidePanelSize(size) {
        return pick(sidePanelSizes, size, sizeDefault);
    }

    // A side panel's width: its size's width (`widths`: Theme.sidePanelWidths, by size), at
    // most `sidePanelShare` of the page area's width, never below 0
    function sidePanelWidth(size, pageWidth, widths) {
        const wanted = Number(widths?.[sidePanelSize(size).value]) || 0;
        const room = Math.floor((Number(pageWidth) || 0) * sidePanelShare);
        return Math.max(0, Math.min(wanted, room));
    }

    // What an open side panel does on `event` (a key of sidePanelReasons), `listOpen` when a
    // dropdown's list inside it is open: { close, reason, closeList }. Escape closes that list
    // first, the panel at the next one; every other event closes the panel. Closed already, or
    // an event it does not know: nothing.
    function sidePanelEvent(open, event, listOpen) {
        const nothing = { close: false, reason: "", closeList: false };
        if (open !== true || typeof event !== "string" || !Object.prototype.hasOwnProperty.call(sidePanelReasons, event))
            return nothing;
        if (event === "escape" && listOpen === true)
            return { close: false, reason: "", closeList: true };
        return { close: true, reason: sidePanelReasons[event], closeList: false };
    }

    // Whether a side panel asked to open may: "" when it may, else why not — no page frame
    // above it (a popup panel, an anchor, the bar), or the session locked
    function sidePanelRefusal(frameFound, locked) {
        if (frameFound !== true)
            return "not on a module's settings page";
        if (locked === true)
            return "the session is locked";
        return "";
    }

    // Whether a mark with this need shows anything: the lock, or "not allowed"
    function markShown(need) {
        const inside = markNeed(need).value;
        return inside === "auth" || inside === "no";
    }

    // The warning for a word an element does not know, and the key it is said once under
    function unknownWord(element, property, word, fallback) {
        const shown = String(word).replace(/[^\x20-\x7e]/g, "?").slice(0, 40);
        return { key: element + "." + property + "=" + shown,
            message: "[Api] " + element + ": " + property + " \"" + shown + "\" is not one it has; shown as \"" + fallback + "\"" };
    }
}
