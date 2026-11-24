pragma Singleton

import Quickshell
import QtQuick

// What the words on a public element (qs.api) stand for inside the shell. A module picks
// a meaning, `kind`, and a `size`; the element asks here for the internal value. A word
// an element does not know stands for the element's default, and `known` says so. Pure.
Singleton {
    // A public button's kind → SmallButton's and DeleteButton's internal kind
    readonly property var buttonKinds: ({ primary: "save", secondary: "normal", danger: "delete", warning: "warning", success: "success" })
    readonly property string buttonKindDefault: "secondary"

    // The size of an element with a text → the theme's type size, by its name in Theme
    readonly property var textSizes: ({ xs: "fontSizeXSmall", s: "fontSizeSmall", m: "fontSizeBody" })
    readonly property string sizeDefault: "m"

    // A public pill's size → Pill's internal size (the theme's three pill heights)
    readonly property var pillSizes: ({ s: "s", m: "m", l: "l" })
    // (1.32) A public pill's text size → the theme's type size, by its name in Theme: always
    // one of the theme's sizes, never pixels
    readonly property var pillTextSizes: ({ small: "fontSizeSmall", body: "fontSizeBody" })
    readonly property string pillTextSizeDefault: "small"

    // What a public mark is told (polkit's answer) → PrivilegedMark's internal need. One
    // it does not know is the lock: a control that may ask is never shown as one that
    // does not.
    readonly property var markNeeds: ({ "": "", yes: "yes", auth: "auth", no: "no" })
    readonly property string markNeedDefault: "auth"

    // A public notice's kind → the colour of its line, by its name in Theme
    readonly property var noticeKinds: ({ warning: "warning", danger: "error", success: "success" })
    readonly property string noticeKindDefault: "warning"

    // (1.31) A public progress bar's kind → the colour of its fill, by its name in Theme
    readonly property var progressKinds: ({ normal: "accent", success: "success", warning: "warning", danger: "error" })
    readonly property string progressKindDefault: "normal"

    // (1.34) A side panel's sizes → its width at the built-in fonts, by its name in
    // Theme.sidePanelWidths; never wider than `sidePanelShare` of the page area
    readonly property var sidePanelSizes: ({ s: "s", m: "m", l: "l" })
    readonly property real sidePanelShare: 0.9
    // Why a side panel closed, by what happened (sidePanelEvent): its Close button, a click
    // on the dimmed page, Escape, another one opening, the page or window going, a lock
    readonly property var sidePanelReasons: ({ closeButton: "close", outsideClick: "outside", escape: "escape",
        otherOpened: "replaced", pageGone: "page", locked: "lock" })

    // (1.35) A status pill's kind → the theme's colours it is drawn in, by their names in
    // Theme: `icon` for the icon (and a part's short text), `text` for the label (and a
    // part's line when expanded). Normal is the accent's icon beside the ordinary text.
    readonly property var statusKinds: ({
        normal: { icon: "accent", text: "textPrimary" },
        muted: { icon: "textMuted", text: "textMuted" },
        success: { icon: "success", text: "success" },
        warning: { icon: "warning", text: "warning" },
        danger: { icon: "error", text: "error" }
    })
    readonly property string statusKindDefault: "normal"
    // (1.35) The most parts a status pill shows; the rest are dropped
    readonly property int statusPartCap: 12
    // (1.35) The most characters an icon keeps: one glyph, perhaps with a variation
    // selector — never a text
    readonly property int iconCap: 2

    // The longest a text a module hands a public element for one line may be, in
    // characters, before it is cut
    readonly property int textCap: 80
    // (1.31) The longest a public tooltip's text may be; it wraps at the tooltip's width
    readonly property int tipCap: 200

    // A text from a module as a public element shows it on one line: line breaks and
    // tabs folded into spaces, and longer than `cap` (`textCap` unless given) cut, "…" at the end. Anything not
    // a string or a number is "". Characters are counted as code points, so a cut never
    // splits one.
    function oneLine(text, cap) {
        if (typeof text !== "string" && typeof text !== "number")
            return "";
        const longest = cap ?? textCap;
        const folded = String(text).replace(/[\r\n\t\v\f\u0085\u2028\u2029]+/g, " ");
        const characters = PrivilegedRules.characters(folded);
        return characters.length > longest ? characters.slice(0, longest - 1).join("") + "…" : folded;
    }

    // A public tooltip's text: as oneLine, cut at `tipCap` (the tooltip wraps it)
    function tipText(text) {
        return oneLine(text, tipCap);
    }

    // A public dropdown's options as the internal one is given them: { value, label } of
    // each, the label on one line. Every other field is left out — the internal dropdown
    // draws a `color` as a dot, and a module puts no colour of its own on screen. Not an
    // array: none.
    function dropdownOptions(options) {
        if (!Array.isArray(options))
            return [];
        return options.map(option => ({ value: option?.value, label: oneLine(option?.label) }));
    }

    // `word` looked up in `table`, else `fallback`'s entry: { value, known }
    function pick(table, word, fallback) {
        const known = typeof word === "string" && Object.prototype.hasOwnProperty.call(table, word);
        return { value: table[known ? word : fallback], known: known };
    }

    function buttonKind(kind) {
        return pick(buttonKinds, kind, buttonKindDefault);
    }

    function textSize(size) {
        return pick(textSizes, size, sizeDefault);
    }

    function pillSize(size) {
        return pick(pillSizes, size, sizeDefault);
    }

    function pillTextSize(size) {
        return pick(pillTextSizes, size, pillTextSizeDefault);
    }

    function markNeed(need) {
        return pick(markNeeds, need, markNeedDefault);
    }

    function noticeKind(kind) {
        return pick(noticeKinds, kind, noticeKindDefault);
    }

    function progressKind(kind) {
        return pick(progressKinds, kind, progressKindDefault);
    }

    // (1.35) Whether a progress bar's wave runs: asked for (`wave`, the owner says the bar
    // moves), a value from 0 up to but not including 1 (not full, not a run of unknown
    // length, a number), and motion not reduced
    function progressWaves(wave, value, reduceMotion) {
        return wave === true && typeof value === "number" && value >= 0 && value < 1 && reduceMotion !== true;
    }

    // When a progress bar's waves start: a new one every `spawnMs`, each crossing the fill in
    // `travelMs`, from a pool of `pool` bands that are reused. Where the pool would run short
    // the waves come further apart (travelMs / pool), never more bands. Returns `slots` (the
    // bands in use), `spacing` (ms between two waves), `travel` and `cycle` (ms from a band's
    // start to its next: slots × spacing, at least travel, so a band ends before it starts
    // again). Durations below 1 ms count as 1
    function progressWaveSchedule(spawnMs, travelMs, pool) {
        const count = Math.max(1, Math.floor(Number(pool) || 1));
        const travel = Math.max(1, Number(travelMs) || 0);
        const spacing = Math.max(1, Number(spawnMs) || 0, travel / count);
        const slots = Math.min(count, Math.ceil(travel / spacing));
        return { slots: slots, spacing: spacing, travel: travel, cycle: Math.max(travel, slots * spacing) };
    }

    function statusKind(kind) {
        return pick(statusKinds, kind, statusKindDefault);
    }

    // (1.35) An icon from a module: its first `iconCap` characters on one line, nothing cut
    // with "…" (a glyph is not a text)
    function iconText(icon) {
        return PrivilegedRules.characters(oneLine(icon)).slice(0, iconCap).join("");
    }

    // (1.35) A status pill's parts as it draws them: { parts, unknownKinds, dropped }.
    // Each part { icon, text, kind, tip, line }: icon one glyph (iconText), text and line on
    // one line (oneLine), tip as a tooltip's (tipText), kind a word statusKinds has — one it
    // does not know is the default and listed in `unknownKinds` (each once); none given is
    // the default, unlisted. A line left empty is the tip, or the text without one. Past
    // `statusPartCap` parts the rest are dropped, `dropped` says how many. Not an array:
    // none; a part that is not an object: an empty one.
    function statusParts(parts) {
        if (!Array.isArray(parts))
            return { parts: [], unknownKinds: [], dropped: 0 };
        const unknownKinds = [];
        const shown = parts.slice(0, statusPartCap).map(part => {
            const given = part !== null && typeof part === "object" ? part : {};
            const unset = given.kind === undefined || given.kind === null || given.kind === "";
            const kindWord = statusKind(given.kind);
            if (!unset && !kindWord.known && !unknownKinds.includes(String(given.kind)))
                unknownKinds.push(String(given.kind));
            const text = oneLine(given.text);
            const tip = tipText(given.tip);
            const line = oneLine(given.line);
            return {
                icon: iconText(given.icon),
                text: text,
                kind: kindWord.known ? given.kind : statusKindDefault,
                tip: tip,
                line: line !== "" ? line : (tip !== "" ? oneLine(tip) : text)
            };
        });
        return { parts: shown, unknownKinds: unknownKinds, dropped: Math.max(0, parts.length - statusPartCap) };
    }

    function sidePanelSize(size) {
        return pick(sidePanelSizes, size, sizeDefault);
    }

    // A side panel's width: its size's width (`widths`: Theme.sidePanelWidths, by size), at
    // most `sidePanelShare` of the page area's width, never below 0
    function sidePanelWidth(size, pageWidth, widths) {
        const wanted = Number(widths?.[sidePanelSize(size).value]) || 0;
        const room = Math.floor((Number(pageWidth) || 0) * sidePanelShare);
        return Math.max(0, Math.min(wanted, room));
    }

    // What an open side panel does on `event` (a key of sidePanelReasons), `listOpen` when a
    // dropdown's list inside it is open: { close, reason, closeList }. Escape closes that list
    // first, the panel at the next one; every other event closes the panel. Closed already, or
    // an event it does not know: nothing.
    function sidePanelEvent(open, event, listOpen) {
        const nothing = { close: false, reason: "", closeList: false };
        if (open !== true || typeof event !== "string" || !Object.prototype.hasOwnProperty.call(sidePanelReasons, event))
            return nothing;
        if (event === "escape" && listOpen === true)
            return { close: false, reason: "", closeList: true };
        return { close: true, reason: sidePanelReasons[event], closeList: false };
    }

    // Where a scrolled view (a Flickable) goes so that an item in it shows whole: the new
    // top of the view, `viewTop` when it shows already. The item's top and bottom are in the
    // content's coordinates; `margin` is kept above or below it. An item taller than the view
    // shows its top. Never past the content's ends.
    function scrollToShow(itemTop, itemBottom, viewTop, viewHeight, contentHeight, margin) {
        const values = [itemTop, itemBottom, viewTop, viewHeight, contentHeight, margin];
        if (!values.every(value => typeof value === "number" && isFinite(value)) || viewHeight <= 0)
            return typeof viewTop === "number" && isFinite(viewTop) ? viewTop : 0;
        const highest = Math.max(0, contentHeight - viewHeight);
        let top = viewTop;
        if (itemBottom + margin > viewTop + viewHeight)
            top = itemBottom + margin - viewHeight;
        if (itemTop - margin < top)
            top = itemTop - margin;
        return Math.min(highest, Math.max(0, top));
    }

    // Whether a side panel asked to open may: "" when it may, else why not — no page frame
    // above it (a popup panel, an anchor, the bar), or the session locked
    function sidePanelRefusal(frameFound, locked) {
        if (frameFound !== true)
            return "not on a module's settings page";
        if (locked === true)
            return "the session is locked";
        return "";
    }

    // ---- The Settings modal (components/SettingsModal.qml; the core's, not in the module API) ----

    // The longest a modal's title and each line of its body may be, in characters
    readonly property int modalTitleCap: 120
    readonly property int modalLineCap: 400
    // The modal's sizes → their width token in Theme.modal
    readonly property var modalSizes: ({ s: "widthSmall", m: "widthMedium" })

    // A modal's buttons as it draws them, in order: { buttons, informing }. Each button
    // { id, label, kind, cancel }: label on one line, kind SmallButton's (ThemeRules.buttonLook),
    // id what the answer names (the given id, else the label; the cancel's is "cancel"). A
    // button is a cancel when it says so (`cancel: true`) or its kind is "cancel". There is
    // always exactly one cancel, and it is last: the first one given is kept, the others
    // dropped; none given, one is added, labelled `cancelLabel` (else "Cancel"). With no button
    // but the cancel the modal only informs (`informing`): its one button, labelled
    // `cancelLabel` (else "OK") unless the cancel given has a label, closes it as the "×"
    // does. A button that is not an object or has no label is left out; not an array: no
    // buttons of its own. `privileged` (true only when given as true, never on the cancel):
    // the button's answer asks for an administrator's password, and it carries the mark.
    function modalButtons(buttons, cancelLabel) {
        const given = (Array.isArray(buttons) ? buttons : [])
            .filter(button => button !== null && typeof button === "object" && oneLine(button.label) !== "");
        const isCancel = button => button.cancel === true || button.kind === "cancel";
        const own = given.filter(button => !isCancel(button)).map(button => {
            const label = oneLine(button.label);
            const id = oneLine(button.id);
            const kind = typeof button.kind === "string" && button.kind !== "" ? button.kind : "normal";
            return { id: id !== "" && id !== "cancel" ? id : label, label: label, kind: kind, cancel: false, privileged: button.privileged === true };
        });
        const cancelGiven = given.find(isCancel) ?? null;
        const informing = own.length === 0;
        const fallback = oneLine(cancelLabel) !== "" ? oneLine(cancelLabel) : (informing ? "OK" : "Cancel");
        const cancelKind = cancelGiven && typeof cancelGiven.kind === "string" && cancelGiven.kind !== "" ? cancelGiven.kind
            : (informing ? "normal" : "cancel");
        const cancel = { id: "cancel", label: cancelGiven ? oneLine(cancelGiven.label) : fallback, kind: cancelKind, cancel: true, privileged: false };
        return { buttons: own.concat([cancel]), informing: informing };
    }

    // A modal's body as it draws it: one entry per line, { text, strong } — `strong` for a
    // line drawn bold (a warning that leads the text). A line is a string, or { text, strong };
    // each on one line (it wraps at the modal's width), cut at `modalLineCap`; an empty one is
    // left out. A string body is one line; anything else: none.
    function modalBody(body) {
        const lines = typeof body === "string" ? [body] : (Array.isArray(body) ? body : []);
        return lines.map(line => {
            const given = line !== null && typeof line === "object" ? line : { text: line };
            return { text: oneLine(given.text, modalLineCap), strong: given.strong === true };
        }).filter(line => line.text !== "");
    }

    // A modal's checkboxes: { key, label } each, label on one line; one without a key or a
    // label, or with a key seen before, is left out
    function modalChecks(checks) {
        const seen = {};
        return (Array.isArray(checks) ? checks : []).filter(check => {
            if (check === null || typeof check !== "object" || typeof check.key !== "string" || check.key === ""
                || oneLine(check.label) === "" || seen[check.key] === true)
                return false;
            seen[check.key] = true;
            return true;
        }).map(check => ({ key: check.key, label: oneLine(check.label) }));
    }

    // A modal's width: its size's (`modal`: Theme.modal), at most the area's width less twice
    // the modal's padding, never below 0. A size it does not have: m.
    function modalWidth(size, areaWidth, modal) {
        const token = pick(modalSizes, size, sizeDefault).value;
        const wanted = Number(modal?.[token]) || 0;
        const room = (Number(areaWidth) || 0) - 2 * (Number(modal?.padding) || 0);
        return Math.max(0, Math.min(wanted, room));
    }

    // Whether a modal may open: "" when it may, else why not — the session locked, or another
    // open (a question never replaces another under the user's pointer)
    function modalRefusal(open, locked) {
        if (locked === true)
            return "the session is locked";
        if (open === true)
            return "another question is open";
        return "";
    }

    // Whether two modal subjects are the same ids, compared by value; none is never the same
    function sameSubject(first, second) {
        return first !== undefined && first !== null && JSON.stringify(first) === JSON.stringify(second);
    }

    // Whether a mark with this need shows anything: the lock, or "not allowed"
    function markShown(need) {
        const inside = markNeed(need).value;
        return inside === "auth" || inside === "no";
    }

    // The warning for a word an element does not know, and the key it is said once under
    function unknownWord(element, property, word, fallback) {
        const shown = String(word).replace(/[^\x20-\x7e]/g, "?").slice(0, 40);
        return { key: element + "." + property + "=" + shown,
            message: "[Api] " + element + ": " + property + " \"" + shown + "\" is not one it has; shown as \"" + fallback + "\"" };
    }
}
