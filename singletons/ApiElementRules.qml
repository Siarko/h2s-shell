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

    // The warning for a word an element does not know, and the key it is said once under
    function unknownWord(element, property, word, fallback) {
        const shown = String(word).replace(/[^\x20-\x7e]/g, "?").slice(0, 40);
        return { key: element + "." + property + "=" + shown,
            message: "[Api] " + element + ": " + property + " \"" + shown + "\" is not one it has; shown as \"" + fallback + "\"" };
    }
}
