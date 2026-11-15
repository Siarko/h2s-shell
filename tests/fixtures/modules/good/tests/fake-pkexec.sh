#!/bin/sh
# Stands in for pkexec in the fixture's suites: "126" or "127" as the first argument exits
# with it (the prompt dismissed; not authorised), anything else runs the rest
case "$1" in
    126|127) exit "$1" ;;
esac
exec "$@"
