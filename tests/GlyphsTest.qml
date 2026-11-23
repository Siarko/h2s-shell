import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Every character outside ASCII that the Settings window and its parts write in a string
// (panels/settings, panels/widget_settings, panels/*.qml, components, api) is in the
// built-in theme's font, the Nerd Font the shell asks for (hud/StartupWarnings.qml): a
// character it lacks is drawn from whatever other font has it, or as an empty box when none
// does. The font's characters are fontconfig's (fc-match); comments are left out. Where
// fc-match or that font is missing nothing can be compared: the suite says so and checks
// nothing more.
TestCase {
    id: suite
    suiteName: "Glyphs"
    asynchronous: true

    // Drawn from another font today, not the Nerd Font: an empty box where only the Nerd
    // Font is installed. New ones are not added here; these are to be replaced.
    readonly property var knownMissing: ({
        "21BB": "↻ PowerMenu.qml",
        "2699": "⚙ BarSectionList.qml",
        "270E": "✎ the theme drafts' mark (SettingsWindow, SettingsPageList, SettingsPicker, ColorsSettings, DraftActions)"
    })

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

    // The characters beyond ASCII inside the string literals of a line, not in a comment
    function _charactersOf(text) {
        const found = [];
        let inString = false;
        for (let i = 0; i < text.length; i++) {
            const character = text[i];
            if (!inString && character === "/" && text[i + 1] === "/")
                break;
            if (character === "\\" && inString) {
                i++;
                continue;
            }
            if (character === "\"") {
                inString = !inString;
                continue;
            }
            if (inString) {
                const codePoint = text.codePointAt(i);
                if (codePoint > 0xFFFF)
                    i++;
                if (codePoint > 127)
                    found.push(codePoint);
            }
        }
        return found;
    }

    function runAsync() {
        _font.command = ["sh", "-c", "command -v fc-match >/dev/null || exit 3; fc-match -f '%{family}\\n%{charset}\\n' \"$1\"", "sh", family];
        _font.running = true;
    }

    function _fontRead(code, lines) {
        const families = (lines[0] ?? "").split(",");
        if (code !== 0 || !families.includes(family)) {
            console.warn("[Glyphs] " + (code === 3 ? "no fc-match here" : family + " is not installed here") + ": the Settings glyphs are not checked");
            assert(true, "not checked");
            finish();
            return;
        }
        _ranges = _rangesOf(lines[1] ?? "");
        assert(_inFont(0x41) && _inFont(0xF0415), "the font has letters and icons");
        assert(!_inFont(0xFF0B), "… and lacks what it lacks (a full-width plus)");

        _scan.command = ["sh", "-c", "cd \"$1\" && LC_ALL=C grep -rnI --include='*.qml' -e \"$(printf '[\\200-\\377]')\" panels/settings panels/widget_settings components api; "
                         + "LC_ALL=C grep -nI -e \"$(printf '[\\200-\\377]')\" panels/*.qml; echo END", "sh", Quickshell.shellDir];
        _scan.running = true;
    }

    function _scanned(code, lines) {
        assert(lines.length > 0 && lines[lines.length - 1] === "END", "the sources read");
        const where = {};
        let characters = 0;
        for (const line of lines) {
            const match = /^([^:]+):(\d+):(.*)$/.exec(line);
            if (!match)
                continue;
            for (const codePoint of _charactersOf(match[3])) {
                characters++;
                const hex = _hex(codePoint);
                if (where[hex] === undefined)
                    where[hex] = { codePoint, places: [] };
                where[hex].places.push(match[1].split("/").pop() + ":" + match[2]);
            }
        }
        assert(characters > 50, "characters beyond ASCII found (" + characters + ")");
        const missing = Object.keys(where).filter(hex => !_inFont(where[hex].codePoint)).sort();
        const unexpected = missing.filter(hex => knownMissing[hex] === undefined)
            .map(hex => "U+" + hex + " " + String.fromCodePoint(where[hex].codePoint) + " at " + where[hex].places.slice(0, 3).join(", "));
        assertEqual(unexpected.join(" | "), "", "every glyph the Settings write is in " + family);
        const gone = Object.keys(knownMissing).filter(hex => !missing.includes(hex));
        assertEqual(gone.join(","), "", "each known missing glyph is still used and still missing (else its line goes)");
        finish();
    }
}
