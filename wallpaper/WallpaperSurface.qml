import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.singletons

// A screen's wallpaper: a window on the background layer, the whole screen, under every
// other surface, taking no input. The image is Wallpapers.fileFor(the screen) — a new one
// fades in over the old (Theme's "fade"), then the old is let go; none fades the old out
// to the background colour. Only what is shown is decoded, at the screen's size. With
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
    readonly property real _scale: root.screen?.devicePixelRatio ?? 1
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

    // The image on top and the one coming in; they swap when a fade ends
    property Image _front: _first
    property Image _back: _second
    // What was asked for last, as a path ("" for none). Compared as paths, never as URLs:
    // Qt hands a source back decoded ("a b.jpg" for "a%20b.jpg"), so an image whose name
    // has a space never matched and never faded in
    property string _target: ""
    property bool _started: false

    function _url(path) {
        return path === "" ? "" : "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function _show(path) {
        if (_started && path === _target)
            return;
        _started = true;
        _target = path;
        _finish();
        if (path === "") {
            _fadeOut.start();
            return;
        }
        _back.opacity = 0;
        _back.path = path;
        _back.source = _url(path);
        if (_back.status === Image.Ready) {
            _sample(_back);
            _fadeIn.start();
        }
    }

    // A fade under way is ended at once: the next starts from what it was going to
    function _finish() {
        if (_fadeIn.running) {
            _fadeIn.stop();
            _swap();
        }
        if (_fadeOut.running) {
            _fadeOut.stop();
            _front.source = "";
            _front.path = "";
            _front.opacity = 1;
        }
    }

    // The faded-in image goes on top for good; the old one is let go and waits behind
    function _swap() {
        const shown = _back;
        _front.source = "";
        _front.path = "";
        _back = _front;
        _front = shown;
        _front.opacity = 1;
        _front.z = 1;
        _back.opacity = 0;
        _back.z = 2;
    }

    on_WantedChanged: if (_wanted !== null) _show(_wanted)
    Component.onCompleted: if (_wanted !== null) _show(_wanted)

    component Wallpaper: Image {
        id: _image
        // The path its source was made from (see `_target`)
        property string path: ""
        anchors.fill: parent
        asynchronous: true
        cache: false
        smooth: true
        fillMode: root._fit === "contain" ? Image.PreserveAspectFit
                : root._fit === "centre" ? Image.Pad
                : root._fit === "tile" ? Image.Tile
                : Image.PreserveAspectCrop
        // Decoded at the screen's size; centred and tiled show the image's own pixels
        sourceSize: root._fit === "cover" || root._fit === "contain"
            ? Qt.size(root.width * root._scale, root.height * root._scale) : undefined
        onStatusChanged: {
            if (_image !== root._back || _image.path !== root._target)
                return;
            if (status === Image.Ready) {
                root._sample(_image);
                _fadeIn.start();
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

    Wallpaper { id: _first; z: 1 }
    Wallpaper { id: _second; z: 2; opacity: 0 }

    NumberAnimation {
        id: _fadeIn
        target: root._back
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.duration("fade")
        easing: Theme.curve("fade")
        onFinished: root._swap()
    }

    NumberAnimation {
        id: _fadeOut
        target: root._front
        property: "opacity"
        to: 0
        duration: Theme.duration("fade")
        easing: Theme.curve("fade")
        onFinished: {
            root._front.source = "";
            root._front.path = "";
            root._front.opacity = 1;
        }
    }
}
