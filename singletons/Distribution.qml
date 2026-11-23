pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io
import qs.distributions.arch
import qs.distributions.generic
import qs.distributions.nixos

// Which distribution the shell runs on, and its static facts (distributions/<id>/
// distribution.json): read by the shell's one DistributionReader, decided by
// DistributionRules. Until the reading has answered — or when it could not be read — `id`
// is "" and `facts` null: unknown, never a default system. Made on first use.
//
// What a change is on this system is its integration's (distributions/Integration.qml,
// IntegrationRules): capability, plan, apply, undo and readInForce forward to the one the
// system is; while it is not known, nothing is offered and nothing runs.
Singleton {
    id: root

    // DistributionRules.detect's answer, frozen
    readonly property var detection: _reader.detection
    readonly property bool ready: detection.ready
    // "nixos" | "arch" | "generic", or "" while unknown
    readonly property string id: detection.id
    // The distribution's facts (DistributionRules.manifest), or null while unknown
    readonly property var facts: detection.facts
    // Every shipped distribution's facts ({ <id>: facts }), for a reading that looks in every
    // system's places; null until the manifests are read, or when one cannot be used
    readonly property var shipped: detection.shipped

    // Calls `callback` once Distribution has answered: at once when it has, else just after
    // it does. For what needs the facts before it may start — never a guess meanwhile. Code
    // that acts on the answer reads it from `detection` (whose ready, id, facts and shipped
    // change together): `ready`, `id`, `facts` and `shipped` are bindings on it, and while
    // one of them takes a new answer another may still hold the old one
    function whenReady(callback) {
        if (typeof callback !== "function")
            return;
        if (detection.ready) {
            callback();
            return;
        }
        _waiting = _waiting.concat([callback]);
    }

    property var _waiting: []

    // The integration of the distribution answered, or null while it is not known
    readonly property var integration: detection.ready ? (_integrations[detection.id] ?? null) : null

    function capability(kind) {
        return integration?.capability(kind) ?? IntegrationRules.unknownCapability();
    }

    function plan(kind, value) {
        return integration?.plan(kind, value) ?? { preview: null, refusal: IntegrationRules.refusal("unknown") };
    }

    function apply(kind, value, handlers) {
        return integration?.apply(kind, value, handlers) ?? { started: false, refusal: IntegrationRules.refusal("unknown") };
    }

    function undo(kind, handlers) {
        return integration?.undo(kind, handlers) ?? { started: false, refusal: IntegrationRules.refusal("unknown") };
    }

    function readInForce(kind, done) {
        if (integration === null) {
            Qt.callLater(() => done(IntegrationRules.inForceUnknown()));
            return;
        }
        integration.readInForce(kind, done);
    }

    readonly property var _integrations: ({ arch: _arch, nixos: _nixos, generic: _generic })
    property ArchIntegration _arch: ArchIntegration {}
    property NixosIntegration _nixos: NixosIntegration {}
    property GenericIntegration _generic: GenericIntegration {}

    onDetectionChanged: {
        if (detection.ready)
            Qt.callLater(root._flush);
    }

    function _flush() {
        if (!detection.ready)
            return;
        const waiting = _waiting;
        _waiting = [];
        for (const callback of waiting)
            callback();
    }

    property DistributionReader _reader: DistributionReader {
        override: TestSeams.distribution
        holdWhile: TestSeams.distributionHold
    }
}
