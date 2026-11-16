import QtQuick
import qs.components

// Text on the bar is plain text: a widget may show what others name (a track, a window, a
// module's tailnet device), and markup in it must show literally, never be rendered
TestCase {
    id: suite
    suiteName: "BarText"

    property Component _barText: Component {
        BarText {}
    }

    function run() {
        const crafted = "<b>x</b><img src=\"http://example.invalid/\">";
        const item = _barText.createObject(null, { text: crafted });
        assert(item !== null, "a BarText builds");
        const inner = item.children[0]?.children[0] ?? null;
        assert(inner instanceof Text, "… its text item");
        assertEqual(inner?.textFormat, Text.PlainText, "… plain text, never AutoText");
        assertEqual(inner?.text, crafted, "… the markup kept literally");
        const rich = Qt.createQmlObject("import QtQuick; Text { textFormat: Text.RichText }", suite);
        rich.text = crafted;
        assert(item.implicitWidth > rich.implicitWidth, "… as wide as its characters, wider than the rendered markup ("
               + item.implicitWidth + " > " + rich.implicitWidth + ")");
        rich.destroy();
        item.destroy();
    }
}
