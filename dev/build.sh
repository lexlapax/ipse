#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
IPSE_BUILD_COMMIT=${IPSE_BUILD_COMMIT:-$(git rev-parse HEAD 2>/dev/null || true)}
export IPSE_BUILD_COMMIT
mix deps.get
sh dev/build-native.sh
mix compile --force --warnings-as-errors
