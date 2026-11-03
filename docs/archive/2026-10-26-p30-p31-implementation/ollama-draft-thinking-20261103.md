# Ollama no-tool draft thinking: focused synthetic check — 2026-11-03

This is focused synthetic evidence for the proposed draft-recovery change, not
full P31I qualification or a live Ollama service test. The isolated source was
exported from commit 5c298dccedc4481256b353479db1c04119c458ff with the
eight-file [patch](ollama-draft-thinking-20261103/task-draft.patch). The exact
[preimages](ollama-draft-thinking-20261103/preimages.sha256) and
[outputs](ollama-draft-thinking-20261103/outputs.sha256) allow a reviewer to
check that patch against those files in the repository. The source export omitted
historical archive data. The build and tests ran in that isolated tree.

Ollama no-tool draft intervals may now contain bounded valid UTF-8 native
thinking while the complete authenticated interval is withheld from later model
input. The shared strict plain-text predicate still refuses nonempty thinking
for its other callers. Unknown native fields, malformed thinking, tool calls,
changed text and unsafe boundaries remain refusals; ordinary thinking outside
the withdrawn interval remains part of the provider continuation. This check
does not establish recovery for Ollama drafts containing tool exchanges.

The exact frozen candidate and build fingerprints are recorded in
[frozen-pretests.sha256](ollama-draft-thinking-20261103/frozen-pretests.sha256).
That manifest refers to the original isolated tree and its generated runtime,
not solely to files in this archive. The separate
[evidence manifest](ollama-draft-thinking-20261103/evidence.sha256) covers the
retained patch, preimage/output manifests, test entry, and logs in this bundle.

An offline isolated build using the task-owned synthetic dependency cache
passed, as did project compilation in both build environments with warnings
as errors, bundle construction and the changed-file format check. Third-party
dependencies emitted warnings in both build logs. The test lockfile
matched the cache lockfile. HOME was inherited unchanged; the run used explicit
synthetic IPSE_HOME, temporary paths, and fixture Session homes. Source review
shows the explicit Session home suppresses shared operator-home skill
discovery; no OS-level home-access trace was taken. Only synthetic loopback
provider responses were used.

The [direct ExUnit entry](ollama-draft-thinking-20261103/task-focused.exs)
avoided the ordinary helper's HOME reassignment and checked the loaded Session,
draft, Ollama and saved-replay module paths. It ran four selections:

- [Projection](ollama-draft-thinking-20261103/projection.log): seven passed,
  covering whole-interval withdrawal and malformed/unsafe native shapes.
- [Actual Session](ollama-draft-thinking-20261103/vertical.log): one passed,
  nineteen excluded; it exercised cancellation, an independently synthesized
  acceptance journal, and subsequent/resumed synthetic Ollama requests.
- [Native acceptance](ollama-draft-thinking-20261103/accept.log): one passed,
  eight excluded; the native terminal path checked acceptance, later requests,
  reopening and non-disclosure in terminal output.
- [Native cancellation](ollama-draft-thinking-20261103/cancel.log): one passed,
  eight excluded; the native terminal path checked cancellation, later requests,
  idle reopen and non-disclosure in terminal output.

The passing test logs were checked for the synthetic thinking canary before
packaging. The patch includes synthetic test inputs; no private transcript or
live account was used. A full integrated suite and release verification remain
separate gates. The cancelled and accepted controls do not prove arbitrary
provider extensions, malformed responses beyond the cases tested, or a
production server's behavior.
