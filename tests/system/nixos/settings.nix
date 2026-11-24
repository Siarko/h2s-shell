# Evaluated by tests/system/nixos/settings.sh: the flake's programs.h2s-shell.settingsFile
# (nix/settings.nix) for a set of minimal systems, not built. → a line "count\t<n>\t" (how
# many follow), then lines "<ok|bad>\t<description>\t<detail>".
#
# The fixture (tests/fixtures/settings-nixos/settings.json) gives the same options and the
# same /etc files as the same values written as options by hand, and publishes what it took
# in as /etc/h2s-shell/settings.json; a plain definition wins over the file's value; without
# the file nothing changes and nothing is published. Then the refusals (a wrong version or
# value: an assertion naming the version or the key) and the warnings (a key the module does
# not know: ignored, the rest still taken).
{ repo }:
let
  flake = builtins.getFlake "path:${repo}";
  lib = flake.inputs.nixpkgs.lib;
  fixturePath = /. + "${repo}/tests/fixtures/settings-nixos/settings.json";
  fixture = builtins.fromJSON (builtins.readFile fixturePath);

  base = {
    programs.h2s-shell.enable = true;
    boot.loader.grub.enable = false;
    # The least a system evaluates with: modules read the type of the root filesystem
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    system.stateVersion = "26.05";
    security.polkit.enable = true;
    # The fixture's fingerprint rows need a reader
    services.fprintd.enable = true;
  };
  configOf = extra: (lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.nixosModules.default base extra ];
  }).config;
  plain = builtins.unsafeDiscardStringContext;
  fileOf = data: builtins.toFile "h2s-shell.json" (builtins.toJSON data);
  withFile = data: { programs.h2s-shell.settingsFile = fileOf data; };
  failedOf = config: map (assertion: assertion.message) (lib.filter (assertion: !assertion.assertion) config.assertions);
  ourWarnings = config: lib.filter (lib.hasInfix "programs.h2s-shell.settingsFile") config.warnings;

  result = ok: description: detail: "${if ok then "ok" else "bad"}\t${description}\t${detail}";

  # The /etc files the mapped options write, as text
  etcText = config: name:
    if config.environment.etc ? ${name} then plain config.environment.etc.${name}.text else "<absent>";
  pamText = config: service: plain config.security.pam.services.${service}.text;
  etcNames = [ "systemd/sleep.conf" "polkit-1/rules.d/10-nixos.rules" "polkit-1/polkitd.conf" ];
  options = config: {
    inherit (config.programs.h2s-shell.idle) hibernateDelay;
    rules = config.programs.h2s-shell.pam.rules;
    sudoRules = config.programs.h2s-shell.pam.sudo.rules;
    polkitRules = config.programs.h2s-shell.pam.polkit.rules;
    inherit (config.programs.h2s-shell.polkit.rememberAdmin) enable users minutes;
  };
  data = value:
    if builtins.isAttrs value then lib.mapAttrs (_: data) (builtins.removeAttrs value [ "_module" ])
    else if builtins.isList value then map data value
    else value;
  shown = value: builtins.toJSON (data value);

  fromFile = configOf { programs.h2s-shell.settingsFile = fixturePath; };
  byHand = configOf {
    programs.h2s-shell = {
      idle.hibernateDelay = "3h";
      pam.rules = [
        { method = "fingerprint"; control = "sufficient"; timeout = 10; tries = 3; }
        { method = "system"; }
      ];
      pam.polkit.rules = [
        { method = "password"; control = "sufficient"; }
        { method = "fingerprint"; control = "sufficient"; timeout = -1; }
        { method = "system"; }
      ];
      polkit.rememberAdmin = { enable = true; users = [ "alex" ]; minutes = 15; };
    };
  };
  without = configOf { };
  published = builtins.fromJSON (etcText fromFile "h2s-shell/settings.json");

  equivalence = [
    (result (shown (options fromFile) == shown (options byHand)) "the fixture gives the same options as the same values written by hand"
      "${shown (options fromFile)} vs ${shown (options byHand)}")
    (result (failedOf fromFile == [ ] && ourWarnings fromFile == [ ]) "the fixture: no assertion fails, no warning of the file's" (builtins.toJSON (failedOf fromFile ++ ourWarnings fromFile)))
  ] ++ map (service:
    result (pamText fromFile service == pamText byHand service) "the fixture: ${service}'s PAM file is the hand-written options'" (builtins.toJSON (pamText fromFile service))
  ) [ "sudo" "polkit-1" ] ++ map (name:
    result (etcText fromFile name == etcText byHand name && etcText fromFile name != "<absent>")
      "the fixture: /etc/${name} is the hand-written options'" (builtins.toJSON (etcText fromFile name))
  ) etcNames ++ [
    (result (lib.hasInfix "HibernateDelaySec=3h" (etcText fromFile "systemd/sleep.conf")) "the fixture: HibernateDelaySec=3h in sleep.conf" "")
    (result (published.version or null == 1) "/etc/h2s-shell/settings.json has the schema version" (builtins.toJSON published))
    (result (published.settings or null == builtins.removeAttrs fixture [ "version" ]) "… and what the file gave, as it gave it" (builtins.toJSON (published.settings or null)))
    (result ((published.inForce.idle.hibernateDelay or null) == "3h" && (published.inForce.polkit.rememberAdmin.minutes or null) == 15
             && (lib.head (published.inForce.pam.rules or [ { } ])).timeout or null == 10)
      "… and the options in force" (builtins.toJSON (published.inForce or null)))
    (result (etcText byHand "h2s-shell/settings.json" == "<absent>") "no settingsFile: /etc/h2s-shell/settings.json is absent" "")
    (result (shown (options without) == shown (options (configOf { programs.h2s-shell.settingsFile = null; })))
      "settingsFile = null: the options are as without it" "")
    (result (options without == { hibernateDelay = null; rules = null; sudoRules = null; polkitRules = null; enable = false; users = [ ]; minutes = 5; })
      "… the options' own defaults" (shown (options without)))
    (result (lib.all (name: etcText without name == etcText (configOf { programs.h2s-shell.settingsFile = null; }) name) (etcNames ++ [ "h2s-shell/settings.json" ]))
      "… and the same /etc files" "")
  ];

  # A plain definition beside the file wins, and nothing clashes
  overridden = configOf {
    programs.h2s-shell.settingsFile = fixturePath;
    programs.h2s-shell.idle.hibernateDelay = "10min";
    programs.h2s-shell.polkit.rememberAdmin.minutes = 30;
    programs.h2s-shell.pam.rules = [ { method = "password"; } { method = "system"; } ];
  };
  overrides = [
    (result (overridden.programs.h2s-shell.idle.hibernateDelay == "10min" && lib.hasInfix "HibernateDelaySec=10min" (etcText overridden "systemd/sleep.conf"))
      "a hand-written hibernateDelay wins over the file's" (builtins.toJSON (etcText overridden "systemd/sleep.conf")))
    (result (overridden.programs.h2s-shell.polkit.rememberAdmin.minutes == 30 && overridden.programs.h2s-shell.polkit.rememberAdmin.users == [ "alex" ])
      "a hand-written minutes wins; the file's users stay" (shown overridden.programs.h2s-shell.polkit.rememberAdmin))
    (result (map (row: row.method) overridden.programs.h2s-shell.pam.rules == [ "password" "system" ]) "hand-written pam.rules win over the file's" (shown overridden.programs.h2s-shell.pam.rules))
    (result (failedOf overridden == [ ]) "… and evaluation succeeds" (builtins.toJSON (failedOf overridden)))
    (let p = builtins.fromJSON (etcText overridden "h2s-shell/settings.json");
     in result (p.settings.idle.hibernateDelay == "3h" && p.inForce.idle.hibernateDelay == "10min")
       "the published file tells the file's value from the one in force" (builtins.toJSON p))
  ];

  refused = description: settings: expected:
    let failed = failedOf (configOf (withFile settings));
    in result (lib.any (message: lib.hasInfix expected message && lib.hasInfix "programs.h2s-shell.settingsFile" message) failed)
      description (builtins.toJSON failed);
  v1 = settings: { version = 1; } // settings;
  row = fields: v1 { pam.rules = [ fields { method = "system"; } ]; };
  refusals = [
    (refused "version 2: refused, naming the version" { version = 2; } "schema version is 2")
    (refused "version \"1\" (a string): refused" { version = "1"; } "schema version is \"1\"")
    (refused "no version: refused" { idle.hibernateDelay = "3h"; } "has no \"version\"")
    (refused "not an object: refused" [ 1 ] "not a JSON object")
    (refused "hibernateDelay true: refused, naming the key" (v1 { idle.hibernateDelay = true; }) "\"idle.hibernateDelay\": true is not")
    (refused "hibernateDelay 0: refused" (v1 { idle.hibernateDelay = 0; }) "\"idle.hibernateDelay\"")
    (refused "hibernateDelay with a line break: refused" (v1 { idle.hibernateDelay = "3h\nHibernateMode=x"; }) "is not a systemd time span")
    (refused "hibernateDelay \"soon\": refused" (v1 { idle.hibernateDelay = "soon"; }) "is not a systemd time span")
    (refused "idle as a string: refused" (v1 { idle = "3h"; }) "the key \"idle\" is \"3h\", not an object")
    (refused "minutes 0: refused, naming the key" (v1 { polkit.rememberAdmin.minutes = 0; }) "\"polkit.rememberAdmin.minutes\": 0 is not 1–60")
    (refused "minutes 61: refused" (v1 { polkit.rememberAdmin.minutes = 61; }) "\"polkit.rememberAdmin.minutes\": 61 is not 1–60")
    (refused "minutes 1.5: refused" (v1 { polkit.rememberAdmin.minutes = 1.5; }) "\"polkit.rememberAdmin.minutes\": 1.5 is not")
    (refused "users [1]: refused" (v1 { polkit.rememberAdmin.users = [ 1 ]; }) "\"polkit.rememberAdmin.users\": [1] is not")
    (refused "enable \"yes\": refused" (v1 { polkit.rememberAdmin.enable = "yes"; }) "\"polkit.rememberAdmin.enable\": \"yes\" is not")
    (refused "pam.rules an object: refused" (v1 { pam.rules = { method = "system"; }; }) "\"pam.rules\": {\"method\":\"system\"} is not a list of rows")
    (refused "a row not an object: refused" (v1 { pam.rules = [ "system" ]; }) "\"pam.rules\": row 0 is \"system\", not an object")
    (refused "a row without a method: refused" (row { control = "sufficient"; }) "row 0 has no \"method\"")
    (refused "a row of an unknown method: refused" (row { method = "face"; }) "row 0, \"method\": \"face\" is not")
    (refused "a row with an unknown field: refused" (row { method = "password"; strength = 3; }) "row 0 has the field \"strength\"")
    (refused "a fingerprint timeout of 900: refused" (row { method = "fingerprint"; timeout = 900; }) "row 0, \"timeout\": 900 is not")
    (refused "a raw row's args not strings: refused" (v1 { pam.sudo.rules = [ { method = "raw"; module = "pam_env.so"; args = [ 1 ]; } { method = "system"; } ]; }) "\"pam.sudo.rules\": row 0, \"args\": [1] is not")
    (let config = configOf (withFile { version = 2; idle.hibernateDelay = "3h"; });
     in result (config.programs.h2s-shell.idle.hibernateDelay == null) "a wrong version: none of the file's values is taken" "")
    (let config = configOf (withFile (v1 { idle.hibernateDelay = true; polkit.rememberAdmin.minutes = 15; }));
     in result (config.programs.h2s-shell.idle.hibernateDelay == null) "a wrong value is never handed to its option" "")
  ];
  # The optional fingerprint row reaches pam.nix's own assertion, which names its option
  optionalRow =
    let failed = failedOf (configOf (withFile (row { method = "fingerprint"; control = "optional"; })));
    in result (lib.any (lib.hasInfix "programs.h2s-shell.pam.rules") failed) "a valid row pam.nix refuses: pam.nix's assertion, naming the option" (builtins.toJSON failed);

  unknown = configOf (withFile (v1 { idle.hibernateDelay = "2h"; future = { thing = 1; }; pam.bogus = true; polkit.rememberAdmin.later = 1; }));
  warnings = [
    (result (lib.any (lib.hasInfix "the key \"future\" is not one") (ourWarnings unknown)) "an unknown top-level key: a warning naming it" (builtins.toJSON (ourWarnings unknown)))
    (result (lib.any (lib.hasInfix "the key \"pam.bogus\"") (ourWarnings unknown)) "an unknown key under pam: a warning naming it" "")
    (result (lib.any (lib.hasInfix "the key \"polkit.rememberAdmin.later\"") (ourWarnings unknown)) "an unknown key under polkit.rememberAdmin: a warning naming it" "")
    (result (failedOf unknown == [ ] && unknown.programs.h2s-shell.idle.hibernateDelay == "2h") "… evaluation succeeds and the known keys are taken" (builtins.toJSON (failedOf unknown)))
    (result (!(lib.hasInfix "future" (etcText unknown "h2s-shell/settings.json"))) "… and the published file leaves the unknown out" (builtins.toJSON (etcText unknown "h2s-shell/settings.json")))
  ];
in
let lines = equivalence ++ overrides ++ refusals ++ [ optionalRow ] ++ warnings;
in lib.concatStringsSep "\n" ([ "count\t${toString (lib.length lines)}\t" ] ++ lines) + "\n"
