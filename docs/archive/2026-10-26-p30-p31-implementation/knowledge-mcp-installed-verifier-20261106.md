# Package and installed knowledge MCP verifier — 2026-11-06

The isolated package checkout `_build/verification/p31-package-20261106-01/source`
was copied from frozen snapshot 06, based on commit
`8304dd4c5357b0786b27540713d3c868f39cb0f1` plus uncommitted patch SHA-256
`4b458b4ec0161fb51c64710a39c63676043730127edf987ebc3581fc4dcec9cc`
and allowlisted additions. It is not a clean build of that commit. It retains the
original test wrapper SHA-256
`54498587788144d5539a30eda32ad153a124fad0cd907434eb19dfa188ead659`; the
separate focused-test checkout later received the two-adapter test-only wrapper
repair described in [its record](completed-backup-wrapper-repair-20261106.md).

The package build produced `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`,
SHA-256 `f808631741a05660ba2a6c093248b24b67189fed16df38843a0c5503bbf0002e`.
The retained `package-build.log` SHA-256 is
`7b4b594f2299a081082f7641571395f617f6de04790344a18d44b2fc8ce1dcd1`.
Dependency compilation emitted an `elixir_uuid` `use Bitwise` deprecation
warning; the package log reports the release, four bundles and documentation
check. The package's embedded source reference is the base commit and does not
by itself describe the additional working patch.

The initial full preexisting-file post-build checksum check failed and remains
in `source-post-check.txt`, SHA-256
`7b49def248f742b87d7e89ba9e92ba6aaed90c87f3868bd51c7f052e45d955a3`.
An independent recursive comparison without following symlinks reported one
changed preexisting file: generated Telemetry rebar compiler cache
`deps/telemetry/_build/prod/lib/.rebar3/rebar_compiler_erl/source.dag`. Added
paths were generated `_build`, `dist`, and `priv` runner, PDF, notices and
bundles; no other differences were reported. This scoped classification was
reported in a team message, without a separate retained comparison receipt; it
does not turn the original full checksum check into a pass.

The installed-mode synthetic MCP verifier returned exit 0, as observed in the
tool receipt; no separate exit file was created. Its retained log
`_build/verification/p31-focused-run-20261106-04/mcp-installed-verifier.log`
has SHA-256
`7a13fd10d49126b26af8838a7b11ec0e8dd94fb21e93c9be08e8d7b1fbe38b4c`.
It reports nine checks, selected-only coverage, zero denied dispatches and model
requests, no domain modules loaded into the host, and no replay of the deliberate
unknown outcome. The archive and selected MCP artifact file sets and hashes
matched their pre-verification inventories.

The synthetic evidence root remains under
`_build/verification/p31-focused-run-20261106-04/mcp-installed-evidence/runtime/tmp/ipse-knowledge-mcp-d2cc5c2999d03b91bb526904cbedd1e8`.
Its `cleanup.json`, SHA-256
`dfba6de5ab561aec15cacf66defde7241fbf4cdd1ad2b397123cba15dbabcf8c`,
reports eight confirmed Session closes, none unconfirmed, and backend process
exit. The receipt covers Session acknowledgement and backend process exit only.
An independent point-in-time host audit reported no matching processes and free
Input and TCP resources; that report has no separate retained audit file and is
not a guarantee about all descendants. The unknown journal and synthetic
records remain retained. This package-specific selected-source proof does not
establish real remote-service behavior, full namespace ranking, paid inference,
or complete P31 qualification.
