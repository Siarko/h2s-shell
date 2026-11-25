import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.components

// The gallery (H2S_MOCKUP=gallery, made by the entry, mockup.qml): every component and view
// in one scrollable window, components first, then views, each alphabetical. A section per
// element: its kind and name, about.txt's description, and the element's own Mockup.qml in
// all its states, every cell labelled as in the all-states window. Plans are not in it.
//
// Each section's mockup is created hosted (MockupWindow's `host`): no window and no
// IpcHandler of its own, its content laid out in the section. A section is created only when
// it scrolls near the view, so that the large views cost nothing until reached, and then kept.
// Every state is on screen at once, so what holds the keyboard while shown does not take it
// back (Isolation.keyboardHeld, as in the all-states window).
//
// A bar along the top stays while the page scrolls: the theme (MockupTheme: "default" and
// every theme file, shown live), a filter (sections whose name, description, state names
// and state descriptions do not hold every word are hidden, in any case, as the screen
// tool's search matches) and a button per section that scrolls to it.
//
// Over IPC (target `mockup`, as every mockup, so the screen tool's close reaches it):
//   name            "gallery"
//   window          "floating" once the window is made, else ""
//   sections        a line per section, in order: "<kind>/<name> <built|waiting|failed: …>"
//                   ("" until the folders are read)
//   cells <section> the section's cells as a mockup's `cells` answers ("not built" before)
//   jump <section>  scrolls to it (and so builds it): "" or why not
//   filter <text>   sets the filter: the sections shown, a line each
//   theme <name>    shows every section in that theme ("" only asks): the name in force, or
//                   why not
QtObject {
    id: root

    // Set by the entry: the folder holding components/ and views/, and its about.txt reader
    // (folder URL, word): { description, names, descriptions, error }
    property url baseUrl
    property var readAbout: null
    property bool visible: true

    // The sections, in order, and each one's about.txt, by <kind>/<name>
    property var sectionKeys: []
    property var _about: ({})
    property bool _listed: false
    property string filterText: ""
    property var _window: null

    readonly property var _kinds: ["components", "views"]

    // Whether the section matches the filter: every word in its name and description, or in
    // one state's name and description
    function matches(key) {
        const words = filterText.toLowerCase().split(/\s+/).filter(word => word !== "");
        if (words.length === 0)
            return true;
        const about = _about[key] ?? { description: "", names: [], descriptions: [] };
        const holds = text => words.every(word => text.toLowerCase().includes(word));
        if (holds(key + " " + about.description))
            return true;
        for (let i = 0; i < about.names.length; i++)
            if (holds(about.names[i] + " " + about.descriptions[i]))
                return true;
        return false;
    }

    function _section(key) {
        for (let i = 0; i < _sections.count; i++) {
            const section = _sections.itemAt(i);
            if (section && section.key === key)
                return section;
        }
        return null;
    }

    function jump(key) {
        const section = _section(key);
        if (!section)
            return "no section '" + key + "'";
        if (!section.visible)
            return "'" + key + "' is hidden by the filter";
        _scroller.contentY = Math.max(0, Math.min(section.y, _scroller.contentHeight - _scroller.height));
        section.build();
        return "";
    }

    // Reads both folders once they are listed: the sections and their about.txt
    function _list() {
        if (_listed || _componentsFolder.status !== FolderListModel.Ready || _viewsFolder.status !== FolderListModel.Ready)
            return;
        _listed = true;
        const keys = [];
        const about = {};
        for (const folder of [_componentsFolder, _viewsFolder]) {
            const kind = folder === _componentsFolder ? "components" : "views";
            const names = [];
            for (let i = 0; i < folder.count; i++)
                names.push(folder.get(i, "fileName"));
            names.sort();
            for (const name of names) {
                const key = kind + "/" + name;
                keys.push(key);
                about[key] = readAbout(Qt.resolvedUrl(baseUrl + "/" + key), "state");
            }
        }
        _about = about;
        sectionKeys = keys;
    }

    // Makes the window; "" or why not
    function start() {
        if (typeof readAbout !== "function")
            return "no about.txt reader";
        Isolation.keyboardHeld = false;
        const window = _floatingWindow.createObject(root);
        if (!window)
            return "the window cannot be made";
        _body.parent = window.contentItem;
        _window = window;
        return "";
    }

    readonly property FolderListModel _componentsFolder: FolderListModel {
        folder: root.baseUrl + "/components"
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
        onStatusChanged: root._list()
    }
    readonly property FolderListModel _viewsFolder: FolderListModel {
        folder: root.baseUrl + "/views"
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
        onStatusChanged: root._list()
    }

    readonly property Component _floatingWindow: Component {
        FloatingWindow {
            title: "gallery"
            implicitWidth: Math.min(1280, screen ? screen.width : 1280)
            implicitHeight: Math.min(900, screen ? screen.height : 900)
            color: Theme.popupBackground
            visible: root.visible
        }
    }

    readonly property Item _body: Item {
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0

        Rectangle {
            id: _bar
            z: 1
            width: parent.width
            height: _barColumn.implicitHeight + 2 * Theme.popup.contentPadding
            color: Theme.surface

            Column {
                id: _barColumn
                x: Theme.popup.contentPadding
                y: Theme.popup.contentPadding
                width: parent.width - 2 * Theme.popup.contentPadding
                spacing: Theme.popup.contentPadding

                Row {
                    spacing: Theme.popup.contentPadding

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Theme"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }
                    Dropdown {
                        id: _themes
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 180
                        options: MockupTheme.names.map(name => ({ value: name, label: name }))
                        value: MockupTheme.inForce
                        onPicked: value => MockupTheme.apply(value)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }
                    InputField {
                        id: _filter
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 240
                        outlined: true
                        placeholder: "Name or state"
                        onTextChanged: root.filterText = text
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: ScriptModel {
                            values: root.sectionKeys
                        }
                        SmallButton {
                            required property string modelData
                            visible: root.matches(modelData)
                            label: modelData.replace(/^[^\/]*\//, "")
                            tooltip: modelData
                            onClicked: root.jump(modelData)
                        }
                    }
                }
            }
        }

        Flickable {
            id: _scroller
            y: _bar.height
            width: parent.width
            height: Math.max(0, parent.height - y)
            contentWidth: width
            contentHeight: _column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            // A drag belongs to the mockups, never to the scroller
            interactive: false

            WheelHandler {
                target: null
                onWheel: event => {
                    const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 48;
                    _scroller.contentY = Math.max(0, Math.min(_scroller.contentHeight - _scroller.height, _scroller.contentY - dy));
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: _scroller.contentHeight > _scroller.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: width / 2
                    color: Theme.textSecondary
                }
            }

            Column {
                id: _column
                width: _scroller.width - 12

                Repeater {
                    id: _sections
                    model: ScriptModel {
                        values: root.sectionKeys
                    }

                    Item {
                        id: section
                        required property string modelData
                        required property int index
                        readonly property string key: modelData
                        readonly property string kind: key.replace(/\/.*$/, "")
                        readonly property var about: root._about[key] ?? { description: "", names: [], descriptions: [], error: "" }
                        readonly property bool firstOfKind: index === 0 || (root.sectionKeys[index - 1] ?? "").replace(/\/.*$/, "") !== kind
                        property var mockup: null
                        property string error: about.error ?? ""
                        property bool _tried: false
                        // Near the view: from one window's height above it to two below
                        readonly property bool near: visible && y < _scroller.contentY + 2 * _scroller.height
                            && y + height > _scroller.contentY - _scroller.height

                        readonly property string status: mockup ? "built" : error !== "" ? "failed: " + error : "waiting"

                        visible: root.matches(key)
                        width: _column.width
                        height: visible ? _heading.implicitHeight + _holder.height : 0

                        onNearChanged: if (near) Qt.callLater(build)
                        Component.onCompleted: if (near) Qt.callLater(build)

                        // Creates the section's mockup, hosted, in all its states (once)
                        function build() {
                            if (_tried)
                                return;
                            _tried = true;
                            if (error !== "")
                                return;
                            const url = Qt.resolvedUrl(root.baseUrl + "/" + key + "/Mockup.qml");
                            const component = Qt.createComponent(url, Component.PreferSynchronous);
                            if (component.status !== Component.Ready) {
                                error = component.errorString().replace(/\s+/g, " ").trim();
                                return;
                            }
                            const made = component.createObject(root, { host: _holder, declaredNames: about.names,
                                                                        declaredDescriptions: about.descriptions, mockupName: key });
                            if (!made) {
                                error = component.errorString().replace(/\s+/g, " ").trim();
                                return;
                            }
                            if (!(made instanceof MockupWindow)) {
                                made.destroy();
                                error = "the root of Mockup.qml is not a MockupWindow (qs.mockups.kit)";
                                return;
                            }
                            const problem = made.start("");
                            if (problem !== "") {
                                made.destroy();
                                error = problem;
                                return;
                            }
                            mockup = made;
                        }

                        Column {
                            id: _heading
                            width: parent.width
                            topPadding: section.firstOfKind ? 24 : 16
                            leftPadding: 16
                            spacing: 4

                            Text {
                                visible: section.firstOfKind
                                text: section.kind === "components" ? "Components" : "Views"
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeHeading
                                font.bold: true
                                color: Theme.textPrimary
                            }
                            Text {
                                width: parent.width - 32
                                text: section.key.replace(/^[^\/]*\//, "")
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                color: Theme.textPrimary
                            }
                            Text {
                                width: parent.width - 32
                                text: section.about.description
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textSecondary
                            }
                            Text {
                                visible: section.error !== ""
                                width: parent.width - 32
                                text: section.error
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.error
                            }
                        }

                        // The mockup's content goes here; until it is built, room as for a row of
                        // cells, so that the sections below do not all count as near
                        Item {
                            id: _holder
                            y: _heading.implicitHeight
                            width: parent.width
                            height: section.mockup ? section.mockup._laidHeight : section.error !== "" ? 8 : 240
                        }
                    }
                }
            }
        }
    }

    readonly property IpcHandler _ipc: IpcHandler {
        target: "mockup"

        function name(): string {
            return "gallery";
        }

        function window(): string {
            return root._window ? "floating" : "";
        }

        function sections(): string {
            const lines = [];
            for (let i = 0; i < _sections.count; i++) {
                const section = _sections.itemAt(i);
                if (section)
                    lines.push(section.key + " " + section.status);
            }
            return lines.join("\n");
        }

        function cells(key: string): string {
            const section = root._section(key);
            if (!section)
                return "no section '" + key + "'";
            return section.mockup ? section.mockup._cellsShown() : "not built";
        }

        function jump(key: string): string {
            return root.jump(key);
        }

        function filter(text: string): string {
            _filter.text = text;
            root.filterText = text;
            return root.sectionKeys.filter(key => root.matches(key)).join("\n");
        }

        function theme(name: string): string {
            return MockupTheme.apply(name);
        }
    }
}
