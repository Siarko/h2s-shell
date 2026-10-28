pragma Singleton

import Quickshell

// Helpers for reading nmcli's terse (-t) output.
Singleton {
    id: root

    // Splits one line of `nmcli -t` output into its fields.
    //
    // In terse mode nmcli escapes ':' and '\' inside values with a backslash, so a plain
    // split(":") cuts an SSID like "Home:5G" in two, and joining the pieces back leaves
    // "Home\:5G" — a name that matches no network. This splits on unescaped colons only
    // and removes the escapes.
    function splitTerse(line) {
        let fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const character = line[i];
            if (character === "\\" && i + 1 < line.length) {
                current += line[i + 1];
                i++;
            } else if (character === ":") {
                fields.push(current);
                current = "";
            } else {
                current += character;
            }
        }
        fields.push(current);
        return fields;
    }
}
