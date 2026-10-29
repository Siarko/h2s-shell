import QtQuick
import qs.singletons

TestCase {
    suiteName: "Workspaces"

    function run() {
        // The name goes into a Lua expression for Hyprland's dispatch
        assertEqual(Workspaces.luaString("music"), '"music"', "a plain name");
        assertEqual(Workspaces.luaString('a"b'), '"a\\"b"', "a quote cannot end the string");
        assertEqual(Workspaces.luaString("a\\b"), '"a\\\\b"', "a backslash cannot escape the closing quote");
        assertEqual(Workspaces.luaString('x") hl.dsp.exit() --'), '"x\\") hl.dsp.exit() --"',
            "a name cannot inject code");
        assertEqual(Workspaces.luaString("a\nb"), '"a\\nb"', "a newline stays inside the string");
    }
}
