# NixOS module: `programs.h2s-shell.enable = true;` installs the shell and what it needs
# from the system — its font, and the services its widgets read (battery, Bluetooth,
# network). Hyprland's autostart is still yours to add: see the README.
self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.h2s-shell;

  # security.pam.u2f.settings as module arguments, the way NixOS's PAM module writes them
  # (true → the name alone, false and null → nothing, else name=value; a value with a
  # space in brackets), with the two the lock needs forced
  u2fArguments = lib.concatLists (lib.mapAttrsToList
    (name: value:
      if lib.isBool value then lib.optional value name
      else lib.optional (value != null) (formatArgument "${name}=${toString value}"))
    (config.security.pam.u2f.settings // { cue = true; interactive = false; }));
  formatArgument = argument:
    if lib.hasInfix " " argument
    then "[${lib.replaceStrings [ "]" ] [ "\\]" ] argument}]"
    else argument;
in
{
  options.programs.h2s-shell = {
    enable = lib.mkEnableOption "h2s-shell, a desktop shell for Hyprland";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "h2s-shell.packages.\${system}.default";
      description = "The h2s-shell package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
    # The battery widget reads UPower; profiles, power-profiles-daemon; the Bluetooth
    # widget, BlueZ; the network widget, NetworkManager. mkDefault: a machine's own
    # setting wins (e.g. TLP instead of power-profiles-daemon).
    services.upower.enable = lib.mkDefault true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;
    networking.networkmanager.enable = lib.mkDefault true;

    # The lock screen's PAM conversations, one per way of unlocking so that they run side
    # by side (singletons/lock/PamMethod.qml); scripts/lock-auth-methods.sh prefers these
    # system-wide configs to the ones shipped in pam/. Those name modules without a path,
    # which libpam looks for only in its own store directory: pam_unix is there, but
    # pam_fprintd and pam_u2f live in other packages. So here the fingerprint and security
    # key configs come from this module, and exist only where the system has those set up.
    #
    # Quickshell runs pam_authenticate and nothing else: only the `auth` lines matter (the
    # account, password and session lines NixOS writes into every service never run).
    security.pam.services = {
      # The password: NixOS's usual stack — pam_unix, and whatever the machine keeps its
      # accounts in that checks the same password (systemd-homed, SSSD, LDAP, Kerberos,
      # kanidm: global switches, kept) — without the modules that would make the typed
      # password wait for something else or ask a second question (a fingerprint, a key,
      # a smartcard, a face, a one-time code, a push). The fingerprint and the key have
      # conversations of their own. Each is only a default: a machine that wants one in
      # the lock's password check says so, e.g.
      #   security.pam.services.h2s-shell-password.oathAuth = true;
      # (a module that asks a second question then shows it as a question on the lock).
      h2s-shell-password = {
        fprintAuth = lib.mkDefault false;
        u2f.enable = lib.mkDefault false;
        p11Auth = lib.mkDefault false;
        yubicoAuth = lib.mkDefault false;
        howdy.enable = lib.mkDefault false;
        oathAuth = lib.mkDefault false;
        otpwAuth = lib.mkDefault false;
        googleAuthenticator.enable = lib.mkDefault false;
        duoSecurity.enable = lib.mkDefault false;
        sshAgentAuth = lib.mkDefault false;
        rssh = lib.mkDefault false;
        usshAuth = lib.mkDefault false;
      };

      # The passive ones are written out whole rather than built from NixOS's options: a
      # global switch (security.pam.oath, services.howdy, systemd-homed…) would otherwise
      # put a module that asks for typed input into them, and the shell treats a passive
      # check that asks as broken (an empty answer in a loop would be a failed password
      # attempt each time). One module, `required`: its own result is the result.
      # mkOverride 900: above NixOS's generated text (a default), below a plain definition
      # of the machine's own, which replaces it.
      # `timeout=-1`: pam_fprintd waits for a finger with no time limit (its default, 30 s,
      # ends an untouched round in an error); the lock ends the conversation itself — at
      # the unlock, at the end of the lock, before sleep. `max-tries` stays pam_fprintd's
      # (3 non-matching fingers, then MaxTries: the shell waits a moment and starts again).
      h2s-shell-fingerprint = lib.mkIf config.services.fprintd.enable {
        text = lib.mkOverride 900 ''
          # The lock screen's fingerprint check (h2s-shell's NixOS module)
          auth required ${config.services.fprintd.package}/lib/security/pam_fprintd.so timeout=-1
        '';
      };
      # pam_u2f with the machine's settings (where the keys are: authfile, appid, origin…),
      # but always `cue` (it says when to touch the key) and never `interactive` (it would
      # wait for Enter). A key that needs a PIN cannot work here.
      h2s-shell-u2f = lib.mkIf config.security.pam.u2f.enable {
        text = lib.mkOverride 900 ''
          # The lock screen's security key check (h2s-shell's NixOS module)
          auth required ${lib.concatStringsSep " " ([ "${pkgs.pam_u2f}/lib/security/pam_u2f.so" ] ++ u2fArguments)}
        '';
      };
    };
  };
}
