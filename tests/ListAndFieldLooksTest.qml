import QtQuick
import qs.components
import qs.singletons

// Looks the owner asked for that a picture alone would not hold: a group's title in a
// FloatingList set off from its entries (bold, further in than an entry's text)
TestCase {
    id: suite
    suiteName: "ListAndFieldLooks"

    property Component _header: Component {
        FloatingListHeader { text: "Group" }
    }

    function run() {
        _groupTitle();
    }

    function _groupTitle() {
        const header = _header.createObject(null);
        assert(header !== null, "a group's title builds");
        assertEqual(header.font.weight, Theme.fontWeightBold, "a group's title: bold, the theme's weight");
        // An entry's text starts 6 px in (Dropdown's option, the mockups' stand-ins)
        assert(header.leftPadding > 6, "… further in than an entry's text (" + header.leftPadding + " > 6)");
        header.destroy();
    }
}
