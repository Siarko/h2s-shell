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

    // What a public mark is told (polkit's answer) → PrivilegedMark's internal need. One
    // it does not know is the lock: a control that may ask is never shown as one that
    // does not.
    readonly property var markNeeds: ({ "": "", yes: "yes", auth: "auth", no: "no" })
    readonly property string markNeedDefault: "auth"

    // A public notice's kind → the colour of its line, by its name in Theme
    readonly property var noticeKinds: ({ warning: "warning", danger: "error", success: "success" })
    readonly property string noticeKindDefault: "warning"

    // The longest a text a module hands a public element for one line may be, in
    // characters, before it is cut
    readonly property int textCap: 80

    // A text from a module as a public element shows it on one line: line breaks and
    // tabs folded into spaces, and longer than `textCap` cut, "…" at the end. Anything not
    // a string or a number is "". Characters are counted as code points, so a cut never
    // splits one.
    function oneLine(text) {
        if (typeof text !== "string" && typeof text !== "number")
            return "";
        const folded = String(text).replace(/[\r\n\t\v\f\u0085\u2028\u2029]+/g, " ");
        const characters = Array.from(folded);
        return characters.length > textCap ? characters.slice(0, textCap - 1).join("") + "…" : folded;
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

    function markNeed(need) {
        return pick(markNeeds, need, markNeedDefault);
    }

    function noticeKind(kind) {
        return pick(noticeKinds, kind, noticeKindDefault);
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
