# A user name as the shell's polkit rule may name it (RememberRules.validUser): letters,
# digits, _ . -, not starting with - or ., at most a final $
lib: user: builtins.isString user && lib.stringLength user <= 256
  && builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*[$]?" user != null
