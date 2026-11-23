# Evaluated by tests/system/nixos/pam.sh: the flake's programs.h2s-shell.pam options for a
# set of minimal systems, not built. → lines "<ok|bad>\t<description>\t<detail>".
#
# The case set (tests/fixtures/pam-nixos/cases.json; tests/PamNixosModuleTest.qml checks it
# against the editor): each case's options, as the editor writes them, evaluated on a
# machine with what the case names; the shell's lines in sudo's and polkit's files must be
# the editor's for the same rows (as NixOS writes them: a module by its file name), and
# must be the files' first auth lines. Then the assertions and warnings, one system each.
{ repo }:
let
  flake = builtins.getFlake "path:${repo}";
  lib = flake.inputs.nixpkgs.lib;
  cases = builtins.fromJSON (builtins.readFile "${repo}/tests/fixtures/pam-nixos/cases.json");

  base = {
    programs.h2s-shell.enable = true;
    boot.loader.grub.enable = false;
    # The least a system evaluates with: modules read the type of the root filesystem
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    system.stateVersion = "26.05";
    security.polkit.enable = true;
  };
  evaluate = extra: (lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.nixosModules.default base extra ];
  });
  configOf = extra: (evaluate extra).config;
  machine = facts: {
    services.fprintd.enable = facts.fprintd or false;
    security.pam.u2f.enable = facts.u2f or false;
    security.pam.services.sudo.logFailures = facts.logFailures or false;
    security.pam.services.polkit-1.logFailures = facts.logFailures or false;
  };

  authLines = config: service:
    lib.filter (line: lib.hasPrefix "auth " line)
      (lib.splitString "\n" config.security.pam.services.${service}.text);
  ours = line: builtins.match ".*# h2s-[0-9]+ \\(order -?[0-9]+\\)$" line != null;
  # A line of the file as the editor's are compared: no comment, the module its file name
  # (a bracketed control holds spaces)
  normalized = line:
    let
      parts = builtins.match "([^ ]+) +(\\[[^]]*]|[^ ]+) +([^ ]+)(.*)" (lib.head (lib.splitString " # " line));
    in
    if parts == null then line
    else lib.concatStringsSep " " ([ (lib.elemAt parts 0) (lib.elemAt parts 1) (baseNameOf (lib.elemAt parts 2)) ]
      ++ lib.filter (word: word != "") (lib.splitString " " (lib.elemAt parts 3)));

  result = ok: description: detail: "${if ok then "ok" else "bad"}\t${description}\t${detail}";

  caseResults = testCase:
    let
      options = import (builtins.toFile "options.nix" "{ ${testCase.snippet} }");
      config = configOf { imports = [ options (machine testCase.machine) ]; };
      serviceResult = service:
        let
          expected = testCase.lines.${service};
          lines = authLines config service;
          first = lib.take (lib.length expected) lines;
          got = map normalized first;
          tagged = lib.length (lib.filter ours lines);
        in
        result (got == expected && lib.all ours first && tagged == lib.length expected)
          "${testCase.name}: ${service}'s first auth lines are the editor's"
          "got ${builtins.toJSON (map normalized (lib.filter ours lines))}, first lines ${builtins.toJSON got}, expected ${builtins.toJSON expected}";
      # NixOS's own fingerprint and key rules are off where the shell's rules are
      noSecondAsk = service:
        let
          others = lib.filter (line: !(ours line)) (authLines config service);
          asks = lib.filter (line: lib.hasInfix "pam_fprintd.so" line || lib.hasInfix "pam_u2f.so" line) others;
        in
        result (asks == [ ]) "${testCase.name}: no fingerprint or key line of NixOS's own in ${service}" (builtins.toJSON asks);
      failed = map (assertion: assertion.message) (lib.filter (assertion: !assertion.assertion) config.assertions);
    in [
      (serviceResult "sudo")
      (serviceResult "polkit-1")
      (noSecondAsk "sudo")
      (noSecondAsk "polkit-1")
      (result (failed == [ ]) "${testCase.name}: no assertion fails" (builtins.toJSON failed))
    ];

  # ── Assertions and warnings ──

  findings = extra:
    let config = configOf extra;
    in {
      refusals = map (assertion: assertion.message) (lib.filter (assertion: !assertion.assertion) config.assertions);
      inherit (config) warnings;
    };
  says = list: text: lib.any (message: lib.hasInfix text message) list;
  expect = description: extra: { refusals ? [ ], warnings ? [ ], notWarnings ? [ ] }:
    let
      found = findings extra;
      ok = lib.all (says found.refusals) refusals && lib.all (says found.warnings) warnings
        && !(lib.any (says found.warnings) notWarnings)
        && (refusals != [ ] || found.refusals == [ ]);
    in
    result ok description "assertions ${builtins.toJSON found.refusals}, warnings ${builtins.toJSON found.warnings}";
  fingerprint = { method = "fingerprint"; };
  system = { method = "system"; };
  raw = module: { method = "raw"; inherit module; args = [ "use_first_pass" ]; };
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;

  checks = [
    (expect "an empty list is refused" { programs.h2s-shell.pam.rules = [ ]; } { refusals = [ "programs.h2s-shell.pam.rules is empty" ]; })
    (expect "a required reader without fprintd is refused (nobody would get in)"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { control = "required"; }) system ]; }
      { refusals = [ "row 1 (fingerprint): this row must pass, but services.fprintd.enable is off" ]; })
    (expect "… with fprintd: a warning, both needed"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { control = "required"; }) system ]; services.fprintd.enable = true; }
      { warnings = [ "both needed" ]; })
    (expect "only a reader for sudo, polkit untouched: a warning"
      { programs.h2s-shell.pam.sudo.rules = [ fingerprint ]; services.fprintd.enable = true; }
      { warnings = [ "programs.h2s-shell.pam.sudo.rules: only the reader lets you in" ]; })
    (expect "only a reader for both: refused, one keeps a password"
      { programs.h2s-shell.pam.rules = [ fingerprint ]; services.fprintd.enable = true; }
      { refusals = [ "keep a password in sudo's or polkit's rules" ]; })
    (expect "a reader that is not there and no password: refused, no way in"
      { programs.h2s-shell.pam.sudo.rules = [ fingerprint ]; }
      { refusals = [ "programs.h2s-shell.pam.sudo.rules: no row can let you in" ]; })
    (expect "the system row not last: refused"
      { programs.h2s-shell.pam.rules = [ system { method = "password"; } ]; }
      { refusals = [ "can only be last, and only once" ]; })
    (expect "a counted password where nothing counts: refused"
      { programs.h2s-shell.pam.rules = [ { method = "password"; counted = true; } system ]; }
      { refusals = [ "failures cannot count here: sudo's rules do not count them" ]; })
    (expect "another row's detail: refused"
      { programs.h2s-shell.pam.rules = [ { method = "password"; timeout = 10; } system ]; }
      { refusals = [ "timeout and tries are a fingerprint row's" ]; })
    (expect "a raw line with another package's module by name: refused"
      { programs.h2s-shell.pam.rules = [ (raw "pam_ldap.so") system ]; }
      { refusals = [ "pam_ldap.so needs its full path on NixOS" ]; })
    (expect "a raw line with a space in its module: refused"
      { programs.h2s-shell.pam.rules = [ (raw "/run/current-system/sw/lib/security/pam x.so") system ]; }
      { refusals = [ "go on one line" ]; })
    (expect "a raw pam_deny that fails: refused"
      { programs.h2s-shell.pam.rules = [ (raw "pam_deny.so" // { control = "required"; }) system ]; }
      { refusals = [ "this line refuses everyone" ]; })
    (expect "a module from the home: a warning, not a refusal"
      { programs.h2s-shell.pam.rules = [ (raw "/home/someone/pam_x.so") system ]; }
      { warnings = [ "/home/someone/pam_x.so is not in the Nix store" ]; })
    (expect "a store path written out: a warning naming its package"
      { programs.h2s-shell.pam.rules = [ (raw "${builtins.unsafeDiscardStringContext pkgs.pam_u2f.outPath}/lib/security/pam_u2f.so") system ]; }
      { warnings = [ "is a path in the Nix store: it changes with an update or a garbage collection: use \${pkgs.pam_u2f} instead" ]; })
    (expect "a module from its package: no warning"
      { programs.h2s-shell.pam.rules = [ (raw "${pkgs.pam_u2f}/lib/security/pam_u2f.so") system ]; }
      { notWarnings = [ "pam_u2f.so" ]; })
    (expect "NixOS's own fingerprint switched on by hand beside the rules: refused"
      { programs.h2s-shell.pam.rules = [ system ]; services.fprintd.enable = true; security.pam.services.sudo.fprintAuth = true; }
      { refusals = [ "sudo's rules come from programs.h2s-shell.pam: remove security.pam.services.sudo.fprintAuth" ]; })
    (expect "polkit.passwordFirst set beside polkit's rules: refused"
      { programs.h2s-shell.pam.rules = [ system ]; programs.h2s-shell.polkit.passwordFirst = true; }
      { refusals = [ "remove programs.h2s-shell.polkit.passwordFirst" ]; })
    (expect "polkit.passwordFirst set without rules: deprecated, a warning"
      { programs.h2s-shell.polkit.passwordFirst = true; services.fprintd.enable = true; }
      { warnings = [ "programs.h2s-shell.polkit.passwordFirst is deprecated" ]; })
    (expect "a raw libpam module that asks nothing, required, without the system row: refused, anyone gets in"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "password"; } { method = "raw"; module = "pam_env.so"; control = "required"; } ]; }
      { refusals = [ "row 2 (raw): this line lets anyone in: pam_env.so" ]; })
    (expect "… the same beside the system row: allowed (the system's rules still decide)"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "raw"; module = "pam_env.so"; control = "required"; } system ]; }
      { })
    (expect "a sufficient pam_permit above the system row: refused"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_permit.so"; } system ]; }
      { refusals = [ "this line lets anyone in: pam_permit.so" ]; })
    (expect "a sufficient pam_u2f with nouserok: refused (no key gets in)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "nouserok" ]; } system ];
        security.pam.u2f.enable = true; }
      { refusals = [ "this line lets anyone in: pam_u2f.so" ]; })
    (expect "a sufficient pam_userdb with its database outside /etc: refused"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_userdb.so"; args = [ "db=/tmp/users" ]; } system ]; }
      { refusals = [ "this line lets anyone in: pam_userdb.so" ]; })
    (expect "… under /etc: allowed"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_userdb.so"; args = [ "db=/etc/users" ]; } system ]; }
      { })
    (expect "a backslash at the end of an argument: refused (it would join the next line)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_env.so"; control = "optional"; args = [ "x\\" ]; } system ]; }
      { refusals = [ "no backslash or # in the module or its arguments" ]; })
    (expect "a # in the module: refused"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/run/current-system/sw/lib/security/pam_x.so#"; control = "optional"; } system ]; }
      { refusals = [ "no backslash or # in the module or its arguments" ]; })
    (expect "polkit off: it keeps no password, so a reader-only sudo is refused"
      { programs.h2s-shell.pam.sudo.rules = [ fingerprint ]; services.fprintd.enable = true; security.polkit.enable = lib.mkForce false; }
      { refusals = [ "keep a password in sudo's or polkit's rules" ]; })
    (expect "a raw pam_unix with nullok: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_unix.so"; args = [ "nullok" ]; } system ]; }
      { warnings = [ "nullok: an account with an empty password gets in" ]; })
    (expect "a path from a package that does not start with the store: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/x${pkgs.pam_u2f}/lib/security/pam_u2f.so"; } system ]; }
      { warnings = [ "is not in the Nix store" ]; })
    (expect "systemd-homed on and no system row: a warning that homed accounts are not asked"
      { programs.h2s-shell.pam.rules = [ { method = "password"; } ]; services.homed.enable = true; }
      { warnings = [ "systemd-homed accounts are not asked for their password" ]; })
    (expect "… with the system row: no such warning"
      { programs.h2s-shell.pam.rules = [ { method = "password"; } system ]; services.homed.enable = true; }
      { notWarnings = [ "accounts are not asked" ]; })
    (expect "polkit.passwordFirst = false beside polkit's rules: allowed"
      { programs.h2s-shell.pam.rules = [ system ]; programs.h2s-shell.polkit.passwordFirst = false; }
      { })
    (expect "nothing set: no assertion, no warning of the shell's"
      { services.fprintd.enable = true; }
      { notWarnings = [ "h2s-shell" ]; })
  ];

  # Nothing set: the files are NixOS's, and polkit's fingerprint still follows its password
  # (polkit.passwordFirst's default with fprintd)
  untouched =
    let
      config = configOf { services.fprintd.enable = true; };
      polkit = authLines config "polkit-1";
      indexOf = text: lib.lists.findFirstIndex (line: lib.hasInfix text line) null polkit;
    in [
      (result (!(lib.any ours (authLines config "sudo" ++ polkit))) "nothing set: no line of the shell's" "")
      (result (indexOf "pam_unix.so" != null && indexOf "pam_fprintd.so" != null && indexOf "pam_unix.so" < indexOf "pam_fprintd.so")
        "nothing set, with fprintd: polkit asks the password before the reader" (builtins.toJSON polkit))
    ];
in
lib.concatStringsSep "\n" (lib.concatMap caseResults cases ++ checks ++ untouched) + "\n"
