#!/bin/sh
# A stand-in program for the fixture's suites: prints its arguments, one per line, and exits
# with the status in $STAND_IN_EXIT (0 by default)
for argument; do printf '%s\n' "$argument"; done
exit "${STAND_IN_EXIT:-0}"
