# A remembered administrator authorization, as an option of the shell's module: polkit's
# rules and polkitd.conf are generated on NixOS, so the shell names this option (Settings,
# with Copy) instead of writing them. A polkit rule makes the shell's own root runs —
# `pkexec <timeout> …`, action org.freedesktop.policykit.exec — AUTH_ADMIN_KEEP for the
# listed users, so polkitd keeps a typed password for the shell's process; `minutes` above
# polkitd's default sets its ExpirationSeconds for the whole system. The texts are
# RememberRules.ruleText's and confText's exactly (singletons/RememberRules.qml), one rule
# per user, so that the shell reads them back as its own: tests/RememberNixosModuleTest.qml
# checks them against RememberRules for a case set, tests/system/nixos/remember.sh evaluates
# the module for the same cases.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.h2s-shell;
  remember = cfg.polkit.rememberAdmin;
  inherit (lib) types mkOption;

  # The setting's range (system.rememberAdminMinutes) and polkitd's own length when no conf
  # file sets one
  minMinutes = 1;
  maxMinutes = 60;
  defaultMinutes = 5;

  # The timeout the shell's runs start: the first on the shell's PATH, which the package's
  # command puts its own coreutils at the front of (its passthru names it; a package
  # without it falls back to nixpkgs' coreutils, with a warning). nixpkgs' coreutils is
  # built as one binary with symlinks: pkexec resolves bin/timeout, as every coreutils
  # program, to bin/coreutils, so the rule names that and also tests the command line's
  # first word. A coreutils built otherwise would have a real bin/timeout, and this rule
  # would not match it (the shell then shows it as outdated).
  hasCoreutils = cfg.package ? coreutils;
  coreutils = cfg.package.coreutils or pkgs.coreutils;
  timeout = "${coreutils}/bin/timeout";
  program = "${coreutils}/bin/coreutils";

  validUser = user: lib.stringLength user <= 256 && builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*[$]?" user != null;

  sha256 = text: builtins.hashString "sha256" text;
  ruleText = user:
    let
      body = ''
        polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.policykit.exec" && subject.user == "${user}" &&
                action.lookup("program") == "${program}" &&
                action.lookup("command_line").indexOf("${timeout} ") == 0)
                return "auth_admin_keep";
        });
      '';
    in
    "// Written by h2s-shell ${sha256 body}\n${body}";
  confText = seconds:
    let body = "[Polkitd]\nExpirationSeconds=${toString seconds}\n";
    in "# Written by h2s-shell ${sha256 body}\n${body}";

  users = lib.unique remember.users;
  active = cfg.enable && remember.enable;

  conf = confText (remember.minutes * 60);
  confNeeded = active && remember.minutes > defaultMinutes;
  # The conf as the system ends up with it: ours alone, or what else in the configuration
  # sets the file (a text joined to ours, a source in its place)
  etcConf = config.environment.etc."polkit-1/polkitd.conf" or null;
  confOurs = etcConf != null && etcConf.text == conf
    && toString etcConf.source == toString (pkgs.writeText "etc-polkit-1-polkitd.conf" conf);
in
{
  options.programs.h2s-shell.polkit.rememberAdmin = {
    enable = lib.mkEnableOption ''
      remembering the administrator password for the shell's own root runs: after one typed
      password, polkit lets the shell run them for `minutes` without asking again, as sudo
      does. Only the shell's runs are remembered for (pkexec of the timeout the shell starts
      them with), only for `users`, and only in the shell's process; the shell forgets at
      lock and on "Forget now"
    '';
    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "alex" ];
      description = "The users whose shell's runs are remembered for.";
    };
    minutes = mkOption {
      type = types.int;
      default = defaultMinutes;
      description = ''
        How long the password is remembered, ${toString minMinutes}–${toString maxMinutes}
        minutes. Above ${toString defaultMinutes} (polkit's own length) it sets polkitd's
        ExpirationSeconds in /etc/polkit-1/polkitd.conf: one length for the whole system,
        every program's remembered authorizations. A shorter setting in the shell is kept
        by the shell itself, which forgets earlier.
      '';
    };
  };

  config = lib.mkIf remember.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.enable;
          message = "programs.h2s-shell.polkit.rememberAdmin needs programs.h2s-shell.enable.";
        }
        {
          assertion = config.security.polkit.enable;
          message = "programs.h2s-shell.polkit.rememberAdmin needs security.polkit.enable.";
        }
        {
          assertion = users != [ ];
          message = "programs.h2s-shell.polkit.rememberAdmin.users is empty: name the users whose runs are remembered for.";
        }
        {
          assertion = remember.minutes >= minMinutes && remember.minutes <= maxMinutes;
          message = "programs.h2s-shell.polkit.rememberAdmin.minutes is ${toString remember.minutes}: it must be ${toString minMinutes}–${toString maxMinutes}.";
        }
        {
          assertion = !confNeeded || confOurs;
          message = "programs.h2s-shell.polkit.rememberAdmin.minutes = ${toString remember.minutes} sets /etc/polkit-1/polkitd.conf (ExpirationSeconds=${toString (remember.minutes * 60)}), but environment.etc.\"polkit-1/polkitd.conf\" is also set elsewhere in the configuration: remove that, or set minutes to ${toString defaultMinutes} or less.";
        }
      ] ++ map (user: {
        assertion = validUser user;
        message = "programs.h2s-shell.polkit.rememberAdmin.users: ${builtins.toJSON user} is not a user name (letters, digits, _ . -, not starting with - or ., at most a final $).";
      }) users;
      warnings = lib.optional (active && !hasCoreutils)
        "programs.h2s-shell.polkit.rememberAdmin: programs.h2s-shell.package has no `coreutils` in its passthru, so the rule names nixpkgs' coreutils; if the shell's PATH has another timeout first, its runs are not remembered.";
    }
    (lib.mkIf active {
      # Before the machine's own rules: polkit takes the first rule that answers
      security.polkit.extraConfig = lib.mkBefore (lib.concatMapStrings ruleText users);
    })
    # polkitd reads its conf only at its start and on SIGHUP: its unit (Type=notify-reload)
    # gets SIGHUP from a reload, which the switch does when the conf changes. mkDefault: a
    # text set elsewhere replaces ours instead of being joined to it, and a source set
    # elsewhere wins without a conflict; the assertion above names either.
    (lib.mkIf confNeeded {
      environment.etc."polkit-1/polkitd.conf".text = lib.mkDefault conf;
      systemd.services.polkit.reloadTriggers = [ conf ];
    })
  ]);
}
