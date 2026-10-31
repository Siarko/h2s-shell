pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The shell's version — the one place the number lives. Semantic versioning:
//   MAJOR  a change that needs a config migration or changes behaviour people rely on
//   MINOR  a new feature
//   PATCH  fixes
// Every release gets a CHANGELOG.md section with this number and a git tag `v<number>`;
// tests/VersionTest.qml checks the changelog agrees.
Singleton {
    id: root

    readonly property string number: "2.0.0"

    // What is shown: the number alone when running exactly the tagged release, otherwise
    // the number plus the commit — "+9d98c91", and ".dirty" for uncommitted changes — so
    // a report says which code it came from. Just the number without git.
    readonly property string display: _build === "" ? number : number + "+" + _build

    property string _build: ""

    // `git describe` against the tags: "v1.0.0-0-g9d98c91" is the release itself, a
    // count above 0 means commits since; before any tag, only the commit
    function _parse(output) {
        const text = output.trim();
        const described = text.match(/^v[\d.]+-(\d+)-g([0-9a-f]+)(-dirty)?$/);
        if (described) {
            if (described[1] === "0" && !described[3])
                return "";
            return described[2] + (described[3] ? ".dirty" : "");
        }
        return /^[0-9a-f]{7,}(-dirty)?$/.test(text) ? text.replace("-dirty", ".dirty") : "";
    }

    Component.onCompleted: _describe.running = true

    Process {
        id: _describe
        command: ["sh", "-c",
            "git -C \"$1\" describe --tags --long --dirty 2>/dev/null || git -C \"$1\" describe --always --dirty 2>/dev/null",
            "sh", Quickshell.shellDir]
        property string _output: ""

        stdout: SplitParser {
            onRead: line => _describe._output += line
        }

        onRunningChanged: {
            if (running)
                return;
            root._build = root._parse(_output);
            _output = "";
        }
    }
}
