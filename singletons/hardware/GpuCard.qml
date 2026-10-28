import Quickshell
import QtQuick

// The three sources of one card, created per entry of GpuDevices.cards
Scope {
    id: root

    required property var card

    readonly property var sources: [load, memory, temperature]

    GpuLoadSource {
        id: load
        card: root.card
    }

    GpuMemorySource {
        id: memory
        card: root.card
    }

    GpuTemperatureSource {
        id: temperature
        card: root.card
    }
}
