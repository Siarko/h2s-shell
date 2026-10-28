import QtQuick
import qs.singletons
import qs.singletons.hardware

TestCase {
    suiteName: "Hardware"

    // lspci -mm lines as they come from the two cards on the host
    readonly property string _navi: '03:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M]" -rc8 "Sapphire" "Device 471e"'
    readonly property string _apu: '11:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Granite Ridge [Radeon 610M]" -rc9 "ASUSTeK" "Device 8877"'

    function _line(fields) {
        return fields.join("\t");
    }

    function run() {
        // --- card names ---
        assertEqual(GpuDevices.cardName(_navi), "Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M", "the bracketed marketing name, in full");
        assertEqual(GpuDevices.cardName(_apu), "Radeon 610M", "integrated card name");
        assertEqual(GpuDevices.cardName('00:02.0 "VGA" "Intel" "Some GPU" -r01'), "Some GPU", "no brackets: the whole device field");
        assertEqual(GpuDevices.cardName(""), "", "no lspci output");

        // --- detection lines ---
        const dedicated = GpuDevices.parseCard(_line(["1", "/sys/class/drm/card1/device", "0000:03:00.0", "25753026560", "1", "/sys/x/temp1_input", _navi]));
        assertEqual(dedicated.number, 1, "card number");
        assertEqual(dedicated.slot, "0000:03:00.0", "PCI slot");
        assert(dedicated.dedicated, "VRAM vendor marks a dedicated card");
        assertEqual(dedicated.name, "Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M", "name from lspci");

        const integrated = GpuDevices.parseCard(_line(["0", "/sys/class/drm/card0/device", "0000:11:00.0", "2147483648", "0", "", ""]));
        assertEqual(integrated.name, "card0", "no lspci: falls back to the card's name");
        assertEqual(integrated.tempPath, "", "no sensor");
        assertEqual(GpuDevices.parseCard("garbage"), null, "short line is rejected");

        // --- primary card ---
        assertEqual(GpuDevices.pickPrimary([integrated, dedicated]), dedicated, "dedicated card wins over a bigger number");
        const bigIntegrated = Object.assign({}, integrated, { vramTotal: 1e12 });
        assertEqual(GpuDevices.pickPrimary([bigIntegrated, dedicated]), dedicated, "dedicated wins even with less VRAM");
        assertEqual(GpuDevices.pickPrimary([integrated, Object.assign({}, integrated, { number: 5, vramTotal: 4e9 })]).number, 5,
            "without a dedicated card, the most VRAM");
        assertEqual(GpuDevices.pickPrimary([]), null, "no cards");

        // --- labels ---
        const labels = { cpu: "Processor", ram: " " };
        assertEqual(Hardware.displayLabel(labels, "cpu"), "Processor", "the user's label");
        assertEqual(Hardware.displayLabel(labels, "ram"), " ", "a blank label stays blank");
        assertEqual(Hardware.displayLabel(labels, "disk"), "Disk", "no label: the source's own");
        assertEqual(Hardware.displayLabel(undefined, "disk"), "Disk", "no labels at all");
    }
}
