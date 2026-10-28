pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Finds every amdgpu card once at startup. Hardware.qml creates a load, a VRAM and a
// temperature source for each.
//
// `primary` is the card the ids from before multi-GPU support ("gpu", "vram",
// "gpuTemp") still point at, so configs written then keep showing the same card. It is
// the card that reports a VRAM vendor (only populated for real dedicated memory chips,
// never for an APU carve-out), largest first; failing that, the card with the most VRAM.
Singleton {
    id: root

    // [{ number, path, slot, name, vramTotal, dedicated, tempPath }], ordered by number
    property var cards: []
    property var primary: null
    // False until detection has finished
    property bool detected: false

    // lspci -mm quotes each field; the third is the device, e.g.
    // "Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M]". The bracketed part is the
    // marketing name; without one, the whole field.
    function cardName(lspciLine) {
        const fields = [];
        const pattern = /"([^"]*)"/g;
        let match;
        while ((match = pattern.exec(lspciLine ?? "")) !== null)
            fields.push(match[1]);
        const device = fields[2] ?? "";
        const bracketed = device.match(/\[([^\]]+)\]\s*$/);
        return bracketed ? bracketed[1] : device;
    }

    // One tab-separated line per card from the detection script below
    function parseCard(line) {
        const parts = line.split("\t");
        if (parts.length < 7 || parts[1] === "")
            return null;
        return {
            number: parseInt(parts[0]),
            path: parts[1],
            slot: parts[2],
            vramTotal: parseFloat(parts[3]) || 0,
            dedicated: parts[4] === "1",
            tempPath: parts[5],
            name: cardName(parts[6]) || "card" + parts[0]
        };
    }

    function pickPrimary(cards) {
        let best = null;
        for (const card of cards) {
            if (!best || card.dedicated > best.dedicated
                    || (card.dedicated === best.dedicated && card.vramTotal > best.vramTotal))
                best = card;
        }
        return best;
    }

    Component.onCompleted: _detect.running = true

    Process {
        id: _detect
        // Every DRM card with amdgpu memory counters (connectors such as card1-DP-2 are
        // skipped): number, sysfs device dir, PCI slot, VRAM size, whether the VRAM has
        // a vendor, the first temperature sensor, and lspci's description
        command: ["sh", "-c",
            "for d in /sys/class/drm/card[0-9]*; do" +
            " case \"$d\" in *-*) continue;; esac;" +
            " dev=\"$d/device\";" +
            " [ -r \"$dev/mem_info_vram_total\" ] || continue;" +
            " slot=$(basename \"$(readlink -f \"$dev\")\");" +
            " vendor=0; [ -r \"$dev/mem_info_vram_vendor\" ] && vendor=1;" +
            " temp=''; for t in \"$dev\"/hwmon/hwmon*/temp1_input; do [ -r \"$t\" ] && temp=$t && break; done;" +
            " printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"${d##*card}\" \"$dev\" \"$slot\"" +
            " \"$(cat \"$dev/mem_info_vram_total\")\" \"$vendor\" \"$temp\"" +
            " \"$(lspci -mm -s \"$slot\" 2>/dev/null)\";" +
            "done"]
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") _detect._lines.push(line) }
        }

        onRunningChanged: {
            if (running) return
            const cards = _lines.map(root.parseCard).filter(card => card !== null);
            cards.sort((a, b) => a.number - b.number);
            root.cards = cards;
            root.primary = root.pickPrimary(cards);
            root.detected = true;
            _lines = [];
        }
    }
}
