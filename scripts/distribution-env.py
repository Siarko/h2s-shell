#!/usr/bin/env python3
"""Writes each distribution's facts for the shell's scripts.

Every distributions/<id>/distribution.json (the facts the shell reads, checked by
singletons/DistributionRules.qml) gets a distribution.env beside it: the same facts as
key=value lines, which scripts/distribution.sh parses without running anything — bash has
no JSON parser, and the lock's methods script must not need one. A string is written as it
is, a boolean as true or false, a list joined with ":" (as PATH is). A value holding a
control character, or a list entry holding ":", is refused: the line format could not carry
it back. The `packages` hints are left out: they are words for the shell's views, which
no script reads (an object, which the line format cannot carry).

The files are generated here, by a developer, after distribution.json changes, and checked
in: the scripts read them in a read-only package too, and without this program.
tests/distribution-selftest.sh fails while any of them differs from what this writes.

    scripts/distribution-env.py [<shell dir>]          write every distribution.env
    scripts/distribution-env.py --check [<shell dir>]  write nothing; status 1 when one differs

Exit status: 0 done (or all equal); 1 a file differs (--check); 2 a distribution.json
cannot be turned into lines (why is printed).
"""

import json
import os
import re
import sys

HEADER = "# Generated from distribution.json by scripts/distribution-env.py: edit that, then run it.\n"
KEY = re.compile(r"^[A-Za-z][A-Za-z0-9]{0,63}$")
# Keys the scripts have no use for, left out of the lines
LEFT_OUT = {"packages"}
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f  ]")


class Refused(Exception):
    pass


def line_value(key, value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        if CONTROL.search(value):
            raise Refused(f"{key}: a control character")
        return value
    if isinstance(value, list):
        for entry in value:
            if not isinstance(entry, str) or entry == "" or ":" in entry or CONTROL.search(entry):
                raise Refused(f"{key}: an entry that is no plain text without ':'")
        return ":".join(value)
    raise Refused(f"{key}: neither text, true/false nor a list of text")


def env_text(json_text):
    try:
        facts = json.loads(json_text)
    except ValueError as error:
        raise Refused(f"no JSON: {error}")
    if not isinstance(facts, dict):
        raise Refused("no JSON object")
    lines = [HEADER]
    for key, value in facts.items():
        if key in LEFT_OUT:
            continue
        if not KEY.match(key):
            raise Refused(f"a key that is no plain word: {key!r}")
        lines.append(f"{key}={line_value(key, value)}\n")
    return "".join(lines)


def main(arguments):
    check = False
    if arguments and arguments[0] == "--check":
        check = True
        arguments = arguments[1:]
    if len(arguments) > 1 or (arguments and arguments[0].startswith("-")):
        print("usage: scripts/distribution-env.py [--check] [<shell dir>]", file=sys.stderr)
        return 2
    shell_dir = arguments[0] if arguments else os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    base = os.path.join(shell_dir, "distributions")
    ids = sorted(name for name in os.listdir(base) if os.path.isfile(os.path.join(base, name, "distribution.json")))
    if not ids:
        print(f"distribution-env: no distribution.json under {base}", file=sys.stderr)
        return 2
    differs = False
    for distribution in ids:
        source = os.path.join(base, distribution, "distribution.json")
        target = os.path.join(base, distribution, "distribution.env")
        try:
            with open(source, encoding="utf-8") as file:
                text = env_text(file.read())
        except (OSError, UnicodeDecodeError, Refused) as error:
            print(f"distribution-env: {source}: {error}", file=sys.stderr)
            return 2
        try:
            with open(target, encoding="utf-8") as file:
                current = file.read()
        except (OSError, UnicodeDecodeError):
            current = None
        if current == text:
            continue
        if check:
            print(f"distribution-env: {target} differs from its distribution.json (scripts/distribution-env.py writes it)")
            differs = True
        else:
            with open(target, "w", encoding="utf-8") as file:
                file.write(text)
            print(f"distribution-env: wrote {target}")
    return 1 if differs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
