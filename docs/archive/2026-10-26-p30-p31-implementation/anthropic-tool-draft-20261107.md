# Anthropic tool-assisted draft withdrawal, 2026-11-07

This is a historical source-runtime record. See the [current plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) for remaining qualification.

Draft withdrawal now admits an Anthropic tool-bearing interval only when its
native tool-use blocks match the normalized calls in order, identity, name and
encoded input. The removed interval, retained prefix and tail must have closed
tool groups, and removed IDs must be unique and disjoint from retained IDs.
Signed thinking and redacted blocks remain opaque; structural validation does
not authenticate signatures. Unknown or inconsistent native content refuses.
The no-tool behavior remains separate. Retained messages stay unchanged in the
projection; the Anthropic adapter renders foreign-provider messages from their
normalized content and calls for its request.

A fresh isolated copy of source `3d409619` with the four draft source/test files
from this change compiled 201 host files and passed seven focused native-shape
tests. A separate synthetic local-loopback Session test passed cancellation,
acceptance, Saved reconstruction and resumed requests with prior native thinking
retained and draft canaries withheld. The complete related Session test file then
passed 25 tests. The focused and full Session runs are separate observations;
the full file includes the focused case. Host checks found no remaining selected
test process, input-lock holder or listener on the test port.

The isolated copy also passed the default `./dev/build.sh`,
`mix compile --force --warnings-as-errors` and the credential-free
`./bin/ipse demo`. The build did not enable the optional PDF parser. An initial sandboxed compile stopped
before compilation because Mix could not open its loopback lock socket; a
separate host run passed using the same offline dependencies. The four Elixir
files passed the project formatter check under Elixir 1.18.5/OTP 27.

The synthetic response fixture supplies complete content blocks rather than
testing streamed deltas in that Session journey. These results do not qualify a
native terminal, installed package, live Anthropic account, model quality or a
full regression on the resulting source. They do not change the earlier failed
[frozen regression](full-regression-3d409619-20261107.md).
