# Evaluated by tests/system/nixos/settings.sh: the flake's programs.h2s-shell.settingsFile
# (nix/settings.nix) for a set of minimal systems, not built. → a line "count\t<n>\t" (how
# many follow), then lines "<ok|bad>\t<description>\t<detail>".
#
# The fixture (tests/fixtures/settings-nixos/settings.json) gives the same options and the
# same /etc files as the same values written as options by hand, and publishes what it took
# in as /etc/h2s-shell/settings.json; a definition of the configuration's own, plain or at
# mkDefault, wins alone over the file's value, and sudo's and polkit's rules are one unit; the
# configuration's own systemd HibernateDelaySec wins over the file's hibernateDelay without a
# clash, and the published file holds both;
# without the file, or with the shell off, nothing is read and nothing is published. Then the refusals (a wrong version or
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
    (result (lib.attrNames (published.settings or { }) == lib.attrNames (builtins.removeAttrs fixture [ "version" ])
             && (published.settings.idle or null) == fixture.idle && (published.settings.polkit or null) == fixture.polkit)
      "… and what the file gave" (builtins.toJSON (published.settings or null)))
    (result (lib.all (key: (published.settings.${key} or null) == (published.inForce.${key} or { })) [ "idle" "polkit" ]
             && (published.settings.pam.rules or null) == (published.inForce.pam.rules or { })
             && (published.settings.pam.polkit.rules or null) == (published.inForce.pam.polkit.rules or { }))
      "… its rows with every field, as the options in force hold them" (builtins.toJSON published))
    (result ((published.inForce.idle.hibernateDelay or null) == "3h" && (published.inForce.polkit.rememberAdmin.minutes or null) == 15
             && (lib.head (published.inForce.pam.rules or [ { } ])).timeout or null == 10)
      "… and the options in force" (builtins.toJSON (published.inForce or null)))
    (result (etcText byHand "h2s-shell/settings.json" == "<absent>") "no settingsFile: /etc/h2s-shell/settings.json is absent" "")
    (result (options without == { hibernateDelay = null; rules = null; sudoRules = null; polkitRules = null; enable = false; users = [ ]; minutes = 5; })
      "… the options' own defaults" (shown (options without)))
    (result (ourWarnings without == [ ] && failedOf without == [ ] && etcText without "h2s-shell/settings.json" == "<absent>")
      "… no warning or assertion of the file's, nothing published" (builtins.toJSON (ourWarnings without)))
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
    (result (overridden.programs.h2s-shell.pam.polkit.rules == null)
      "… and the file's pam.polkit.rules are not taken beside them" (shown overridden.programs.h2s-shell.pam.polkit.rules))
    (result (lib.any (message: lib.hasInfix "\"pam.rules\", \"pam.polkit.rules\" are not taken" message && lib.hasInfix "sets programs.h2s-shell.pam.rules itself" message) (ourWarnings overridden))
      "… a warning names the file's keys and the configuration's option" (builtins.toJSON (ourWarnings overridden)))
    (let p = builtins.fromJSON (etcText overridden "h2s-shell/settings.json");
     in result (p.settings.idle.hibernateDelay == "3h" && p.inForce.idle.hibernateDelay == "10min")
       "the published file tells the file's value from the one in force" (builtins.toJSON p))
  ];

  # A definition of the configuration's own at mkDefault (a profile's) wins alone too: no
  # merge of lists, no clash of single values
  defaulted = configOf {
    programs.h2s-shell.settingsFile = fixturePath;
    programs.h2s-shell.idle.hibernateDelay = lib.mkDefault "10min";
    programs.h2s-shell.polkit.rememberAdmin.users = lib.mkDefault [ "kim" ];
    programs.h2s-shell.pam.rules = lib.mkDefault [ { method = "password"; } { method = "system"; } ];
  };
  # The rules as one unit: the file's split rows beside the configuration's own pam.rules,
  # and the configuration's own sudo or polkit rules beside the file's pam.rules
  split = fileOf { version = 1; pam.sudo.rules = [ { method = "fingerprint"; } { method = "system"; } ]; pam.polkit.rules = [ { method = "password"; } { method = "system"; } ]; };
  splitBeside = configOf { programs.h2s-shell.settingsFile = split; programs.h2s-shell.pam.rules = [ { method = "password"; } { method = "system"; } ]; };
  sudoOwn = configOf { imports = [ (withFile { version = 1; pam.rules = [ { method = "fingerprint"; } { method = "system"; } ]; }) ]; programs.h2s-shell.pam.sudo.rules = [ { method = "password"; } { method = "system"; } ]; };
  polkitOwn = configOf { imports = [ (withFile { version = 1; pam.rules = [ { method = "fingerprint"; } { method = "system"; } ]; }) ]; programs.h2s-shell.pam.polkit.rules = lib.mkDefault [ { method = "password"; } { method = "system"; } ]; };
  methods = rows: if rows == null then null else map (row: row.method) rows;
  pamOf = config: { rules = methods config.programs.h2s-shell.pam.rules; sudo = methods config.programs.h2s-shell.pam.sudo.rules; polkit = methods config.programs.h2s-shell.pam.polkit.rules; };
  units = [
    (result (defaulted.programs.h2s-shell.idle.hibernateDelay == "10min") "the configuration's mkDefault hibernateDelay wins alone, no clash" "")
    (result (defaulted.programs.h2s-shell.polkit.rememberAdmin.users == [ "kim" ]) "the configuration's mkDefault users win alone, not merged with the file's" (builtins.toJSON defaulted.programs.h2s-shell.polkit.rememberAdmin.users))
    (result (methods defaulted.programs.h2s-shell.pam.rules == [ "password" "system" ]) "the configuration's mkDefault pam.rules win alone, not merged with the file's rows" (builtins.toJSON (pamOf defaulted)))
    (result (failedOf defaulted == [ ]) "… and evaluation succeeds" (builtins.toJSON (failedOf defaulted)))
    (result (pamOf splitBeside == { rules = [ "password" "system" ]; sudo = null; polkit = null; }) "the file's sudo and polkit rules beside the configuration's pam.rules: none taken" (builtins.toJSON (pamOf splitBeside)))
    (result (lib.any (lib.hasInfix "\"pam.sudo.rules\", \"pam.polkit.rules\" are not taken") (ourWarnings splitBeside)) "… a warning names them" (builtins.toJSON (ourWarnings splitBeside)))
    (result (pamOf sudoOwn == { rules = null; sudo = [ "password" "system" ]; polkit = null; }) "the configuration's sudo rules beside the file's pam.rules: the file's not taken (polkit stays NixOS's)" (builtins.toJSON (pamOf sudoOwn)))
    (result (lib.any (lib.hasInfix "sets programs.h2s-shell.pam.sudo.rules itself") (ourWarnings sudoOwn)) "… a warning names the configuration's option" (builtins.toJSON (ourWarnings sudoOwn)))
    (result (pamOf polkitOwn == { rules = null; sudo = null; polkit = [ "password" "system" ]; }) "the configuration's mkDefault polkit rules beside the file's pam.rules: the file's not taken" (builtins.toJSON (pamOf polkitOwn)))
    (result (failedOf sudoOwn == [ ] && failedOf polkitOwn == [ ] && failedOf splitBeside == [ ]) "… and evaluation succeeds" "")
    (let config = configOf (withFile { version = 1; pam.sudo.rules = [ { method = "password"; } { method = "system"; } ]; });
     in result (pamOf config == { rules = null; sudo = [ "password" "system" ]; polkit = null; } && ourWarnings config == [ ]) "the file's own sudo rules alone: taken, no warning" (builtins.toJSON (pamOf config)))
  ];

  # The configuration's own HibernateDelaySec beside the file's hibernateDelay (the owner's
  # shape): it wins, nothing clashes, and the published file tells the two apart
  collidedOf = own: configOf { programs.h2s-shell.settingsFile = fixturePath; systemd.sleep.settings.Sleep.HibernateDelaySec = own; };
  collided = collidedOf "10min";
  collidedDefault = collidedOf (lib.mkDefault "10min");
  collidedPublished = builtins.fromJSON (etcText collided "h2s-shell/settings.json");
  # … and beside the shell's own option written by hand: the configuration's systemd line wins too
  collidedOption = configOf { programs.h2s-shell.idle.hibernateDelay = "3h"; systemd.sleep.settings.Sleep.HibernateDelaySec = "10min"; };
  collisions = [
    (result (lib.hasInfix "HibernateDelaySec=10min" (etcText collided "systemd/sleep.conf") && !(lib.hasInfix "HibernateDelaySec=3h" (etcText collided "systemd/sleep.conf")))
      "the configuration's own HibernateDelaySec beside the file's: it wins, no conflicting definitions" (builtins.toJSON (etcText collided "systemd/sleep.conf")))
    (result (failedOf collided == [ ]) "… and evaluation succeeds" (builtins.toJSON (failedOf collided)))
    (result (collidedPublished.settings.idle.hibernateDelay or null == "3h" && collidedPublished.system.idle.hibernateDelay or null == "10min")
      "… the published file has the file's value and the system's merged one" (builtins.toJSON collidedPublished))
    (result (lib.hasInfix "HibernateDelaySec=10min" (etcText collidedDefault "systemd/sleep.conf"))
      "the configuration's own HibernateDelaySec at mkDefault beside the file's: it wins too" (builtins.toJSON (etcText collidedDefault "systemd/sleep.conf")))
    (result (lib.hasInfix "HibernateDelaySec=10min" (etcText collidedOption "systemd/sleep.conf"))
      "the configuration's own HibernateDelaySec beside a hand-written idle.hibernateDelay: it wins, no clash" (builtins.toJSON (etcText collidedOption "systemd/sleep.conf")))
    (result ((published.system.idle.hibernateDelay or null) == "3h")
      "the file's hibernateDelay alone: the published system value is it" (builtins.toJSON (published.system or null)))
    (let p = builtins.fromJSON (etcText (configOf (withFile { version = 1; })) "h2s-shell/settings.json");
     in result (p ? system && p.system.idle.hibernateDelay == null) "no hibernateDelay anywhere: the published system value is null" (builtins.toJSON p))
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
     in result (config.programs.h2s-shell.idle.hibernateDelay == null && config.programs.h2s-shell.polkit.rememberAdmin.minutes == 15)
       "a wrong value is never handed to its option; the valid one beside it is" "")
    (refused "a user name rememberAdmin refuses: refused, naming the key" (v1 { polkit.rememberAdmin.users = [ "alex" "-x" ]; }) "\"polkit.rememberAdmin.users\": \"-x\" is not a user name")
    (let failed = failedOf (configOf { programs.h2s-shell.settingsFile = /. + "/nonexistent-h2s-shell/h2s-shell.json"; });
     in result (lib.any (message: lib.hasInfix "programs.h2s-shell.settingsFile" message && lib.hasInfix "does not exist" message && lib.hasInfix "git add" message) failed)
       "a file that does not exist: refused, naming the option and git add" (builtins.toJSON failed))
    (let config = configOf { imports = [ (withFile { version = 2; }) ]; programs.h2s-shell.enable = lib.mkForce false; };
     in result (failedOf config == [ ] && etcText config "h2s-shell/settings.json" == "<absent>")
       "the shell not enabled: the file is not read, nothing published" (builtins.toJSON (failedOf config)))
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
let lines = equivalence ++ overrides ++ units ++ collisions ++ refusals ++ [ optionalRow ] ++ warnings;
in lib.concatStringsSep "\n" ([ "count\t${toString (lib.length lines)}\t" ] ++ lines) + "\n"
