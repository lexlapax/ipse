#!/bin/sh
set -eu
RUNESPELL_RELEASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$RUNESPELL_RELEASE/bin/runespell" eval 'Runespell.CLI.main(System.argv())' "$@"
