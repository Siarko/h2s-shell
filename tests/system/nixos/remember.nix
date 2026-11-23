# Evaluated by tests/system/nixos/remember.sh: the flake's programs.h2s-shell.polkit.rememberAdmin
# for a set of minimal systems, not built. → a line "count\t<n>\t" (how many follow), then
# lines "<ok|bad>\t<description>\t<detail>".
#
# The case set (tests/fixtures/remember-nixos/cases.json; tests/RememberNixosModuleTest.qml
# checks it against RememberRules), each with the package's coreutils set to the case's:
# polkit's rules file holds each expected rule as whole lines, and no other of the shell's;
# polkitd.conf is the expected text, or absent, and its text reloads polkit. Then the real
# package: the rule names the coreutils whose timeout its command puts first on PATH. Then
# the assertions and warnings, and the shell's rules before the machine's own.
{ repo }:
let
  flake = builtins.getFlake "path:${repo}";
  lib = flake.inputs.nixpkgs.lib;
  fixture = builtins.fromJSON (builtins.readFile "${repo}/tests/fixtures/remember-nixos/cases.json");
  package = flake.packages.x86_64-linux.default;
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;

  base = {
    programs.h2s-shell.enable = true;
    boot.loader.grub.enable = false;
    # The least a system evaluates with: modules read the type of the root filesystem
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    system.stateVersion = "26.05";
    security.polkit.enable = true;
  };
  configOf = extra: (lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.nixosModules.default base extra ];
  }).config;
  plain = builtins.unsafeDiscardStringContext;
  rulesOf = config: plain config.environment.etc."polkit-1/rules.d/10-nixos.rules".text;
  confOf = config: if config.environment.etc ? "polkit-1/polkitd.conf" then plain config.environment.etc."polkit-1/polkitd.conf".text else "";
  triggers = config: map (trigger: plain (toString trigger)) config.systemd.services.polkit.reloadTriggers;
  headers = text: lib.length (lib.filter (line: lib.hasPrefix "// Written by h2s-shell" line) (lib.splitString "\n" text));
  failedOf = config: map (assertion: assertion.message) (lib.filter (assertion: !assertion.assertion) config.assertions);

  result = ok: description: detail: "${if ok then "ok" else "bad"}\t${description}\t${detail}";

  caseResults = testCase:
    let
      config = configOf {
        programs.h2s-shell.package = package // { coreutils = fixture.coreutils; };
        programs.h2s-shell.polkit.rememberAdmin = { enable = true; inherit (testCase) users minutes; };
      };
      rules = rulesOf config;
      conf = confOf config;
      missing = lib.filter (rule: !(lib.hasInfix "\n${rule}" rules)) testCase.rules;
    in [
      (result (missing == [ ]) "${testCase.name}: polkit's rules file holds RememberRules' rule for each user" "missing ${builtins.toJSON missing} in ${builtins.toJSON rules}")
      (result (headers rules == lib.length testCase.rules) "${testCase.name}: … and no other rule of the shell's" "${toString (headers rules)} headers")
      (result (conf == testCase.conf) "${testCase.name}: polkitd.conf is ${if testCase.conf == "" then "absent" else "RememberRules' conf"}" (builtins.toJSON conf))
      (result ((testCase.conf == "") || lib.elem testCase.conf (triggers config)) "${testCase.name}: a change of the conf reloads polkit" (builtins.toJSON (triggers config)))
      (result (failedOf config == [ ]) "${testCase.name}: no assertion fails" (builtins.toJSON (failedOf config)))
    ];

  # The real package: its coreutils is the one its command puts first on PATH among those
  # with a timeout (none of the programs before it has one), and the rule names it
  real =
    let
      config = configOf { programs.h2s-shell.polkit.rememberAdmin = { enable = true; users = [ "alex" ]; }; };
      coreutils = plain package.coreutils.outPath;
      rules = rulesOf config;
      pathLine = lib.findFirst (line: lib.hasPrefix "export PATH=" line) "" (lib.splitString "\n" (plain package.installPhase));
      entries = lib.splitString ":" (lib.removePrefix "export PATH=\"" (lib.head (lib.splitString ":\\$PATH" pathLine)));
      firstCoreutils = lib.findFirst (entry: lib.hasInfix "-coreutils-" entry) "" entries;
    in [
      (result (firstCoreutils == "${coreutils}/bin") "the package's command puts its own coreutils on PATH first" "${firstCoreutils} vs ${coreutils}")
      (result (lib.hasInfix "action.lookup(\"program\") == \"${coreutils}/bin/coreutils\"" rules
               && lib.hasInfix "indexOf(\"${coreutils}/bin/timeout \") == 0" rules)
        "the default package's rule names its coreutils: the program and the command line's timeout" (builtins.toJSON rules))
      (result (confOf config == "") "the default minutes: no polkitd.conf" "")
    ];

  warned = description: options: expected:
    let warnings = (configOf options).warnings;
    in result (lib.any (message: lib.hasInfix expected message) warnings) description (builtins.toJSON warnings);
  refused = description: options: expected:
    let failed = failedOf (configOf options);
    in result (lib.any (message: lib.hasInfix expected message) failed) description (builtins.toJSON failed);
  remember = settings: { programs.h2s-shell.polkit.rememberAdmin = { enable = true; users = [ "alex" ]; } // settings; };

  checks = map (user: refused "the user name ${builtins.toJSON user} is refused" (remember { users = [ user ]; }) "is not a user name") fixture.invalidUsers ++ [
    (refused "no users: refused" (remember { users = [ ]; }) "rememberAdmin.users is empty")
    (refused "0 minutes: refused" (remember { minutes = 0; }) "rememberAdmin.minutes is 0")
    (refused "61 minutes: refused" (remember { minutes = 61; }) "rememberAdmin.minutes is 61")
    (refused "polkit off: refused" { imports = [ (remember { }) ]; security.polkit.enable = lib.mkForce false; } "needs security.polkit.enable")
    (refused "the shell off: refused" { imports = [ (remember { }) ]; programs.h2s-shell.enable = lib.mkForce false; } "needs programs.h2s-shell.enable")
    (refused "polkitd.conf's text set elsewhere beside 15 minutes: refused, naming the file and minutes"
      { imports = [ (remember { minutes = 15; }) ]; environment.etc."polkit-1/polkitd.conf".text = "[Polkitd]\nExpirationSeconds=60\n"; }
      "rememberAdmin.minutes = 15 sets /etc/polkit-1/polkitd.conf")
    (refused "polkitd.conf's source set elsewhere beside 15 minutes: refused"
      { imports = [ (remember { minutes = 15; }) ]; environment.etc."polkit-1/polkitd.conf".source = pkgs.writeText "polkitd.conf" "[Polkitd]\n"; }
      "is also set elsewhere in the configuration")
    (let config = configOf { imports = [ (remember { }) ]; environment.etc."polkit-1/polkitd.conf".text = "[Polkitd]\nExpirationSeconds=60\n"; };
     in result (failedOf config == [ ]) "polkitd.conf set elsewhere beside the default minutes: allowed (the module writes none)" (builtins.toJSON (failedOf config)))
    (warned "a package without coreutils in its passthru: a warning"
      { imports = [ (remember { }) ]; programs.h2s-shell.package = builtins.removeAttrs package [ "coreutils" ]; }
      "has no `coreutils` in its passthru")
    (let config = configOf (remember { });
     in result (!(lib.any (lib.hasInfix "rememberAdmin") config.warnings)) "the flake's package: no warning" (builtins.toJSON config.warnings))
    (let
       config = configOf (remember { } // { security.polkit.extraConfig = "// the machine's own\n"; });
       rules = rulesOf config;
       before = lib.head (lib.splitString "// the machine's own" rules);
     in result (lib.hasInfix "// the machine's own" rules && lib.hasInfix "// Written by h2s-shell" before) "the shell's rules come before the machine's own extraConfig" (builtins.toJSON rules))
    (let config = configOf { };
     in result (headers (rulesOf config) == 0 && confOf config == "" && failedOf config == [ ]) "nothing set: no rule, no conf" (builtins.toJSON (rulesOf config)))
    (let config = configOf { programs.h2s-shell.polkit.rememberAdmin = { users = [ "alex" ]; minutes = 30; }; };
     in result (headers (rulesOf config) == 0 && confOf config == "") "not enabled: no rule, no conf, whatever else is set" (builtins.toJSON (rulesOf config)))
  ];
in
let lines = lib.concatMap caseResults fixture.cases ++ real ++ checks;
in lib.concatStringsSep "\n" ([ "count\t${toString (lib.length lines)}\t" ] ++ lines) + "\n"
