import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.components

// The gallery (H2S_MOCKUP=gallery, made by the entry, mockup.qml): every component in one
// scrollable window, alphabetical. A section per component: its name, about.txt's
// description, and the component's own Mockup.qml in all its states, every cell labelled as
// in the all-states window. Views and plans are not in it: a view is opened on its own.
//
// Each section's mockup is created hosted (MockupWindow's `host`): no window and no
// IpcHandler of its own, its content laid out in the section. A section is created only when
// it scrolls near the view, so that the sections far below cost nothing until reached, and
// then kept.
// Every state is on screen at once, so what holds the keyboard while shown does not take it
// back (Isolation.keyboardHeld, as in the all-states window).
//
// A bar along the top stays while the page scrolls: the theme (MockupTheme: "default" and
// every theme file, shown live), a filter (sections whose name, description, state names
// and state descriptions do not hold every word are hidden, in any case, as the screen
// tool's search matches) and a button per section that scrolls to it.
//
// The window closed by the user or the compositor emits `closed`, on which the entry ends the
// process.
//
// Over IPC (target `mockup`, as every mockup, so the screen tool's close reaches it):
//   name            "gallery"
//   window          "floating" once the window is made, else ""
//   sections        a line per section, in order: "<kind>/<name> <built|waiting|failed: …>"
//                   ("" until the folders are read)
//   cells <section> the section's cells as a mockup's `cells` answers ("not built" before)
//   jump <section>  scrolls to it (and so builds it), kept at the top while the sections
//                   above it are built and grow, until the wheel scrolls: "" or why not
//   top             the section at the top of the view
//   place <section> the centre of its button in the bar, in window coordinates: "<x>,<y>"
//                   ("" while it is not shown)
//   position        how far the page is scrolled: "0,<y>" in pixels ("" before the window)
//   filter <text>   sets the filter: the sections shown, a line each
//   theme <name>    shows every section in that theme ("" only asks): the name in force, or
//                   why not
QtObject {
    id: root

    // Set by the entry: the folder holding components/, and its about.txt reader
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

    // The window closed by the user or the compositor
    signal closed

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
        _anchored = key;
        section.build();
        _place();
        Qt.callLater(_place);
        return "";
    }

    // The section a jump keeps at the top of the view while sections above it are built and
    // grow from their placeholders, until the wheel scrolls; "" for none
    property string _anchored: ""

    function _place() {
        const section = _anchored !== "" ? _section(_anchored) : null;
        if (section && section.visible)
            _scroller.contentY = Math.max(0, Math.min(section.y, _scroller.contentHeight - _scroller.height));
    }

    // Builds the sections near the view where the column has placed them: laid out again
    // after each one built, so that a section that grew (or shrank to its error) moves the
    // ones below before they are looked at, never built for where its placeholder stood
    function _buildNear() {
        for (let i = 0; i < _sections.count; i++) {
            const section = _sections.itemAt(i);
            if (section && section.near && !section._tried) {
                section.build();
                _column.forceLayout();
            }
        }
    }

    // The section at the top of the view, or ""
    function _top() {
        for (let i = 0; i < _sections.count; i++) {
            const section = _sections.itemAt(i);
            if (section && section.visible && section.y <= _scroller.contentY && _scroller.contentY < section.y + section.height)
                return section.key;
        }
        return "";
    }

    onFilterTextChanged: Qt.callLater(_buildNear)

    // Reads the components' folder once it is listed: the sections and their about.txt
    function _list() {
        if (_listed || _componentsFolder.status !== FolderListModel.Ready)
            return;
        _listed = true;
        const keys = [];
        const about = {};
        const names = [];
        for (let i = 0; i < _componentsFolder.count; i++)
            names.push(_componentsFolder.get(i, "fileName"));
        names.sort();
        for (const name of names) {
            const key = "components/" + name;
            keys.push(key);
            about[key] = readAbout(Qt.resolvedUrl(baseUrl + "/" + key), "state");
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

    readonly property Component _floatingWindow: Component {
        FloatingWindow {
            title: "gallery"
            implicitWidth: Math.min(1280, screen ? screen.width : 1280)
            implicitHeight: Math.min(900, screen ? screen.height : 900)
            color: Theme.popupBackground
            visible: root.visible
            onClosed: root.closed()
        }
    }

    readonly property Item _body: Item {
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0

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

            WheelScroll {
                target: null
                onWheel: event => {
                    root._anchored = "";
                    const dy = step(event);
                    _scroller.contentY = Math.max(0, Math.min(_scroller.contentHeight - _scroller.height, _scroller.contentY - dy));
                }
            }

            // In the controls' layer, over the scroller's edge
            ScrollBar.vertical: ScrollBar {
                parent: root._controls
                x: _scroller.x + _scroller.width - width
                y: _scroller.y
                height: _scroller.height
                policy: _scroller.contentHeight > _scroller.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: width / 2
                    color: Theme.textSecondary
                }
            }

            onContentYChanged: Qt.callLater(root._buildNear)
            onHeightChanged: Qt.callLater(root._buildNear)

            Column {
                id: _column
                width: _scroller.width - 12
                // Room under the last section, so that a jump puts any section at the top
                bottomPadding: _scroller.height
                // Laid out again (a section placed, built or grown): the jumped-to section
                // kept at the top, then what is near built
                onImplicitHeightChanged: {
                    Qt.callLater(root._place);
                    Qt.callLater(root._buildNear);
                }

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
                        readonly property var about: root._about[key] ?? { description: "", names: [], descriptions: [], error: "" }
                        readonly property bool first: index === 0
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
                            topPadding: section.first ? 24 : 16
                            leftPadding: 16
                            spacing: 4

                            Text {
                                visible: section.first
                                text: "Components"
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

    // The bar and the scroll bar: a layer of their own in the Qt window's top item (which
    // holds the Quickshell window's contentItem), between a FloatingList's press catcher
    // (z 999, over the whole window) and the overlays a section's items put there (a
    // FloatingList, a HoverTip: z 1000), so that they always take a press while lists and
    // tooltips still float over them. The bar's own lists (the theme's dropdown) float in
    // this layer, its overlay host, above the bar
    readonly property Item _controls: Item {
        objectName: "overlayHost"
        parent: _body.Window.window ? _body.Window.window.contentItem : null
        z: 999.5
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
                        id: _sectionButtons
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

        function top(): string {
            return root._top();
        }

        // The centre of a section's button in the bar, in window coordinates: "<x>,<y>", or ""
        // while it is not shown
        function place(key: string): string {
            for (let i = 0; i < _sectionButtons.count; i++) {
                const button = _sectionButtons.itemAt(i);
                if (!button || button.modelData !== key || !button.visible)
                    continue;
                const centre = button.mapToItem(null, button.width / 2, button.height / 2);
                return Math.round(centre.x) + "," + Math.round(centre.y);
            }
            return "";
        }

        function position(): string {
            return root._window ? "0," + Math.round(_scroller.contentY) : "";
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
