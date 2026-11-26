import QtQuick
import QtQuick.Layouts
import qs.panels.settings
import qs.mockups.kit

// SchemaSettingEditor in its states, each in a settings column (408 px): real settings of
// the schema, each type's control, on stand-in profiles handed in through the editor's
// `store` — "Base", then "Work", the one edited (editIndex 1); nothing is written:
//   bool             media.coverColors set to on in Work: the switch, the reset (×)
//   enum-pills       media.visualizerStyle set to Bars in Work: a pill per choice
//   interval-pills   polling.hardware.interval set to 5 s in Work
//   string           wallpaper.source set to a folder in Work: the text field
//   number-field     notifications.toastDuration set to 8 in Work: the field and its unit
//   slider           media.coverRounding set to 50 in Work
//   text-list        notifications.codePatterns set to two patterns in Work
//   inherited        media.visualizerStyle not set in Work, Glow from Base: dimmed,
//                    "inherited from Base", no reset
//   global           media.visualizerStyle pinned as global at Dots: "global" and the pin
//                    in the accent
//   out-of-range     notifications.toastDuration stored as 300 in Work, above its maximum
//                    120: shown at 120, the warning note under it
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    // Each state's setting: its key, Work's own value (absent: not set there), what Base
    // gives it, and the global value when pinned
    readonly property var settings: ({
        bool: { key: "media.coverColors", own: true },
        "enum-pills": { key: "media.visualizerStyle", own: "bars" },
        "interval-pills": { key: "polling.hardware.interval", own: 5000 },
        string: { key: "wallpaper.source", own: "/home/user/Pictures/Wallpapers" },
        "number-field": { key: "notifications.toastDuration", own: 8 },
        slider: { key: "media.coverRounding", own: 50 },
        "text-list": { key: "notifications.codePatterns", own: ["\\d{4,8}", "[A-Z]{3}-\\d{3}"] },
        inherited: { key: "media.visualizerStyle", base: "glow" },
        global: { key: "media.visualizerStyle", global: "dots" },
        "out-of-range": { key: "notifications.toastDuration", own: 300 }
    })

    // The stand-in profiles for one setting: the members the editor reads, and writes that
    // do nothing
    function store(setting) {
        const work = {};
        if (setting.own !== undefined)
            work[setting.key] = setting.own;
        const base = {};
        if (setting.base !== undefined)
            base[setting.key] = setting.base;
        const globals = {};
        if (setting.global !== undefined)
            globals[setting.key] = setting.global;
        return {
            profiles: [{ name: "Base", set: base }, { name: "Work", set: work }],
            effectiveGlobals: globals,
            inheritedValue: (index, key) => setting.base,
            inheritedFrom: (index, key) => setting.base !== undefined ? "Base" : "",
            setBy: key => "",
            writeSetting: (index, key, value) => {},
            clearOverride: (index, key) => {},
            pinGlobal: key => {},
            unpinGlobal: key => {}
        };
    }

    StateGrid {
        id: grid
        cellWidth: 440
        cellHeight: 150
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property var setting: root.settings[cell.name]

                ColumnLayout {
                    x: 16
                    y: 16
                    width: grid.cellWidth - 32

                    SchemaSettingEditor {
                        key: cell.setting.key
                        editIndex: 1
                        store: root.store(cell.setting)
                    }
                }
            }
        }
    }
}
