import QtQuick
import QtQuick.Layouts
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.api as Public
import qs.components
import qs.panels.settings as Settings
import qs.singletons

// The public elements (qs.api), pinned. For each: its public property and signal names —
// a change to a list written here is a module API version change —; each kind and size
// reaching the internal value it stands for, read from the item inside, so a wrong
// mapping fails; the element in a RowLayout and a ColumnLayout with the internal one's
// geometry, stretched and hidden; a label with markup in it shown as written. The words
// alone: ApiElementRules, checked here too.
//
// Opens a small window in a corner of the screen for a moment (a layer surface, so it
// moves no windows).
TestCase {
    id: root
    suiteName: "ApiElements"
    asynchronous: true

    // What a module can rely on, per element: properties and signals, sorted
    readonly property var pinned: ({
        "SmallButton": ["apiElement", "asked", "asking", "available", "cancelTip", "checked", "clicked", "confirm", "confirmLabel", "defaultSize", "kind", "label", "size", "tooltip"],
        "Dropdown": ["options", "picked", "placeholder", "size", "value"],
        "InputField": ["accepted", "editingFinished", "password", "placeholder", "problem", "revealToggled", "revealed", "size", "text", "textEdited"],
        "Pill": ["clicked", "label", "picked", "size", "textSize", "tooltip"],
        "Checkbox": ["checked", "label", "toggled"],
        "ToggleSwitch": ["checked", "toggled"],
        "PrivilegedMark": ["need"],
        "SettingsRow": ["controls", "hint", "label", "value"],
        "ExpandingRow": ["content", "hint", "label", "open"],
        "Notice": ["kind", "text"],
        "ProgressBar": ["kind", "value", "wave"],
        "HoverTip": ["target", "text"],
        "SidePanel": ["closed", "content", "open", "size", "title"],
        "StatusPill": ["expandable", "expanded", "icon", "kind", "label", "parts", "toggled"]
    })

    // The base types: a module's object is the internal one itself, so only these names
    // are promised of it — each must be there; what else it has is not pinned
    readonly property var pinnedBase: ({
        "PopupWidget": ["clicked", "hover", "interactive", "middleClicked", "popup", "popupOpen", "scrollNotch", "scrolled", "widgetType"],
        "BarText": ["alignment", "color", "elide", "font", "leadingGap", "length", "text"],
        "BarRow": ["spacing", "vertical"],
        "PointerArea": ["centred", "lit", "reach"],
        "VpnProvider": ["attend", "busy", "canChange", "connect", "disconnect", "entries", "failed", "glyph", "kind", "lockdownNote", "providerId", "ready",
            "settingsPage", "typeName"]
    })

    // A notice's kinds, and the theme's colour each is drawn in
    readonly property var noticeKinds: [
        { kind: "warning", inside: "warning" },
        { kind: "danger", inside: "error" },
        { kind: "success", inside: "success" }
    ]

    // A progress bar's kinds, and the theme's colour its fill is drawn in
    readonly property var progressKinds: [
        { kind: "normal", inside: "accent" },
        { kind: "success", inside: "success" },
        { kind: "warning", inside: "warning" },
        { kind: "danger", inside: "error" }
    ]

    // A public pill's sizes, and what each is inside
    readonly property var pillSizes: [
        { size: "s", inside: "s" },
        { size: "m", inside: "m" },
        { size: "l", inside: "l" }
    ]

    // (1.32) A public pill's text sizes, and the theme's type size each is
    readonly property var pillTextSizes: [
        { size: "small", inside: "fontSizeSmall" },
        { size: "body", inside: "fontSizeBody" }
    ]

    // What a public mark is told, what that is inside, and whether anything shows
    readonly property var needs: [
        { need: "", inside: "", shown: false },
        { need: "yes", inside: "yes", shown: false },
        { need: "auth", inside: "auth", shown: true },
        { need: "no", inside: "no", shown: true }
    ]

    readonly property var choices: [{ value: "a", label: "<b>x</b>" }, { value: "b", label: "Second" }]

    // The public button's kinds and sizes, and what each is inside
    readonly property var kinds: [
        { kind: "primary", inside: "save" },
        { kind: "secondary", inside: "normal" },
        { kind: "danger", inside: "delete" },
        { kind: "warning", inside: "warning" },
        { kind: "success", inside: "success" }
    ]
    readonly property var sizes: [
        { size: "xs", inside: "fontSizeXSmall" },
        { size: "s", inside: "fontSizeSmall" },
        { size: "m", inside: "fontSizeBody" }
    ]

    // The progress bar and the tooltip, in a window of their own in the other corner
    property var _secondWindow: PanelWindow {
        anchors { top: true; right: true }
        implicitWidth: 360
        implicitHeight: 260
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item { id: tipHolder; Public.HoverTip { id: bareTip } }

        Item {
            id: elsewhere
            x: 320; y: 220
            width: 30; height: 30
        }

        ColumnLayout {
            id: progressColumn
            x: 10; y: 10
            width: 200
            spacing: 6
            Public.ProgressBar { id: progress; value: 0.5 }
            Public.ProgressBar { id: mistypedProgress; kind: "blue"; value: 0.25 }
            Public.ProgressBar { id: unknownLength; value: -1 }
            Public.ProgressBar { visible: false }
        }

        Rectangle {
            id: tipped
            x: 10; y: 120
            width: 60; height: 24
            color: Theme.surface
            Public.HoverTip { id: tip; text: "<b>x</b>" }
        }
        Public.SmallButton {
            id: tippedButton
            property int clicks: 0
            x: 100; y: 120
            label: "Tip"
            onClicked: clicks++
            Public.HoverTip { id: buttonTip; text: "On the button" }
        }
        Rectangle {
            id: aimed
            x: 200; y: 120
            width: 40; height: 24
            color: Theme.surface
        }
        Public.HoverTip { id: aimedTip; target: aimed; text: "Aimed" }

        RowLayout {
            id: tipRow
            x: 10; y: 180
            spacing: 6
            Rectangle { implicitWidth: 40; implicitHeight: 20; color: Theme.surface; Public.HoverTip { text: "First" } }
            Public.HoverTip { text: "Loose in the row" }
            Rectangle { implicitWidth: 40; implicitHeight: 20; color: Theme.surface }
        }
    }

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 700
        implicitHeight: 1060
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item { id: bare }

        // Somewhere for the mouse to go that is no button
        Item {
            id: away
            x: 640; y: 240
            width: 40; height: 40
        }

        Row {
            x: 10; y: 10
            spacing: 20

            Public.SmallButton {
                id: plain
                property int clicks: 0
                property int questions: 0
                label: "Plain"
                onClicked: clicks++
                onAsked: questions++
            }
            Public.SmallButton {
                id: danger
                property int clicks: 0
                property int questions: 0
                label: "Stop"
                kind: "danger"
                onClicked: clicks++
                onAsked: questions++
            }
            Public.SmallButton {
                id: asks
                property int clicks: 0
                property int questions: 0
                label: "Remove"
                kind: "danger"
                confirm: true
                onClicked: clicks++
                onAsked: questions++
            }
            Public.SmallButton {
                id: asksInWords
                label: "Turn on"
                kind: "primary"
                confirm: true
                confirmLabel: "Really <b>on</b>?"
                cancelTip: "Leave it off"
            }
            Public.SmallButton {
                id: unavailable
                property int clicks: 0
                label: "Not now"
                available: false
                onClicked: clicks++
            }
            Public.SmallButton {
                id: marked
                label: "<b>x</b>"
            }
        }

        Row {
            x: 10; y: 60
            spacing: 20

            Public.SmallButton { id: checkedButton; label: "On"; checked: true; tooltip: "A tip" }
            Public.SmallButton { id: mistyped; label: "Typo"; kind: "primry"; size: "huge" }
            Public.SmallButton { id: mistypedAgain; label: "Typo"; kind: "primry"; size: "huge" }
            Public.SmallButton { id: reserved; label: "Typo"; kind: "toString"; size: "constructor" }
            Public.SmallButton { id: varied; label: "Varied" }
            Public.SmallButton { id: narrow; label: "A label much longer than its button"; width: 80 }
            Public.SmallButton { id: narrowAsks; label: "A label much longer than its button"; confirm: true; width: 80 }
            Public.SmallButton { id: asksWithTip; label: "Tip"; confirm: true; tooltip: "Another tip" }
        }

        // The public button and the internal one, in the same layouts
        RowLayout {
            id: publicRow
            x: 10; y: 110
            width: 400
            spacing: 6
            Public.SmallButton { label: "First"; kind: "primary" }
            Public.SmallButton { label: "Hidden"; visible: false }
            Public.SmallButton { label: "Stretched"; Layout.fillWidth: true }
            Public.SmallButton { label: "Last"; size: "s" }
        }
        RowLayout {
            id: internalRow
            x: 10; y: 150
            width: 400
            spacing: 6
            SmallButton { label: "First"; kind: "save" }
            SmallButton { label: "Hidden"; visible: false }
            SmallButton { label: "Stretched"; Layout.fillWidth: true }
            SmallButton { label: "Last"; fontSize: Theme.fontSizeSmall }
        }
        ColumnLayout {
            id: publicColumn
            x: 430; y: 110
            width: 200
            spacing: 6
            Public.SmallButton { label: "First"; kind: "primary" }
            Public.SmallButton { label: "Hidden"; visible: false }
            Public.SmallButton { label: "Stretched"; Layout.fillWidth: true }
            Public.SmallButton { label: "Asks"; kind: "danger"; confirm: true }
        }
        ColumnLayout {
            id: internalColumn
            x: 430; y: 210
            width: 200
            spacing: 6
            SmallButton { label: "First"; kind: "save" }
            SmallButton { label: "Hidden"; visible: false }
            SmallButton { label: "Stretched"; Layout.fillWidth: true }
            DeleteButton { label: "Asks"; fontSize: Theme.fontSizeBody }
        }

        // How `asking` is declared, one-line texts, an unavailable question
        Row {
            x: 10; y: 200
            spacing: 10

            Public.SmallButton {
                id: unavailableAsking
                label: "U"
                confirm: true
                asking: true
                available: false
            }
            Public.SmallButton { id: askingFirst; label: "A"; asking: true; confirm: true }
            Public.SmallButton { id: confirmFirst; label: "B"; confirm: true; asking: true }
            Public.SmallButton { id: boundAsking; property bool flag: true; label: "C"; confirm: true; asking: flag }
            Public.SmallButton { id: multiLine; label: "One\nTwo\nThree"; confirm: true; confirmLabel: "Really\nsure?" }
            Public.Pill { id: multiPill; label: "One\nTwo\nThree" }
        }
        Row {
            x: 10; y: 250
            spacing: 10

            Pill { id: internalMultiPill; label: "One\nTwo\nThree" }
            DeleteButton { id: internalMultiAsk; label: "One\nTwo"; confirmLabel: "Really\nsure?" }
            DeleteButton { id: internalOneAsk; label: "One"; confirmLabel: "Sure?" }
            ToggleSwitch { id: internalOff; enabled: false }
            ToggleSwitch { id: internalOn }
            Public.Dropdown { id: coloured; options: [{ value: "a", label: "Red\nline", color: "red" }]; value: "a" }
            Public.Pill { id: longPill; label: "y".repeat(200) }
            Public.SmallButton { id: longButton; label: "x".repeat(200) }
        }

        // --- the controls ---
        Row {
            x: 10; y: 300
            spacing: 20

            Public.Dropdown {
                id: dropdown
                property string got: ""
                options: root.choices
                value: "a"
                onPicked: value => got += value
            }
            Public.Dropdown { id: unchosen; placeholder: "<b>x</b>" }
            Public.InputField {
                id: field
                property string heard: ""
                placeholder: "<b>x</b>"
                onAccepted: heard += "accepted "
                onTextEdited: heard += "textEdited "
                onEditingFinished: heard += "editingFinished "
                onRevealToggled: heard += "revealToggled "
            }
            Public.InputField {
                id: secret
                property int toggles: 0
                password: true
                problem: true
                text: "hidden"
                onRevealToggled: toggles++
            }
        }
        Row {
            x: 10; y: 340
            spacing: 20

            Public.Pill {
                id: pill
                property int clicks: 0
                label: "<b>x</b>"
                tooltip: "What it means"
                onClicked: clicks++
            }
            Public.Pill { id: pickedPill; label: "Picked"; picked: true }
            Public.Pill { id: mistypedPill; label: "Typo"; size: "xs"; textSize: "huge" }
            Public.Checkbox {
                id: checkbox
                property int toggles: 0
                label: "<b>x</b>"
                onToggled: toggles++
            }
            Public.Checkbox { id: checkedBox; checked: true }
            Public.ToggleSwitch {
                id: toggle
                property int toggles: 0
                onToggled: toggles++
            }
            Public.ToggleSwitch {
                id: toggleOff
                property int toggles: 0
                checked: true
                enabled: false
                onToggled: toggles++
            }
            Public.PrivilegedMark { id: mark }
            Public.PrivilegedMark { id: variedMark }
            Public.PrivilegedMark { id: mistypedMark; need: "perhaps" }
            // A module's own condition, true, with nothing to mark
            Public.PrivilegedMark { id: forcedMark; visible: true; need: "yes" }
        }

        // The public controls and the internal ones, in the same layouts: as they are,
        // then every one stretched
        RowLayout {
            id: publicControls
            x: 10; y: 390
            width: 680
            spacing: 6
            Public.Dropdown { options: root.choices; value: "b" }
            Public.InputField { placeholder: "Field"; Layout.fillWidth: true }
            Public.Pill { label: "Pill"; size: "s" }
            Public.Checkbox { label: "Check" }
            Public.ToggleSwitch {}
            Public.PrivilegedMark {}
            Public.PrivilegedMark { need: "yes" }
            Public.Dropdown { visible: false }
            Public.InputField { visible: false }
            Public.Pill { label: "Hidden"; visible: false }
            Public.Checkbox { label: "Hidden"; visible: false }
            Public.ToggleSwitch { visible: false }
            Public.PrivilegedMark { visible: false }
        }
        RowLayout {
            id: internalControls
            x: 10; y: 425
            width: 680
            spacing: 6
            Dropdown { options: root.choices; value: "b" }
            InputField { placeholder: "Field"; Layout.fillWidth: true }
            Pill { label: "Pill" }
            Checkbox { label: "Check" }
            ToggleSwitch {}
            PrivilegedMark {}
            PrivilegedMark { need: "yes" }
            Dropdown { visible: false }
            InputField { visible: false }
            Pill { label: "Hidden"; visible: false }
            Checkbox { label: "Hidden"; visible: false }
            ToggleSwitch { visible: false }
            PrivilegedMark { visible: false }
        }
        RowLayout {
            id: publicStretched
            x: 10; y: 460
            width: 680
            spacing: 6
            Public.Dropdown { Layout.fillWidth: true }
            Public.InputField { Layout.fillWidth: true }
            Public.Pill { label: "Pill"; size: "s"; Layout.fillWidth: true }
            Public.Checkbox { label: "Check"; Layout.fillWidth: true }
            Public.ToggleSwitch { Layout.fillWidth: true }
            Public.PrivilegedMark { Layout.fillWidth: true }
        }
        RowLayout {
            id: internalStretched
            x: 10; y: 495
            width: 680
            spacing: 6
            Dropdown { Layout.fillWidth: true }
            InputField { Layout.fillWidth: true }
            Pill { label: "Pill"; Layout.fillWidth: true }
            Checkbox { label: "Check"; Layout.fillWidth: true }
            ToggleSwitch { Layout.fillWidth: true }
            PrivilegedMark { Layout.fillWidth: true }
        }
        ColumnLayout {
            id: publicControlColumn
            x: 10; y: 530
            width: 200
            spacing: 6
            Public.Dropdown { options: root.choices; value: "b" }
            Public.InputField { Layout.fillWidth: true }
            Public.Pill { label: "Pill"; size: "s" }
            Public.Checkbox { label: "Check"; Layout.fillWidth: true }
            Public.ToggleSwitch {}
            Public.PrivilegedMark {}
            Public.PrivilegedMark { need: "yes" }
            Public.Dropdown { visible: false }
            Public.InputField { visible: false }
            Public.Pill { label: "Hidden"; visible: false }
            Public.Checkbox { label: "Hidden"; visible: false }
            Public.ToggleSwitch { visible: false }
            Public.PrivilegedMark { visible: false }
        }
        ColumnLayout {
            id: internalControlColumn
            x: 240; y: 530
            width: 200
            spacing: 6
            Dropdown { options: root.choices; value: "b" }
            InputField { Layout.fillWidth: true }
            Pill { label: "Pill" }
            Checkbox { label: "Check"; Layout.fillWidth: true }
            ToggleSwitch {}
            PrivilegedMark {}
            PrivilegedMark { need: "yes" }
            Dropdown { visible: false }
            InputField { visible: false }
            Pill { label: "Hidden"; visible: false }
            Checkbox { label: "Hidden"; visible: false }
            ToggleSwitch { visible: false }
            PrivilegedMark { visible: false }
        }

        // --- rows and texts ---
        Column {
            x: 460; y: 530
            width: 230
            spacing: 6

            Public.SettingsRow {
                id: settingsRow
                width: parent.width
                label: "<b>x</b>"
                hint: "<b>x</b>"
                value: "<b>x</b>"
                Public.SmallButton {
                    id: rowButton
                    property int clicks: 0
                    label: "Go"
                    onClicked: clicks++
                }
                Public.ToggleSwitch { id: rowSwitch }
            }
            Public.SettingsRow { id: bareRow; width: parent.width }
            Public.ExpandingRow {
                id: expandingRow
                property int built: 0
                width: parent.width
                label: "<b>x</b>"
                hint: "<b>x</b>"
                Rectangle {
                    objectName: "opened"
                    implicitHeight: 20
                    color: "transparent"
                    Component.onCompleted: expandingRow.built++
                }
            }
            Public.Notice { id: notice; width: parent.width; text: "<b>x</b>" }
            Public.Notice { id: mistypedNotice; width: parent.width; kind: "info"; text: "Typo" }
            Public.Heading { id: heading; text: "<b>x</b>" }
            Public.SectionTitle { id: sectionTitle; text: "<b>x</b>" }
            Public.Hint { id: hint; width: parent.width; text: "<b>x</b>" }
            Public.SwitchRow { id: switchRow; width: parent.width; label: "<b>x</b>"; hint: "<b>x</b>" }
            Settings.SchemaSettingEditor { id: labelled; width: parent.width; key: "notifications.toastColumnSize"; editIndex: 0; label: "<b>x</b>" }
            Settings.SchemaSettingEditor { id: suffixed; width: parent.width; key: "lockscreen.screensaverTimeout"; editIndex: 0 }
            Settings.SettingsPageList {
                id: pageList
                width: parent.width
                tab: "system"
                selectedPage: "first"
                pages: [{ id: "first", tab: "system", label: "<b>x</b>" }]
            }
        }

        // The public rows and the internal ones, in the same layouts. The line a notice is
        // drawn as is the one on a network's card (panels/settings/NetworkProfileCard.qml).
        ColumnLayout {
            id: publicRows
            x: 10; y: 760
            width: 300
            spacing: 6
            Public.SettingsRow {
                label: "Row"; hint: "A line about it that is long enough to wrap onto a second line of the row"; value: "Value"
                Public.SmallButton { label: "Go" }
            }
            Public.SettingsRow { visible: false; label: "Hidden" }
            Public.ExpandingRow { label: "Closed"; hint: "A line"; Rectangle { implicitHeight: 20 } }
            Public.ExpandingRow { label: "Open"; open: true; Rectangle { implicitHeight: 20 } }
            Public.ExpandingRow { visible: false; label: "Hidden" }
            Public.Notice { text: "A notice long enough to wrap onto a second line of the column it stands in, and on" }
            Public.Notice { visible: false; text: "Hidden" }
        }
        ColumnLayout {
            id: internalRows
            x: 330; y: 760
            width: 300
            spacing: 6
            SettingsRow {
                label: "Row"; hint: "A line about it that is long enough to wrap onto a second line of the row"; value: "Value"
                SmallButton { label: "Go" }
            }
            SettingsRow { visible: false; label: "Hidden" }
            ExpandingRow { label: "Closed"; hint: "A line"; Rectangle { implicitHeight: 20 } }
            ExpandingRow { label: "Open"; open: true; Rectangle { implicitHeight: 20 } }
            ExpandingRow { visible: false; label: "Hidden" }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: "A notice long enough to wrap onto a second line of the column it stands in, and on"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            Text { visible: false; text: "Hidden" }
        }
        RowLayout {
            id: publicRowsAcross
            x: 10; y: 930
            width: 680
            spacing: 6
            Public.SettingsRow { label: "Row"; value: "Value" }
            Public.ExpandingRow { label: "Closed"; Rectangle { implicitHeight: 20 } }
            Public.Notice { text: "A notice" }
            Public.SettingsRow { visible: false; label: "Hidden" }
        }
        RowLayout {
            id: internalRowsAcross
            x: 10; y: 965
            width: 680
            spacing: 6
            SettingsRow { label: "Row"; value: "Value" }
            ExpandingRow { label: "Closed"; Rectangle { implicitHeight: 20 } }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: "A notice"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            SettingsRow { visible: false; label: "Hidden" }
        }

        // A value longer than the row has room for: in a narrow row and in a wide one
        Column {
            x: 10; y: 995
            width: 680
            spacing: 6
            Public.SettingsRow {
                id: narrowLongRow
                width: 300
                label: "Save to"
                value: "/home/someone/Downloads/a/folder/with/a/long/path/in/it"
                Public.SmallButton { id: narrowLongButton; label: "Change" }
            }
            Public.SettingsRow {
                id: wideLongRow
                width: 680
                label: "Save to"
                value: "/home/someone/Downloads/a/folder/with/a/long/path/in/it/and/more"
                Public.SmallButton { id: wideLongButton; label: "Change" }
            }
        }

        // --- the base types ---
        Public.PopupWidget {
            id: popupWidget
            property int clicks: 0
            x: 460; y: 480
            width: 60; height: 24
            widgetType: "apiElementsTest"
            onClicked: clicks++
            Public.BarRow {
                id: barRow
                anchors.centerIn: parent
                spacing: 4
                Public.BarText { id: barText; text: "<b>x</b>" }
                Public.BarText { text: "y" }
            }
        }
        Rectangle {
            id: ownControl
            x: 540; y: 480
            width: 60; height: 24
            color: ownArea.lit ? Theme.surfaceHover : Theme.surface
            Public.PointerArea {
                id: ownArea
                property int clicks: 0
                onClicked: clicks++
            }
        }
        Public.VpnProvider { id: unregistered; autoRegister: false; providerId: "api-elements-test" }

        QT.TestCase {
            id: driver
            name: "ApiElementsDriver"
            when: false
        }
    }

    // Waits for `condition`, at most `limitMs`; whether it came true
    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _child(item, typeName, nth = 0) {
        return Array.from(item.children).filter(child => child.toString().startsWith(typeName))[nth] ?? null;
    }

    // The internal button inside a public one
    function _inside(element) {
        return _child(element, "QQuickLoader").item;
    }

    // The internal control inside a public one
    function _within(element) {
        return element.children[0];
    }

    // The texts under `item`, at any depth, in order
    function _texts(item) {
        let found = [];
        for (const child of Array.from(item.children)) {
            if (/^QQuickText(_QML_\d+)?\(/.test(child.toString()))
                found.push(child);
            found = found.concat(_texts(child));
        }
        return found;
    }

    // The parts of an internal button that asks: the button, its label, the "×"
    function _parts(asking) {
        const face = asking.children[0];
        return { face: face, label: _child(face, "QQuickText"), cancel: asking.children[1] };
    }

    // What an element adds to a plain Item: its properties and signals, without the
    // "…Changed" signal every property has
    function _names(element) {
        const plain = [];
        for (const name in bare)
            plain.push(name);
        const added = [];
        for (const name in element) {
            if (!plain.includes(name) && !(name.endsWith("Changed") && (name.slice(0, -7) in element)))
                added.push(name);
        }
        return added.sort();
    }

    // Whether a label is shown as written: plain text, and wider than it would be as markup
    function _asWritten(label) {
        if (label.textFormat !== Text.PlainText)
            return false;
        const writtenWidth = label.implicitWidth;
        label.textFormat = Text.StyledText;
        const narrowerAsMarkup = label.implicitWidth < writtenWidth;
        label.textFormat = Text.PlainText;
        return narrowerAsMarkup;
    }

    function _geometry(item) {
        return [item.x, item.y, item.width, item.height].join(" ");
    }

    function _items(layout) {
        return Array.from(layout.children);
    }

    function runAsync() {
        // --- the words ---
        const rules = ApiElementRules;
        for (const entry of kinds)
            assertEqual(JSON.stringify(rules.buttonKind(entry.kind)), JSON.stringify({ value: entry.inside, known: true }), "the kind " + entry.kind + " is " + entry.inside + " inside");
        assertEqual(Object.keys(rules.buttonKinds).sort().join(" "), kinds.map(entry => entry.kind).sort().join(" "), "and those are all a button's kinds");
        for (const entry of sizes)
            assertEqual(JSON.stringify(rules.textSize(entry.size)), JSON.stringify({ value: entry.inside, known: true }), "the size " + entry.size + " is the theme's " + entry.inside);
        assertEqual(Object.keys(rules.textSizes).sort().join(" "), sizes.map(entry => entry.size).sort().join(" "), "and those are all a button's sizes");
        for (const word of ["primry", "", "save", "delete", "normal", "toString", "__proto__", undefined, null, 3]) {
            assertEqual(JSON.stringify(rules.buttonKind(word)), JSON.stringify({ value: "normal", known: false }), "a kind " + JSON.stringify(word) + " is not one: the default, secondary");
            assertEqual(JSON.stringify(rules.textSize(word)), JSON.stringify({ value: "fontSizeBody", known: false }), "a size " + JSON.stringify(word) + " is not one: the default, m");
        }
        assertEqual(JSON.stringify(rules.textSize("l")), JSON.stringify({ value: "fontSizeBody", known: false }), "a button has no size l");
        const warning = rules.unknownWord("SmallButton", "kind", "prim\nry" + "x".repeat(100), "secondary");
        assert(!warning.message.includes("\n") && warning.message.length < 140, "the warning for an unknown word is one short line: " + warning.message);
        assert(warning.message.includes("SmallButton") && warning.message.includes("kind") && warning.message.includes("secondary"), "… naming the element, the property and what is shown");

        // --- the names ---
        assertEqual(JSON.stringify(_names(marked)), JSON.stringify(pinned.SmallButton), "SmallButton's public properties and signals are the pinned ones");
        assert(_names(_inside(plain)).includes("fontSize") && _names(_inside(plain)).includes("hovered"), "… the internal button's own are not among them (it has fontSize, hovered)");
        // (1.34) The side panel: its behaviour in tests/SidePanelTest.qml
        const sidePanel = Qt.createQmlObject("import qs.api\nSidePanel {}", bare, "PinnedSidePanel.qml");
        assertEqual(JSON.stringify(_names(sidePanel)), JSON.stringify(pinned.SidePanel), "SidePanel's public properties and signals are the pinned ones");
        assertEqual(JSON.stringify([sidePanel.open, sidePanel.size, sidePanel.title, sidePanel.content, sidePanel.width, sidePanel.height, sidePanel.visible]),
                    JSON.stringify([false, "m", "", null, 0, 0, false]), "… its defaults: closed, size m, no title, no content, taking no room");
        assertEqual(sidePanel.data.length + " " + sidePanel.resources.length, "0 0", "… nothing of the frame reachable through it: no objects inside");
        sidePanel.destroy();
        // (1.35) The status pill: its behaviour in tests/StatusPillTest.qml
        const statusPill = Qt.createQmlObject("import qs.api\nStatusPill {}", bare, "PinnedStatusPill.qml");
        assertEqual(JSON.stringify(_names(statusPill)), JSON.stringify(pinned.StatusPill), "StatusPill's public properties and signals are the pinned ones");
        assertEqual(JSON.stringify([statusPill.icon, statusPill.label, statusPill.kind, statusPill.parts, statusPill.expanded]),
                    JSON.stringify(["", "", "normal", [], false]), "… its defaults: no icon, no label, normal, no parts, folded");
        statusPill.destroy();
        _statusWords();

        // --- beside qs.components, which has a SmallButton too ---
        const publicLast = Qt.createQmlObject("import QtQuick\nimport qs.components\nimport qs.api\nSmallButton {}", bare, "PublicLast.qml");
        const internalLast = Qt.createQmlObject("import QtQuick\nimport qs.api\nimport qs.components\nSmallButton {}", bare, "InternalLast.qml");
        assert("confirm" in publicLast && !("fontSize" in publicLast), "a file that imports qs.api last gets the public button");
        assert("fontSize" in internalLast && !("confirm" in internalLast), "one that imports qs.components last gets the internal one");
        publicLast.destroy();
        internalLast.destroy();

        // --- defaults ---
        assertEqual([plain.kind, plain.size, plain.confirm, plain.available, plain.checked, plain.asking, plain.tooltip, plain.cancelTip].join(" "),
            "secondary m false true false false  Cancel", "a button's defaults: secondary, m, does not ask, available");
        assertEqual(plain.confirmLabel, "Plain?", "the question is the label and \"?\" unless given");
        assertEqual(asksInWords.confirmLabel, "Really <b>on</b>?", "… or the one given");
        // (1.28) A place's default size reaches only a button that sets none
        const unsized = Qt.createQmlObject("import QtQuick\nimport qs.api\nSmallButton { label: \"a\" }", bare, "Unsized.qml");
        const sized = Qt.createQmlObject("import QtQuick\nimport qs.api\nSmallButton { label: \"a\"; size: \"s\" }", bare, "Sized.qml");
        unsized.defaultSize = "xs";
        sized.defaultSize = "xs";
        assertEqual(unsized.size + " " + _inside(unsized).fontSize + " " + sized.size + " " + _inside(sized).fontSize,
                    "xs " + Theme[ApiElementRules.textSize("xs").value] + " s " + Theme[ApiElementRules.textSize("s").value],
                    "defaultSize: a button with no size takes it, one that sets its size keeps it");
        unsized.destroy();
        sized.destroy();

        // --- each kind and size, read from the button inside ---
        for (const entry of kinds) {
            varied.kind = entry.kind;
            assertEqual(_inside(varied).kind, entry.inside, "a " + entry.kind + " button is " + entry.inside + " inside");
        }
        for (const entry of sizes) {
            varied.size = entry.size;
            assertEqual(_inside(varied).fontSize, Theme[entry.inside], "a button of size " + entry.size + " has the theme's " + entry.inside);
        }
        assert(Theme.fontSizeXSmall < Theme.fontSizeSmall && Theme.fontSizeSmall < Theme.fontSizeBody, "the three sizes differ in the theme");
        varied.confirm = true;
        for (const entry of kinds) {
            varied.kind = entry.kind;
            assertEqual(_inside(varied).kind, entry.inside, "a " + entry.kind + " button that asks is " + entry.inside + " inside");
        }
        for (const entry of sizes) {
            varied.size = entry.size;
            assertEqual(_inside(varied).fontSize, Theme[entry.inside], "a button of size " + entry.size + " that asks has the theme's " + entry.inside);
        }
        assert(_inside(varied).toString().startsWith("DeleteButton") && _inside(plain).toString().startsWith("SmallButton"),
            "a button that asks is the shell's asking button inside, another its plain one");

        // --- what is passed on ---
        assert(_inside(checkedButton).checked && !_inside(plain).checked, "checked reaches the button inside");
        assertEqual(_inside(checkedButton).tooltip, "A tip", "and so does the tooltip");
        assertEqual(_inside(asksWithTip).tooltip, "Another tip", "… of a button that asks too");
        assert(!_inside(unavailable).available && !_inside(unavailable).hovered, "and not available");
        assertEqual(_inside(asksInWords).cancelTip, "Leave it off", "the \"×\"'s tooltip reaches the button inside");

        // --- words it does not know ---
        assertEqual(_inside(mistyped).kind + " " + _inside(mistyped).fontSize, "normal " + Theme.fontSizeBody, "a kind and a size that do not exist show as secondary, m");
        assertEqual(_inside(reserved).kind + " " + _inside(reserved).fontSize, "normal " + Theme.fontSizeBody, "… words every object knows included");
        assertEqual(mistyped.kind, "primry", "the element keeps the word it was given");
        assertEqual(ApiElements.warned.filter(key => key.startsWith("SmallButton.") && key.includes("primry")).length, 1, "the kind is warned about once, for two buttons with it");
        assertEqual(ApiElements.warned.filter(key => key.startsWith("SmallButton.") && key.includes("huge")).length, 1, "and the size once");
        assert(!ApiElements.warned.some(key => key.includes("secondary") || key.includes("=m") || key.includes("danger")), "a word it knows is not warned about");
        const warnedBefore = ApiElements.warned.length;
        varied.kind = "later";
        varied.kind = "primary";
        varied.kind = "later";
        assertEqual(ApiElements.warned.length, warnedBefore + 1, "a word set later is warned about too, once");

        // --- clicks ---
        const inner = _inside(plain);
        assert(_until(() => {
            driver.mouseMove(away, 5, 5);
            driver.mouseMove(plain, 5, 5);
            return inner.hovered;
        }, 5000), "the window is shown and the pointer is seen over a public button");
        driver.mouseClick(plain, 5, 5);
        assertEqual(plain.clicks + " " + plain.questions, "1 0", "a click on a button acts");
        driver.mouseClick(danger, 5, 5);
        assertEqual(danger.clicks + " " + danger.questions + " " + danger.asking, "1 0 false", "a danger button that does not ask acts on the first click");
        driver.mouseClick(unavailable, 5, 5);
        assertEqual(unavailable.clicks, 0, "a button that is not available does nothing");

        const parts = _parts(_inside(asks));
        assertEqual(parts.label.text, "Remove", "a button that asks shows its label");
        driver.mouseClick(asks, 5, 5);
        assertEqual(asks.clicks + " " + asks.questions + " " + asks.asking, "0 1 true", "its first click asks: asked(), asking, nothing done");
        assertEqual(parts.label.text, "Remove?", "and it shows the question");
        assert(_until(() => asks.width === parts.face.width + parts.cancel.width && parts.cancel.x === parts.face.width) && parts.cancel.visible,
               "the element is as wide as the question and its \"×\", the \"×\" right of the question");
        driver.mouseClick(parts.cancel, 3, 3);
        assertEqual(asks.clicks + " " + asks.questions + " " + asks.asking, "0 1 false", "the \"×\" takes the question back");
        driver.mouseClick(asks, 5, 5);
        driver.mouseClick(asks, 5, 5);
        assertEqual(asks.clicks + " " + asks.questions + " " + asks.asking, "1 2 false", "a second click acts: clicked()");
        driver.mouseClick(asks, 5, 5);
        asks.asking = false;
        assertEqual(parts.label.text + " " + asks.clicks, "Remove 1", "the owner takes the question back with asking = false");
        asks.asking = true;
        assertEqual(parts.label.text + " " + asks.questions, "Remove? 3", "and may put it, without asked()");
        asks.confirm = false;
        assertEqual(asks.asking, false, "a button that no longer asks is not asking");
        driver.mouseClick(asks, 5, 5);
        assertEqual(asks.clicks + " " + asks.questions, "2 3", "and acts on one click, the same handler");
        plain.asking = true;
        assertEqual(plain.asking, false, "a button that does not ask cannot be asking");
        driver.mouseMove(away, 5, 5);

        // --- a label as written ---
        assert(_asWritten(_child(_inside(marked), "QQuickText")), "a label with markup in it is shown as written");
        const wordParts = _parts(_inside(asksInWords));
        driver.mouseClick(asksInWords, 5, 5);
        assert(wordParts.label.text === "Really <b>on</b>?" && _asWritten(wordParts.label), "and a question too");
        asksInWords.asking = false;
        driver.mouseMove(away, 5, 5);

        // --- in layouts, as the internal one ---
        for (const pair of [{ name: "a RowLayout", mine: publicRow, theirs: internalRow }, { name: "a ColumnLayout", mine: publicColumn, theirs: internalColumn }]) {
            const mine = _items(pair.mine);
            const theirs = _items(pair.theirs);
            assert(_until(() => mine[3].width > 0 && theirs[3].width > 0 && _geometry(mine[3]) === _geometry(theirs[3])), "in " + pair.name + " the layout is done");
            for (const i of [0, 2, 3])
                assertEqual(_geometry(mine[i]), _geometry(theirs[i]), "in " + pair.name + ", \"" + mine[i].label + "\" stands where the internal one does, as large");
            assertEqual(pair.mine.implicitWidth + " " + pair.mine.implicitHeight, pair.theirs.implicitWidth + " " + pair.theirs.implicitHeight,
                "in " + pair.name + ", the hidden one takes no room: the layout wants the internal one's size");
            const stretched = _inside(mine[2]);
            assert(mine[2].width > mine[2].implicitWidth, "in " + pair.name + ", the stretched one is wider than its label needs");
            assertEqual(stretched.width + " " + stretched.height, mine[2].width + " " + mine[2].height, "… and the button inside fills it");
            assertEqual(mine[0].width + " " + mine[0].height, _inside(mine[0]).width + " " + _inside(mine[0]).height, "… one not stretched is as large as the button inside");
            assertEqual(mine[0].implicitWidth + " " + mine[0].implicitHeight, theirs[0].implicitWidth + " " + theirs[0].implicitHeight, "… and wants the internal one's size");
        }

        // --- narrower than its label ---
        const narrowLabel = _child(_inside(narrow), "QQuickText");
        assert(narrow.width === 80 && _inside(narrow).width === 80 && narrowLabel.truncated, "a button made narrower than its label keeps that width and cuts the label");
        const narrowParts = _parts(_inside(narrowAsks));
        assert(_inside(narrowAsks).width <= 80 && narrowParts.face.width === 80 && narrowParts.label.truncated,
               "a button that asks, made narrower than its label: no wider than that, its label cut");
        assert(narrowAsks.implicitWidth > 80, "… while it still asks for its full width");
        _inside(narrowAsks).asking = true;
        assert(_until(() => narrowParts.cancel.x === narrowParts.face.width) && narrowParts.face.width + narrowParts.cancel.width === 80 && narrowParts.label.truncated,
               "… asking, the question and its \"×\" in that width, the question cut");
        _inside(narrowAsks).asking = false;
        assertEqual(narrow.apiElement + " " + narrowAsks.apiElement, "SmallButton SmallButton", "the public button carries its mark, apiElement");
        try {
            narrow.apiElement = "Other";
        } catch (error) {
            // Read-only
        }
        assertEqual(narrow.apiElement, "SmallButton", "… read-only");

        _askingAndOneLine();
        _controls();
        _rows();
        _baseTypes();
        _progressAndTips();

        _window.visible = false;
        _secondWindow.visible = false;
        finish();
    }

    // `asking` however it is declared; module texts on one line and capped; the dimmed
    // states (an unavailable question's "×", a switch not enabled); a dropdown's colours
    function _askingAndOneLine() {
        const rules = ApiElementRules;

        // --- asking, declared ---
        assert(askingFirst.asking && _inside(askingFirst).asking, "asking declared before confirm: asking");
        assert(confirmFirst.asking && _inside(confirmFirst).asking, "… and after it");
        assert(boundAsking.asking && _inside(boundAsking).asking, "asking bound to the owner's flag: asking while it is true");
        for (const flag of [false, true, false, true]) {
            boundAsking.flag = flag;
            assertEqual(boundAsking.asking + " " + _inside(boundAsking).asking, flag + " " + flag, "… and follows it when it turns " + flag);
        }

        // --- the cap ---
        assertEqual(rules.oneLine("a\nb\r\nc\td\u2028e"), "a b c d e", "oneLine: line breaks and tabs folded into spaces");
        assertEqual(rules.oneLine("x".repeat(rules.textCap)), "x".repeat(rules.textCap), "… a text as long as the cap kept");
        const cut = rules.oneLine("x".repeat(rules.textCap + 1));
        assert(Array.from(cut).length === rules.textCap && cut.endsWith("…"), "… a longer one cut to the cap, \"…\" at the end");
        assertEqual(rules.oneLine("😀".repeat(100)), "😀".repeat(rules.textCap - 1) + "…", "… counted in characters, never splitting one");
        assertEqual(rules.oneLine("x".repeat(rules.textCap - 2) + "😀😀"), "x".repeat(rules.textCap - 2) + "😀😀", "… an emoji at the cap kept whole");
        assertEqual(rules.oneLine("x".repeat(rules.textCap - 2) + "😀😀z"), "x".repeat(rules.textCap - 2) + "😀…", "… an emoji at the cut kept whole");
        assertEqual(rules.oneLine(null) + rules.oneLine(undefined) + rules.oneLine({}) + rules.oneLine(3), "3", "… not a text: \"\"; a number as written");
        assertEqual(rules.textCap, 80, "the cap is 80 characters");
        assertEqual(Array.from(_child(_inside(longButton), "QQuickText").text).length, rules.textCap, "a button's long label is capped");
        assertEqual(Array.from(_texts(_within(longPill))[0].text).length, rules.textCap, "… a pill's");
        assertEqual(longPill.label.length, 200, "the element keeps what it was given");

        // --- one line ---
        const multiParts = _parts(_inside(multiLine));
        assertEqual(multiParts.label.text, "One Two Three", "a button's label with line breaks is one line");
        assertEqual(multiLine.height, asks.height, "… as tall as one with a one-line label");
        multiLine.asking = true;
        assertEqual(multiParts.label.text + "|" + multiLine.height, "Really sure?|" + asks.height, "… and so is its question");
        multiLine.asking = false;
        assertEqual(_texts(_within(multiPill))[0].text + "|" + multiPill.height, "One Two Three|" + Theme.pill.mediumHeight, "a pill's label too, the pill at its size's height");
        assertEqual(internalMultiPill.height, ThemeRules.pillHeight(Theme.pill, "s"), "the shell's own pill shows a label with line breaks on one line");
        assertEqual(internalMultiAsk.height, internalOneAsk.height, "… and its asking button");
        internalMultiAsk.asking = true;
        internalOneAsk.asking = true;
        assertEqual(internalMultiAsk.height, internalOneAsk.height, "… asking too");
        internalMultiAsk.asking = false;
        internalOneAsk.asking = false;

        // --- a dropdown's options ---
        const option = _within(coloured).options[0];
        assertEqual(JSON.stringify(option), JSON.stringify({ value: "a", label: "Red line" }), "a dropdown's option reaches the one inside without its colour, its label on one line");
        assertEqual(JSON.stringify(rules.dropdownOptions([{ value: 1, label: "One", color: "#f00", extra: true }, null])),
            JSON.stringify([{ value: 1, label: "One" }, { label: "" }]), "dropdownOptions: value and label alone");
        assertEqual(rules.dropdownOptions("junk").length, 0, "… not a list: none");

        // --- dimmed ---
        const dimmed = _inside(unavailable).opacity;
        assert(dimmed < 1, "a button that is not available is dimmed");
        const unavailableParts = _parts(_inside(unavailableAsking));
        assert(unavailableAsking.asking && unavailableParts.cancel.visible, "a button that is not available may be asking");
        assertEqual(unavailableParts.face.opacity + " " + unavailableParts.cancel.opacity, dimmed + " " + dimmed, "… its question and its \"×\" dimmed alike");
        driver.mouseClick(unavailableParts.cancel, 3, 3);
        assert(unavailableAsking.asking, "… and the \"×\" takes no click");
        driver.mouseMove(away, 5, 5);
        assertEqual(internalOff.opacity + " " + internalOn.opacity, dimmed + " 1", "a switch not enabled is dimmed as a button not available");
        assertEqual(_within(toggleOff).opacity + " " + _within(toggle).opacity, dimmed + " 1", "… the public one too");
    }

    // PopupWidget, BarText, BarRow, PointerArea, VpnProvider: subtypes, not wrappers
    function _baseTypes() {
        const made = { PopupWidget: popupWidget, BarText: barText, BarRow: barRow, PointerArea: ownArea, VpnProvider: unregistered };
        const inside = { PopupWidget: PopupWidget, BarText: BarText, BarRow: BarRow, PointerArea: PointerArea, VpnProvider: VpnProvider };
        for (const name in made) {
            assertEqual(pinnedBase[name].filter(pinnedName => !(pinnedName in made[name])).join(" "), "", name + " has every name pinned for it");
            assert(made[name] instanceof inside[name], "… and is the shell's own " + name + ", not a wrapper");
        }
        for (const name of ["rowExtras", "cardExtras", "pageUrl"])
            assert(!pinnedBase.VpnProvider.includes(name), "a provider's " + name + " is not promised");

        assert(!unregistered.registered && unregistered.kind === "vpn" && unregistered.canChange && unregistered.entries.length === 0,
            "a provider's defaults: a VPN, may change, no entries");
        assertEqual(popupWidget.widgetType + " " + popupWidget.popupOpen + " " + popupWidget.interactive, "apiElementsTest false true", "a widget keeps its type; no popup open, takes input");
        assert(barRow.parent !== popupWidget && barText.parent === barRow, "a widget's children are its cell's content");
        assert(_asWritten(_texts(barText)[0]), "a bar text with markup in it is shown as written");
        assert(_until(() => barRow.width >= barText.width + 4 && barRow.vertical === BarLayout.vertical), "a bar row lays its texts out along the bar");

        assert(_until(() => {
            driver.mouseMove(away, 5, 5);
            driver.mouseMove(ownControl, 5, 5);
            return ownArea.lit;
        }), "a module's own control is lit under the pointer");
        assert(ownArea.centred && ownArea.width >= Theme.target.minSize && ownArea.height >= Theme.target.minSize, "its area is at least the theme's least target");
        driver.mouseClick(ownControl, 5, 5);
        assertEqual(ownArea.clicks, 1, "and takes the click");
        driver.mouseClick(popupWidget, 5, 5);
        assertEqual(popupWidget.clicks, 1, "a click on a widget's cell is clicked()");
        driver.mouseMove(away, 5, 5);
        assert(_until(() => !ownArea.lit), "the look goes when the pointer has left");
    }

    // The texts under `item` that say "<b>x</b>"
    function _marked(item) {
        return _texts(item).filter(text => text.text === "<b>x</b>");
    }

    // SettingsRow, ExpandingRow, Notice; and the texts of the settings blocks, as written
    function _rows() {
        const rules = ApiElementRules;

        // --- the words ---
        for (const entry of noticeKinds)
            assertEqual(JSON.stringify(rules.noticeKind(entry.kind)), JSON.stringify({ value: entry.inside, known: true }), "a notice's kind " + entry.kind + " is the theme's " + entry.inside);
        assertEqual(Object.keys(rules.noticeKinds).sort().join(" "), noticeKinds.map(entry => entry.kind).sort().join(" "), "and those are all a notice's kinds");
        for (const word of ["info", "", "primary", "error", "toString", undefined, 3])
            assertEqual(JSON.stringify(rules.noticeKind(word)), JSON.stringify({ value: "warning", known: false }), "a notice's kind " + JSON.stringify(word) + " is not one: the default, warning");

        // --- the names ---
        const across = _items(publicRowsAcross);
        const types = ["SettingsRow", "ExpandingRow", "Notice"];
        for (let i = 0; i < types.length; i++)
            assertEqual(JSON.stringify(_names(across[i])), JSON.stringify(pinned[types[i]]), types[i] + "'s public properties and signals are the pinned ones");

        // --- defaults ---
        assertEqual([bareRow.label, bareRow.hint, bareRow.value, expandingRow.open, notice.kind].join("|"), "|||false|warning", "a row has no texts, a row that opens is closed, a notice warns");

        // --- the row ---
        const marked = _marked(_within(settingsRow));
        assertEqual(marked.length, 3, "a row shows its label, its hint and its value");
        assert(marked.every(text => root._asWritten(text)), "each with markup in it as written");
        assertEqual(_texts(_within(bareRow)).filter(text => text.visible && text.text !== "").length, 0, "a row without texts shows none");
        assert(_until(() => rowButton.width > 0 && rowButton.mapToItem(settingsRow, 0, 0).x > marked[0].mapToItem(settingsRow, 0, 0).x + marked[0].width - 1),
            "its children are the controls, to the right of its label");
        assert(rowSwitch.mapToItem(settingsRow, 0, 0).x >= rowButton.mapToItem(settingsRow, 0, 0).x + rowButton.width, "one after another");
        assertEqual(Math.round(rowSwitch.mapToItem(settingsRow, 0, 0).x + rowSwitch.width), settingsRow.width, "the last at the row's right edge");
        driver.mouseClick(rowButton, 5, 5);
        assertEqual(rowButton.clicks, 1, "and take their clicks");
        driver.mouseMove(away, 5, 5);

        // --- a long value ---
        for (const entry of [{ row: narrowLongRow, button: narrowLongButton }, { row: wideLongRow, button: wideLongButton }]) {
            const texts = _texts(_within(entry.row));
            const label = texts.find(text => text.text === "Save to");
            const value = texts.find(text => text.text === entry.row.value);
            const name = "a long value in a row " + entry.row.width + " wide: ";
            assert(_until(() => entry.button.width > 0 && value.width > 0), name + "laid out");
            assert(!label.truncated && label.width >= label.implicitWidth, name + "the label keeps its full width");
            assert(value.truncated && value.width <= 220, name + "the value elides, at most 220 wide (" + value.width + ")");
            const valueRight = value.mapToItem(entry.row, 0, 0).x + value.width;
            const buttonLeft = entry.button.mapToItem(entry.row, 0, 0).x;
            assert(value.mapToItem(entry.row, 0, 0).x >= label.mapToItem(entry.row, 0, 0).x + label.width && buttonLeft >= valueRight,
                name + "label, value, button, one after another");
            assertEqual(Math.round(buttonLeft + entry.button.width), entry.row.width, name + "the button whole, at the row's right edge");
        }
        assertEqual(_texts(_within(wideLongRow)).find(text => text.text === wideLongRow.value).width, 220, "in a wide row, the value takes its 220");

        // --- the row that opens ---
        const opening = _within(expandingRow);
        const openMarked = _marked(opening);
        assert(openMarked.length === 2 && openMarked.every(text => root._asWritten(text)), "a row that opens shows its label and its hint, as written");
        const mark = _texts(opening).find(text => text.text === "▸" || text.text === "▾");
        assertEqual(expandingRow.built + " " + mark.text, "0 ▸", "closed, nothing of its child exists, and its mark is the closed card's");
        const closedHeight = expandingRow.implicitHeight;
        driver.mouseClick(expandingRow, expandingRow.width / 2, 5);
        assertEqual(expandingRow.open + " " + expandingRow.built + " " + mark.text, "true 1 ▾", "a click on its line opens it: the child is built, the mark is the opened card's");
        const loader = _child(opening, "QQuickLoader");
        assert(_until(() => loader.item && loader.item.width === expandingRow.width && expandingRow.implicitHeight === closedHeight + 6 + 20), "the child is as wide as the row, under the line");
        assertEqual(loader.item.objectName, "opened", "… the element written inside the row");
        driver.mouseClick(expandingRow, expandingRow.width / 2, 5);
        assert(!expandingRow.open && loader.item === null && _until(() => expandingRow.implicitHeight === closedHeight), "a second click closes it: the child is gone, the row as tall as before");
        expandingRow.open = true;
        assertEqual(expandingRow.built, 2, "the owner opens it too, and the child is built anew");
        expandingRow.open = false;
        driver.mouseMove(away, 5, 5);

        // --- the notice ---
        const line = _texts(notice)[0];
        assert(_asWritten(line), "a notice with markup in it is shown as written");
        assertEqual(line.font.pixelSize + " " + line.wrapMode, Theme.fontSizeSmall + " " + Text.WordWrap, "small, wrapping");
        for (const entry of noticeKinds) {
            notice.kind = entry.kind;
            assert(Qt.colorEqual(line.color, Theme[entry.inside]), "a " + entry.kind + " notice is drawn in the theme's " + entry.inside);
        }
        assert(!Qt.colorEqual(Theme.warning, Theme.error) && !Qt.colorEqual(Theme.warning, Theme.success) && !Qt.colorEqual(Theme.error, Theme.success), "the three colours differ in the theme");
        notice.kind = "warning";
        assert(Qt.colorEqual(_texts(mistypedNotice)[0].color, Theme.warning), "a kind that does not exist shows as warning");
        assertEqual(ApiElements.warned.filter(key => key === "Notice.kind=info").length, 1, "… warned about once");
        assert(!ApiElements.warned.some(key => /^Notice\.kind=(warning|danger|success)$/.test(key)), "a kind it knows is not warned about");

        // --- the settings blocks' texts, as written ---
        assert(_asWritten(heading), "a heading with markup in it is shown as written");
        assert(_asWritten(sectionTitle), "a section's title");
        assert(_asWritten(hint), "a hint");
        const switchMarked = _marked(switchRow);
        assert(switchMarked.length === 2 && switchMarked.every(text => root._asWritten(text)), "a switch row's label and hint");
        assert(_marked(labelled).length === 1 && _asWritten(_marked(labelled)[0]), "a setting's label");
        const settingHint = _texts(labelled).find(text => text.text === SettingsSchema.entry("notifications.toastColumnSize").hint);
        assert(!!settingHint && settingHint.textFormat === Text.PlainText, "a setting's hint is plain text");
        const settingSuffix = _texts(suffixed).find(text => text.text === SettingsSchema.entry("lockscreen.screensaverTimeout").suffix);
        assert(!!settingSuffix && settingSuffix.textFormat === Text.PlainText, "and its unit");
        assert(_until(() => root._marked(pageList).length === 1) && _asWritten(_marked(pageList)[0]), "a page's name in the settings window's list");

        // --- in layouts, as the internal ones ---
        const pairs = [
            { name: "a ColumnLayout", mine: publicRows, theirs: internalRows, shown: [0, 2, 3, 5], names: ["SettingsRow", "", "closed ExpandingRow", "open ExpandingRow", "", "Notice"] },
            { name: "a RowLayout", mine: publicRowsAcross, theirs: internalRowsAcross, shown: [0, 1, 2], names: types }
        ];
        for (const pair of pairs) {
            const mine = _items(pair.mine);
            const theirs = _items(pair.theirs);
            const last = pair.shown[pair.shown.length - 1];
            assert(_until(() => mine[last].width > 0 && theirs[last].width > 0 && pair.shown.every(i => root._geometry(mine[i]) === root._geometry(theirs[i]))), "in " + pair.name + " the layout is done");
            for (const i of pair.shown) {
                assertEqual(_geometry(mine[i]), _geometry(theirs[i]), "in " + pair.name + ", the " + pair.names[i] + " stands where the internal one does, as large");
                assertEqual(_within(mine[i]).width, mine[i].width, "… and the one inside is as wide");
            }
            assertEqual(pair.mine.implicitWidth + " " + pair.mine.implicitHeight, pair.theirs.implicitWidth + " " + pair.theirs.implicitHeight,
                "in " + pair.name + ", the hidden ones take no room: the layout wants the internal one's size");
        }
        assertEqual(_items(publicRows)[0].width + " " + _items(publicRows)[5].width, "300 300", "a row and a notice fill a column's width unasked");
        assert(_items(publicRows)[5].height > _texts(_items(publicRowsAcross)[2])[0].height, "a notice too long for its width wraps");
    }

    // Dropdown, InputField, Pill, Checkbox, ToggleSwitch, PrivilegedMark
    function _controls() {
        const rules = ApiElementRules;

        // --- the words ---
        for (const entry of pillSizes)
            assertEqual(JSON.stringify(rules.pillSize(entry.size)), JSON.stringify({ value: entry.inside, known: true }), "a pill's size " + entry.size + " is " + entry.inside + " inside");
        assertEqual(Object.keys(rules.pillSizes).sort().join(" "), pillSizes.map(entry => entry.size).sort().join(" "), "and those are all a pill's sizes");
        for (const word of ["xs", "", "huge", "toString", undefined, 3])
            assertEqual(JSON.stringify(rules.pillSize(word)), JSON.stringify({ value: "m", known: false }), "a pill's size " + JSON.stringify(word) + " is not one: the default, m");
        for (const entry of pillTextSizes)
            assertEqual(JSON.stringify(rules.pillTextSize(entry.size)), JSON.stringify({ value: entry.inside, known: true }), "a pill's text size " + entry.size + " is the theme's " + entry.inside);
        assertEqual(Object.keys(rules.pillTextSizes).sort().join(" "), pillTextSizes.map(entry => entry.size).sort().join(" "), "and those are all a pill's text sizes");
        for (const word of ["s", "m", "", "huge", "12", "toString", undefined, 12])
            assertEqual(JSON.stringify(rules.pillTextSize(word)), JSON.stringify({ value: "fontSizeSmall", known: false }), "a pill's text size " + JSON.stringify(word) + " is not one: the default, small");
        for (const entry of needs) {
            assertEqual(JSON.stringify(rules.markNeed(entry.need)), JSON.stringify({ value: entry.inside, known: true }), "a mark's need \"" + entry.need + "\" is \"" + entry.inside + "\" inside");
            assertEqual(rules.markShown(entry.need), entry.shown, "… and " + (entry.shown ? "shows" : "shows nothing"));
        }
        assertEqual(Object.keys(rules.markNeeds).sort().join(" "), needs.map(entry => entry.need).sort().join(" "), "and those are all a mark's needs");
        for (const word of ["perhaps", "AUTH", "toString", "__proto__", undefined, null, 3]) {
            assertEqual(JSON.stringify(rules.markNeed(word)), JSON.stringify({ value: "auth", known: false }), "a need " + JSON.stringify(word) + " is not one: the lock");
            assert(rules.markShown(word), "… which shows");
        }

        // --- the names ---
        const types = ["Dropdown", "InputField", "Pill", "Checkbox", "ToggleSwitch", "PrivilegedMark"];
        for (let i = 0; i < types.length; i++)
            assertEqual(JSON.stringify(_names(_items(publicStretched)[i])), JSON.stringify(pinned[types[i]]), types[i] + "'s public properties and signals are the pinned ones");
        assert(_names(_within(dropdown)).includes("fontSize") && _names(_within(dropdown)).includes("open"), "… the internal dropdown's own are not among them (it has fontSize, open)");
        assert(_names(_within(field)).includes("fieldColor") && _names(_within(field)).includes("outlined") && _names(_within(field)).includes("input"),
            "nor the internal field's (fieldColor, outlined, input)");
        assert(_names(_within(pill)).includes("minimumHeight") && _names(_within(toggle)).includes("offColor"), "nor the pill's minimumHeight, the switch's offColor");

        // --- defaults ---
        assertEqual([unchosen.size, field.size, pill.size].join(" "), "m m m", "a dropdown, a field and a pill are of size m unless told");
        assertEqual(JSON.stringify([unchosen.options, unchosen.value === undefined, field.text, field.placeholder === "<b>x</b>", field.problem, field.password, field.revealed]),
            JSON.stringify([[], true, "", true, false, false, false]), "a dropdown has no options and no value, a field is empty, right, not a password");
        assertEqual([pill.picked, pill.tooltip, checkbox.checked, toggle.checked, toggle.enabled, mark.need].join(" "), "false What it means false false true auth",
            "a pill is not picked, a box not checked, a switch off and enabled, a mark the lock");

        // --- each size, read from the control inside ---
        for (const entry of sizes) {
            unchosen.size = entry.size;
            field.size = entry.size;
            assertEqual(_within(unchosen).fontSize, Theme[entry.inside], "a dropdown of size " + entry.size + " has the theme's " + entry.inside);
            assertEqual(_texts(_within(unchosen))[0].font.pixelSize, Theme[entry.inside], "… its label drawn in it");
            assertEqual(_within(field).fontSize, Theme[entry.inside], "a field of size " + entry.size + " has the theme's " + entry.inside);
            assertEqual(_within(field).input.font.pixelSize, Theme[entry.inside], "… its text drawn in it");
        }
        unchosen.size = "m";
        field.size = "m";
        for (const entry of pillSizes) {
            pickedPill.size = entry.size;
            assertEqual(_within(pickedPill).size, entry.inside, "a pill of size " + entry.size + " is " + entry.inside + " inside");
            assertEqual(pickedPill.height + " " + pickedPill.implicitHeight, ThemeRules.pillHeight(Theme.pill, entry.inside) + " " + ThemeRules.pillHeight(Theme.pill, entry.inside),
                "… and as tall as the theme's pill of that size");
        }
        assert(Theme.pill.minHeight < Theme.pill.mediumHeight && Theme.pill.mediumHeight < Theme.pill.largeHeight, "the three heights differ in the theme");
        assertEqual(pill.height, Theme.pill.mediumHeight, "a pill that names no size is m: the theme's medium height");
        assertEqual(pill.textSize + " " + _within(pill).fontSize + " " + _texts(_within(pill))[0].font.pixelSize, "small " + Theme.fontSizeSmall + " " + Theme.fontSizeSmall,
            "a pill that names no text size: small, its label in the theme's small size (as before 1.32)");
        for (const entry of pillTextSizes) {
            pickedPill.textSize = entry.size;
            assertEqual(_within(pickedPill).fontSize + " " + _texts(_within(pickedPill))[0].font.pixelSize, Theme[entry.inside] + " " + Theme[entry.inside],
                "a pill of text size " + entry.size + ": its label in the theme's " + entry.inside);
        }
        pickedPill.textSize = "small";

        // --- what is passed on ---
        assertEqual(_within(dropdown).value + " " + _within(dropdown).options.length + " " + _within(unchosen).placeholder, "a 2 <b>x</b>", "a dropdown's value, options and placeholder reach the one inside");
        dropdown.value = "b";
        assertEqual(_texts(_within(dropdown))[0].text, "Second", "it shows the label of the value it is given");
        dropdown.value = "a";
        field.text = "typed";
        assertEqual(_within(field).input.text, "typed", "a field's text reaches the input inside");
        _within(field).input.text = "changed inside";
        assertEqual(field.text, "changed inside", "and what the input holds is the field's text");
        field.text = "";
        assert(_within(secret).problem && _within(secret).password && !_within(field).problem && !_within(field).password, "problem and password reach the field inside");
        assertEqual(_within(secret).input.echoMode, TextInput.Password, "a password is not shown");
        assert(_within(pickedPill).picked && !_within(pill).picked, "picked reaches the pill inside");
        assertEqual(_within(pill).tooltip, "What it means", "and so does the tooltip");
        assert(_within(checkedBox).checked && !_within(checkbox).checked, "checked reaches the checkbox inside");
        assert(_within(toggleOff).checked && !_within(toggle).checked, "and the switch inside");
        for (const signalName of ["accepted", "textEdited", "editingFinished"])
            _within(field).input[signalName]();
        assertEqual(field.heard, "accepted textEdited editingFinished ", "the input's accepted, textEdited and editingFinished are the field's");

        // --- the mark ---
        for (const entry of needs) {
            variedMark.need = entry.need;
            assertEqual(_within(variedMark).need, entry.inside, "a mark with need \"" + entry.need + "\" is \"" + entry.inside + "\" inside");
            assertEqual(variedMark.visible + " " + _within(variedMark).visible, entry.shown + " " + entry.shown, "… and is " + (entry.shown ? "there" : "hidden"));
        }
        assert(mark.visible && mark.width > 0 && mark.width === _within(mark).implicitWidth, "the lock is as wide as the mark inside");
        assert(mistypedMark.visible && _within(mistypedMark).visible && _within(mistypedMark).need === "auth", "a need it does not know shows the lock");
        assertEqual(mistypedMark.need, "perhaps", "the element keeps the word it was given");
        assert(forcedMark.visible && !_within(forcedMark).visible, "a mark a module shows itself still shows nothing when there is nothing to mark");
        assertEqual(forcedMark.width + " " + forcedMark.height + " " + forcedMark.implicitWidth, "0 0 0", "… and has no size");

        // --- words it does not know ---
        assertEqual(_within(mistypedPill).size + " " + mistypedPill.height, "m " + Theme.pill.mediumHeight, "a pill of a size that does not exist shows as m");
        unchosen.size = "l";
        field.size = "l";
        assertEqual(_within(unchosen).fontSize + " " + _within(field).fontSize, Theme.fontSizeBody + " " + Theme.fontSizeBody, "a dropdown and a field have no size l: m");
        unchosen.size = "m";
        field.size = "m";
        assertEqual(_within(mistypedPill).fontSize, Theme.fontSizeSmall, "a pill of a text size that does not exist shows as small");
        for (const key of ["Pill.size=xs", "Pill.textSize=huge", "Dropdown.size=l", "InputField.size=l", "PrivilegedMark.need=perhaps"])
            assertEqual(ApiElements.warned.filter(warned => warned === key).length, 1, "warned about once: " + key);
        assert(!ApiElements.warned.some(key => /^(Dropdown|InputField|Pill)\.size=(s|m)$/.test(key) || /^PrivilegedMark\.need=(|yes|auth|no)$/.test(key)), "a word a control knows is not warned about");

        // --- clicks ---
        driver.mouseClick(pill, 5, 5);
        assertEqual(pill.clicks, 1, "a click on a pill is clicked()");
        assert(!pill.picked, "… the owner picks it");
        driver.mouseClick(checkbox, 5, 5);
        assertEqual(checkbox.toggles + " " + checkbox.checked, "1 false", "a click on a checkbox is toggled(); the owner flips it");
        driver.mouseClick(toggle, 5, 5);
        assertEqual(toggle.toggles + " " + toggle.checked, "1 false", "a click on a switch is toggled(); the owner flips it");
        driver.mouseClick(toggleOff, 5, 5);
        assertEqual(toggleOff.toggles, 0, "a switch that is not enabled does nothing");
        const eye = _texts(_within(secret)).find(text => text.visible && text.text !== "" && text.text !== "hidden");
        driver.mouseClick(eye, 3, 3);
        assertEqual(secret.revealed + " " + secret.toggles, "true 1", "the eye of a password shows it: revealed, revealToggled()");
        assertEqual(_within(secret).input.echoMode, TextInput.Normal, "… readable now");
        secret.revealed = false;
        assertEqual(_within(secret).input.echoMode, TextInput.Password, "and the owner hides it again");

        driver.mouseClick(dropdown, 5, 5);
        assert(_within(dropdown).open, "a click opens a dropdown");
        // The list lives in the window's top item, over everything else
        const list = Array.from(_within(dropdown).Window.contentItem.children).find(child => child.toString().startsWith("FloatingList") && child.visible);
        assert(!!list, "its list is shown over the content");
        const rows = list ? Array.from(list.children[0].contentItem.children[0].children).filter(child => child.toString().startsWith("QQuickRectangle")) : [];
        assertEqual(rows.length, 2, "with a row for each option");
        if (rows.length === 2) {
            assert(_until(() => rows[1].width > 0 && list.y > 0), "placed under the dropdown");
            driver.mouseClick(rows[1], 5, 5);
            assertEqual(dropdown.got + " " + dropdown.value + " " + _within(dropdown).open, "b a false", "a click on an option is picked(value) and closes the list; the owner sets the value");
            assert(_asWritten(_texts(rows[0])[0]), "an option's label with markup in it is shown as written");
        }
        driver.mouseMove(away, 5, 5);

        // --- labels as written ---
        assert(_texts(_within(dropdown))[0].text === "<b>x</b>" && _asWritten(_texts(_within(dropdown))[0]), "a dropdown's label with markup in it is shown as written");
        assert(_texts(_within(unchosen))[0].text === "<b>x</b>" && _asWritten(_texts(_within(unchosen))[0]), "and its placeholder");
        assert(_texts(_within(field))[0].text === "<b>x</b>" && _asWritten(_texts(_within(field))[0]), "a field's placeholder");
        assert(_asWritten(_texts(_within(pill))[0]), "a pill's label");
        assert(_asWritten(_texts(_within(checkbox)).find(text => text.text === "<b>x</b>")), "a checkbox's label");

        // --- in layouts, as the internal ones ---
        const pairs = [
            { name: "a RowLayout", mine: publicControls, theirs: internalControls, shown: 6 },
            { name: "a RowLayout, all stretched", mine: publicStretched, theirs: internalStretched, shown: 6 },
            { name: "a ColumnLayout", mine: publicControlColumn, theirs: internalControlColumn, shown: 6 }
        ];
        for (const pair of pairs) {
            const mine = _items(pair.mine);
            const theirs = _items(pair.theirs);
            assert(_until(() => mine[5].width > 0 && theirs[5].width > 0 && _geometry(mine[5]) === _geometry(theirs[5])), "in " + pair.name + " the layout is done");
            for (let i = 0; i < pair.shown; i++) {
                assertEqual(_geometry(mine[i]), _geometry(theirs[i]), "in " + pair.name + ", the " + types[i] + " stands where the internal one does, as large");
                assertEqual(_within(mine[i]).width + " " + _within(mine[i]).height, mine[i].width + " " + mine[i].height, "… and the one inside fills it");
                assertEqual(mine[i].implicitWidth + " " + mine[i].implicitHeight, theirs[i].implicitWidth + " " + theirs[i].implicitHeight, "… and wants the internal one's size");
            }
            assertEqual(pair.mine.implicitWidth + " " + pair.mine.implicitHeight, pair.theirs.implicitWidth + " " + pair.theirs.implicitHeight,
                "in " + pair.name + ", the hidden ones and a mark with nothing to mark take no room: the layout wants the internal one's size");
        }
        const stretched = _items(publicStretched);
        for (let i = 0; i < stretched.length; i++)
            assert(stretched[i].width > stretched[i].implicitWidth, "stretched, the " + types[i] + " is wider than it needs");
    }

    // The internal tooltip a public one shows: it lives in the window's top item
    function _tipOf(publicTip) {
        const top = publicTip.Window.window?.contentItem;
        return top ? Array.from(top.children).find(child => child.toString().startsWith("HoverTip") && child.target === publicTip.target) ?? null : null;
    }

    // The hover handlers on `item`
    function _handlersOn(item) {
        return Array.from(item.data).filter(child => child.toString().startsWith("QQuickHoverHandler")).length;
    }

    // (1.35) The words of the bar's wave and the status pill
    function _statusWords() {
        const rules = ApiElementRules;
        // --- progressWaves(wave, value, reduceMotion) ---
        assert(rules.progressWaves(true, 0.4, false) && rules.progressWaves(true, 0, false), "a wave asked for, a value from 0 below 1: it runs");
        assert(!rules.progressWaves(false, 0.4, false), "not asked for: none");
        assert(!rules.progressWaves(true, 1, false) && !rules.progressWaves(true, 1.5, false), "a full bar: none");
        assert(!rules.progressWaves(true, -0.5, false) && !rules.progressWaves(true, -1, false), "a run of unknown length (below 0): none");
        assert(!rules.progressWaves(true, NaN, false) && !rules.progressWaves(true, "0.4", false) && !rules.progressWaves(true, undefined, false), "not a number: none");
        assert(!rules.progressWaves(true, 0.4, true), "reduced motion: none");
        assert(!rules.progressWaves("yes", 0.4, false) && !rules.progressWaves(1, 0.4, false), "only true asks for it");
        // --- progressWaveSchedule(spawnMs, travelMs, pool) ---
        const schedule = (spawn, travel, pool) => JSON.stringify(rules.progressWaveSchedule(spawn, travel, pool));
        assertEqual(schedule(300, 1200, 6), JSON.stringify({ slots: 4, spacing: 300, travel: 1200, cycle: 1200 }), "a wave every 300 ms crossing in 1200: four bands, each again after 1200 ms");
        assertEqual(schedule(300, 1000, 6), JSON.stringify({ slots: 4, spacing: 300, travel: 1000, cycle: 1200 }), "a crossing not a whole number of spawns: a band rests until its turn");
        assertEqual(schedule(500, 300, 6), JSON.stringify({ slots: 1, spacing: 500, travel: 300, cycle: 500 }), "a crossing shorter than the spawn: one band");
        assertEqual(schedule(100, 1200, 6), JSON.stringify({ slots: 6, spacing: 200, travel: 1200, cycle: 1200 }), "the pool short: the waves come further apart, never more bands");
        assertEqual(schedule(0, 0, 6), JSON.stringify({ slots: 1, spacing: 1, travel: 1, cycle: 1 }), "durations of 0: 1 ms");
        assertEqual(schedule(300, 1200, 0), JSON.stringify({ slots: 1, spacing: 1200, travel: 1200, cycle: 1200 }), "no pool: one band");

        // --- statusKind ---
        const statusKinds = { normal: ["accent", "textPrimary"], muted: ["textMuted", "textMuted"], success: ["success", "success"],
            warning: ["warning", "warning"], danger: ["error", "error"] };
        for (const kind in statusKinds)
            assertEqual(JSON.stringify(rules.statusKind(kind)), JSON.stringify({ value: { icon: statusKinds[kind][0], text: statusKinds[kind][1] }, known: true }),
                        "a status pill's kind " + kind + ": the icon in " + statusKinds[kind][0] + ", the text in " + statusKinds[kind][1]);
        assertEqual(Object.keys(rules.statusKinds).sort().join(" "), Object.keys(statusKinds).sort().join(" "), "and those are all its kinds");
        for (const word of ["error", "accent", "", "toString", undefined, 3])
            assertEqual(JSON.stringify(rules.statusKind(word)), JSON.stringify({ value: { icon: "accent", text: "textPrimary" }, known: false }), "a kind " + JSON.stringify(word) + " is not one: normal");

        // --- statusParts ---
        const plain = rules.statusParts([{ icon: "\uf017", text: "3\n", kind: "muted", tip: "3 queued", line: "" },
                                         { icon: "\uf071x", text: "<b>1</b>", kind: "warning", tip: "1 with\nno progress", line: "1 with no progress for 3 min" },
                                         { icon: "\uf00c", text: "5", tip: "" },
                                         { text: "y".repeat(100), kind: "blue" },
                                         { kind: "pink" }, { kind: "blue" }, null, "text"]);
        assertEqual(JSON.stringify(plain.parts[0]), JSON.stringify({ icon: "\uf017", text: "3 ", kind: "muted", tip: "3 queued", line: "3 queued" }),
                    "a part made plain: its text on one line, a line left empty is the tip");
        assertEqual(plain.parts[1].text + "|" + plain.parts[1].tip + "|" + plain.parts[1].line, "<b>1</b>|1 with no progress|1 with no progress for 3 min",
                    "… markup kept as written (shown plain), a tip on one line, a line given kept");
        assertEqual(Array.from(plain.parts[1].icon).length, rules.iconCap, "… an icon one glyph long at most (" + rules.iconCap + " characters), nothing added");
        assertEqual(plain.parts[2].kind + " " + plain.parts[2].line, "normal 5", "no kind: normal, unlisted; no tip: the line is the text");
        assert(Array.from(plain.parts[3].text).length === rules.textCap && plain.parts[3].text.endsWith("…") && plain.parts[3].kind === "normal",
               "a long text cut at " + rules.textCap + "; a kind it does not know: normal");
        assertEqual(plain.unknownKinds.join(" "), "blue pink", "… the unknown kinds listed once each, in order");
        assertEqual(JSON.stringify(plain.parts[6]) + " " + JSON.stringify(plain.parts[7]), JSON.stringify(plain.parts[4]) + " " + JSON.stringify(plain.parts[4]),
                    "a part that is not an object: an empty one");
        assertEqual(JSON.stringify(plain.parts[4]), JSON.stringify({ icon: "", text: "", kind: "normal", tip: "", line: "" }), "… with nothing in it");
        assertEqual(plain.dropped, 0, "eight parts: none dropped");
        const many = rules.statusParts(Array.from({ length: 15 }, (_, i) => ({ text: String(i) })));
        assertEqual(many.parts.length + " " + many.dropped + " " + many.parts[11].text, rules.statusPartCap + " 3 11", "past " + rules.statusPartCap + " parts the rest dropped, counted");
        assertEqual(JSON.stringify(rules.statusParts(null)) + JSON.stringify(rules.statusParts("parts")), JSON.stringify({ parts: [], unknownKinds: [], dropped: 0 }).repeat(2),
                    "not an array: no parts");
        assertEqual(rules.iconText("\uf062\n") + "|" + rules.iconText(3) + "|" + rules.iconText({}), "\uf062 |3|", "an icon: one line, a number as written, anything else none");
    }

    // ProgressBar and HoverTip (1.31)
    function _progressAndTips() {
        const rules = ApiElementRules;

        // --- the words ---
        for (const entry of progressKinds)
            assertEqual(JSON.stringify(rules.progressKind(entry.kind)), JSON.stringify({ value: entry.inside, known: true }), "a progress bar's kind " + entry.kind + " is the theme's " + entry.inside);
        assertEqual(Object.keys(rules.progressKinds).sort().join(" "), progressKinds.map(entry => entry.kind).sort().join(" "), "and those are all a progress bar's kinds");
        for (const word of ["accent", "", "primary", "error", "toString", undefined, 3])
            assertEqual(JSON.stringify(rules.progressKind(word)), JSON.stringify({ value: "accent", known: false }), "a progress bar's kind " + JSON.stringify(word) + " is not one: the default, normal");
        assertEqual(rules.tipText("a\nb"), "a b", "a tooltip's text: line breaks as spaces");
        const long = rules.tipText("y".repeat(300));
        assert(Array.from(long).length === rules.tipCap && long.endsWith("…"), "… cut with \"…\" at " + rules.tipCap + " characters");
        assertEqual(rules.tipText("y".repeat(rules.tipCap)), "y".repeat(rules.tipCap), "… one of exactly that length whole");
        assertEqual(rules.tipText(null) + rules.tipText({}), "", "… nothing that is not a text");
        assertEqual(rules.oneLine("y".repeat(100)).length, rules.textCap, "a label still cut at " + rules.textCap);

        // --- the names ---
        assertEqual(JSON.stringify(_names(progress)), JSON.stringify(pinned.ProgressBar), "ProgressBar's public properties and signals are the pinned ones");
        assertEqual(JSON.stringify(_names(tip)), JSON.stringify(pinned.HoverTip), "HoverTip's public properties and signals are the pinned ones");
        assertEqual(progress.kind + " " + bareTip.text + "|" + (bareTip.target === tipHolder), "normal |true", "defaults: a normal bar, a tooltip with no text on the item it is written in");

        // --- the progress bar ---
        assert(_secondWindow.visible && _until(() => progress.width > 0), "the second window shows, the bars laid out");
        const inner = _within(progress);
        const track = inner.children[0];
        const fill = inner.children[1];
        assertEqual(progress.width + " " + progress.height, progressColumn.width + " " + Theme.progress.thickness, "a bar fills its layout's width, as thick as the theme says");
        assertEqual(track.radius, Math.min(Theme.progress.radius, Theme.progress.thickness / 2), "its ends rounded by the theme's radius, at most half its thickness");
        assert(Qt.colorEqual(track.color, Theme.track), "its track in the theme's track colour");
        assert(_until(() => Math.abs(fill.width - progress.width / 2) < 0.5), "value 0.5: half of it filled (" + fill.width + ")");
        for (const entry of progressKinds) {
            progress.kind = entry.kind;
            assert(Qt.colorEqual(fill.color, Theme[entry.inside]), "a " + entry.kind + " bar is filled in the theme's " + entry.inside);
        }
        progress.kind = "normal";
        assert(Qt.colorEqual(_within(mistypedProgress).children[1].color, Theme.accent), "a kind that does not exist shows as normal");
        assertEqual(ApiElements.warned.filter(key => key === "ProgressBar.kind=blue").length, 1, "… warned about once");
        assert(!ApiElements.warned.some(key => /^ProgressBar\.kind=(normal|success|warning|danger)$/.test(key)), "a kind it knows is not warned about");
        for (const [value, share, what] of [[2, 1, "above 1: full"], [0, 0, "0: empty"], [Infinity, 1, "Infinity: full"], [NaN, 0, "not a number: empty"], [1, 1, "1: full"]]) {
            progress.value = value;
            assert(_until(() => Math.abs(fill.width - progress.width * share) < 0.5), "value " + what + " (" + fill.width + ")");
        }
        progress.value = -Infinity;
        assert(_within(progress).indeterminate, "value -Infinity: a run of unknown length");
        progress.value = 1;
        const piece = _within(unknownLength).children[1];
        assert(Math.abs(piece.width - unknownLength.width * 0.3) < 0.5 && piece.x >= 0 && piece.x + piece.width <= unknownLength.width + 0.5,
               "a value below 0: a piece of the fill along the track (" + piece.x + ", " + piece.width + ")");
        if (!Theme.reduceMotion) {
            const firstPlace = piece.x;
            assert(_until(() => Math.abs(piece.x - firstPlace) > 2), "… sliding");
        }
        assertEqual(progressColumn.children[3].height, Theme.progress.thickness, "a hidden bar keeps its thickness");
        assertEqual(progressColumn.implicitHeight, 3 * Theme.progress.thickness + 2 * 6, "… and takes no room in a layout");
        assertEqual(Public.Api.theme.progress.thickness + " " + Public.Api.theme.progress.radius, Theme.progress.thickness + " " + Theme.progress.radius, "the thickness and radius are offered to modules (Api.theme.progress)");

        // --- the tooltip ---
        driver.mouseMove(elsewhere, 5, 5);
        const shown = _tipOf(tip);
        assert(shown !== null && !shown.visible, "a tooltip shows nothing before the pointer comes");
        driver.mouseMove(tipped, 10, 10);
        assert(_until(() => shown.visible), "the pointer over its item: the tooltip shows");
        assert(_asWritten(_texts(shown)[0]) && _texts(shown)[0].text === "<b>x</b>", "its text with markup in it as written");
        assert(shown.y + shown.height <= tipped.mapToItem(shown.parent, 0, 0).y + 0.5, "above the item");
        tip.text = "y".repeat(300);
        assertEqual(Array.from(_texts(shown)[0].text).length, ApiElementRules.tipCap, "a long text cut");
        tip.text = "<b>x</b>";
        driver.mouseMove(elsewhere, 5, 5);
        assert(_until(() => !shown.visible), "the pointer gone: the tooltip goes");

        const onButton = _tipOf(buttonTip);
        driver.mouseMove(tippedButton, 5, 5);
        assert(_until(() => onButton.visible) && _texts(onButton)[0].text === "On the button", "a tooltip inside a button shows over it");
        assert(_inside(tippedButton).hovered, "… the button lit all the same");
        driver.mouseClick(tippedButton, 5, 5);
        assertEqual(tippedButton.clicks, 1, "… and takes its clicks");
        driver.mouseMove(elsewhere, 5, 5);
        assert(_until(() => !onButton.visible), "… gone with the pointer");

        driver.mouseMove(aimed, 5, 5);
        assert(_until(() => _tipOf(aimedTip)?.visible === true), "a tooltip given a target shows over that item");
        driver.mouseMove(elsewhere, 5, 5);
        assert(_until(() => !_tipOf(aimedTip).visible), "… gone with the pointer");
        driver.mouseMove(aimed, 5, 5);
        assert(_until(() => _tipOf(aimedTip).visible), "… back with it");
        aimed.visible = false;
        assert(_until(() => !_tipOf(aimedTip).visible), "… gone when its item is hidden under the pointer");
        driver.mouseMove(elsewhere, 5, 5);
        aimed.visible = true;

        // A target destroyed while its tooltip shows (a row going away under the pointer):
        // the tooltip goes, nothing read from the handler that went with it
        const doomed = Qt.createQmlObject("import QtQuick\nRectangle { x: 260; y: 120; width: 40; height: 24 }", _secondWindow.contentItem, "DoomedTarget.qml");
        const doomedTip = Qt.createQmlObject("import qs.api\nHoverTip { text: \"Doomed\" }", _secondWindow.contentItem, "DoomedTip.qml");
        doomedTip.target = doomed;
        const doomedShown = _tipOf(doomedTip);
        driver.mouseMove(doomed, 5, 5);
        assert(_until(() => doomedShown.visible), "a tooltip on an item made later shows");
        doomed.destroy();
        assert(_until(() => doomedTip.target === null) && _until(() => !doomedShown.visible), "… its item destroyed under the pointer: the tooltip goes");
        driver.mouseMove(elsewhere, 5, 5);
        doomedTip.destroy();

        // Tooltips made and destroyed against one item leave one handler on it, not one each
        const kept = Qt.createQmlObject("import QtQuick\nRectangle { x: 260; y: 160; width: 40; height: 24 }", _secondWindow.contentItem, "KeptTarget.qml");
        let again = null;
        for (let i = 0; i < 3; i++) {
            again = Qt.createQmlObject("import qs.api\nHoverTip { text: \"Again\" }", _secondWindow.contentItem, "AgainTip.qml");
            again.target = kept;
            if (i < 2) {
                let gone = false;
                again.Component.destruction.connect(() => gone = true);
                again.destroy();
                assert(_until(() => gone), "a tooltip made against the item, destroyed");
            }
        }
        assert(_until(() => _handlersOn(kept) === 1), "three tooltips made in turn against one item, two destroyed: one handler on it (" + _handlersOn(kept) + ")");
        again.destroy();
        kept.destroy();

        const rowItems = _items(tipRow);
        assert(_until(() => rowItems[2].x > 0), "the row laid out");
        assertEqual(rowItems[2].x, 40 + 6, "a tooltip loose in a layout takes no room in it");
        assertEqual(rowItems[1].width + " " + rowItems[1].visible, "0 false", "… no size, and nothing shown in its place");
    }
}
