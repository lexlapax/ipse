#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
case "${IPSE_BUILD_PDF:-0}" in
  0|1) ;;
  *) printf '%s\n' 'IPSE_BUILD_PDF must be 0 or 1.' >&2; exit 2 ;;
esac
mkdir -p priv
rustc --edition=2021 -C opt-level=z -C strip=symbols -C panic=abort native/ipse-runner.rs -o priv/ipse-runner
if [ "${IPSE_BUILD_PDF:-0}" = 1 ]; then
  elixir native/ipse-pdf/build.exs --output priv/ipse-pdf --notices priv/ipse-pdf-notices
else
  # These are generated artifacts. A parser-free build must not inherit a prior
  # parser-enabled build's executable or notices through Mix's copied priv tree.
  rm -f priv/ipse-pdf
  rm -rf priv/ipse-pdf-notices
fi
