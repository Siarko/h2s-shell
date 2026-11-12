import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.singletons

// A screen's wallpaper: a window on the background layer, the whole screen, under every
// other surface, taking no input. The image is Wallpapers.fileFor(the screen). A new one
// comes in over the old as the theme says (Theme.wallpaper): a switch to a workspace with
// its own image slides the way the workspaces go, or not; any other change fades, zooms,
// slides, or runs a shader (shaders/transition.frag: wipe, circle, dissolve, pixelate) —
// the shader only while the change runs, the image drawn plainly before and after. Then
// the old image is let go; none fades the old out to the background colour. Only what is
// shown is decoded, at the screen's size. With
// `wallpaper.backgroundFromImage` the background is the colour the image's edge averages
// to (WallpaperRules.edgeColor), read from a small copy as each image comes in.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: WallpaperRules.namespace
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    // The colour is the backdrop's, which fades along with the image
    color: "transparent"
    // Clicks on the desktop are nobody's: no input region
    mask: Region {}

    readonly property string _fit: Profiles.value("wallpaper.fit") ?? "cover"
    // The window's own scale, not the screen's: at a fractional scale (1.2 on the
    // Framework) the screen reports it rounded up (2) while windows draw at 1.2 — taking
    // the screen's decoded the wallpaper at 3200×2000 for a 1920×1200 panel
    readonly property real _scale: root.devicePixelRatio > 0 ? root.devicePixelRatio : 1
    // Decoded at the screen's size; centred and tiled show the image's own pixels. One
    // value for the images and their preloaded copies: the size asked for is part of what
    // makes Qt's cache share a decoded image
    readonly property real _pixelWidth: Math.round(width * _scale)
    readonly property real _pixelHeight: Math.round(height * _scale)
    readonly property var _requestSize: _fit === "cover" || _fit === "contain"
        ? Qt.size(_pixelWidth, _pixelHeight) : undefined
    // null: keep what is shown (WallpaperRules.fileFor)
    readonly property var _wanted: Wallpapers.fileFor(modelData.name)
    readonly property bool _fromImage: Profiles.value("wallpaper.backgroundFromImage") === true
    readonly property string _edgeColor: Wallpapers.edgeColors[modelData.name] ?? ""
    readonly property color _background: _fromImage && _target !== "" && _edgeColor !== ""
        ? _edgeColor : (Profiles.value("wallpaper.background") ?? "#000000")

    // The image whose edge is read next (the one coming in), or null
    property Image _sampled: null

    function _sample(image) {
        if (!_fromImage || image === null || image.status !== Image.Ready)
            return;
        _sampled = image;
        _sampleCanvas.requestPaint();
    }

    // Turned on with an image shown: read it now
    on_FromImageChanged: _sample(_front.status === Image.Ready ? _front : null)

    // The image on top and the one coming in; they swap when a change ends
    property Image _front: _first
    property Image _back: _second
    // What was asked for last, as a path ("" for none). Compared as paths, never as URLs:
    // Qt hands a source back decoded ("a b.jpg" for "a%20b.jpg"), so an image whose name
    // has a space never matched and never faded in
    property string _target: ""
    property bool _started: false

    // The change under way: what kind ("fade", "zoom", "slide", "wipe", "circle",
    // "dissolve", "pixelate"; "out" for none fading out), which way a slide goes (1: the
    // new image from the right), and how far it is, 0 → 1
    property bool _changing: false
    property string _kind: "fade"
    property int _direction: 1
    property real _progress: 0
    readonly property bool _shaderKind: ["wipe", "circle", "dissolve", "pixelate"].includes(_kind)
    readonly property string _role: _workspaceSwitch ? "wallpaperWorkspace" : "wallpaper"
    property bool _workspaceSwitch: false

    // The screen's workspace, and the last switch: { from, to, at } — a new image asked for
    // right after a switch is the switch's
    readonly property int _workspace: Workspaces.screens.find(entry => entry.name === modelData.name)?.workspace ?? 0
    property var _lastSwitch: null
    property int _previousWorkspace: 0
    on_WorkspaceChanged: {
        if (_previousWorkspace > 0 && _workspace > 0)
            _lastSwitch = { from: _previousWorkspace, to: _workspace, at: Date.now() };
        _previousWorkspace = _workspace;
    }

    function _url(path) {
        return path === "" ? "" : "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function _show(path) {
        if (_started && path === _target)
            return;
        const first = !_started;
        _started = true;
        _target = path;
        _finish();
        const theme = Theme.wallpaper ?? {};
        // Which bindings update first on a switch is not ours to know: read the workspace
        // itself, and take the switch whether its handler has run yet or not
        const now = Workspaces.screens.find(entry => entry.name === modelData.name)?.workspace ?? 0;
        const sw = _previousWorkspace > 0 && now > 0 && now !== _previousWorkspace ? { from: _previousWorkspace, to: now }
            : _lastSwitch !== null && _lastSwitch.to === now && Date.now() - _lastSwitch.at < 500 ? _lastSwitch
            : null;
        const switched = sw !== null;
        _workspaceSwitch = switched;
        _direction = switched && sw.to < sw.from ? -1 : 1;
        if (path === "")
            _kind = "out";
        else if (first)
            _kind = "fade";
        else if (switched && (theme.workspaceTransition ?? "slide") === "slide")
            _kind = "slide";
        else
            _kind = theme.transition ?? "fade";
        if (path === "") {
            _begin();
            return;
        }
        _back.path = path;
        // Its copy resized to this screen when there is one (Wallpapers, "Copies"); asked
        // for when not, for the next time
        _back.source = _url(Wallpapers.displayPath(path, _pixelWidth, _pixelHeight, _fit));
        Wallpapers.prepare(path, _pixelWidth, _pixelHeight, _fit);
        if (_back.status === Image.Ready) {
            _sample(_back);
            _begin();
        }
    }

    function _begin() {
        _progress = 0;
        _changing = true;
        _change.restart();
    }

    // A change under way is ended at once: the next starts from what it was going to
    function _finish() {
        if (!_change.running)
            return;
        _change.stop();
        _end();
    }

    function _end() {
        _changing = false;
        _progress = 0;
        if (_kind === "out") {
            _front.source = "";
            _front.path = "";
            return;
        }
        // The new image goes on top for good; the old one is let go and waits behind
        const shown = _back;
        _front.source = "";
        _front.path = "";
        _back = _front;
        _front = shown;
    }

    // Images of the nearest workspaces on this screen, decoded ahead (at most four): a
    // 4K image takes about a second to decode and scale, which a switch showed as a delay.
    // They share the decoded copy with the images shown (Qt's pixmap cache), so a switch
    // finds the image ready.
    readonly property var _preload: {
        const current = _workspace;
        if (current <= 0)
            return [];
        const numbers = new Set([current - 1, current + 1]);
        for (const workspace of Workspaces.workspaces?.values ?? []) {
            if (workspace.id > 0 && workspace.monitor?.name === modelData.name)
                numbers.add(workspace.id);
        }
        numbers.delete(current);
        const nearest = Array.from(numbers).filter(number => number > 0)
            .sort((a, b) => Math.abs(a - current) - Math.abs(b - current)).slice(0, 4);
        const paths = [];
        for (const number of nearest) {
            const path = Wallpapers.workspaceFileFor(modelData.name, number);
            if (path !== "" && path !== _target && !paths.includes(path))
                paths.push(path);
        }
        return paths;
    }

    // Their copies too, so a switch finds one
    on_PreloadChanged: {
        for (const path of _preload)
            Wallpapers.prepare(path, _pixelWidth, _pixelHeight, _fit);
    }

    on_WantedChanged: if (_wanted !== null) _show(_wanted)
    Component.onCompleted: if (_wanted !== null) _show(_wanted)

    component Wallpaper: Image {
        id: _image
        // The path its source was made from (see `_target`)
        property string path: ""
        readonly property bool _coming: _image === root._back
        width: parent.width
        height: parent.height
        asynchronous: true
        // Shared with the preloaded copies below, so a switch finds its image decoded
        cache: true
        smooth: true
        fillMode: root._fit === "contain" ? Image.PreserveAspectFit
                : root._fit === "centre" ? Image.Pad
                : root._fit === "tile" ? Image.Tile
                : Image.PreserveAspectCrop
        sourceSize: root._requestSize
        z: _coming ? 2 : 1

        // Where the change has it: the one coming in shows only while it comes
        opacity: !root._changing ? (_coming ? 0 : 1)
            : root._kind === "out" ? (_coming ? 0 : 1 - root._progress)
            : root._kind === "fade" || root._kind === "zoom" ? (_coming ? root._progress : 1)
            : 1
        x: root._changing && root._kind === "slide"
            ? (_coming ? root._direction * root.width * (1 - root._progress) : -root._direction * root.width * root._progress)
            : 0
        scale: root._changing && root._kind === "zoom" && _coming ? 1.08 - 0.08 * root._progress : 1

        onStatusChanged: {
            if (!_coming || _image.path !== root._target)
                return;
            if (status === Image.Ready) {
                root._sample(_image);
                root._begin();
            }
            else if (status === Image.Error)
                console.warn("Wallpaper: cannot read", source);
        }
    }

    Rectangle {
        id: _backdrop
        anchors.fill: parent
        z: -1
        color: root._background
        Behavior on color { ColorAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
    }

    // The image drawn small to read its edge from. Under the images, never hidden: a Canvas
    // that is not shown does not paint. Cleared once read.
    Canvas {
        id: _sampleCanvas
        anchors.centerIn: parent
        width: 32
        height: 32
        z: 0
        onAvailableChanged: if (available && root._sampled !== null) requestPaint()
        onPaint: {
            const context = getContext("2d");
            context.clearRect(0, 0, width, height);
            const image = root._sampled;
            if (image === null || image.status !== Image.Ready)
                return;
            context.drawImage(image, 0, 0, width, height);
            const color = WallpaperRules.edgeColor(context.getImageData(0, 0, width, height).data, width, height);
            context.clearRect(0, 0, width, height);
            // Nothing drawn yet (all transparent): asked again with the next paint
            if (color === "")
                return;
            root._sampled = null;
            Wallpapers.setEdgeColor(root.modelData.name, color);
        }
    }

    Wallpaper { id: _first }
    Wallpaper { id: _second }

    // The nearest workspaces' images, decoded and kept, never shown (see `_preload`)
    Repeater {
        // ScriptModel, never the bare array (CLAUDE.md)
        model: ScriptModel { values: root._preload }
        Image {
            required property string modelData
            visible: false
            asynchronous: true
            cache: true
            source: root._url(Wallpapers.displayPath(modelData, root._pixelWidth, root._pixelHeight, root._fit))
            fillMode: _first.fillMode
            sourceSize: root._requestSize
        }
    }

    // The shader's view of the two images while it runs; they are hidden meanwhile
    ShaderEffectSource {
        id: _outgoingView
        sourceItem: root._front
        hideSource: _shader.visible
        visible: false
    }
    ShaderEffectSource {
        id: _incomingView
        sourceItem: root._back
        hideSource: _shader.visible
        visible: false
    }

    ShaderEffect {
        id: _shader
        anchors.fill: parent
        z: 3
        visible: root._changing && root._shaderKind
        property variant outgoing: _outgoingView
        property variant incoming: _incomingView
        property real progress: root._progress
        property real mode: ["wipe", "circle", "dissolve", "pixelate"].indexOf(root._kind)
        property real aspect: width / Math.max(1, height)
        property size size: Qt.size(width * root._scale, height * root._scale)
        property real softness: 0.08
        fragmentShader: Qt.resolvedUrl("shaders/transition.frag.qsb")
    }

    NumberAnimation {
        id: _change
        target: root
        property: "_progress"
        from: 0
        to: 1
        duration: Theme.duration(root._role)
        easing: Theme.curve(root._role)
        onFinished: root._end()
    }
}
