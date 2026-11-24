# The shell's settings file: a JSON data file the shell writes beside the system's
# configuration, which hands its path once (`programs.h2s-shell.settingsFile =
# ./h2s-shell.json;` — a flake's pure evaluation reads nothing outside the flake, so there
# is no default path). Its keys are this module's own option paths, and each value becomes
# that option's definition at mkDefault: a plain definition in the configuration wins (the
# owner's deliberate override) and the two never clash. Data only — `builtins.fromJSON`
# runs nothing — and every value is checked here before it reaches an option: a wrong
# value or schema version is an assertion naming the key; a key this module does not know
# (a newer shell's) is a warning and is ignored. What was taken in, and what is in force
# for the same options, is published as /etc/h2s-shell/settings.json for the shell to read
# unprivileged; the file's presence says the line is in place.
{ config, options, lib, ... }:

let
  cfg = config.programs.h2s-shell;
  opts = options.programs.h2s-shell;
  inherit (lib) types;

  # The schema version this module reads: the file's `version` must be this number
  schemaVersion = 1;

  # The options the file may set, as their paths under programs.h2s-shell
  leaves = [
    [ "idle" "hibernateDelay" ]
    [ "pam" "rules" ]
    [ "pam" "sudo" "rules" ]
    [ "pam" "polkit" "rules" ]
    [ "polkit" "rememberAdmin" "enable" ]
    [ "polkit" "rememberAdmin" "users" ]
    [ "polkit" "rememberAdmin" "minutes" ]
  ];
  rowLeaves = [ [ "pam" "rules" ] [ "pam" "sudo" "rules" ] [ "pam" "polkit" "rules" ] ];

  keyOf = lib.concatStringsSep ".";
  shown = value:
    let text = builtins.toJSON value;
    in if lib.stringLength text > 120 then lib.substring 0 117 text + "..." else text;
  isLeaf = path: lib.elem path leaves;
  isBranch = path: lib.any (leaf: lib.length leaf > lib.length path && lib.take (lib.length path) leaf == path) leaves;

  # A value against an option type, into lists and alternatives (a list's own check looks
  # only at the list)
  fits = type: value:
    if type.name == "nullOr" then value == null || fits type.nestedTypes.elemType value
    else if type.name == "listOf" then builtins.isList value && lib.all (fits type.nestedTypes.elemType) value
    else if type.name == "either" then fits type.nestedTypes.left value || fits type.nestedTypes.right value
    else type.check value;

  # systemd's time span as sleep.conf reads it: numbers with units ("3h", "1h 30min"), or
  # seconds alone; nothing that could end the line
  timeUnits = "usec|us|msec|ms|seconds|second|sec|s|minutes|minute|min|m|hours|hour|hr|h|days|day|d|weeks|week|w|months|month|M|years|year|y";
  timeSpan = text: lib.stringLength text <= 64
    && (builtins.match "[0-9]+" text != null
      || builtins.match "( *[0-9]+(\\.[0-9]+)? *(${timeUnits}))+ *" text != null);

  # The row fields pam.nix's rows have; a field without a default must be given
  rowOptions = lib.filterAttrs (name: _: !(lib.hasPrefix "_" name)) (opts.pam.rules.type.getSubOptions [ ]);
  rowProblem = index: row:
    let
      unknown = lib.filter (name: !(rowOptions ? ${name})) (lib.attrNames row);
      missing = lib.filter (name: !(rowOptions.${name} ? default) && !(row ? ${name})) (lib.attrNames rowOptions);
      wrong = lib.filter (name: rowOptions ? ${name} && !(fits rowOptions.${name}.type row.${name})) (lib.attrNames row);
      at = "row ${toString index}";
    in
    if !builtins.isAttrs row then "${at} is ${shown row}, not an object"
    # A row that cannot be built as it was meant stops the build: dropping a field of a
    # sign-in rule would change what it lets through
    else if unknown != [ ] then "${at} has the field ${builtins.toJSON (lib.head unknown)}, which this module's rows do not have (${lib.concatStringsSep ", " (lib.attrNames rowOptions)})"
    else if missing != [ ] then "${at} has no ${builtins.toJSON (lib.head missing)}"
    else if wrong != [ ] then
      let name = lib.head wrong;
      in "${at}, ${builtins.toJSON name}: ${shown row.${name}} is not ${rowOptions.${name}.type.description}"
    else null;
  rowsProblem = value:
    if value == null then null
    else if !builtins.isList value then "${shown value} is not a list of rows or null"
    else lib.findFirst (problem: problem != null) null (lib.imap0 rowProblem value);

  # What is wrong with a value for one of the options, or null
  leafProblem = path: value:
    let type = (lib.getAttrFromPath path opts).type;
    in
    if lib.elem path rowLeaves then rowsProblem value
    else if !(fits type value) then "${shown value} is not ${type.description}"
    else if path == [ "idle" "hibernateDelay" ] && builtins.isString value && !(timeSpan value) then
      "${shown value} is not a systemd time span (such as \"3h\" or \"1h 30min\")"
    else if path == [ "polkit" "rememberAdmin" "minutes" ] && (value < 1 || value > 60) then
      "${toString value} is not 1–60"
    else null;

  none = { errors = [ ]; warnings = [ ]; taken = [ ]; };
  joined = results: {
    errors = lib.concatMap (result: result.errors) results;
    warnings = lib.concatMap (result: result.warnings) results;
    taken = lib.concatMap (result: result.taken) results;
  };
  walk = path: value:
    if isLeaf path then
      let problem = leafProblem path value;
      in if problem == null then none // { taken = [ { inherit path value; } ]; }
      else none // { errors = [ "the key \"${keyOf path}\": ${problem}." ]; }
    else if isBranch path then
      if builtins.isAttrs value then joined (lib.mapAttrsToList (name: walk (path ++ [ name ])) value)
      else none // { errors = [ "the key \"${keyOf path}\" is ${shown value}, not an object." ]; }
    else none // { warnings = [ "the key \"${keyOf path}\" is not one this version of the shell's module knows; it is ignored." ]; };

  file = builtins.fromJSON (builtins.readFile cfg.settingsFile);
  result =
    if cfg.settingsFile == null then none
    else if !builtins.isAttrs file then none // { errors = [ "the file is ${shown file}, not a JSON object." ]; }
    else if !(file ? version) then none // { errors = [ "the file has no \"version\" (this module reads schema version ${toString schemaVersion})." ]; }
    else if file.version != schemaVersion then
      none // { errors = [ "the file's schema version is ${shown file.version}; this module reads version ${toString schemaVersion} (the shell and its NixOS module are of different versions)." ]; }
    else walk [ ] (builtins.removeAttrs file [ "version" ]);

  where = "programs.h2s-shell.settingsFile (${toString cfg.settingsFile})";
  takenAt = path: lib.findFirst (taken: taken.path == path) null result.taken;
  definition = path:
    let taken = takenAt path;
    in { programs.h2s-shell = lib.setAttrByPath path (lib.mkIf (taken != null) (lib.mkDefault taken.value)); };

  # An option's value as data: a submodule's value carries the module system's own
  # `_module`
  data = value:
    if builtins.isAttrs value then lib.mapAttrs (_: data) (builtins.removeAttrs value [ "_module" ])
    else if builtins.isList value then map data value
    else value;
  nested = entries: lib.foldl' (tree: entry: lib.recursiveUpdate tree (lib.setAttrByPath entry.path entry.value)) { } entries;
  published = {
    version = schemaVersion;
    settings = nested result.taken;
    inForce = nested (map (path: { inherit path; value = data (lib.getAttrFromPath path cfg); }) leaves);
  };
in
{
  options.programs.h2s-shell.settingsFile = lib.mkOption {
    type = types.nullOr types.path;
    default = null;
    example = lib.literalExpression "./h2s-shell.json";
    description = ''
      The shell's settings file, a JSON file the shell keeps beside this configuration
      (with a flake, inside it: pure evaluation reads nothing outside the flake). Its keys
      are this module's options (`idle.hibernateDelay`, `pam.rules`, `pam.sudo.rules`,
      `pam.polkit.rules`, `polkit.rememberAdmin.{enable,users,minutes}`) with a `version`;
      each becomes the option's default, so a definition of your own wins. A wrong value or
      version stops the build naming the key; a key this version does not know is a
      warning. What was taken in is published as /etc/h2s-shell/settings.json. null: no
      file is read.
    '';
  };

  config = lib.mkMerge ([
    {
      assertions = map (error: { assertion = false; message = "${where}: ${error}"; }) result.errors;
      warnings = map (warning: "${where}: ${warning}") result.warnings;
      environment.etc."h2s-shell/settings.json" = lib.mkIf (cfg.enable && cfg.settingsFile != null) {
        text = builtins.toJSON published + "\n";
      };
    }
  ] ++ map definition leaves);
}
