# security.pam.u2f.settings as pam_u2f's arguments, the way NixOS's PAM module writes them
# (true → the name alone, false and null → nothing, else name=value; a value with a space in
# brackets): `arguments overrides`, `overrides` laid over the settings. One place for the
# lock screen's key check (module.nix) and the security key rows of sudo's and polkit's
# rules (pam.nix): both look for the keys where the machine says (authfile, appid,
# origin…). `broken`: the names of settings whose value holds a line break — written into
# a PAM file it would end the line there and start another, so pam.nix refuses them.
lib: settings:
let
  formatArgument = argument:
    if lib.hasInfix " " argument
    then "[${lib.replaceStrings [ "]" ] [ "\\]" ] argument}]"
    else argument;
  written = value: !(lib.isBool value) && value != null;
in
{
  arguments = overrides: lib.concatLists (lib.mapAttrsToList
    (name: value:
      if lib.isBool value then lib.optional value name
      else lib.optional (value != null) (formatArgument "${name}=${toString value}"))
    (settings // overrides));
  broken = lib.attrNames (lib.filterAttrs
    (name: value: written value && (lib.hasInfix "\n" (toString value) || lib.hasInfix "\r" (toString value)))
    settings);
}
