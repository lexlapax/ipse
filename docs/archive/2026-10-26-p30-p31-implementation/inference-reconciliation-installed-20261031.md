# Installed inference inspection and explicit reconciliation

2026-10-31. The [source command and native controls](inference-reconciliation-cli-20261031.md)
now have matching installed evidence. This qualifies the command boundary on the
recorded Linux host, not owned-daemon recovery or the full P31D1 scope.

The standard PDF-enabled package was built from a clean local clone at
`9483ef1418f837cb6e1eb115512720879d632be0`, with locked dependencies and no private
untracked files. Build identity reports Ipse0.1.0, Elixir1.20.4, OTP29, Linux
x86_64. Archive SHA256:
`0b2b31f861542aec644188dd6acb65f920faf8512daa08227ceac4029e30037c`.
Local archive:
`/tmp/ipse-installed-inference-20261031/dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`.
No release was published.

The generic installed-package verifier passed against those exact bytes. Its new
offline inference checks require the exact empty status report despite malformed
conversation configuration, no operator-home creation, unchanged configuration,
and refusal of unsupported flags/noncanonical or absent reconciliation. All
existing installed checks passed too, including native helpers, idle resume,
Memory, MCP, delegation, upgrades and inventory preservation. Verifier log SHA256:
`2c1625a3bd8a78a40e9bacf0e2f107b62a8f0cc45c4a1a8c9e87b6d40fe2f632`;
local log: `/tmp/ipse-installed-inference-package-verify-20261031.log`.

A separate extracted-package proof reused the original source reconciliation
fixture and Rust PTY driver. The fixture's ExUnit bootstrap/import was removed
and its boolean assertions became exact `true =`/`false =` matches so bundled
ERTS could execute it without ExUnit or a development toolchain. The parent
compiled the already-inventoried Rust test driver before launch. Each child had
only declared shell utilities and the release's own runtime. Five independent
synthetic reservations covered confirm, cancel, stale challenge, piped input and
concurrent ledger revision; all passed. Confirmation checks the exact receipt,
cleared active marker and refused duplicate. Refusals preserve the active marker
and ledger bytes except for the deliberately concurrent enqueue. All retain
ledger/service lock inodes and create no conversation/configuration files.

The [sanitized report](inference-reconciliation-installed-20261031.json), SHA256
`10affc1d6a36e1640cf9aae4db7c91ad9b4f4555ed111d5b0c53eec2833f083d`,
pins original/executed fixture, PTY source/binary and each output. Release files
were unchanged. The local launcher is
`/tmp/ipse-installed-inference-proof-20261031.exs`, SHA256
`b6991f42c7379bf6bcfa87228e2467f786df04124e3afc5398571abddfa94503`.
No model, metadata service or daemon request was made. Synthetic active records
do not establish a real remote request's quiescence or authorize clearing one.
Other platforms, actual owned-daemon recovery, final whole-source testing and
P30/P31 acceptance remain open. The whole Recovery and developer verification
chapters were reviewed against the current implementation and actual checks.
Verifier regressions passed35tests in82.5seconds. Format/diff checks passed;
the documentation checker reports978Markdown files/8140local links/0errors.
