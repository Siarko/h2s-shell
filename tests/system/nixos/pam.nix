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
    (expect "an empty list: a warning, nobody would get in" { programs.h2s-shell.pam.rules = [ ]; } { warnings = [ "Nobody will get in with this config: programs.h2s-shell.pam.rules has no rows" ]; })
    (expect "a required reader without fprintd: a warning, nobody would get in"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { control = "required"; }) system ]; }
      { warnings = [ "Nobody will get in with this config: programs.h2s-shell.pam.rules, row 1 (fingerprint): a row must pass, but its reader is not ready (services.fprintd.enable is off)" ]; })
    (expect "… with fprintd: a warning, both needed"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { control = "required"; }) system ]; services.fprintd.enable = true; }
      { warnings = [ "both needed" ]; })
    (expect "only a reader for sudo, polkit untouched: a warning"
      { programs.h2s-shell.pam.sudo.rules = [ fingerprint ]; services.fprintd.enable = true; }
      { warnings = [ "programs.h2s-shell.pam.sudo.rules: only the reader lets you in" ]; })
    (expect "only a reader for both: a warning, one keeps a password"
      { programs.h2s-shell.pam.rules = [ fingerprint ]; services.fprintd.enable = true; }
      { warnings = [ "You could lose access: programs.h2s-shell.pam: neither sudo nor polkit keep a password, so if the reader breaks, both are closed. sudo may become unreachable, and the shell cannot fix it" ]; })
    (expect "a reader that is not there and no password: a warning, no way in"
      { programs.h2s-shell.pam.sudo.rules = [ fingerprint ]; }
      { warnings = [ "Nobody will get in with this config: programs.h2s-shell.pam.sudo.rules: no row can let you in" ]; })
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
    (expect "a raw pam_deny that fails: a warning"
      { programs.h2s-shell.pam.rules = [ (raw "pam_deny.so" // { control = "required"; }) system ]; }
      { warnings = [ "a line refuses everyone" ]; })
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
    (expect "a raw libpam module that asks nothing, required, without the system row: a warning, anyone gets in"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "password"; } { method = "raw"; module = "pam_env.so"; control = "required"; } ]; }
      { warnings = [ "Authorization config is unsafe: programs.h2s-shell.pam.sudo.rules, row 2 (raw): a line lets anyone in without a password (pam_env.so asks for no password" ]; })
    (expect "… the same beside the system row: allowed (the system's rules still decide)"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "raw"; module = "pam_env.so"; control = "required"; } system ]; }
      { })
    (expect "a sufficient pam_permit above the system row: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_permit.so"; } system ]; }
      { warnings = [ "Authorization config is unsafe: programs.h2s-shell.pam.rules, row 1 (raw): a line lets anyone in without a password (pam_permit.so asks for no password" ]; })
    (expect "a sufficient pam_u2f with nouserok: allowed (a user without a key goes on to the next row)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "nouserok" ]; } system ];
        security.pam.u2f.enable = true; }
      { notWarnings = [ "may not ask for a key" ]; })
    (expect "a required pam_u2f with nouserok beside a sufficient password, without the system row: a warning (the permit lets a user without a key in)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "nouserok" ]; control = "required"; } { method = "password"; } ];
        security.pam.u2f.enable = true; }
      { warnings = [ "a line lets anyone in without a password (pam_u2f.so asks for no password" ]; })
    (expect "a required pam_permit beside a required password row: a warning, not refused (the password still asks)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_permit.so"; control = "required"; } { method = "password"; control = "required"; } ]; }
      { warnings = [ "row 1 (raw): pam_permit.so asks for nothing: only the other rows decide" ]; })
    (expect "a sufficient pam_userdb with its database outside /etc: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_userdb.so"; args = [ "db=/tmp/users" ]; } system ]; }
      { warnings = [ "a line lets anyone in without a password (pam_userdb.so asks for no password" ]; })
    (expect "… under /etc: allowed"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_userdb.so"; args = [ "db=/etc/users" ]; } system ]; }
      { })
    (expect "a backslash at the end of an argument: refused (it would join the next line)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_env.so"; control = "optional"; args = [ "x\\" ]; } system ]; }
      { refusals = [ "no backslash or # in the module or its arguments" ]; })
    (expect "a # in the module: refused"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/run/current-system/sw/lib/security/pam_x.so#"; control = "optional"; } system ]; }
      { refusals = [ "no backslash or # in the module or its arguments" ]; })
    (expect "polkit off: it keeps no password, so a reader-only sudo is warned of"
      { programs.h2s-shell.pam.sudo.rules = [ fingerprint ]; services.fprintd.enable = true; security.polkit.enable = lib.mkForce false; }
      { warnings = [ "You could lose access: programs.h2s-shell.pam: neither sudo nor polkit keep a password" ]; })
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
    (expect "a bracketed argument: refused (libpam hands the module the word inside)"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "[nouserok]" ]; } system ];
        security.pam.u2f.enable = true; }
      { refusals = [ "one word per argument" ]; })
    (expect "a tab inside an argument: refused"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "cue\tnouserok" ]; } system ];
        security.pam.u2f.enable = true; }
      { refusals = [ "one word per argument" ]; })
    (expect "pam_u2f with alwaysok: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "alwaysok" ]; } system ];
        security.pam.u2f.enable = true; }
      { warnings = [ "a line lets anyone in without a password (pam_u2f.so asks for no password" ]; })
    (expect "pam_u2f with userpresence=00: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "userpresence=00" ]; } system ];
        security.pam.u2f.enable = true; }
      { warnings = [ "a line lets anyone in without a password (pam_u2f.so asks for no password" ]; })
    (expect "pam_userdb with unknown_ok, required, without the system row: a warning"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "password"; } { method = "raw"; module = "pam_userdb.so"; control = "required"; args = [ "db=/etc/users" "unknown_ok" ]; } ]; }
      { warnings = [ "a line lets anyone in without a password (pam_userdb.so asks for no password" ]; })
    (expect "pam_userdb with UNKNOWN_OK in capitals: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_userdb.so"; args = [ "db=/etc/users" "UNKNOWN_OK" ]; } system ]; }
      { warnings = [ "a line lets anyone in without a password (pam_userdb.so asks for no password" ]; })
    (expect "pam_userdb with a second DB= outside /etc: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_userdb.so"; args = [ "db=/etc/users" "DB=/tmp/users" ]; } system ]; }
      { warnings = [ "a line lets anyone in without a password (pam_userdb.so asks for no password" ]; })
    (expect "pam_permit by a store path written out: a warning, judged by its name"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-linux-pam-1.7.2/lib/security/pam_permit.so"; } system ]; }
      { warnings = [ "a line lets anyone in without a password (pam_permit.so asks for no password" ]; })
    (expect "a copy of pam_permit in /etc: a warning, judged by its name"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/etc/pam_permit.so"; } system ]; }
      { warnings = [ "a line lets anyone in without a password (pam_permit.so asks for no password" ]; })
    (expect "a copy of pam_deny in /etc, required: a warning, nobody gets in"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/etc/pam_deny.so"; control = "required"; } system ]; }
      { warnings = [ "a line refuses everyone" ]; })
    (expect "a module the shell does not know: a warning"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "/run/current-system/sw/lib/security/pam_ldap.so"; } system ]; }
      { warnings = [ "the shell does not know pam_ldap.so" ]; })
    (expect "an optional password row: refused, optional is only for a raw row"
      { programs.h2s-shell.pam.rules = [ { method = "password"; control = "optional"; } system ]; }
      { refusals = [ "row 1 (password): optional is only for a raw row" ]; })
    (expect "an optional counted password row: refused, and it still evaluates"
      { programs.h2s-shell.pam.rules = [ { method = "password"; control = "optional"; counted = true; } system ];
        security.pam.services.sudo.logFailures = true; security.pam.services.polkit-1.logFailures = true; }
      { refusals = [ "row 1 (password): optional is only for a raw row" ]; })
    (expect "an optional fingerprint row: refused"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { control = "optional"; }) system ]; services.fprintd.enable = true; }
      { refusals = [ "row 1 (fingerprint): optional is only for a raw row" ]; })
    (expect "a raw optional line: allowed"
      { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "pam_env.so"; control = "optional"; } system ]; }
      { })
    (expect "an unknown module's required line without the system row: a warning naming it"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "password"; } { method = "raw"; module = "/run/current-system/sw/lib/security/pam_ldap.so"; control = "required"; } ]; }
      { warnings = [ "row 2 (raw): if pam_ldap.so answers that it does not apply to someone, the rules end without a refusal and let them in" ]; })
    (expect "… with the system row: no such warning"
      { programs.h2s-shell.pam.sudo.rules = [ { method = "raw"; module = "/run/current-system/sw/lib/security/pam_ldap.so"; control = "required"; } system ]; }
      { notWarnings = [ "does not apply to someone" ]; })
    (expect "a fingerprint with no time limit above the system row: a warning"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { timeout = -1; tries = -1; }) system ]; services.fprintd.enable = true; }
      { warnings = [ "row 1 (fingerprint): waits for the finger until it is touched or the prompt is cancelled" ]; })
    (expect "… with a time limit: no such warning"
      { programs.h2s-shell.pam.rules = [ (fingerprint // { timeout = 600; tries = 20; }) system ]; services.fprintd.enable = true; }
      { notWarnings = [ "waits for the finger" ]; })
    (expect "nothing set: no assertion, no warning of the shell's"
      { services.fprintd.enable = true; }
      { notWarnings = [ "h2s-shell" ]; })
  ];

  # The machine's settings that would let a key row pass without a key or a touch: kept as
  # they are, and warned about where the row's pass can let the user in
  keySafety =
    let
      keyRules = { programs.h2s-shell.pam.rules = [ { method = "securityKey"; } system ]; };
      withKey = rules: settings: rules // { security.pam.u2f = { enable = true; inherit settings; }; };
      keyLine = settings: lib.findFirst ours "" (authLines (configOf (withKey keyRules settings)) "sudo");
      kept = keyLine { nouserok = true; alwaysok = true; userpresence = 0; pinverification = 1; authfile = "/etc/u2f-keys"; };
      words = lib.splitString " " (normalized kept);
      requiredKey = { programs.h2s-shell.pam.rules = [ { method = "securityKey"; control = "required"; } { method = "password"; } ]; };
      requiredKeySystem = { programs.h2s-shell.pam.rules = [ { method = "securityKey"; control = "required"; } system ]; };
      requiredKeyPassword = { programs.h2s-shell.pam.rules = [ { method = "securityKey"; control = "required"; } { method = "password"; control = "required"; } ]; };
      lockSays = "the lock screen's security key unlocks without a key";
    in [
      (result (lib.all (word: lib.elem word words) [ "nouserok" "alwaysok" "userpresence=0" "pinverification=1" "authfile=/etc/u2f-keys" ])
        "the machine's u2f settings reach a key row as they are (nouserok, alwaysok, userpresence, pinverification)" kept)
      (expect "the machine's alwaysok beside a sufficient key row: a warning, no assertion"
        (withKey keyRules { alwaysok = true; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have alwaysok: this row lets anyone in without a key" lockSays ]; })
      (expect "the machine's userpresence = 0 beside a key row: a warning, no assertion"
        (withKey keyRules { userpresence = 0; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have userpresence = 0, which may turn the touch off: while a key is plugged in, any program can pass this row"
            "while a key is plugged in, the lock screen may unlock without a touch" ]; })
      (expect "… userpresence = \"00\": the same (pam_u2f reads 0)"
        (withKey keyRules { userpresence = "00"; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have userpresence = 0" ]; })
      (expect "… userpresence = 1: no warning"
        (withKey keyRules { userpresence = 1; })
        { notWarnings = [ "may turn the touch off" ]; })
      (expect "… userpresence = 2: no warning (the authenticator's default, which asks)"
        (withKey keyRules { userpresence = 2; })
        { notWarnings = [ "may turn the touch off" ]; })
      (expect "userpresence = 0 on a required key row above the system row: a warning (the touch may no longer be asked)"
        (withKey requiredKeySystem { userpresence = 0; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have userpresence = 0, which may turn the touch off: this row may no longer ask for a touch; only the other rows decide" ]; })
      (expect "the machine's nouserok beside a sufficient key row: no warning (a user without a key goes on to the next row)"
        (withKey keyRules { nouserok = true; })
        { notWarnings = [ "nouserok" ]; })
      (expect "… beside a required key row the permit closes: no warning (the row is written with ignore=bad: nouserok's PAM_IGNORE fails it)"
        (withKey requiredKey { nouserok = true; })
        { notWarnings = [ "nouserok" ]; })
      (expect "… beside a required key row above the system row: no warning"
        (withKey requiredKeySystem { nouserok = true; })
        { notWarnings = [ "nouserok" ]; })
      (expect "alwaysok on a required key row the permit closes: a warning (its pass keeps the result)"
        (withKey requiredKey { alwaysok = true; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have alwaysok" ]; })
      (expect "alwaysok on a required key row above the system row: a warning (two factors become one)"
        (withKey requiredKeySystem { alwaysok = true; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have alwaysok: this row no longer asks for a key; only the other rows decide" lockSays ]; })
      (expect "userpresence = 0 on two required key rows: each lets any program in without a touch (neither asks for one)"
        (withKey { programs.h2s-shell.pam.sudo.rules = [ { method = "securityKey"; control = "required"; } { method = "securityKey"; control = "required"; } ]; } { userpresence = 0; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have userpresence = 0, which may turn the touch off: while a key is plugged in, any program can pass this row"
            "row 2 (securityKey): the machine's security.pam.u2f.settings have userpresence = 0, which may turn the touch off: while a key is plugged in, any program can pass this row" ]; })
      (expect "alwaysok on a required key row beside a required password row the permit closes: no longer asks (the password still does)"
        (withKey requiredKeyPassword { alwaysok = true; })
        { warnings = [ "row 1 (securityKey): the machine's security.pam.u2f.settings have alwaysok: this row no longer asks for a key; only the other rows decide" ];
          notWarnings = [ "this row lets anyone in" ]; })
      (expect "a raw pam_u2f line with its own conf=: a warning that the file is not checked"
        { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "cue" "conf=/etc/u2f-other.conf" ]; } system ];
          security.pam.u2f.enable = true; }
        { warnings = [ "row 1 (raw): conf=/etc/u2f-other.conf: the options in it are not checked" ]; })
      (expect "… on an optional line (it decides nothing): no such warning"
        { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "cue" "conf=/etc/u2f-other.conf" ]; control = "optional"; } system ];
          security.pam.u2f.enable = true; }
        { notWarnings = [ "are not checked" ]; })
      (expect "a raw pam_u2f nouserok line required above the system row: a warning (a user without a key skips it)"
        { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "cue" "nouserok" ]; control = "required"; } system ];
          security.pam.u2f.enable = true; }
        { warnings = [ "row 1 (raw): with nouserok, alwaysok or userpresence=0 this line may not ask for a key or a touch; only the other rows decide" ]; })
      (expect "… without nouserok: no such warning"
        { programs.h2s-shell.pam.rules = [ { method = "raw"; module = "${pkgs.pam_u2f}/lib/security/pam_u2f.so"; args = [ "cue" ]; control = "required"; } system ];
          security.pam.u2f.enable = true; }
        { notWarnings = [ "may not ask for a key" ]; })
      (expect "security.pam.u2f.settings.conf set: a warning that its options are not checked"
        (withKey keyRules { conf = "/etc/u2f.conf"; })
        { warnings = [ "security.pam.u2f.settings.conf names /etc/u2f.conf: the options in it are not checked" ]; })
      (expect "… not set: no such warning"
        (withKey keyRules { })
        { notWarnings = [ "are not checked" ]; })
      (expect "alwaysok without any key row: the lock screen's warning alone"
        (withKey { } { alwaysok = true; })
        { warnings = [ lockSays ]; notWarnings = [ "row 1" ]; })
      (expect "alwaysok with security.pam.u2f off: no lock screen warning (it has no key check)"
        { security.pam.u2f.settings.alwaysok = true; }
        { notWarnings = [ lockSays ]; })
      (expect "a u2f setting with a line break: refused"
        (keyRules // { security.pam.u2f = { enable = true; settings.authfile = "/etc/keys\nauth sufficient pam_permit.so"; }; })
        { refusals = [ "security.pam.u2f.settings: authfile is not a plain option name, or holds a tab or a line break" ]; })
      (expect "a u2f setting with a tab: refused (libpam would split it into two arguments)"
        (keyRules // { security.pam.u2f = { enable = true; settings.authfile = "/etc/keys\tnouserok"; }; })
        { refusals = [ "security.pam.u2f.settings: authfile is not" ]; })
      (expect "a u2f setting named as an argument with its value: refused"
        (keyRules // { security.pam.u2f = { enable = true; settings."userpresence=0" = true; }; })
        { refusals = [ "security.pam.u2f.settings: userpresence=0 is not" ]; })
      (expect "a u2f setting set true whose name holds a line break: refused"
        (keyRules // { security.pam.u2f = { enable = true; settings."cue\nauth" = true; }; })
        { refusals = [ "is not a plain option name" ]; })
    ];

  # The machine's pam_u2f settings on a key row, as the lock screen takes them: authfile and
  # appid there, `cue` always; `interactive` kept on the row, left out (and said) on the lock
  # screen; with them left out, the editor's line
  u2fSettings =
    let
      config = configOf {
        programs.h2s-shell.pam.rules = [ { method = "securityKey"; pin = true; } system ];
        security.pam.u2f = { enable = true; settings = { authfile = "/etc/u2f-keys"; appid = "pam://machine"; interactive = true; cue = false; }; };
      };
      line = lib.findFirst ours "" (authLines config "sudo");
      words = lib.filter (word: word != "") (lib.splitString " " (normalized line));
      settings = [ "authfile=/etc/u2f-keys" "appid=pam://machine" ];
      without = lib.concatStringsSep " " (lib.filter (word: !(lib.elem word (settings ++ [ "interactive" ]))) words);
      lockText = config.security.pam.services.h2s-shell-u2f.text;
      lock = lib.filter (text: lib.hasInfix "pam_u2f.so" text) (lib.splitString "\n" lockText);
    in [
      (result (lib.all (word: lib.elem word words) settings) "a key row takes the machine's u2f settings (authfile, appid)" line)
      (result (lib.elem "cue" words && lib.elem "interactive" words) "… always cue, interactive as the machine has it" line)
      (result (lock != [ ] && !(lib.hasInfix "interactive" (lib.head lock))
          && lib.hasInfix "# interactive is left out here: the lock screen cannot answer its Enter prompt" lockText)
        "… the lock screen's leaves interactive out, and says so in the file" (builtins.toJSON lockText))
      (result (without == "auth sufficient pam_u2f.so cue pinverification=1") "… without them, the editor's line" without)
      (result (lock != [ ] && lib.all (word: lib.hasInfix word (lib.head lock)) settings) "… as the lock screen's key check has them" (builtins.toJSON lock))
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
lib.concatStringsSep "\n" (lib.concatMap caseResults cases ++ checks ++ u2fSettings ++ keySafety ++ untouched) + "\n"
