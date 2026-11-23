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
  # command puts its own coreutils at the front of. NixOS's coreutils is one multi-call
  # binary that pkexec resolves every coreutils program to, so the rule also tests the
  # command line's first word.
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
      ] ++ map (user: {
        assertion = validUser user;
        message = "programs.h2s-shell.polkit.rememberAdmin.users: ${builtins.toJSON user} is not a user name (letters, digits, _ . -, not starting with - or ., at most a final $).";
      }) users;
    }
    (lib.mkIf active {
      security.polkit.extraConfig = lib.concatMapStrings ruleText users;
    })
    # polkitd reads its conf only at its start and on SIGHUP: its unit (Type=notify-reload)
    # gets SIGHUP from a reload, which the switch does when the conf changes
    (lib.mkIf (active && remember.minutes > defaultMinutes) (
      let conf = confText (remember.minutes * 60);
      in {
        environment.etc."polkit-1/polkitd.conf".text = conf;
        systemd.services.polkit.reloadTriggers = [ conf ];
      }))
  ]);
}
