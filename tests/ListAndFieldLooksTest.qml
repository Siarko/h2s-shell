import QtQuick
import qs.components
import qs.singletons

// Looks the owner asked for that a picture alone would not hold: a group's title in a
// FloatingList set off from its entries (bold, further in than an entry's text); a hidden
// password's dots apart, by the theme's spacing, and nothing else spaced
TestCase {
    id: suite
    suiteName: "ListAndFieldLooks"

    property Component _header: Component {
        FloatingListHeader { text: "Group" }
    }
    property Component _field: Component {
        InputField { placeholder: "Password" }
    }

    function run() {
        _groupTitle();
        _passwordDots();
    }

    function _groupTitle() {
        const header = _header.createObject(null);
        assert(header !== null, "a group's title builds");
        assertEqual(header.font.weight, Theme.fontWeightBold, "a group's title: bold, the theme's weight");
        // An entry's text starts 6 px in (Dropdown's option, the mockups' stand-ins)
        assert(header.leftPadding > 6, "… further in than an entry's text (" + header.leftPadding + " > 6)");
        header.destroy();
    }

    function _passwordDots() {
        const field = _field.createObject(null, { text: "secret", password: true });
        assert(field !== null, "a password field builds");
        assert(Theme.passwordLetterSpacing > 0, "the theme spaces a password's dots");
        assertEqual(field.input.font.letterSpacing, Theme.passwordLetterSpacing, "hidden: the dots apart by the theme's spacing");
        const placeholder = field.input.children.find(child => child.text === "Password");
        assertEqual(placeholder?.font.letterSpacing, 0, "… its placeholder not spaced");
        field.revealed = true;
        assertEqual(field.input.font.letterSpacing, 0, "shown: the text as typed, not spaced");
        field.password = false;
        field.revealed = false;
        assertEqual(field.input.font.letterSpacing, 0, "not a password: not spaced");
        field.destroy();
    }
}
