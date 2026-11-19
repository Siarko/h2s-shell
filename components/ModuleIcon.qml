import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.singletons

// A module's icon (module API 1.26), the one place the shell draws it — given a module id: a
// square as tall as a line of body text, the picture fitted inside, never cropped or
// stretched. What the manifest declared (ModuleManifestRules.readIcon), as the host checked
// it (ModuleHost.icons):
//   a glyph       as text, in `color` (its place's text colour): it follows the theme
//   an SVG        painted in `color` (a one-colour drawing follows the theme), or in its
//                 own colours when the manifest says "colors": "own"
//   a picture     (PNG, WebP) in its own colours
// With none — none declared, a wrong one (an error in the module's status), one whose file
// cannot be drawn (reported to the host once: an error, and every place shows the letter
// from then on) — the first letter of the module's name, in the muted colour. No QML of the
// module is involved. A glyph the font lacks cannot be detected: it shows as the font's
// empty box.
//
//   ModuleIcon { moduleId: "tailscale"; tip: "Tailscale: Exit node: home" }
Item {
    id: root

    property string moduleId: ""
    // The module host whose module it shows (a suite gives its own)
    property var host: Modules.host
    // The text colour of its place: a glyph's and a theme-coloured SVG's
    property color color: Theme.textPrimary
    // Its accessible name and the tooltip shown on hover ("" none). It takes no click: what
    // stands under it keeps it
    property string tip: ""

    readonly property var icon: host && ModuleRules.has(host.icons ?? {}, moduleId) ? host.icons[moduleId] : null
    // What it shows: "glyph", "svg", "image" or "letter"
    readonly property string shownAs: icon === null ? "letter" : icon.kind
    readonly property string letter: ModuleRules.iconLetter(host?.status(moduleId)?.name ?? "", moduleId)
    readonly property real size: Math.ceil(_metrics.height)
    // For the core's tests: the picture and the painted one
    readonly property alias picture: _picture
    readonly property alias painted: _painted

    implicitWidth: size
    implicitHeight: size
    Accessible.role: Accessible.Graphic
    Accessible.name: tip

    FontMetrics {
        id: _metrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
    }

    Text {
        id: _text
        anchors.centerIn: parent
        visible: root.shownAs === "glyph" || root.shownAs === "letter"
        text: root.shownAs === "glyph" ? root.icon.glyph : root.letter
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: root.shownAs === "glyph" ? root.color : Theme.textMuted
    }

    // Asked for at the size it shows, so a large picture costs no more than its file
    Image {
        id: _picture
        readonly property bool wanted: root.shownAs === "svg" || root.shownAs === "image"
        readonly property bool ownColours: root.shownAs === "image" || root.icon?.colors === "own"
        anchors.fill: parent
        visible: wanted && ownColours
        source: wanted ? root.icon.url : ""
        sourceSize: Qt.size(Math.ceil(root.size * Screen.devicePixelRatio), Math.ceil(root.size * Screen.devicePixelRatio))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        onStatusChanged: {
            if (status === Image.Error && wanted)
                root.host?.iconFailed(root.moduleId, "cannot be drawn");
        }
    }

    // A one-colour drawing in the place's colour: brightened to white, then coloured — so a
    // black drawing and a white one both come out in `color`, their edges' softness kept
    MultiEffect {
        id: _painted
        anchors.fill: _picture
        source: _picture
        visible: _picture.wanted && !_picture.ownColours && _picture.status === Image.Ready
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.color
    }

    MouseArea {
        id: _hover
        anchors.fill: parent
        enabled: root.tip !== ""
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    HoverTip {
        target: root
        shown: _hover.containsMouse
        text: root.tip
    }
}
