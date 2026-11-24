# security.pam.u2f.settings as pam_u2f's arguments, the way NixOS's PAM module writes them
# (true → the name alone, false and null → nothing, else name=value; a value with a space in
# brackets): `arguments overrides`, `overrides` laid over the settings. One place for the
# lock screen's key check (module.nix) and the security key rows of sudo's and polkit's
# rules (pam.nix): both look for the keys where the machine says (authfile, appid,
# origin…). `broken`: the settings pam.nix refuses — a name that is not a plain option name
# (lower-case letters and _: "userpresence=0" set true would be written as that argument),
# or a name or value holding a tab (libpam splits the argument there) or a line break (it
# would end the line and start another). `alwaysok`, `nouserok`, `touchOff`: the settings
# that let a key line pass without a key or a touch — kept as they are, and warned about
# (pam.nix, module.nix); `interactive`, `conf` as set. `argsTouchOff`: a line's own
# arguments turn the touch off.
lib: settings:
let
  formatArgument = argument:
    if lib.hasInfix " " argument
    then "[${lib.replaceStrings [ "]" ] [ "\\]" ] argument}]"
    else argument;
  written = value: !(lib.isBool value) && value != null;
  splits = text: lib.any (character: lib.hasInfix character text) [ "\t" "\n" "\r" ];
  userpresence = settings.userpresence or null;
  # pam_u2f reads `userpresence=` with sscanf("%d"): 0 turns the touch off, 1 asks for it,
  # anything else leaves the authenticator's default (which asks)
  zeroPresence = value: builtins.match "[[:space:]]*[+-]?0+([^0-9].*)?" (toString value) != null;
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
  # pam_u2f reads these two as bare words only: true writes them, anything else does not
  alwaysok = (settings.alwaysok or null) == true;
  nouserok = (settings.nouserok or null) == true;
  # `userpresence` written as 0 (true and false write no `userpresence=` and leave pam_u2f's
  # default)
  inherit userpresence;
  touchOff = userpresence != null && !(lib.isBool userpresence) && zeroPresence userpresence;
  interactive = (settings.interactive or null) == true;
  conf = let value = settings.conf or null; in if value == null || lib.isBool value then null else toString value;
  # The last `userpresence=` of a line's arguments decides
  argsTouchOff = args:
    let words = lib.filter (lib.hasPrefix "userpresence=") args;
    in words != [ ] && zeroPresence (lib.removePrefix "userpresence=" (lib.last words));
}
