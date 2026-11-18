import QtQuick
import qs.singletons
import qs.singletons.network

TestCase {
    suiteName: "AddressRules"

    function run() {
        const rules = AddressRules;

        // --- addresses ---
        for (const good of ["192.168.1.1", "0.0.0.0", "255.255.255.255", "10.0.0.1"])
            assert(rules.isIpv4(good), "IPv4: " + good);
        for (const bad of ["256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "1.2.3.04", " 1.2.3.4", "1.2.3.4 ", "a.b.c.d", "", null, undefined, 1234, {}])
            assert(!rules.isIpv4(bad), "IPv4: " + JSON.stringify(bad) + " refused");
        for (const good of ["2606:4700:4700::1111", "::1", "::", "fe80::6f33:7072:7167:c19c", "::ffff:192.168.1.1", "1:2:3:4:5:6:7:8",
                            "1:2:3:4:5:6:1.2.3.4", "FD7A:115C:A1E0::1"])
            assert(rules.isIpv6(good), "IPv6: " + good);
        for (const bad of ["1::2::3", "12345::1", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9", "fe80::1%eth0", "::1.2.3.4:5", "1.2.3.4::1",
                           "1.2.3.4", ":::", "1:", "g::1", "::01.2.3.4", "1:2:3:4:5:6:7:1.2.3.4", "a".repeat(46), "", null, 6])
            assert(!rules.isIpv6(bad), "IPv6: " + JSON.stringify(bad) + " refused");
        assert(rules.isIp("10.0.0.1") && rules.isIp("::1") && !rules.isIp("example.com") && !rules.isIp(null), "isIp: either family");

        // --- networks (the Tailscale module's cases, from its TailscaleRules) ---
        const cidr = rules.parseCidr("192.168.1.0/24");
        assert(cidr && cidr.family === 4 && cidr.bits === 24 && cidr.canonical && cidr.address === "192.168.1.0", "cidr: an IPv4 network");
        assert(Object.isFrozen(cidr) && Object.isFrozen(cidr.bytes), "cidr: frozen, its bytes too");
        const hostBits = rules.parseCidr("192.168.1.5/24");
        assert(hostBits && !hostBits.canonical && hostBits.network === "192.168.1.0/24", "cidr: host bits → not canonical, the network named");
        assertEqual(rules.parseCidr("10.1.2.3")?.network, "10.1.2.3/32", "cidr: a bare IPv4 address is a /32");
        assertEqual(rules.parseCidr("fd00:99:0:0::/64")?.network, "fd00:99::/64", "cidr: IPv6 written canonically");
        assertEqual(rules.parseCidr("FD00:99::/64")?.network, "fd00:99::/64", "cidr: IPv6 in lower case");
        assertEqual(rules.parseCidr("fd7a:115c:a1e0::1")?.network, "fd7a:115c:a1e0::1/128", "cidr: a bare IPv6 address is a /128");
        assertEqual(rules.parseCidr("::ffff:192.0.2.1/128")?.network, "::ffff:192.0.2.1/128", "cidr: an embedded IPv4, written as Go's netip prints it");
        assertEqual(rules.parseCidr("::/0")?.bits, 0, "cidr: the IPv6 default route");
        assertEqual(rules.parseCidr("0.0.0.0/0")?.network, "0.0.0.0/0", "cidr: the IPv4 default route");
        assertEqual(rules.parseCidr("2001:db8:0:1:1:1:1:1/64")?.network, "2001:db8:0:1::/64", "cidr: zeros compressed once, the longest run");
        assertEqual(rules.parseCidr("1:0:0:2:0:0:0:3")?.address, "1:0:0:2::3", "cidr: the longer of two runs");
        for (const bad of ["300.1.1.1/24", "1.2.3/24", "1.2.3.4/33", "fd00::/129", "1::2::3", "01.2.3.4/8", "1.2.3.4/", "1.2.3.4/x", "fe80::1%eth0",
                           "::1.2.3.4:5", "1.2.3.4.5", "", null, 5, "1:2:3:4:5:6:7:8:9", "a".repeat(80), "1.2.3.4/8/8", "1.2.3.4/-1", "1.2.3.4/1000"])
            assertEqual(rules.parseCidr(bad), null, "cidr: " + JSON.stringify(bad) + " refused");

        assert(rules.overlap(rules.parseCidr("10.0.0.0/8"), rules.parseCidr("10.20.0.0/16")), "overlap: contained");
        assert(rules.overlap("10.20.0.0/16", "10.0.0.0/8"), "overlap: either order, as texts");
        assert(!rules.overlap(rules.parseCidr("10.0.0.0/8"), rules.parseCidr("11.0.0.0/8")), "overlap: beside");
        assert(!rules.overlap(rules.parseCidr("10.0.0.0/8"), rules.parseCidr("fd00::/8")), "overlap: different families");
        assert(rules.overlap(rules.parseCidr("fd00:99::/64"), rules.parseCidr("fd00:99::1")), "overlap: IPv6 host in network");
        assert(!rules.overlap(null, cidr), "overlap: nothing");
        assert(!rules.overlap("not an address", "10.0.0.0/8"), "overlap: a text that is not a network");
        assert(!rules.overlap({ family: 4, bits: 8, bytes: [10, 0, 0] }, "10.0.0.0/8"), "overlap: a made-up result with too few bytes");
        assert(!rules.overlap({ family: 4, bits: 40, bytes: [10, 0, 0, 0] }, "10.0.0.0/8"), "overlap: a made-up result with too many bits");
        assert(rules.overlap({ family: 4, bits: 8, bytes: [10, 0, 0, 0] }, "10.9.0.0/16"), "overlap: a plain object shaped like a result");

        assert(rules.contains("192.168.10.0/24", "192.168.10.200"), "contains: an address in the network");
        assert(rules.contains("192.168.10.5/24", "192.168.10.200"), "contains: the network given with host bits");
        assert(!rules.contains("192.168.10.0/24", "192.168.11.1"), "contains: an address outside");
        assert(rules.contains("10.0.0.0/8", "10.20.0.0/16"), "contains: a smaller network inside");
        assert(!rules.contains("10.20.0.0/16", "10.0.0.0/8"), "contains: a larger network is not inside a smaller one");
        assert(rules.contains("0.0.0.0/0", "8.8.8.8") && rules.contains("::/0", "2001:db8::1"), "contains: the default routes hold everything of their family");
        assert(!rules.contains("0.0.0.0/0", "::1"), "contains: not the other family");
        assert(rules.contains(rules.parseCidr("fd7a:115c:a1e0::/48"), "fd7a:115c:a1e0:ab12::1"), "contains: a parsed network, IPv6");
        assert(!rules.contains("10.0.0.0/8", "01.2.3.4") && !rules.contains(undefined, "10.0.0.1"), "contains: bad input");

        // --- redact ---
        assertEqual(rules.redact("peer 100.64.0.4 gone"), "peer [address] gone", "redact: a placeholder without angle brackets");
        assertEqual(rules.redact("invalid value \"100.64.0.4\" for --exit-node; fd7a:115c:a1e0::1 and 10.0.0.0/8 too, version 1.104.4 at 12:30"),
                    "invalid value \"[address]\" for --exit-node; [address] and [address] too, version 1.104.4 at 12:30",
                    "redact: IPv4, IPv6, prefixes gone; versions and times kept");
        assertEqual(rules.redact("ends with 10.0.0.1."), "ends with [address].", "redact: a full stop after an address stays");
        assertEqual(rules.redact("prefix fd7a:115c:a1e0:: and fd00::1: then"), "prefix [address] and [address]: then", "redact: an IPv6 ending in \"::\", and a colon after one");
        // Neighbours of an address: a port, a label, hex letters glued on
        assertEqual(rules.redact("connect to 192.168.1.5:443 failed"), "connect to [address]:443 failed", "redact: an IPv4 with a port, the port kept");
        assertEqual(rules.redact("100.64.0.4:41641"), "[address]:41641", "redact: an IPv4 and port alone");
        assertEqual(rules.redact("peer:10.0.0.1 down"), "peer:[address] down", "redact: a label and colon before an IPv4");
        assertEqual(rules.redact("ID:10.0.0.1"), "ID:[address]", "redact: a hex-letter label before an IPv4");
        assertEqual(rules.redact("Bad10.0.0.1"), "Bad[address]", "redact: hex letters glued before an IPv4");
        assertEqual(rules.redact("dial [fd7a::1]:41641 refused"), "dial [[address]]:41641 refused", "redact: an IPv6 in brackets with a port");
        assertEqual(rules.redact("peer:fd00::1 down, 10.0.0.0/8:x"), "peer:[address] down, [address]:x", "redact: a label before an IPv6; a prefix before a colon");
        assertEqual(rules.redact("1.2.3.4.5 and 01.2.3.4"), "1.2.3.4.5 and 01.2.3.4", "redact: not addresses, neither in part");
        // "::" in code is not an address
        assertEqual(rules.redact("std::string and anyhow::Error"), "std::string and anyhow::Error", "redact: names with \"::\" stay");
        assertEqual(rules.redact("Foo::bar, a :: b, cafe::beef_x"), "Foo::bar, a :: b, cafe::beef_x", "redact: hex letters glued to \"::\", a bare \"::\"");
        assertEqual(rules.redact("from ::1 and ::ffff:10.0.0.1"), "from [address] and [address]", "redact: \"::1\" and a mapped IPv4");
        assertEqual(rules.redact("x".repeat(2500)).length, 2000, "redact: at most 2000 characters read");
        assertEqual(rules.redact(null) + rules.redact(42), "", "redact: not a text");

        // --- NetworkRules reads addresses through AddressRules ---
        assert(NetworkRules.isIpv4("192.168.1.1") && !NetworkRules.isIpv4("192.168.01.1"), "NetworkRules.isIpv4: the same reader (no leading zeros)");
        assert(NetworkRules.isIpv6("::1") && !NetworkRules.isIpv6("fe80::1%eth0"), "NetworkRules.isIpv6: the same reader");
        assert(NetworkRules.isIpAddress("::1") && !NetworkRules.isIpAddress("host"), "NetworkRules.isIpAddress");
        assert(NetworkRules.isCidr4("192.168.1.5/24") && NetworkRules.isCidr4("192.168.1.5") && !NetworkRules.isCidr4("2001:db8::/64")
               && !NetworkRules.isCidr4("1.2.3.4/33"), "NetworkRules.isCidr4");
        assert(NetworkRules.isCidr6("2001:db8::5/64") && !NetworkRules.isCidr6("10.0.0.0/8"), "NetworkRules.isCidr6");
        assert(NetworkRules.inSubnet4("192.168.10.200", ["10.0.0.0/8", "192.168.10.5/24"]) && !NetworkRules.inSubnet4("192.168.11.1", ["192.168.10.5/24"])
               && !NetworkRules.inSubnet4("::1", ["::/0"]) && !NetworkRules.inSubnet4("10.0.0.1", null), "NetworkRules.inSubnet4");
    }
}
