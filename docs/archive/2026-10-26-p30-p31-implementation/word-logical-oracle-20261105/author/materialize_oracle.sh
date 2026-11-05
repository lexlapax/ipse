#!/bin/sh
set -eu
cd /home/lexlapax/projects/lexlapax/ipse
ulimit -t 30
export ERL_FLAGS='+S 2:2 +A 1 +SDcpu 1 +SDio 1'
exec timeout 35s elixir _build/verification/word-independent-oracle-20261105-01/author/author_oracle.exs
