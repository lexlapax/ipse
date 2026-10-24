#!/bin/sh
set -eu
IPSE_WORKSPACE=$PWD
export IPSE_WORKSPACE
IPSE_LAUNCHER=$0
case "$IPSE_LAUNCHER" in
  */*) ;;
  *) IPSE_LAUNCHER=$(command -v "$IPSE_LAUNCHER") ;;
esac
IPSE_LINKS=0
while [ -L "$IPSE_LAUNCHER" ]; do
  IPSE_LINKS=$((IPSE_LINKS + 1))
  if [ "$IPSE_LINKS" -gt 40 ]; then
    printf '%s\n' 'Ipse launcher: too many symlinks; inspect the installation link.' >&2
    exit 1
  fi
  IPSE_PARENT=$(CDPATH= cd -- "$(dirname -- "$IPSE_LAUNCHER")" && pwd)
  IPSE_TARGET=$(readlink "$IPSE_LAUNCHER")
  case "$IPSE_TARGET" in
    /*) IPSE_LAUNCHER=$IPSE_TARGET ;;
    *) IPSE_LAUNCHER=$IPSE_PARENT/$IPSE_TARGET ;;
  esac
done
IPSE_RELEASE=$(CDPATH= cd -- "$(dirname -- "$IPSE_LAUNCHER")" && pwd)
exec "$IPSE_RELEASE/bin/ipse" eval 'Ipse.CLI.main(System.argv())' "$@"
