#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p priv
rustc --edition=2021 -C opt-level=z -C strip=symbols -C panic=abort native/runespell-runner.rs -o priv/runespell-runner
