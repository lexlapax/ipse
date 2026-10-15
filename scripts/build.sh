#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mix deps.get
sh native/build.sh
mix compile --warnings-as-errors
