import QtQuick

// Counts, in `tally` ({ gone, dropped }), its destructions and those that ran after Qt had
// dropped its properties: what TeardownTest checks that it reached that case. The count is
// made by a closure that holds `tally`, as such a probe cannot read a property of its own.
QtObject {
    property var tally: null
    property bool marker: true

    Component.onCompleted: {
        const kept = tally;
        Component.destruction.connect(() => {
            kept.gone++;
            // Looked up through its scope, not a reference the closure keeps (that would keep
            // the probe's wrapper, and so its properties)
            if (marker !== true)
                kept.dropped++;
        });
    }
}
