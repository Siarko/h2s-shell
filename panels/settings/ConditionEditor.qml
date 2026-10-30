import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// One condition leaf of a profile: which fact, and the value it is compared with. The
// value control follows the fact's type in ProfileRules.factTypes.
Item {
    id: root

    required property var leaf

    signal changedTo(var newLeaf)
    signal removed

    readonly property var factType: ProfileRules.factType(leaf.fact)
    property bool _pickingFact: false

    // Popup content keys, for "Popup open"
    readonly property var _panels: WidgetRegistry.entries.filter(entry => entry.popup).map(entry => entry.popup)

    // A leaf for a newly picked fact, with a sensible starting value
    function _leafFor(fact) {
        const type = ProfileRules.factType(fact)?.type;
        if (type === "percent")
            return { fact: fact, lt: 20 };
        if (type === "enum")
            return { fact: fact, is: ProfileRules.factType(fact).options[0] };
        if (type === "panel")
            return { fact: fact, is: _panels[0] };
        return { fact: fact, is: true };
    }

    Layout.fillWidth: true
    implicitHeight: _column.implicitHeight + 6

    Column {
        id: _column
        width: root.width
        spacing: 4

        Flow {
            width: parent.width
            spacing: 4

            // The fact; clicking it opens the list of facts below
            Pill {
                fontSize: Theme.fontSizeBody
                minimumHeight: 24
                label: (root.factType?.label ?? root.leaf.fact) + " ▾"
                picked: root._pickingFact
                onClicked: root._pickingFact = !root._pickingFact
            }

            // bool
            Pill {
                fontSize: Theme.fontSizeBody
                minimumHeight: 24
                visible: root.factType?.type === "bool"
                label: "yes"
                picked: root.leaf.is === true
                onClicked: root.changedTo({ fact: root.leaf.fact, is: true })
            }
            Pill {
                fontSize: Theme.fontSizeBody
                minimumHeight: 24
                visible: root.factType?.type === "bool"
                label: "no"
                picked: root.leaf.is === false
                onClicked: root.changedTo({ fact: root.leaf.fact, is: false })
            }

            // percent: below / above, and the number
            Pill {
                fontSize: Theme.fontSizeBody
                minimumHeight: 24
                visible: root.factType?.type === "percent"
                label: "below"
                picked: root.leaf.lt !== undefined
                onClicked: root.changedTo({ fact: root.leaf.fact, lt: root.leaf.gt ?? root.leaf.lt ?? 20 })
            }
            Pill {
                fontSize: Theme.fontSizeBody
                minimumHeight: 24
                visible: root.factType?.type === "percent"
                label: "above"
                picked: root.leaf.gt !== undefined
                onClicked: root.changedTo({ fact: root.leaf.fact, gt: root.leaf.lt ?? root.leaf.gt ?? 80 })
            }
            InputField {
                id: _percentInput
                visible: root.factType?.type === "percent"
                width: 52
                text: root.leaf.lt ?? root.leaf.gt ?? ""
                input.validator: IntValidator { bottom: 0; top: 100 }
                onEditingFinished: {
                    if (!input.acceptableInput)
                        return;
                    const number = parseInt(text);
                    root.changedTo(root.leaf.gt !== undefined
                        ? { fact: root.leaf.fact, gt: number }
                        : { fact: root.leaf.fact, lt: number });
                }
            }
            Text {
                visible: root.factType?.type === "percent"
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }

            // enum and panel: one pill per value
            Repeater {
                model: ScriptModel {
                    values: root.factType?.type === "enum" ? root.factType.options
                          : root.factType?.type === "panel" ? root._panels : []
                }

                Pill {
                    fontSize: Theme.fontSizeBody
                    minimumHeight: 24
                    required property string modelData
                    label: modelData
                    picked: root.leaf.is === modelData
                    onClicked: root.changedTo({ fact: root.leaf.fact, is: modelData })
                }
            }

            Pill {
                fontSize: Theme.fontSizeBody
                minimumHeight: 24
                label: "×"
                onClicked: root.removed()
            }
        }

        // The fact picker
        Flow {
            visible: root._pickingFact
            width: parent.width
            spacing: 4
            leftPadding: 12

            Repeater {
                model: ScriptModel {
                    values: ProfileRules.factTypes
                }

                Pill {
                    fontSize: Theme.fontSizeBody
                    minimumHeight: 24
                    required property var modelData
                    label: modelData.label
                    picked: modelData.fact === root.leaf.fact
                    onClicked: {
                        root._pickingFact = false;
                        if (modelData.fact !== root.leaf.fact)
                            root.changedTo(root._leafFor(modelData.fact));
                    }
                }
            }
        }
    }
}
