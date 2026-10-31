pragma Singleton

import Quickshell

// A notification body's markup, made safe to show (docs/TODO.md 11.17).
//
// The notification spec lets a body carry <b>, <i>, <u>, <a href> and <img src alt>, and
// the server says it supports them. Shown as Qt rich text unfiltered, a body could bring
// any HTML Qt draws — remote images (tracking pixels) included — so it is rebuilt from
// what the spec allows:
// - <b>, <i>, <u> kept; <br> and <p> become line breaks; every other tag is dropped and
//   its text kept.
// - Links: http, https and mailto are "standard", in the link colour, opened on a click;
//   any other scheme (file:, an app's own) is "unusual", in the warning colour, opened
//   only after a question. A link without a usable target is plain text.
// - Images are never loaded: an image is a row of its own, tinted, with an image glyph and
//   a link to it (its alt text, else its address), so it can still be opened by hand.
// - Entities decoded and the text escaped again, so a stray "&", "<" or ">" — "a < b" —
//   stays as typed; new lines become line breaks.
// The body is read by a small tokenizer (tokens()), not matched by patterns: quoted
// attributes with ">" in them, self-closing tags, comments and odd tag names all parse.
// Pure functions: no I/O, so the test suite checks them.
Singleton {
    id: root

    // How a link is treated: "standard", "unusual", or "" for no link (empty, a data: URI —
    // nothing to open, and possibly huge)
    function linkKind(url) {
        const target = (url ?? "").trim();
        if (target === "")
            return "";
        const scheme = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(target);
        if (!scheme)
            return target.startsWith("/") ? "unusual" : "";
        const name = scheme[1].toLowerCase();
        if (name === "data" || name === "javascript")
            return "";
        return ["http", "https", "mailto"].includes(name) ? "standard" : "unusual";
    }

    // What a link opens: a bare absolute path is a file
    function linkTarget(url) {
        const target = (url ?? "").trim();
        return target.startsWith("/") ? "file://" + target : target;
    }

    readonly property var _entities: ({ amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: "\u00a0" })

    function _decode(text) {
        return text.replace(/&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);/g, (match, name) => {
            if (name[0] === "#") {
                const code = name[1] === "x" || name[1] === "X" ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
                return isNaN(code) ? match : String.fromCodePoint(code);
            }
            return root._entities[name] ?? match;
        });
    }

    function _escape(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    // A long address shortened in the middle, for an image row's label
    function _shortened(text) {
        return text.length <= 60 ? text : text.slice(0, 40) + "…" + text.slice(-17);
    }

    // The body as tokens, read character by character — a small HTML tokenizer, so tags
    // of any shape are understood rather than matched by a pattern:
    //   { type: "text", text }                          entities decoded
    //   { type: "open", name, attributes, selfClosing } name lower case; attributes by
    //   { type: "close", name }                         lower-case name, values decoded
    // Attribute values may be quoted with " or ', or bare; a ">" inside quotes does not end
    // the tag; "<br/>", "<br />" and "<img ... />" close themselves. Comments, <!...> and
    // <?...?> are dropped. A "<" that starts no tag ("a < b", "<3") is text.
    function tokens(body) {
        const text = body ?? "";
        const result = [];
        let plain = "";
        const flush = () => {
            if (plain !== "")
                result.push({ type: "text", text: _decode(plain) });
            plain = "";
        };
        let i = 0;
        while (i < text.length) {
            const char = text[i];
            if (char !== "<") {
                plain += char;
                i++;
                continue;
            }
            // Comments, declarations, processing instructions: up to their end
            if (text.startsWith("<!--", i)) {
                const close = text.indexOf("-->", i + 4);
                flush();
                i = close === -1 ? text.length : close + 3;
                continue;
            }
            if (text[i + 1] === "!" || text[i + 1] === "?") {
                const close = text.indexOf(">", i + 2);
                flush();
                i = close === -1 ? text.length : close + 1;
                continue;
            }
            const tag = _readTag(text, i);
            if (!tag) {
                plain += char;
                i++;
                continue;
            }
            flush();
            result.push(tag.token);
            i = tag.end;
        }
        flush();
        return result;
    }

    // The tag starting at `start` ("<"), as { token, end }, or null when there is none
    function _readTag(text, start) {
        let i = start + 1;
        const closing = text[i] === "/";
        if (closing)
            i++;
        const name = /^[a-zA-Z][a-zA-Z0-9:_-]*/.exec(text.slice(i, i + 64));
        if (!name)
            return null;
        i += name[0].length;
        const attributes = {};
        let selfClosing = false;
        while (i < text.length) {
            const char = text[i];
            if (char === ">")
                return { token: closing ? { type: "close", name: name[0].toLowerCase() }
                    : { type: "open", name: name[0].toLowerCase(), attributes: attributes, selfClosing: selfClosing }, end: i + 1 };
            if (char === "<")
                return null;
            if (char === "/") {
                selfClosing = true;
                i++;
                continue;
            }
            if (/\s/.test(char)) {
                i++;
                continue;
            }
            selfClosing = false;
            // An attribute: a name, and maybe = and a value
            const attribute = /^[^\s"'<>\/=]+/.exec(text.slice(i));
            if (!attribute)
                return null;
            i += attribute[0].length;
            while (/\s/.test(text[i] ?? ""))
                i++;
            let value = "";
            if (text[i] === "=") {
                i++;
                while (/\s/.test(text[i] ?? ""))
                    i++;
                const quote = text[i];
                if (quote === "\"" || quote === "'") {
                    const close = text.indexOf(quote, i + 1);
                    if (close === -1)
                        return null;
                    value = text.slice(i + 1, close);
                    i = close + 1;
                } else {
                    const bare = /^[^\s<>]*/.exec(text.slice(i))[0];
                    value = bare.endsWith("/") && text[i + bare.length] === ">" ? bare.slice(0, -1) : bare;
                    i += value.length;
                }
            }
            attributes[attribute[0].toLowerCase()] = _decode(value);
        }
        return null;
    }

    // The body as Qt rich text. `colors`: { link, unusualLink, imageRow, imageGlyph,
    // address } —
    // colour strings from the theme ("#rrggbb"; the image row's opaque, as Qt's table
    // background takes no alpha)
    function richText(body, colors) {
        let out = "";
        // Open formatting tags, to close what the body left open; whether inside a link
        const open = [];
        let inLink = false;
        const linkOpen = (url, kind) => "<a href=\"" + _escape(linkTarget(url)) + "\"><span style=\"color:"
            + (kind === "standard" ? colors.link : colors.unusualLink) + "\">";
        for (const token of tokens(body)) {
            if (token.type === "text") {
                out += _escape(token.text).replace(/\n/g, "<br>");
                continue;
            }
            const tag = token.name;
            const closing = token.type === "close";
            if (tag === "b" || tag === "i" || tag === "u") {
                if (!closing && !token.selfClosing) {
                    open.push(tag);
                    out += "<" + tag + ">";
                } else if (closing && open.includes(tag)) {
                    // Close what was opened inside it too, then reopen those
                    const reopen = [];
                    while (open.length > 0) {
                        const inner = open.pop();
                        out += "</" + inner + ">";
                        if (inner === tag)
                            break;
                        reopen.unshift(inner);
                    }
                    for (const inner of reopen) {
                        open.push(inner);
                        out += "<" + inner + ">";
                    }
                }
            } else if (tag === "br") {
                out += "<br>";
            } else if (tag === "p") {
                // A paragraph is a line break between it and what is around it
                if (out !== "" && !out.endsWith("<br>"))
                    out += "<br>";
            } else if (tag === "a") {
                if (!closing && !token.selfClosing && !inLink) {
                    const url = token.attributes.href ?? "";
                    const kind = linkKind(url);
                    if (kind !== "") {
                        out += linkOpen(url, kind);
                        inLink = true;
                    }
                } else if (closing && inLink) {
                    out += "</span></a>";
                    inLink = false;
                }
            } else if (tag === "img" && !closing) {
                const source = token.attributes.src ?? "";
                const alt = (token.attributes.alt ?? "").trim();
                const kind = linkKind(source);
                // No alt text: the address names it — unless it is no link (a data: URI)
                const label = _escape(alt !== "" ? alt : kind !== "" ? _shortened(source) : "");
                if (label === "")
                    continue;
                const content = kind !== "" && !inLink ? linkOpen(source, kind) + label + "</span></a>" : label;
                // Under an alt text, the address it leads to: where a link goes matters more
                // than what it says
                const address = alt !== "" && kind !== ""
                    ? "<br><span style=\"color:" + colors.address + "\">" + _escape(_shortened(linkTarget(source))) + "</span>" : "";
                out += "<table width=\"100%\" cellspacing=\"0\" cellpadding=\"3\" bgcolor=\"" + colors.imageRow + "\"><tr><td>"
                    + "<span style=\"color:" + colors.imageGlyph + "\">\u{F02E9}</span>&nbsp;" + content + address
                    + "</td></tr></table>";
            }
            // Any other tag: dropped, its text kept
        }
        if (inLink)
            out += "</span></a>";
        while (open.length > 0)
            out += "</" + open.pop() + ">";
        return out;
    }

    // The targets of the image rows' links: their row shows the address already, so the
    // card gives them no address tooltip
    function imageLinks(body) {
        return tokens(body).filter(token => token.type === "open" && token.name === "img"
                && linkKind(token.attributes.src ?? "") !== "")
            .map(token => linkTarget(token.attributes.src));
    }

    // The body as plain text: tags dropped (an image as its alt text), line breaks as new
    // lines — for the codes found in it and for the screensaver's preview
    function plainText(body) {
        let out = "";
        for (const token of tokens(body)) {
            if (token.type === "text")
                out += token.text;
            else if (token.name === "br" || token.name === "p")
                out += "\n";
            else if (token.name === "img" && token.type === "open") {
                const alt = (token.attributes.alt ?? "").trim();
                out += alt !== "" ? "\n" + alt + "\n" : "\n";
            }
        }
        return out.replace(/\n{3,}/g, "\n\n").trim();
    }
}
