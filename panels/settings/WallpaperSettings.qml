import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The wallpaper the shell draws (Wallpapers, WallpaperRules; docs/plans/wallpapers.md),
// edited in the profile picked in the settings window. A file is the same image
// everywhere and nothing else applies; a folder's images are chosen per scope and mode.
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    anchors.fill: parent
    // Up and down only: the slots' Flow once made the page a little wider than the window
    contentWidth: width
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    flickableDirection: Flickable.VerticalFlick
    clip: true

    readonly property bool _on: Profiles.editedValue(editIndex, "wallpaper.enabled") === true
    // What the edited profile's source is — known for the source in effect only, which is
    // the edited one unless another profile is being edited
    readonly property string _editedSource: WallpaperRules.expand(Profiles.editedValue(editIndex, "wallpaper.source") ?? "",
                                                                   Quickshell.env("HOME") ?? "")
    readonly property bool _known: Wallpapers.enabled && _editedSource === Wallpapers.source
    // Folder options are open unless the source is known to be a single file
    readonly property bool _folder: !(_known && Wallpapers.kind === "file")
    readonly property string _background: Profiles.editedValue(editIndex, "wallpaper.background") ?? "#000000"
    readonly property bool _fromImage: Profiles.editedValue(editIndex, "wallpaper.backgroundFromImage") === true
    // The colour the first screen's image gave, when it is the source in effect
    readonly property string _edgeColor: _known && Quickshell.screens[0] ? (Wallpapers.edgeColors[Quickshell.screens[0].name] ?? "") : ""
    // What the background is now: taken from the image, or the colour set
    readonly property string _shownBackground: _fromImage && _edgeColor !== "" ? _edgeColor : _background
    property bool _picking: false

    // ── Choosing images ──
    readonly property string _mode: Profiles.editedValue(editIndex, "wallpaper.mode") ?? "fixed"
    readonly property string _scope: Profiles.editedValue(editIndex, "wallpaper.scope") ?? "everywhere"
    readonly property var _subset: Profiles.editedValue(editIndex, "wallpaper.subset") ?? []
    readonly property var _assignments: Profiles.editedValue(editIndex, "wallpaper.assignments") ?? {}
    readonly property var _pinned: Profiles.editedValue(editIndex, "wallpaper.pinned") ?? {}
    readonly property var _weekdays: Profiles.editedValue(editIndex, "wallpaper.weekdays") ?? ["", "", "", "", "", "", ""]
    // Thumbnails need the folder listed: the source in effect, a folder
    readonly property bool _thumbnails: _known && Wallpapers.kind === "folder" && Wallpapers.files.length > 0
    readonly property var _dayNames: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    // The picker open now, or null: { key, slot } — the image of a slot of that setting (a
    // slot of `wallpaper.weekdays` is the day's index) — or { key: "wallpaper.subset" }, the
    // images to draw from. It opens under the section it belongs to.
    property var _target: null
    // Keep the same image: choosing which place to add, before its image
    property bool _addingPin: false

    // The monitors: connected ones, and any chosen for that is not connected now
    function _monitorSlots(stored) {
        const connected = Quickshell.screens.map(screen => screen.name);
        const away = Object.keys(stored).filter(key => key !== "*" && !/^[0-9]+$/.test(key) && !connected.includes(key));
        return connected.map(name => ({ slot: name, label: name }))
            .concat(away.map(name => ({ slot: name, label: name + " (off)" })));
    }

    // Workspaces 1–10, any other that exists, and any chosen for
    function _workspaceSlots(stored) {
        const numbers = new Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        for (const workspace of Workspaces.workspaces?.values ?? []) {
            if (workspace.id > 0)
                numbers.add(workspace.id);
        }
        for (const key of Object.keys(stored)) {
            if (/^[0-9]+$/.test(key))
                numbers.add(Number(key));
        }
        return Array.from(numbers).sort((a, b) => a - b).map(number => ({ slot: String(number), label: "Workspace " + number }));
    }

    function _slotName(slot) {
        return slot === "*" ? "all screens" : /^[0-9]+$/.test(slot) ? "workspace " + slot : slot;
    }

    readonly property var _fixedSlots: _scope === "monitor" ? _monitorSlots(_assignments)
        : _scope === "workspace" ? _workspaceSlots(_assignments)
        : [{ slot: "*", label: "All screens" }]
    // Places with an image kept, and the ones that could be added
    readonly property var _pinnedSlots: _monitorSlots(_pinned).concat(_workspaceSlots(_pinned)).filter(entry => !!_pinned[entry.slot])
    readonly property var _pinCandidates: _monitorSlots({}).concat(_workspaceSlots({})).filter(entry => !_pinned[entry.slot])

    function _absolute(path) {
        return path && root._thumbnails && Wallpapers.files.includes(path) ? Wallpapers.source + "/" + path : "";
    }

    function _editorFor(key) {
        return key === "wallpaper.subset" ? _subsetSetting
            : key === "wallpaper.assignments" ? _assignmentsSetting
            : key === "wallpaper.pinned" ? _pinnedSetting
            : _weekdaysSetting;
    }

    function _valueOf(key) {
        return key === "wallpaper.subset" ? _subset
            : key === "wallpaper.assignments" ? _assignments
            : key === "wallpaper.pinned" ? _pinned
            : _weekdays;
    }

    function _isTarget(key, slot) {
        return _target !== null && _target.key === key && _target.slot === slot;
    }

    function _open(key, slot) {
        _addingPin = false;
        _target = _isTarget(key, slot) ? null : { key: key, slot: slot };
    }

    // Writes one slot's choice ("" clears it) as a whole new value
    function _choose(key, slot, path) {
        if (key === "wallpaper.weekdays") {
            const days = _weekdays.slice();
            while (days.length < 7)
                days.push("");
            days[slot] = path;
            _weekdaysSetting.edited(days);
            return;
        }
        const chosen = Object.assign({}, _valueOf(key));
        if (path === "")
            delete chosen[slot];
        else
            chosen[slot] = path;
        _editorFor(key).edited(chosen);
    }

    // A thumbnail clicked in the open picker: the images to draw from toggle, a slot's
    // image is chosen and the picker closes
    function _picked(path) {
        if (_target === null)
            return;
        if (_target.key === "wallpaper.subset") {
            const list = _subset.includes(path) ? _subset.filter(entry => entry !== path) : _subset.concat([path]);
            _subsetSetting.edited(list);
            return;
        }
        _choose(_target.key, _target.slot, path);
        _target = null;
    }

    // Labels on the thumbnails: where the open picker's setting uses each image
    function _badgesFor(key) {
        const badges = {};
        const add = (path, label) => {
            if (path)
                badges[path] = badges[path] ? badges[path] + ", " + label : label;
        };
        if (key === "wallpaper.weekdays") {
            _weekdays.forEach((path, index) => add(path, _dayNames[index].slice(0, 3)));
            return badges;
        }
        const chosen = _valueOf(key);
        for (const slot in chosen)
            add(chosen[slot], slot === "*" ? "All" : /^[0-9]+$/.test(slot) ? "WS " + slot : slot);
        return badges;
    }

    function _pickerTitle() {
        if (_target === null)
            return "";
        if (_target.key === "wallpaper.subset")
            return "Tick the images to draw from. " + (_subset.length === 0 ? "None ticked: all are used." : _subset.length + " ticked.");
        const name = _target.key === "wallpaper.weekdays" ? _dayNames[_target.slot] : _slotName(_target.slot);
        return "Choosing the image for " + name + ".";
    }

    // A chosen path, with the home folder written as ~ so it reads shorter
    function _pathOf(url) {
        const path = decodeURIComponent(String(url).replace(/^file:\/\//, ""));
        const home = Quickshell.env("HOME") ?? "";
        return home !== "" && path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }

    function _folderUrl() {
        const home = Quickshell.env("HOME") ?? "";
        const start = _editedSource !== "" ? _editedSource : home + "/Pictures";
        return "file://" + start;
    }

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 0

        Heading {
            text: "Wallpaper"
            Layout.bottomMargin: 8
        }

        SchemaSettingEditor { key: "wallpaper.enabled"; editIndex: root.editIndex; Layout.fillWidth: true }

        // Another program draws one too: which covers the other is not ours to decide
        Text {
            visible: root._on && Wallpapers.foreign.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.warning
            text: {
                const names = Array.from(new Set(Wallpapers.foreign.map(entry => entry.namespace)));
                const screens = Array.from(new Set(Wallpapers.foreign.map(entry => entry.monitor)));
                return "⚠ " + names.join(", ") + " also draws a wallpaper (" + screens.join(", ")
                    + "): either may cover the other. Stop it, or turn this off.";
            }
        }

        SchemaSettingEditor {
            id: _sourceSetting
            key: "wallpaper.source"
            editIndex: root.editIndex
            available: root._on
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 6
            opacity: root._on ? 1 : 0.35

            SmallButton {
                label: "Choose a folder…"
                available: root._on
                onClicked: _folderDialog.open()
            }
            SmallButton {
                label: "Choose an image…"
                available: root._on
                onClicked: _fileDialog.open()
            }

            // How deep into subfolders: part of the source, so beside its buttons rather
            // than a setting of its own; written through the (hidden) editor below
            SettingSlider {
                visible: root._folder
                Layout.preferredWidth: 250
                Layout.maximumWidth: 250
                Layout.fillWidth: false
                Layout.leftMargin: 10
                label: "Subfolders"
                sliderRatio: 0.55
                from: 0
                to: 5
                suffix: " deep"
                value: _depthSetting.shownValue ?? 2
                disabled: !root._on
                tooltip: "How deep into subfolders images are looked for; 0 is the folder only."
                onValueEdited: newValue => _depthSetting.edited(newValue)
            }

            // What the source turned out to be
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                opacity: root._known ? 1 : 0
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Wallpapers.kind === "missing" || (Wallpapers.kind === "folder" && Wallpapers.files.length === 0)
                    ? Theme.warning : Theme.textMuted
                text: Wallpapers.kind === "file" ? "An image: the same everywhere."
                    : Wallpapers.kind === "missing" ? (Wallpapers.source === "" ? "Nothing chosen." : "Not found.")
                    : Wallpapers.kind === "folder" ? (Wallpapers.files.length === 0 ? "No images in it."
                        : Wallpapers.files.length + (Wallpapers.files.length === 1 ? " image" : " images")
                          + (Wallpapers.pool.length < Wallpapers.files.length ? ", " + Wallpapers.pool.length + " used" : ""))
                    : "Looking…"
            }
        }

        FolderDialog {
            id: _folderDialog
            title: "The wallpapers' folder"
            currentFolder: root._folderUrl()
            onAccepted: _sourceSetting.edited(root._pathOf(selectedFolder))
        }

        FileDialog {
            id: _fileDialog
            title: "The wallpaper"
            currentFolder: root._folderUrl()
            nameFilters: ["Images (" + WallpaperRules.imageExtensions.map(extension => "*." + extension).join(" ") + ")"]
            onAccepted: _sourceSetting.edited(root._pathOf(selectedFile))
        }

        // Writes the subfolder depth for the slider beside the source's buttons
        SchemaSettingEditor { id: _depthSetting; key: "wallpaper.depth"; editIndex: root.editIndex; visible: false }

        // ── How images are chosen: one section per mode, only that one shown ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: root._folder
            opacity: root._on ? 1 : 0.35
            enabled: root._on

            SchemaSettingEditor { key: "wallpaper.mode"; editIndex: root.editIndex; Layout.fillWidth: true; Layout.topMargin: 8 }

            Hint {
                visible: !root._thumbnails
                Layout.bottomMargin: 6
                text: "Images can be picked once the wallpaper is on with a folder, in the profile in effect."
            }

            // A titled block for the mode's settings, so they read as one
            component Section: ColumnLayout {
                property string title: ""
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 0
                Text {
                    text: parent.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.textSecondary
                    Layout.bottomMargin: 2
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.border.width
                    color: Theme.outline
                    Layout.bottomMargin: 6
                }
            }

            // ── By me ──
            Section {
                title: "By me"
                visible: root._mode === "fixed"

                SchemaSettingEditor { key: "wallpaper.scope"; editIndex: root.editIndex; Layout.fillWidth: true }

                SchemaSettingEditor { id: _assignmentsSetting; key: "wallpaper.assignments"; editIndex: root.editIndex; Layout.fillWidth: true }
                Hint {
                    Layout.bottomMargin: 4
                    text: "Click one to choose its image. " + (root._scope === "everywhere"
                        ? "None chosen: the folder's first image." : "One without an image shows the first one chosen.")
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    spacing: 6
                    Repeater {
                        // ScriptModel, never the bare array (CLAUDE.md)
                        model: ScriptModel { values: root._fixedSlots; objectProp: "slot" }
                        WallpaperSlot {
                            required property var modelData
                            label: modelData.label.replace("Workspace ", "WS ")
                            image: root._absolute(root._assignments[modelData.slot])
                            emptyText: root._scope === "everywhere" ? "First image" : "First chosen"
                            picked: root._isTarget("wallpaper.assignments", modelData.slot)
                            onClicked: if (root._thumbnails) root._open("wallpaper.assignments", modelData.slot)
                            onCleared: root._choose("wallpaper.assignments", modelData.slot, "")
                        }
                    }
                }
                WallpaperPicker {
                    visible: root._target?.key === "wallpaper.assignments"
                    Layout.fillWidth: true
                    title: root._pickerTitle()
                    folder: Wallpapers.source
                    files: visible ? Wallpapers.files : []
                    badges: visible ? root._badgesFor("wallpaper.assignments") : ({})
                    extraLabel: "Clear"
                    extraAvailable: !!root._assignments[root._target?.slot]
                    onPicked: path => root._picked(path)
                    onExtra: { root._choose("wallpaper.assignments", root._target.slot, ""); root._target = null; }
                    onDone: root._target = null
                }
            }

            // ── At random ──
            Section {
                title: "At random"
                visible: root._mode === "random"

                SchemaSettingEditor { key: "wallpaper.scope"; editIndex: root.editIndex; Layout.fillWidth: true }
                SchemaSettingEditor { key: "wallpaper.interval"; editIndex: root.editIndex; Layout.fillWidth: true }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    spacing: 8
                    SmallButton {
                        label: "Shuffle now"
                        available: Wallpapers.enabled && Wallpapers.kind === "folder"
                        tooltip: available ? "Draw again, and look at the folder again for new images"
                            : "Turn the wallpaper on with a folder, in the profile in effect"
                        onClicked: Wallpapers.shuffle()
                    }
                    Hint { text: "From a keybind: h2s-shell ipc call wallpaper shuffle" }
                }

                SchemaSettingEditor { id: _subsetSetting; key: "wallpaper.subset"; editIndex: root.editIndex; Layout.fillWidth: true }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    spacing: 6
                    Text {
                        text: root._subset.length === 0
                            ? "All " + (root._thumbnails ? Wallpapers.files.length + " " : "") + "images of the folder."
                            : root._subset.length + (root._thumbnails ? " of " + Wallpapers.files.length : "") + " images, ticked."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }
                    SmallButton {
                        label: "Pick images…"
                        checked: root._isTarget("wallpaper.subset", undefined)
                        available: root._thumbnails
                        onClicked: root._open("wallpaper.subset", undefined)
                    }
                    Item { Layout.fillWidth: true }
                }
                WallpaperPicker {
                    visible: root._target?.key === "wallpaper.subset"
                    Layout.fillWidth: true
                    multiple: true
                    title: root._pickerTitle()
                    folder: Wallpapers.source
                    files: visible ? Wallpapers.files : []
                    marked: root._subset
                    extraLabel: "Use all"
                    extraAvailable: root._subset.length > 0
                    onPicked: path => root._picked(path)
                    onExtra: _subsetSetting.edited([])
                    onDone: root._target = null
                }
            }

            // ── By day ──
            Section {
                title: "By day"
                visible: root._mode === "weekday"

                SchemaSettingEditor { id: _weekdaysSetting; key: "wallpaper.weekdays"; editIndex: root.editIndex; Layout.fillWidth: true }
                Hint {
                    Layout.bottomMargin: 4
                    text: "Click a day to choose its image; changes at midnight. A day without one shows the first day's that is set."
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    spacing: 6
                    Repeater {
                        model: ScriptModel { values: root._dayNames.map((name, index) => ({ index: index, name: name })); objectProp: "name" }
                        WallpaperSlot {
                            required property var modelData
                            label: modelData.name.slice(0, 3)
                            image: root._absolute(root._weekdays[modelData.index])
                            emptyText: "First set"
                            picked: root._isTarget("wallpaper.weekdays", modelData.index)
                            onClicked: if (root._thumbnails) root._open("wallpaper.weekdays", modelData.index)
                            onCleared: root._choose("wallpaper.weekdays", modelData.index, "")
                        }
                    }
                }
                WallpaperPicker {
                    visible: root._target?.key === "wallpaper.weekdays"
                    Layout.fillWidth: true
                    title: root._pickerTitle()
                    folder: Wallpapers.source
                    files: visible ? Wallpapers.files : []
                    badges: visible ? root._badgesFor("wallpaper.weekdays") : ({})
                    extraLabel: "Clear"
                    extraAvailable: root._target !== null && !!root._weekdays[root._target.slot]
                    onPicked: path => root._picked(path)
                    onExtra: { root._choose("wallpaper.weekdays", root._target.slot, ""); root._target = null; }
                    onDone: root._target = null
                }
            }

            // ── Random and by day: places that keep one image ──
            Section {
                title: "Exceptions"
                visible: root._mode !== "fixed"

                SchemaSettingEditor { id: _pinnedSetting; key: "wallpaper.pinned"; editIndex: root.editIndex; Layout.fillWidth: true }
                Hint {
                    Layout.bottomMargin: 4
                    text: "A monitor or workspace here always shows its image, instead of " + (root._mode === "random" ? "a drawn one" : "the day's")
                        + ". A workspace's before its monitor's."
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    spacing: 6
                    Repeater {
                        model: ScriptModel { values: root._pinnedSlots; objectProp: "slot" }
                        WallpaperSlot {
                            required property var modelData
                            label: modelData.label.replace("Workspace ", "WS ")
                            image: root._absolute(root._pinned[modelData.slot])
                            picked: root._isTarget("wallpaper.pinned", modelData.slot)
                            onClicked: if (root._thumbnails) root._open("wallpaper.pinned", modelData.slot)
                            onCleared: root._choose("wallpaper.pinned", modelData.slot, "")
                        }
                    }
                    // Adds one: which place first, then its image
                    Rectangle {
                        implicitWidth: 76
                        implicitHeight: 76
                        radius: Theme.field.radius
                        color: _addArea.lit || root._addingPin ? Theme.fillSubtle : "transparent"
                        border.width: Theme.border.width
                        border.color: root._addingPin ? Theme.accent : Theme.outline
                        opacity: root._thumbnails ? 1 : 0.4
                        Text {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "+\nAdd"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textSecondary
                        }
                        PointerArea {
                            id: _addArea
                            centred: false
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root._thumbnails) { root._target = null; root._addingPin = !root._addingPin; }
                        }
                    }
                }
                // Which place to add
                ColumnLayout {
                    visible: root._addingPin
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    spacing: 4
                    Hint { text: "Which one keeps the same image?" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: ScriptModel { values: root._addingPin ? root._pinCandidates : []; objectProp: "slot" }
                            Pill {
                                required property var modelData
                                label: modelData.label
                                fontSize: Theme.fontSizeBody
                                minimumHeight: 26
                                onClicked: root._open("wallpaper.pinned", modelData.slot)
                            }
                        }
                    }
                }
                WallpaperPicker {
                    visible: root._target?.key === "wallpaper.pinned"
                    Layout.fillWidth: true
                    title: root._pickerTitle()
                    folder: Wallpapers.source
                    files: visible ? Wallpapers.files : []
                    badges: visible ? root._badgesFor("wallpaper.pinned") : ({})
                    extraLabel: "Remove"
                    extraAvailable: root._target !== null && !!root._pinned[root._target.slot]
                    onPicked: path => root._picked(path)
                    onExtra: { root._choose("wallpaper.pinned", root._target.slot, ""); root._target = null; }
                    onDone: root._target = null
                }
            }
        }

        // ── How it looks ──
        Heading {
            text: "Look"
            Layout.topMargin: 18
            Layout.bottomMargin: 4
            opacity: root._on ? 1 : 0.35
        }

        SchemaSettingEditor { key: "wallpaper.fit"; editIndex: root.editIndex; available: root._on; Layout.fillWidth: true }

        // What the fit does, played on a small screen
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 14
            opacity: root._on ? 1 : 0.35

            WallpaperFitPreview {
                id: _fitPreview
                fit: Profiles.editedValue(root.editIndex, "wallpaper.fit") ?? "cover"
                background: root._shownBackground
                image: {
                    const screen = Quickshell.screens[0];
                    return root._known && screen ? (Wallpapers.fileFor(screen.name) ?? "") : "";
                }
                aspect: Quickshell.screens[0] ? Quickshell.screens[0].width / Quickshell.screens[0].height : 16 / 10
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                text: _fitPreview.fit === "contain" ? "Fit: all of the image, as large as the screen allows; the background colour fills the rest."
                    : _fitPreview.fit === "centre" ? "Centre: the image at its own size, in the middle; the background colour around it."
                    : _fitPreview.fit === "tile" ? "Tile: the image at its own size, repeated from the top left corner to fill the screen."
                    : "Fill: the whole screen covered, the image enlarged as needed; what sticks out is cut off."
            }
        }

        SchemaSettingEditor {
            id: _backgroundSetting
            key: "wallpaper.background"
            editIndex: root.editIndex
            available: root._on
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 8
            opacity: root._on ? 1 : 0.35
            enabled: root._on

            ColorSwatch {
                color: root._background
                open: root._picking
                onClicked: root._picking = !root._picking
            }
            Text {
                text: root._background
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
            Item { Layout.fillWidth: true }
        }

        ColorPicker {
            visible: root._picking && root._on
            Layout.bottomMargin: 8
            color: root._background
            // Written once a drag ends or a hex is typed: not the profiles on every move
            onCommitted: value => _backgroundSetting.edited(String(value))
        }

        SchemaSettingEditor { key: "wallpaper.backgroundFromImage"; editIndex: root.editIndex; available: root._on; Layout.fillWidth: true }

        // The colour the image gave, to see what it is
        RowLayout {
            visible: root._on && root._fromImage
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 8

            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: Theme.field.radius
                color: root._edgeColor !== "" ? root._edgeColor : "transparent"
                border.width: Theme.border.width
                border.color: Theme.outline
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
                text: root._edgeColor !== ""
                    ? root._edgeColor + " from " + (Quickshell.screens[0]?.name ?? "the screen") + "'s image now; each screen takes its own."
                    : "Read from each screen's image as it shows; seen here for the profile in effect."
            }
        }

    }
}
