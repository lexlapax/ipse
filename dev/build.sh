#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mix deps.get
sh dev/build-native.sh
mix compile --warnings-as-errors
