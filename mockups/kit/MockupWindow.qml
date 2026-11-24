import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.singletons
import qs.components

// The window every mockup is: a Mockup.qml's root (mockups/<kind>/<name>/Mockup.qml), started
// by the root entry (mockup.qml). A panel anchored at the output's top-left corner, ignoring
// exclusive zones, so that an item's window coordinates are output coordinates and a shooter
// can crop to them; of a fixed size (contentWidth x contentHeight), on the theme's
// background.
//
// The scene contract:
//   scenes        the names of the scenes, in their fixed order; each non-empty, without
//                 whitespace or "/" (a name goes into the shot line and a file name), none
//                 repeated
//   scene         the current scene: the mockup binds its stand-in data to it
//   subject       the item a shot is cropped to; the content by default
//   subjectRect   overrides the crop, in window coordinates, for a subject spread over
//                 several items (a side panel and a modal); ignored while it has no size
//
// Shooting (shooting, set by the entry): each scene in turn is set, three frames are
// waited for (the first frame after a change can still show the scene before), and a line
//   MOCKUP-SHOT <i> <scene> <x>,<y> <w>x<h>
// gives the subject's bounds; then the shooter calls `ipc call mockup next`. After the last
// scene `finished` comes; an error (a bad scene list, a subject without a size) `failed`.
// On screen: the scene the entry names (H2S_MOCKUP_SCENE), else the first, and a row of
// buttons under the content that switches between them.
//
// Over IPC (the config path is the entry's, the same for every mockup, so `name` tells
// running ones apart):
//   qs -p <tree>/mockup.qml ipc call mockup next   the next scene, after a shot: "" or why not
//   qs -p <tree>/mockup.qml ipc call mockup name   the mockup's <kind>/<name>
PanelWindow {
    id: root

    property var scenes: []
    property string scene: ""
    property Item subject: content
    property rect subjectRect: Qt.rect(0, 0, 0, 0)

    property int contentWidth: 480
    property int contentHeight: 320
    // The mockup's own items go into the content area
    default property alias data: content.data

    // Set by the entry before start()
    property string mockupName: ""
    property bool shooting: false

    signal finished
    signal failed(string text)

    property int _index: -1
    property bool _waitingForNext: false

    // Why the scene list cannot be used, or ""
    function _scenesError() {
        if (!Array.isArray(scenes) && !(scenes && typeof scenes.length === "number"))
            return "scenes is not a list";
        if (scenes.length === 0)
            return "no scenes";
        const seen = {};
        for (let i = 0; i < scenes.length; i++) {
            const name = scenes[i];
            if (typeof name !== "string" || name === "")
                return "scene " + i + " has an empty name";
            if (/[\s\/]/.test(name))
                return "scene name '" + name + "' has whitespace or '/'";
            if (seen[name])
                return "scene name '" + name + "' is repeated";
            seen[name] = true;
        }
        return "";
    }

    // Starts the mockup on `firstScene` ("" for the first); "" or why it cannot start
    function start(firstScene) {
        const error = _scenesError();
        if (error !== "")
            return error;
        if (shooting) {
            _show(0);
            return "";
        }
        const index = firstScene === "" ? 0 : Array.prototype.indexOf.call(scenes, firstScene);
        if (index < 0)
            return "no scene '" + firstScene + "' (the scenes: " + Array.prototype.join.call(scenes, " ") + ")";
        _index = index;
        scene = scenes[index];
        return "";
    }

    function _show(index) {
        _index = index;
        scene = scenes[index];
        _settle.frames = 0;
        _settle.running = true;
    }

    function _shoot() {
        let bounds = subjectRect;
        if (!(bounds.width > 0 && bounds.height > 0)) {
            if (!subject) {
                failed("no subject");
                return;
            }
            const origin = subject.mapToItem(null, 0, 0);
            bounds = Qt.rect(origin.x, origin.y, subject.width, subject.height);
        }
        const x = Math.round(bounds.x), y = Math.round(bounds.y);
        const width = Math.round(bounds.width), height = Math.round(bounds.height);
        if (width <= 0 || height <= 0) {
            failed("scene '" + scene + "': the subject has no size");
            return;
        }
        if (x < 0 || y < 0 || x + width > root.width || y + height > root.height) {
            failed("scene '" + scene + "': the subject (" + x + "," + y + " " + width + "x" + height
                   + ") is not inside the window (" + root.width + "x" + root.height + ")");
            return;
        }
        console.info("MOCKUP-SHOT " + _index + " " + scene + " " + x + "," + y + " " + width + "x" + height);
        _waitingForNext = true;
    }

    function _next() {
        if (!shooting)
            return "not shooting";
        if (!_waitingForNext)
            return "no shot is waiting";
        _waitingForNext = false;
        if (_index + 1 >= scenes.length)
            finished();
        else
            _show(_index + 1);
        return "";
    }

    anchors {
        top: true
        left: true
    }
    margins {
        top: 0
        left: 0
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "h2s-mockup"
    implicitWidth: Math.max(contentWidth, shooting ? 0 : _switcher.implicitWidth)
    implicitHeight: contentHeight + (shooting ? 0 : _switcher.implicitHeight)
    color: Theme.popupBackground

    Item {
        id: content
        x: 0
        y: 0
        width: root.contentWidth
        height: root.contentHeight
    }

    // Three frames after a scene is set, then the shot line
    FrameAnimation {
        id: _settle
        property int frames: 0
        running: false
        onTriggered: {
            if (++frames < 3)
                return;
            running = false;
            root._shoot();
        }
    }

    Flow {
        id: _switcher
        visible: !root.shooting
        y: root.contentHeight
        width: root.width
        padding: Theme.popup.contentPadding
        spacing: Theme.popup.contentPadding
        Repeater {
            model: ScriptModel {
                values: root.shooting ? [] : Array.prototype.slice.call(root.scenes)
            }
            SmallButton {
                required property string modelData
                label: modelData
                checked: modelData === root.scene
                onClicked: root.scene = modelData
            }
        }
    }

    IpcHandler {
        target: "mockup"

        function next(): string {
            return root._next();
        }

        function name(): string {
            return root.mockupName;
        }
    }
}
