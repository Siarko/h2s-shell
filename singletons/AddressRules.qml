pragma Singleton

import Quickshell

// IP addresses and networks — pure, tested in tests/AddressRulesTest.qml. The one place the
// shell reads them: NetworkRules (the connection editor, the hotspot, VPN lockdown) calls
// these, and modules reach them as Api.address.
//
// What is an address: IPv4 as four decimal numbers 0–255 without leading zeros ("01.2.3.4"
// is refused, as inet_pton refuses it); IPv6 full, shortened with one "::", or ending in an
// IPv4 address, at most 45 characters, without a zone ("fe80::1%eth0" is refused). A network
// is "address/prefix"; a bare address is a /32 or /128. Nothing here throws on any input.
Singleton {
    id: root

    // How much of a text redact() reads; the rest is dropped
    readonly property int redactMaxLength: 2000
    // What redact() puts where an address was (no angle brackets: shown as plain text)
    readonly property string redacted: "[address]"

    function isIpv4(text) {
        return _parseIpv4(text) !== null;
    }

    function isIpv6(text) {
        return _parseIpv6(text) !== null;
    }

    function isIp(text) {
        return isIpv4(text) || isIpv6(text);
    }

    // "address/prefix" (or a bare address) → frozen { family (4 | 6), bits (the prefix
    // length), bytes (the network's bytes, host bits cleared), address (the network's
    // address, written canonically: IPv6 in lower case, the longest run of zeros as "::",
    // an IPv4-mapped address dotted), network ("<address>/<bits>"), canonical (false when
    // the text had host bits set: "192.168.1.5/24") } — or null
    function parseCidr(text) {
        if (typeof text !== "string" || text.length > 64)
            return null;
        const parts = text.split("/");
        if (parts.length > 2)
            return null;
        const ipv4 = _parseIpv4(parts[0]);
        const ipv6 = ipv4 ? null : _parseIpv6(parts[0]);
        const bytes = ipv4 ?? ipv6;
        if (!bytes)
            return null;
        const maxBits = ipv4 ? 32 : 128;
        if (parts.length === 2 && !/^\d{1,3}$/.test(parts[1]))
            return null;
        const bits = parts.length === 2 ? Number(parts[1]) : maxBits;
        if (bits > maxBits)
            return null;
        const masked = bytes.map((byte, index) => byte & _maskByte(bits, index));
        const canonical = masked.every((byte, index) => byte === bytes[index]);
        const address = ipv4 ? masked.join(".") : _formatIpv6(masked);
        return Object.freeze({
            family: ipv4 ? 4 : 6, bits: bits, bytes: Object.freeze(masked), address: address,
            network: address + "/" + bits, canonical: canonical
        });
    }

    // Whether everything `inner` names lies in `network`: an address in a network, or a
    // smaller network inside a larger one. Each a text (parseCidr's) or parseCidr's result;
    // anything else, or two families, → false
    function contains(network, inner) {
        const outer = _cidr(network);
        const within = _cidr(inner);
        if (!outer || !within || outer.family !== within.family || within.bits < outer.bits)
            return false;
        return _samePrefix(outer, within, outer.bits);
    }

    // Whether two networks share addresses (one contains the other). Each a text or
    // parseCidr's result; anything else, or two families, → false
    function overlap(a, b) {
        const first = _cidr(a);
        const second = _cidr(b);
        if (!first || !second || first.family !== second.family)
            return false;
        return _samePrefix(first, second, Math.min(first.bits, second.bits));
    }

    // A text with every IPv4 and IPv6 address in it (with a prefix: "10.0.0.0/8") replaced
    // by "[address]" — for a line that may show on a shared screen or in a log. What is
    // around an address stays: a port ("[address]:443", "[[address]]:41641"), a label
    // ("peer:[address]"), a full stop or colon after it. Version numbers and times stay
    // ("1.104.4", "12:30"), and so do names with "::" in code ("std::string", "Foo::bar"):
    // an IPv6 address has no letter, digit or "_" glued on either side, and a bare "::" is
    // not one. Not a string: "". At most redactMaxLength characters are read.
    function redact(text) {
        if (typeof text !== "string")
            return "";
        const source = text.slice(0, redactMaxLength);
        return source.replace(/[0-9A-Fa-f:.]+(?:\/\d{1,3})?/g, (match, offset) => _redactRun(source, match, offset));
    }

    // ---- Inside ----

    // One run of address characters in `source` at `offset`, with each address in it
    // replaced. The run may hold more than an address ("Bad10.0.0.1", "D:10.0.0.1",
    // "100.64.0.4:41641"): an address starts at the run's start, after a "." or ":", or where
    // a hex letter meets a digit, and ends at the run's end or before a "." or ":". From each
    // start the longest address whose neighbours allow it is taken.
    function _redactRun(source, match, offset) {
        const prefix = /\/\d{1,3}$/.exec(match)?.[0] ?? "";
        const run = match.slice(0, match.length - prefix.length);
        const isSeparator = character => character === "." || character === ":";
        const isDigit = character => character >= "0" && character <= "9";
        const isWordCharacter = character => /^[A-Za-z0-9_]$/.test(character);
        const before = index => source.charAt(offset + index - 1);
        const after = index => source.charAt(offset + index);
        // The neighbours an address of `family` between `from` and `to` of the run may have
        const fits = (family, from, to) => {
            const left = before(from);
            const right = after(to);
            const rightNext = after(to + 1);
            if (family === 4)
                return !isDigit(left) && left !== "." && !isDigit(right) && !(right === "." && isDigit(rightNext));
            return !isWordCharacter(left) && left !== "." && !isWordCharacter(right)
                && !(right === "." && isWordCharacter(rightNext));
        };
        let result = "";
        let copied = 0;
        for (let start = 0; start < run.length; start++) {
            const opens = start === 0 || isSeparator(run[start - 1])
                || (isDigit(run[start]) && !isDigit(run[start - 1]) && !isSeparator(run[start - 1]));
            if (!opens)
                continue;
            let found = -1;
            for (let end = Math.min(run.length, start + 45); end > start; end--) {
                if (end < run.length && !isSeparator(run[end]))
                    continue;
                const candidate = run.slice(start, end);
                const family = _parseIpv4(candidate) !== null ? 4
                    : candidate !== "::" && _parseIpv6(candidate) !== null ? 6 : 0;
                if (family !== 0 && fits(family, start, end === run.length ? match.length : end)) {
                    found = end;
                    break;
                }
            }
            if (found < 0)
                continue;
            result += run.slice(copied, start) + redacted;
            copied = found === run.length ? match.length : found;
            start = found - 1;
        }
        return copied === 0 ? match : result + match.slice(copied);
    }

    // The bits of byte `index` a prefix of `bits` keeps, as a mask
    function _maskByte(bits, index) {
        const keep = Math.max(0, Math.min(8, bits - index * 8));
        return keep === 0 ? 0 : (0xff << (8 - keep)) & 0xff;
    }

    function _samePrefix(a, b, bits) {
        for (let i = 0; i < a.bytes.length; i++) {
            const mask = _maskByte(bits, i);
            if (mask === 0)
                break;
            if ((a.bytes[i] & mask) !== (b.bytes[i] & mask))
                return false;
        }
        return true;
    }

    // A text read by parseCidr, or one of its results checked to be whole (a module may
    // hand anything)
    function _cidr(value) {
        if (typeof value === "string")
            return parseCidr(value);
        if (value === null || typeof value !== "object")
            return null;
        try {
            const family = value.family;
            const bits = value.bits;
            const bytes = value.bytes;
            const length = family === 4 ? 4 : family === 6 ? 16 : 0;
            if (length === 0 || !Number.isInteger(bits) || bits < 0 || bits > length * 8)
                return null;
            if (!bytes || bytes.length !== length)
                return null;
            const copy = [];
            for (let i = 0; i < length; i++) {
                const byte = bytes[i];
                if (!Number.isInteger(byte) || byte < 0 || byte > 255)
                    return null;
                copy.push(byte);
            }
            return { family: family, bits: bits, bytes: copy };
        } catch (error) {
            return null;
        }
    }

    // IPv4 → 4 bytes, or null
    function _parseIpv4(text) {
        if (typeof text !== "string")
            return null;
        const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(text);
        if (!match)
            return null;
        const parts = match.slice(1, 5);
        const bytes = parts.map(Number);
        if (bytes.some(byte => byte > 255) || parts.some(part => part.length > 1 && part[0] === "0"))
            return null;
        return bytes;
    }

    // IPv6 → 16 bytes, or null (zones refused)
    function _parseIpv6(text) {
        if (typeof text !== "string" || text.length > 45 || !/^[0-9A-Fa-f:.]+$/.test(text) || !text.includes(":"))
            return null;
        const halves = text.split("::");
        if (halves.length > 2)
            return null;
        const groupsOf = part => part === "" ? [] : part.split(":");
        const head = groupsOf(halves[0]);
        const tail = halves.length === 2 ? groupsOf(halves[1]) : [];
        // An IPv4 tail only in the last group of the whole address
        const toWords = (groups, last) => {
            const result = [];
            for (let i = 0; i < groups.length; i++) {
                const group = groups[i];
                if (last && i === groups.length - 1 && group.includes(".")) {
                    const ipv4 = _parseIpv4(group);
                    if (!ipv4)
                        return null;
                    result.push(ipv4[0] * 256 + ipv4[1], ipv4[2] * 256 + ipv4[3]);
                } else if (/^[0-9A-Fa-f]{1,4}$/.test(group)) {
                    result.push(parseInt(group, 16));
                } else {
                    return null;
                }
            }
            return result;
        };
        const headWords = toWords(head, halves.length === 1);
        const tailWords = toWords(tail, true);
        if (!headWords || !tailWords)
            return null;
        const missing = 8 - headWords.length - tailWords.length;
        if (halves.length === 1 ? missing !== 0 : missing < 1)
            return null;
        const words = headWords.slice();
        for (let i = 0; i < (halves.length === 2 ? missing : 0); i++)
            words.push(0);
        words.push(...tailWords);
        const bytes = [];
        for (const word of words)
            bytes.push(word >> 8, word & 255);
        return bytes;
    }

    function _formatIpv6(bytes) {
        // IPv4-mapped (::ffff:a.b.c.d) with the IPv4 part dotted, as Go's netip prints it
        if (bytes.slice(0, 10).every(byte => byte === 0) && bytes[10] === 255 && bytes[11] === 255)
            return "::ffff:" + bytes.slice(12, 16).join(".");
        const words = [];
        for (let i = 0; i < 16; i += 2)
            words.push((bytes[i] << 8) | bytes[i + 1]);
        // The longest run of zero words (two or more) becomes "::" (RFC 5952)
        let bestStart = -1;
        let bestLength = 0;
        for (let i = 0; i < 8;) {
            if (words[i] !== 0) {
                i++;
                continue;
            }
            let j = i;
            while (j < 8 && words[j] === 0)
                j++;
            if (j - i > bestLength && j - i >= 2) {
                bestStart = i;
                bestLength = j - i;
            }
            i = j;
        }
        const hex = words.map(word => word.toString(16));
        if (bestStart < 0)
            return hex.join(":");
        return hex.slice(0, bestStart).join(":") + "::" + hex.slice(bestStart + bestLength).join(":");
    }
}
