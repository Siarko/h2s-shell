# security.pam.u2f.settings as pam_u2f's arguments, the way NixOS's PAM module writes them
# (true → the name alone, false and null → nothing, else name=value; a value with a space in
# brackets), `overrides` laid over the settings. One place for the lock screen's key check
# (module.nix) and the security key rows of sudo's and polkit's rules (pam.nix): both look
# for the keys where the machine says (authfile, appid, origin…).
lib: settings: overrides:
let
  formatArgument = argument:
    if lib.hasInfix " " argument
    then "[${lib.replaceStrings [ "]" ] [ "\\]" ] argument}]"
    else argument;
in
lib.concatLists (lib.mapAttrsToList
  (name: value:
    if lib.isBool value then lib.optional value name
    else lib.optional (value != null) (formatArgument "${name}=${toString value}"))
  (settings // overrides))
