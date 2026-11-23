# sudo's and polkit's `auth` rules, as options of the shell's module: /etc/pam.d is generated
# on NixOS, so the shell's rule editor gives its rules as these options to copy into the
# system's configuration (PamEditRules.nixosSnippet writes them). Each row
# becomes one or more of NixOS's PAM rules, above NixOS's own; the checks that can be made
# from the configuration are assertions and warnings, as the editor's are refusals and
# warnings (PamRuleRules.check). tests/PamNixosModuleTest.qml checks the names and ranges
# here against the editor's; tests/system/nixos/pam.sh evaluates the lines against
# PamEditRules' for the same rows.
{ config, options, lib, pkgs, ... }:

let
  cfg = config.programs.h2s-shell;
  inherit (lib) types mkOption;

  methods = [ "fingerprint" "securityKey" "password" "system" "raw" ];
  controls = [ "sufficient" "required" "requisite" "optional" ];
  # libpam's own modules: NixOS's libpam finds these, and only these, by bare name
  libpamModules = map (name: name + ".so") [ "pam_access" "pam_canonicalize_user" "pam_debug"
    "pam_deny" "pam_echo" "pam_env" "pam_exec" "pam_faildelay" "pam_faillock" "pam_filter"
    "pam_ftp" "pam_group" "pam_issue" "pam_keyinit" "pam_lastlog" "pam_limits" "pam_listfile"
    "pam_localuser" "pam_loginuid" "pam_mail" "pam_mkhomedir" "pam_motd" "pam_namespace"
    "pam_nologin" "pam_permit" "pam_pwhistory" "pam_rhosts" "pam_rootok" "pam_securetty"
    "pam_selinux" "pam_sepermit" "pam_setquota" "pam_shells" "pam_stress" "pam_succeed_if"
    "pam_time" "pam_timestamp" "pam_tty_audit" "pam_umask" "pam_unix" "pam_userdb"
    "pam_usertype" "pam_warn" "pam_wheel" "pam_xauth" ];
  # The system profile's module folder: the one place outside the store a module is taken
  # from without a warning
  systemModules = "/run/current-system/sw/lib/security/";

  rowType = types.submodule {
    options = {
      method = mkOption {
        type = types.enum methods;
        description = ''
          What the row asks for: `fingerprint` (pam_fprintd), `securityKey` (pam_u2f),
          `password` (pam_unix), `raw` (any module, as `module` and `args` say), or `system`:
          NixOS's own auth rules for the service, kept below the rows. Without a `system`
          row the rows end with closing lines and NixOS's own rules are never reached.
        '';
      };
      control = mkOption {
        type = types.enum controls;
        default = "sufficient";
        description = ''
          PAM's control word: `sufficient` (enough on its own: if it passes and no row
          above has failed, you are in; if not, the next row is tried), `required` (must
          pass; the next rows still run and a failure is told at the end), `requisite` (must
          pass; a failure ends it at once), `optional` (counts only when no other row
          decides). Not used by the `system` row.
        '';
      };
      timeout = mkOption {
        type = types.nullOr (types.ints.between 5 120);
        default = null;
        description = "Fingerprint: seconds to wait for a finger (pam_fprintd's `timeout`); null leaves pam_fprintd's.";
      };
      tries = mkOption {
        type = types.nullOr (types.ints.between 1 10);
        default = null;
        description = "Fingerprint: fingers tried before it fails (pam_fprintd's `max-tries`); null leaves pam_fprintd's.";
      };
      pin = mkOption {
        type = types.bool;
        default = false;
        description = "Security key: ask for the key's PIN too (pam_u2f's `pinverification=1`). pam_u2f always says when to touch the key (`cue`).";
      };
      counted = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Password: wrong passwords count toward pam_faillock's lockout. Only where the
          service counts them already (`security.pam.services.<name>.logFailures`). An
          empty Enter used to reach a reader below then counts as a wrong password.
        '';
      };
      module = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = lib.literalExpression ''"''${pkgs.pam_ldap}/lib/security/pam_ldap.so"'';
        description = ''
          Raw row: the module. libpam's own modules by name (`pam_env.so`); any other by its
          full path, best from its package (`"''${pkgs.pam_ldap}/lib/security/pam_ldap.so"`):
          a store path written out changes with an update or a garbage collection, and a
          file outside the store that a user can write is a way to root — both are allowed,
          with a warning.
        '';
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Raw row: the module's arguments.";
      };
    };
  };

  rulesOption = description: mkOption {
    type = types.nullOr (types.listOf rowType);
    default = null;
    example = lib.literalExpression ''
      [
        { method = "fingerprint"; control = "sufficient"; timeout = 10; tries = 3; }
        { method = "system"; }
      ]
    '';
    inherit description;
  };

  # Each service's rows (null: NixOS's rules as they are) and the option they come from
  services = {
    sudo = {
      option = if cfg.pam.sudo.rules != null then "programs.h2s-shell.pam.sudo.rules" else "programs.h2s-shell.pam.rules";
      rows = if cfg.pam.sudo.rules != null then cfg.pam.sudo.rules else cfg.pam.rules;
      enabled = config.security.sudo.enable
        || (options.security ? sudo-rs && config.security.sudo-rs.enable);
    };
    polkit-1 = {
      option = if cfg.pam.polkit.rules != null then "programs.h2s-shell.pam.polkit.rules" else "programs.h2s-shell.pam.rules";
      rows = if cfg.pam.polkit.rules != null then cfg.pam.polkit.rules else cfg.pam.rules;
      enabled = config.security.polkit.enable;
    };
  };
  ruled = lib.filterAttrs (name: service: service.rows != null && service.enabled) services;

  # ── The rows judged ──

  ready = method:
    if method == "fingerprint" then config.services.fprintd.enable
    else config.security.pam.u2f.enable;
  readyOption = method:
    if method == "fingerprint" then "services.fprintd.enable" else "security.pam.u2f.enable";

  # Where a raw row's module comes from: null when it is fine (libpam's own by name, a path
  # from a package, the system profile), "bare" (another module by name: NixOS's libpam
  # would not find it), "store" (a store path written out), "place" (anywhere else),
  # "missing"
  placeOf = row:
    let
      module = toString row.module;
      segments = lib.splitString "/" module;
      dotted = lib.elem ".." segments || lib.elem "." segments;
    in
    if row.module == null then "missing"
    else if !(lib.hasInfix "/" module) then (if lib.elem module libpamModules then null else "bare")
    else if dotted then "place"
    else if builtins.hasContext module && lib.hasPrefix "${builtins.storeDir}/" module then null
    else if lib.hasPrefix systemModules module then null
    else if lib.hasPrefix "${builtins.storeDir}/" module then "store"
    else "place";
  rawName = row: builtins.unsafeDiscardStringContext (baseNameOf (toString row.module));
  # A raw row of a module from outside counts as no method, whatever its file is called
  rawMethods = { "pam_unix.so" = "password"; "pam_fprintd.so" = "fingerprint"; "pam_u2f.so" = "securityKey"; };
  methodOf = row:
    if row.method != "raw" then row.method
    else if placeOf row != null then "unknown"
    else rawMethods.${rawName row} or "unknown";
  fails = row: row.method != "system" && lib.elem row.control [ "required" "requisite" ];
  # Whether a raw row's module asks for a credential: "yes" (pam_unix, pam_fprintd; pam_u2f
  # without the arguments that let it pass with no key or no touch; pam_userdb with its
  # database under /etc), "no" (another of libpam's modules, or one of those made to pass by
  # its arguments), "unknown" (a module the shell does not know, or from outside)
  # its arguments), "unknown" (a module the shell does not know). The arguments as the
  # modules read them: pam_u2f's words exactly (nouserok, alwaysok; userpresence= through
  # sscanf, so anything but a plain 1 may be off), pam_userdb's without case (every db=
  # counts: the last one wins). A module from outside is judged by its name only to refuse
  # it, never to trust it.
  credentialOf = row:
    let
      name = rawName row;
      lower = map lib.toLower row.args;
      databases = map (lib.substring 3 (-1)) (lib.filter (word: lib.hasPrefix "db=" (lib.toLower word)) row.args);
      underEtc = path: lib.hasPrefix "/etc/" path && !(lib.elem ".." (lib.splitString "/" path));
      byName =
        if name == "pam_u2f.so" then
          (if lib.elem "nouserok" row.args || lib.elem "alwaysok" row.args
              || lib.any (word: lib.hasPrefix "userpresence=" word && word != "userpresence=1") row.args
           then "no" else "yes")
        else if name == "pam_userdb.so" then
          (if !(lib.elem "unknown_ok" lower) && databases != [ ] && lib.all underEtc databases then "yes" else "no")
        else if lib.elem name [ "pam_unix.so" "pam_fprintd.so" ] then "yes"
        else if lib.elem name libpamModules then "no"
        else "unknown";
    in
    if placeOf row == null || byName == "no" then byName else "unknown";
  firstPass = row: methodOf row == "password" && row.method == "raw" && lib.elem "use_first_pass" row.args;

  # The rows' roles and how the rows end: "system" (NixOS's own rules below), "permit" (a
  # row that fails the stack on failure is in the list: `[default=done] pam_permit.so` then
  # `requisite pam_deny.so` keep the result), "deny" (`requisite pam_deny.so`: only a row
  # that lets in at once lets in)
  analyse = rows:
    let
      closing =
        if lib.any (row: row.method == "system") rows then "system"
        else if lib.any fails rows then "permit"
        else "deny";
      # A row can decide that the user is in: NixOS's rules; a row that lets in at once or
      # fails the stack; an own optional row only beside NixOS's rules; a raw pam_unix
      # use_first_pass only below a row that asks for the password
      role = index: row:
        let
          unasked = firstPass row
            && !(lib.any (above: methodOf above == "password" && !(firstPass above)) (lib.take index rows));
        in {
          method = methodOf row;
          reader = lib.elem (methodOf row) [ "fingerprint" "securityKey" ];
          fails = fails row;
          # A name that refuses is believed wherever the file is
          denies = row.method == "raw" && rawName row == "pam_deny.so" && fails row;
          # A raw line that can let the user in (sufficient; required or requisite where the
          # closing line keeps its result) with a module that asks for no credential
          letsAnyone = row.method == "raw" && credentialOf row == "no" && rawName row != "pam_deny.so"
            && (row.control == "sufficient" || (fails row && closing != "system"));
          nullok = row.method == "raw" && methodOf row == "password" && lib.elem "nullok" row.args;
          unknown = row.method == "raw" && methodOf row == "unknown" && credentialOf row != "no" && rawName row != "pam_deny.so";
          # An own optional row: another row decides, or the closing line does
          idle = row.method != "raw" && row.method != "system" && row.control == "optional"
            && (closing != "system"
              || lib.any (other: other.method == "system" || other.control != "optional") (lib.take index rows ++ lib.drop (index + 1) rows));
          decides = !unasked && (row.method == "system" || row.control == "sufficient" || fails row
            || (row.method != "raw" && row.control == "optional" && closing == "system"));
        };
      roles = lib.imap0 role rows;
      hasPassword = lib.any (role: lib.elem role.method [ "password" "system" ] && role.decides) roles;
    in {
      inherit closing roles hasPassword;
      wayIn = hasPassword || lib.any (role: role.reader && ready role.method && role.decides) roles;
    };

  # A service keeps a password: it is enabled, and its rows have one or it has no rows
  # (NixOS's own rules)
  keepsPassword = service: service.enabled && (service.rows == null || (analyse service.rows).hasPassword);

  # The refusals and warnings of one service's rows, as messages
  problems = name: service:
    let
      rows = service.rows;
      where = service.option;
      analysis = analyse rows;
      at = index: row: "${where}, row ${toString (index + 1)} (${row.method})";
      each = check: lib.concatLists (lib.imap0 check rows);
      systemRows = lib.filter (row: row.method == "system") rows;
    in {
      refusals =
        lib.optional (rows == [ ])
          "${where} is empty: give it rows, or leave it null for NixOS's own rules."
        ++ lib.optional (systemRows != [ ] && (lib.length systemRows > 1 || (lib.last rows).method != "system"))
          "${where}: the { method = \"system\"; } row can only be last, and only once."
        ++ each (index: row:
          lib.optional (row.method != "fingerprint" && (row.timeout != null || row.tries != null))
            "${at index row}: timeout and tries are a fingerprint row's."
          ++ lib.optional (row.method != "securityKey" && row.pin)
            "${at index row}: pin is a security key row's."
          ++ lib.optional (row.method != "password" && row.counted)
            "${at index row}: counted is a password row's."
          ++ lib.optional (row.method != "raw" && (row.module != null || row.args != [ ]))
            "${at index row}: module and args are a raw row's."
          ++ lib.optional (row.method == "password" && row.counted && !config.security.pam.services.${name}.logFailures)
            "${at index row}: failures cannot count here: ${name}'s rules do not count them (security.pam.services.${name}.logFailures)."
          ++ lib.optional (row.method == "raw" && placeOf row == "missing")
            "${at index row}: a raw row needs its module."
          ++ lib.optional (row.method == "raw" && placeOf row == "bare")
            "${at index row}: ${toString row.module} needs its full path on NixOS, e.g. \"\${pkgs.<package>}/lib/security/${toString row.module}\"."
          ++ lib.optional (row.method == "raw" && (spaced (toString row.module) || lib.any broken row.args))
            "${at index row}: the module and its arguments go on one line, the module without spaces."
          # A backslash at the end would join the next line of the file to this one; a "#"
          # would end the line there
          ++ lib.optional (row.method == "raw" && lib.any joins (lib.optional (row.module != null) (toString row.module) ++ row.args))
            "${at index row}: no backslash or # in the module or its arguments."
          # NixOS writes a bracketed argument or one with a tab as it is, and libpam hands the
          # module the words inside: what the checks read would not be what the module gets
          ++ lib.optional (row.method == "raw" && lib.any (word: spaced word || lib.hasPrefix "[" word) row.args)
            "${at index row}: one word per argument: no spaces, tabs or brackets.")
        ++ lib.concatLists (lib.imap0 (index: role:
          lib.optional role.denies
            "${at index (lib.elemAt rows index)}: this line refuses everyone: nobody would get in."
          ++ lib.optional role.letsAnyone
            "${at index (lib.elemAt rows index)}: this line lets anyone in: ${rawName (lib.elemAt rows index)} asks for no password, key or finger."
          ++ lib.optional (role.reader && role.fails && !ready role.method)
            "${at index (lib.elemAt rows index)}: this row must pass, but ${readyOption role.method} is off: nobody would get in.")
          analysis.roles)
        ++ lib.optional (rows != [ ] && !analysis.wayIn)
          "${where}: no row can let you in: keep a password row, or a fingerprint or security key row with services.fprintd.enable or security.pam.u2f.enable."
        ++ lib.optional (fprintAuthSet name)
          "${name}'s rules come from programs.h2s-shell.pam: remove security.pam.services.${name}.fprintAuth."
        ++ lib.optional (serviceU2f name)
          "${name}'s rules come from programs.h2s-shell.pam: remove security.pam.services.${name}.${u2fName}.";
      warnings =
        lib.optional (rows != [ ] && analysis.wayIn && !analysis.hasPassword)
          "${where}: only the reader lets you in. If it breaks, use the other of sudo and polkit, su or a root console."
        ++ lib.concatLists (lib.imap0 (index: role:
          lib.optional (role.reader && role.fails && ready role.method)
            "${at index (lib.elemAt rows index)}: both needed: without the reader nobody gets in."
          ++ lib.optional role.unknown
            "${at index (lib.elemAt rows index)}: the shell does not know ${rawName (lib.elemAt rows index)}: its checks do not judge this line."
          ++ lib.optional role.idle
            "${at index (lib.elemAt rows index)}: does nothing here: another row decides."
          ++ lib.optional role.nullok
            "${at index (lib.elemAt rows index)}: nullok: an account with an empty password gets in.")
          analysis.roles)
        ++ lib.optional (rows != [ ] && analysis.closing != "system" && otherAccounts != [ ])
          "${where}: without the { method = \"system\"; } row, a password row checks only local accounts (pam_unix): ${lib.concatStringsSep ", " otherAccounts} accounts are not asked for their password."
        ++ each (index: row:
          lib.optional (row.method == "raw" && placeOf row == "store")
            "${at index row}: ${toString row.module} is a path in the Nix store: it changes with an update or a garbage collection${storeHint row.module}."
          ++ lib.optional (row.method == "raw" && placeOf row == "place")
            "${at index row}: ${toString row.module} is not in the Nix store or ${systemModules}: if a user can write this file, any of that user's programs can replace it without a password, and it runs as root at the next sudo or administrator prompt.");
    };
  spaced = text: lib.any (character: lib.hasInfix character text) [ " " "\t" "\n" "\r" ];
  broken = text: lib.hasInfix "\n" text || lib.hasInfix "\r" text;
  # A service's own switch for NixOS's key rule: u2f.enable, u2fAuth before it
  serviceOptions = options.security.pam.services.type.getSubOptions [ ];
  u2fName = if serviceOptions ? u2f then "u2f.enable" else "u2fAuth";
  serviceU2f = name:
    if serviceOptions ? u2f then config.security.pam.services.${name}.u2f.enable
    else config.security.pam.services.${name}.u2fAuth or false;
  joins = text: lib.hasInfix "\\" text || lib.hasInfix "#" text;
  # Where accounts live besides the local files, as NixOS's own rules check them
  otherAccounts =
    lib.optional config.services.homed.enable "systemd-homed"
    ++ lib.optional config.services.sssd.enable "SSSD"
    ++ lib.optional (config.users.ldap.enable && config.users.ldap.loginPam) "LDAP"
    ++ lib.optional (options.services ? kanidm && options.services.kanidm ? unix && config.services.kanidm.unix.enable) "kanidm"
    ++ lib.optional config.security.pam.krb5.enable "Kerberos";
  fprintAuthSet = name: config.security.pam.services.${name}.fprintAuth;
  # "use ${pkgs.<name>} instead", where the store path names a package of pkgs
  storeHint = module:
    let
      match = builtins.match "${builtins.storeDir}/[0-9a-z]{32}-([^/]+)/.*" module;
      name = if match == null then null else (builtins.parseDrvName (lib.head match)).name;
    in
    if name != null && pkgs ? ${name} then ": use \${pkgs.${name}} instead" else "";

  allProblems = lib.mapAttrsToList problems ruled;
  passwordFirstSet = options.programs.h2s-shell.polkit.passwordFirst.highestPrio < 1500;
  polkitRuled = ruled ? polkit-1;

  # ── The rows as NixOS's rules ──

  pamModule = name: "${config.security.pam.package}/lib/security/${name}";
  # An own row's required/requisite: the plain word's actions with only `ignore` a failure,
  # so a module's PAM_IGNORE never reaches the closing `[default=done] pam_permit.so` as no
  # answer (PamEditRules.writtenControls says why)
  writtenControls = {
    required = "[success=ok new_authtok_reqd=ok ignore=bad default=bad]";
    requisite = "[success=ok new_authtok_reqd=ok ignore=die default=die]";
  };
  writtenControl = control: writtenControls.${control} or control;
  line = control: modulePath: args: { inherit control modulePath args; };
  # A counted password row: pam_faillock's preauth (a lockout closes the service), pam_unix,
  # and authfail reached only on a wrong password
  countedLines = control:
    let
      middle = {
        sufficient = [ "[success=done default=ignore]" "optional" ];
        optional = [ "[success=1 default=ignore]" "optional" ];
        required = [ "[success=1 default=bad]" "[default=bad]" ];
        requisite = [ "[success=1 default=bad]" "[default=die]" ];
      }.${control};
    in [
      (line "required" (pamModule "pam_faillock.so") [ "preauth" ])
      (line (lib.elemAt middle 0) (pamModule "pam_unix.so") [ "try_first_pass" ])
      (line (lib.elemAt middle 1) (pamModule "pam_faillock.so") [ "authfail" ])
    ];
  # The lines of one row. The modules come from their packages, so a fingerprint or key row
  # never needs Arch's `-auth` (skip the line when the module is gone).
  rowLines = row:
    if row.method == "fingerprint" then [
      (line (writtenControl row.control) "${config.services.fprintd.package}/lib/security/pam_fprintd.so"
        (lib.optional (row.timeout != null) "timeout=${toString row.timeout}"
         ++ lib.optional (row.tries != null) "max-tries=${toString row.tries}"))
    ]
    else if row.method == "securityKey" then [
      (line (writtenControl row.control) "${pkgs.pam_u2f}/lib/security/pam_u2f.so" ([ "cue" ] ++ lib.optional row.pin "pinverification=1"))
    ]
    else if row.method == "password" then
      (if row.counted then countedLines row.control else [ (line (writtenControl row.control) (pamModule "pam_unix.so") [ "try_first_pass" ]) ])
    else if row.method == "raw" then [ (line row.control (toString row.module) row.args) ]
    else [ ];
  # `done` ends the stack only on a pass so far: a stack that already failed goes on to the
  # pam_deny line, whose `requisite` ends it with that failure, before NixOS's own rules
  closingLines = {
    permit = [ (line "[default=done]" (pamModule "pam_permit.so") [ ]) (line "requisite" (pamModule "pam_deny.so") [ ]) ];
    deny = [ (line "requisite" (pamModule "pam_deny.so") [ ]) ];
  };
  serviceLines = rows:
    let closing = (analyse rows).closing;
    in lib.concatMap rowLines rows ++ lib.optionals (closing != "system") closingLines.${closing};

  # The rows go above the first of NixOS's own auth rules, in their order, as h2s-1, h2s-2…
  serviceConfig = name: service:
    let
      lines = serviceLines service.rows;
      count = lib.length lines;
      others = lib.filterAttrs (ruleName: rule: !(lib.hasPrefix "h2s-" ruleName) && rule.enable)
        config.security.pam.services.${name}.rules.auth;
      orders = map (rule: rule.order) (lib.attrValues others);
      first = if orders == [ ] then 10000 else lib.foldl' lib.min (lib.head orders) orders;
    in {
      # NixOS's own fingerprint and key rules would ask a second time below the rows
      fprintAuth = lib.mkDefault false;
    } // (if serviceOptions ? u2f then { u2f.enable = lib.mkDefault false; } else { u2fAuth = lib.mkDefault false; }) // {
      rules.auth = lib.listToAttrs (lib.imap1 (index: rule:
        lib.nameValuePair "h2s-${toString index}" (rule // { order = first - 10 * (count - index + 1); }))
        lines);
    };
in
{
  options.programs.h2s-shell = {
    pam = {
      rules = rulesOption ''
        sudo's and polkit's `auth` rules, tried from the top; null leaves both as NixOS
        makes them. `sudo.rules` and
        `polkit.rules` give a service rules of its own instead.
      '';
      sudo.rules = rulesOption "sudo's own `auth` rules, in place of `rules`; null: `rules`.";
      polkit.rules = rulesOption ''
        polkit's own `auth` rules (`security.pam.services.polkit-1`, used by every polkit
        agent, the shell's prompt among them), in place of `rules`; null: `rules`.
      '';
    };
    polkit.passwordFirst = mkOption {
      type = types.bool;
      default = config.services.fprintd.enable;
      defaultText = lib.literalExpression "config.services.fprintd.enable";
      description = ''
        Deprecated: polkit's rules are `programs.h2s-shell.pam.rules` or
        `programs.h2s-shell.pam.polkit.rules` (a password row above the fingerprint row).
        Without them, this still asks polkit's PAM stack for the password before the
        fingerprint reader: NixOS puts pam_fprintd first, so a prompt shows only "Place
        your finger…" until the reader gives up, and only then asks for the password. With
        this on, the password is asked at once; an empty one (Enter on an empty field) fails
        pam_unix and goes on to the reader. Only the order changes: the modules and their
        arguments stay NixOS's.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    security.pam.services = {
      sudo = lib.mkIf (ruled ? sudo) (serviceConfig "sudo" services.sudo);
      polkit-1 = lib.mkMerge [
        (lib.mkIf polkitRuled (serviceConfig "polkit-1" services.polkit-1))
        # polkit.passwordFirst: pam_fprintd moved to just after pam_unix — relative to
        # pam_unix's own order, as NixOS's PAM module advises, so a renumbering upstream
        # keeps it right. Nothing else in the stack moves.
        (lib.mkIf (cfg.polkit.passwordFirst && config.security.polkit.enable && !polkitRuled) {
          rules.auth.fprintd.order = config.security.pam.services.polkit-1.rules.auth.unix.order + 10;
        })
      ];
    };

    assertions = map (message: { assertion = false; inherit message; }) (lib.unique (
      lib.concatMap (found: found.refusals) allProblems
      ++ lib.optional (ruled != { } && !(keepsPassword services.sudo || keepsPassword services.polkit-1))
        "programs.h2s-shell.pam: keep a password in sudo's or polkit's rules: one is the way to repair the other."
      ++ lib.optional (polkitRuled && passwordFirstSet && cfg.polkit.passwordFirst)
        "polkit's rules come from programs.h2s-shell.pam: remove programs.h2s-shell.polkit.passwordFirst."
    ));
    warnings = lib.unique (
      lib.concatMap (found: found.warnings) allProblems
      ++ lib.optional (!polkitRuled && passwordFirstSet)
        "programs.h2s-shell.polkit.passwordFirst is deprecated: put a password row above the fingerprint row in programs.h2s-shell.pam.rules (or pam.polkit.rules)."
    );
  };
}
