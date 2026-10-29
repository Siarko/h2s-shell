import QtQuick
import qs.components
import qs.singletons

BarWidget {
    id: root
    property string profile: ""
    property string widgetType: "stt"

    // Profile override first, global setting as the fallback
    readonly property bool _previewEnabled: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}")
            var override = data["stt"]?.[profile]?.previewEnabled
            if (override !== undefined) return override
        }
        return Profiles.value("stt.previewEnabled") ?? true
    }

    readonly property int _previewWidth: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}")
            var override = data["stt"]?.[profile]?.previewWidth
            if (override !== undefined) return override
        }
        return Profiles.value("stt.previewWidth") ?? 180
    }

    // Wake is the second, independent axis: the outline means the microphone is open,
    // whatever dictation happens to be doing. It stays on while dictation runs, so it
    // is clear that a stop phrase returns to listening rather than closing the mic.
    borderColor: Stt.wake ? Theme.sliderAccent : "transparent"
    borderWidth: Stt.wake ? 1 : 0

    readonly property bool _dictating: Stt.dictation !== "idle"
    readonly property bool _pulsing: Stt.connected
        && (Stt.server === "loading" || Stt.dictation === "speaking")

    // The widget is icon-only at rest and slides the preview open once dictation is
    // actually running — the same condition that turns the icon green. Lingering final
    // text keeps it open, so the last words aren't cut off mid-display.
    readonly property bool _previewExpanded: _previewEnabled && _previewWidth > 0
        && (_dictating || Stt.previewText !== "")

    onClicked: Stt.toggle()

    Row {
        anchors.centerIn: parent
        // Gaps live in the collapsible items' own padding, so a collapsed item leaves
        // no stray spacing behind
        spacing: 0

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (!Stt.connected || Stt.server === "error") ? "󰍭" : "󰍬"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            // Optical correction, tuned by eye. The Material Design mic glyph carries
            // more empty space on its left than on its right inside its own advance
            // box, so centring the box leaves the ink right of centre and the gap to
            // the left edge looking wider. Since the collapsed cell sits at
            // BarWidget's 40px minimum width, padding the box on the right shifts the
            // ink back left by half this value.
            rightPadding: 2
            color: {
                if (!Stt.connected) return Theme.textDim
                if (Stt.server === "error") return Theme.textError
                if (Stt.server === "off") return Theme.textDim
                if (Stt.server === "loading") return Theme.textSecondary
                return root._dictating ? Theme.sliderAccent : Theme.textPrimary
            }

            // Animating a separate property and gating opacity on _pulsing, so a
            // half-faded value can never be left behind when the pulse stops
            property real pulse: 1.0
            opacity: root._pulsing ? pulse : 1.0

            SequentialAnimation on pulse {
                running: root._pulsing
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 500; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutQuad }
            }
        }

        // Fragments waiting to be transcribed and typed. A digit rather than a glyph,
        // so this doesn't depend on an exotic Nerd Font codepoint.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            // The gap is folded into the animated width rather than left as static
            // padding, so a collapsed item contributes nothing at all — static padding
            // on a zero-width item would push the icon off the widget's centre.
            readonly property bool shown: (Profiles.value("stt.showPending") ?? true) && Stt.pending > 0
            width: shown ? 18 : 0
            leftPadding: shown ? 4 : 0
            clip: true
            horizontalAlignment: Text.AlignHCenter
            text: Stt.pending > 0 ? String(Stt.pending) : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.textWarning

            Behavior on width {
                NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
            }
        }

        // Slides open while dictation runs. Elided on the left to keep the newest
        // words visible.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root._previewExpanded ? root._previewWidth : 0
            leftPadding: root._previewExpanded ? 6 : 0
            clip: true
            elide: Text.ElideLeft
            text: Stt.previewText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.textSecondary

            Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
            }
        }
    }
}
