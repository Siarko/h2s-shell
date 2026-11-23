import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Every character outside ASCII that the Settings window and its parts write in a string
// (panels/settings, panels/widget_settings, panels/*.qml, components, api, and singletons,
// whose texts the pages show) is in the built-in theme's font, the Nerd Font the shell asks
// for (hud/StartupWarnings.qml): a character it lacks is drawn from whatever other font has
// it, or as an empty box when none does. The font's characters are fontconfig's (fc-match, a
// tool the runner requires); the font not installed fails the suite. Strings in double or
// single quotes and template literals count, written as characters or as \uXXXX and \u{…}
// escapes; comments, log lines, invisible format characters and what is matched but never
// drawn (notDrawn) do not. A template literal over several lines counts on its first line
// only.
TestCase {
    id: suite
    suiteName: "Glyphs"
    asynchronous: true

    // Missing from the font but still written, by "<file>:<code point>" ("panels/X.qml:270E"):
    // each to be replaced; none is added. The suite fails on a line here that is no longer
    // true, so the list only shrinks.
    readonly property var knownMissing: ({})
    // Written but never drawn, by "<file>:<code point>", with why: not glyphs to check
    readonly property var notDrawn: ({
        "singletons/PolkitRules.qml:3008": "a quote mark polkit's translations put around a command: matched, not drawn",
        "singletons/PolkitRules.qml:3009": "the same",
        "singletons/PolkitRules.qml:300A": "the same",
        "singletons/PolkitRules.qml:300B": "the same",
        "singletons/PolkitRules.qml:300C": "the same",
        "singletons/PolkitRules.qml:300D": "the same",
        "singletons/PolkitRules.qml:300E": "the same",
        "singletons/PolkitRules.qml:300F": "the same",
        "singletons/PolkitRules.qml:FF02": "the same",
        "singletons/PolkitRules.qml:FF07": "the same",
        "singletons/PolkitRules.qml:FF62": "the same",
        "singletons/PolkitRules.qml:FF63": "the same"
    })

    // Invisible by design (direction marks and isolates, joiners): no glyph to draw
    function _formatCharacter(codePoint) {
        return (codePoint >= 0x200B && codePoint <= 0x200F) || (codePoint >= 0x202A && codePoint <= 0x202E)
            || (codePoint >= 0x2060 && codePoint <= 0x2069) || codePoint === 0xFEFF;
    }

    readonly property string family: ThemeBuiltin.values.fonts.family

    // The font's characters: [first, last] code point ranges
    property var _ranges: []
    property Process _font: Process {
        property var lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => suite._font.lines.push(line)
        }
        onExited: code => suite._fontRead(code, lines)
    }

    property Process _scan: Process {
        property var lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => suite._scan.lines.push(line)
        }
        onExited: code => suite._scanned(code, lines)
    }

    function _inFont(codePoint) {
        return _ranges.some(range => codePoint >= range[0] && codePoint <= range[1]);
    }

    // fc-match's charset: "20-7e a0-131 192 …"
    function _rangesOf(charset) {
        return charset.trim().split(/\s+/).filter(part => part !== "").map(part => {
            const ends = part.split("-").map(end => parseInt(end, 16));
            return [ends[0], ends[ends.length - 1]];
        });
    }

    function _hex(codePoint) {
        return codePoint.toString(16).toUpperCase().padStart(4, "0");
    }

    // The escape at text[i] (a backslash) inside a string: { codePoint (or -1), next index }
    function _escape(text, i) {
        if (text[i + 1] !== "u")
            return { codePoint: -1, next: i + 2 };
        if (text[i + 2] === "{") {
            const end = text.indexOf("}", i + 3);
            const value = end > 0 ? parseInt(text.slice(i + 3, end), 16) : NaN;
            return { codePoint: isNaN(value) ? -1 : value, next: end > 0 ? end + 1 : text.length };
        }
        const value = /^[0-9a-fA-F]{4}$/.test(text.slice(i + 2, i + 6)) ? parseInt(text.slice(i + 2, i + 6), 16) : NaN;
        if (isNaN(value))
            return { codePoint: -1, next: i + 2 };
        // A surrogate pair written as two escapes: one character
        if (value >= 0xD800 && value <= 0xDBFF && text[i + 6] === "\\" && text[i + 7] === "u") {
            const low = parseInt(text.slice(i + 8, i + 12), 16);
            if (low >= 0xDC00 && low <= 0xDFFF)
                return { codePoint: 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00), next: i + 12 };
        }
        return { codePoint: value, next: i + 6 };
    }

    // The characters beyond ASCII inside the string literals of a line, not in a comment
    function _charactersOf(text) {
        const found = [];
        let quote = "";
        let i = 0;
        while (i < text.length) {
            const character = text[i];
            if (quote === "") {
                if (character === "/" && text[i + 1] === "/")
                    break;
                if (character === "\"" || character === "'" || character === "`")
                    quote = character;
                i++;
                continue;
            }
            if (character === "\\") {
                const escape = _escape(text, i);
                if (escape.codePoint > 127)
                    found.push(escape.codePoint);
                i = escape.next;
                continue;
            }
            if (character === quote) {
                quote = "";
                i++;
                continue;
            }
            const codePoint = text.codePointAt(i);
            if (codePoint > 127)
                found.push(codePoint);
            i += codePoint > 0xFFFF ? 2 : 1;
        }
        return found;
    }

    function runAsync() {
        // The parser on its own
        assertEqual(_charactersOf("text: \"a é\" // ü").join(","), String(0xE9), "a character in a string; not in a comment");
        assertEqual(_charactersOf("a: 'x\\u00e9' + `y\\u{F0415}` + \"\\uD83D\\uDE00\" + \"\\n\\\"ä\"").join(","),
                    [0xE9, 0xF0415, 0x1F600, 0xE4].join(","), "single quotes, a template literal, escapes, a pair, an escaped quote");
        assertEqual(_charactersOf("ü + \"a\"").join(","), "", "outside a string: no");

        _font.command = ["fc-match", "-f", "%{family}\\n%{charset}\\n", family];
        _font.running = true;
    }

    function _fontRead(code, lines) {
        const families = (lines[0] ?? "").split(",");
        assert(code === 0 && families.includes(family), "the theme's font is installed (" + family + "; fc-match names " + (lines[0] ?? "none") + ")");
        if (!families.includes(family)) {
            finish();
            return;
        }
        _ranges = _rangesOf(lines[1] ?? "");
        assert(_inFont(0x41) && _inFont(0xF0415), "the font has letters and icons");
        assert(!_inFont(0xFF0B), "… and lacks what it lacks (a full-width plus)");

        _scan.command = ["sh", "-c", "cd \"$1\" && b=$(printf '[\\200-\\377]') && LC_ALL=C grep -rnI --include='*.qml' -e \"$b\" -e '\\\\u' "
                         + "panels/settings panels/widget_settings components api singletons; "
                         + "LC_ALL=C grep -nI -e \"$b\" -e '\\\\u' panels/*.qml; echo END", "sh", Quickshell.shellDir];
        _scan.running = true;
    }

    function _scanned(code, lines) {
        assert(lines.length > 0 && lines[lines.length - 1] === "END", "the sources read");
        const missing = {};
        let characters = 0;
        for (const line of lines) {
            const match = /^([^:]+):(\d+):(.*)$/.exec(line);
            // A log line is read in the journal, not drawn
            if (!match || /\b(console|logger)\.(log|warn|error|info|debug)\(/.test(match[3]))
                continue;
            for (const codePoint of _charactersOf(match[3])) {
                characters++;
                const key = match[1] + ":" + _hex(codePoint);
                if (_inFont(codePoint) || _formatCharacter(codePoint) || notDrawn[key] !== undefined)
                    continue;
                missing[key] = (missing[key] ?? []).concat([match[2]]);
            }
        }
        assert(characters > 50, "characters beyond ASCII found (" + characters + ")");
        const unexpected = Object.keys(missing).filter(key => knownMissing[key] === undefined).sort()
            .map(key => key + " (" + String.fromCodePoint(parseInt(key.split(":").pop(), 16)) + ") line " + missing[key].join(", "));
        assertEqual(unexpected.join(" | "), "", "every glyph the Settings write is in " + family);
        assert(Object.keys(notDrawn).every(key => lines.some(line => line.startsWith(key.slice(0, key.lastIndexOf(":")) + ":"))), "each file of the not-drawn list still read");
        const gone = Object.keys(knownMissing).filter(key => missing[key] === undefined);
        assertEqual(gone.join(", "), "", "each known missing glyph is still written there (else its line goes)");
        finish();
    }
}
