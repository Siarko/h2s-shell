# security.pam.u2f.settings as pam_u2f's arguments, the way NixOS's PAM module writes them
# (true → the name alone, false and null → nothing, else name=value; a value with a space in
# brackets): `arguments overrides`, `overrides` laid over the settings. One place for the
# lock screen's key check (module.nix) and the security key rows of sudo's and polkit's
# rules (pam.nix): both look for the keys where the machine says (authfile, appid,
# origin…). `broken`: the settings pam.nix refuses — a name that is not a plain option name
# (lower-case letters and _: "userpresence=0" set true would be written as that argument),
# or a name or value holding a tab (libpam splits the argument there) or a line break (it
# would end the line and start another).
lib: settings:
let
  formatArgument = argument:
    if lib.hasInfix " " argument
    then "[${lib.replaceStrings [ "]" ] [ "\\]" ] argument}]"
    else argument;
  written = value: !(lib.isBool value) && value != null;
  splits = text: lib.any (character: lib.hasInfix character text) [ "\t" "\n" "\r" ];
in
{
  arguments = overrides: lib.concatLists (lib.mapAttrsToList
    (name: value:
      if lib.isBool value then lib.optional value name
      else lib.optional (value != null) (formatArgument "${name}=${toString value}"))
    (settings // overrides));
  broken = lib.attrNames (lib.filterAttrs
    (name: value: builtins.match "[a-z_]+" name == null || splits name || (written value && splits (toString value)))
    settings);
}
