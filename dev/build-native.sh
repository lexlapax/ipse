#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p priv
rustc --edition=2021 -C opt-level=z -C strip=symbols -C panic=abort native/ipse-runner.rs -o priv/ipse-runner
