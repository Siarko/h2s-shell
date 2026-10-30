import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The animation roles of the theme picked in the sidebar (ThemeRules.animationRoles):
// each with its duration and its curve — a popup has one for opening and one for closing —
// where each value comes from, Reset and Undo, and a preview playing it. Curves come from
// the library (Curves page) or Qt. Changes go into the theme's draft (ThemeRules,
// "Drafts"). The profile's animation speed and reduced motion apply on top, not here
// (docs/plans/themes.md, stage 6).
Flickable {
    id: root

    // The theme being edited, picked in the settings window's sidebar
    required property string themeName

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true

    readonly property var _values: (Theme.revision, Theme.valuesOf(themeName))
    readonly property var _origins: (Theme.revision, Theme.originsOf(themeName))
    // A theme file that does not parse is not changed
    readonly property bool _editable: !Theme.themeNames.includes(themeName) || themeName in Theme.themeFiles
    // The curve tokens whose list of curves is open
    property string pickingCurve: ""
    onThemeNameChanged: pickingCurve = ""

    // Slider moves go out at most every 80 ms
    property var _pending: ({})

    function _write(token, value) {
        const pending = Object.assign({}, _pending);
        pending[token] = value;
        _pending = pending;
        if (!_flush.running)
            _flush.start();
    }

    function _flushPending() {
        _flush.stop();
        const pending = _pending;
        _pending = {};
        for (const token in pending)
            Theme.draftToken(themeName, "durations", token, pending[token]);
    }

    Timer {
        id: _flush
        interval: 80
        onTriggered: root._flushPending()
    }

    function _duration(role) {
        return _pending[role] ?? _values.durations[role] ?? 0;
    }

    // Library curves first, then Qt's
    readonly property var _curveChoices: Object.keys(Theme.curveLibrary).sort().concat(ThemeRules.qtCurveNames)

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.settings.pageMargin
        }
        spacing: 6

        Heading { text: "Animations" }
        Hint {
            text: "How long each kind of motion takes in this theme, and how it moves. Your own curves are made on the Curves page. "
                + "The profile's animation speed and reduced motion (General) apply on top of these; the previews here do not use them."
        }
        Text {
            visible: !root._editable
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "The file " + root.themeName + ".json does not parse, so nothing here changes it."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
        }

        DraftActions {
            themeName: root.themeName
            groups: ["durations", "curves"]
            message: "Animations changed, not saved"
            onAboutToSave: root._flushPending()
        }

        Repeater {
            model: ThemeRules.animationRoles

            ColumnLayout {
                id: _role
                required property var modelData
                required property int index
                readonly property string role: modelData.role
                Layout.fillWidth: true
                Layout.topMargin: index === 0 ? 4 : 10
                spacing: 2

                // The role, what it moves, and a preview of it
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: _role.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            color: Theme.textPrimary
                        }
                        Text {
                            Layout.fillWidth: true
                            text: _role.modelData.hint
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textMuted
                        }
                    }

                    SmallButton {
                        label: "▶"
                        tooltip: "Play it"
                        onClicked: _preview.play()
                    }
                }

                // A square crossing a track with the role's duration and curve (a popup's:
                // there with opening, back with closing)
                Item {
                    id: _preview
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    property real progress: 0
                    readonly property var _curves: _role.modelData.curves

                    function play() {
                        _playback.stop();
                        progress = 0;
                        _playback.start();
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 2
                        color: Theme.track
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        radius: 3
                        color: Theme.accent
                        x: _preview.progress * (parent.width - width)
                    }

                    SequentialAnimation {
                        id: _playback
                        NumberAnimation {
                            target: _preview
                            property: "progress"
                            from: 0
                            to: 1
                            duration: Math.max(1, root._duration(_role.role))
                            easing: ThemeRules.curveEasing(root._values.curves[_preview._curves[0]], Theme.curveLibrary).easing
                        }
                        PauseAnimation { duration: _preview._curves.length > 1 ? 300 : 0 }
                        NumberAnimation {
                            target: _preview
                            property: "progress"
                            from: 1
                            to: 0
                            duration: _preview._curves.length > 1 ? Math.max(1, root._duration(_role.role)) : 0
                            easing: ThemeRules.curveEasing(root._values.curves[_preview._curves[_preview._curves.length - 1]], Theme.curveLibrary).easing
                        }
                    }
                }

                // The duration
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SettingSlider {
                        Layout.fillWidth: true
                        label: "Duration"
                        from: 0
                        to: _role.modelData.to
                        suffix: " ms"
                        disabled: !root._editable
                        value: root._duration(_role.role)
                        onValueEdited: newValue => root._write(_role.role, newValue)
                    }
                    TokenActions {
                        themeName: root.themeName
                        group: "durations"
                        token: _role.role
                        origins: root._origins.durations ?? {}
                        editable: root._editable
                        onAboutToChange: root._flushPending()
                    }
                }

                // Its curve, or a popup's two
                Repeater {
                    model: _role.modelData.curves

                    ColumnLayout {
                        id: _curve
                        required property string modelData
                        readonly property string token: modelData
                        readonly property bool open: root.pickingCurve === token
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: _curve.token === "popupOpen" ? "Opening curve"
                                    : _curve.token === "popupClose" ? "Closing curve" : "Curve"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                            }
                            SmallButton {
                                label: (root._values.curves[_curve.token] ?? "") + (_curve.open ? "  ▴" : "  ▾")
                                available: root._editable
                                onClicked: root.pickingCurve = _curve.open ? "" : _curve.token
                            }
                            Item { Layout.fillWidth: true }
                            TokenActions {
                                themeName: root.themeName
                                group: "curves"
                                token: _curve.token
                                origins: root._origins.curves ?? {}
                                editable: root._editable
                            }
                        }

                        // The curves to pick from: the library's, then Qt's
                        Flow {
                            visible: _curve.open
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: ScriptModel { values: _curve.open ? root._curveChoices : [] }
                                Pill {
                                    required property string modelData
                                    label: modelData
                                    picked: modelData === root._values.curves[_curve.token]
                                    onClicked: {
                                        if (!picked)
                                            Theme.draftToken(root.themeName, "curves", _curve.token, modelData);
                                        root.pickingCurve = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
