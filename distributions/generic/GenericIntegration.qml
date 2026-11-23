import QtQuick
import qs.distributions

// A distribution the shell has no integration for: every change that differs per system is
// unavailable ("Not supported on this distribution"); nothing is written, nothing run
Integration {
    distribution: "generic"
    table: ({})
}
