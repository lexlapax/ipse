#!/bin/sh
set -eu
IPSE_RELEASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IPSE_WORKSPACE=$PWD
export IPSE_WORKSPACE
exec "$IPSE_RELEASE/bin/ipse" eval 'Ipse.CLI.main(System.argv())' "$@"
