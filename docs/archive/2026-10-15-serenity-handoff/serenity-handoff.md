> Historical handoff archived on 2026-10-15 after the Serenity return checks.
> Use [current testing and evidence](../2026-10-18-before-manual-rewrite/docs/developer/testing.md#p0-closure-on-serenity-2026-10-15) and [the plan](../../plan.md).

# Resume development on Serenity

This handoff returns Ipse development from the Mac to Serenity after implementing
native macOS shell execution. Use `origin/main`; the implementation is `2ffcad2`,
with formatter compatibility in `f07d3f2` and corrected compiler-policy tests in
`3c349f5`. Pull the later documentation commit containing this handoff as well.
The Mac worktree was clean before writing the handoff. The implementation CI
passed on Linux x86_64 and macOS 14 arm64.

## Restore the Linux baseline

Inspect the existing Serenity branch and worktree first. Preserve local changes;
do not reset, clean, force-push, or overwrite them to match the Mac.
On a clean `main`, update with:

```sh
git fetch origin
git pull --ff-only origin main
```

Read `AGENTS.md`, [the plan](../../../docs/plan.md), [architecture](../../../docs/developer/architecture.md),
[native policy](../../../docs/developer/sandbox.md), and [verification evidence](../../../docs/developer/testing.md).
Rebuild the helper on Serenity; a Mac helper or archive cannot run on Linux.

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test --include native_sandbox
IPSE_HOME=$(mktemp -d) ./bin/ipse demo
./scripts/package.sh
```

Run `elixir scripts/verify-package.exs` with the exact Linux archive path printed
by packaging. If multiple archives exist, do not pass a wildcard selecting all
of them. Record Serenity's actual kernel, architecture, Elixir/OTP, Rust, test
counts, and native-enforcement results in [testing](../../../docs/developer/testing.md). Linux native
enforcement needs Landlock ABI 6+ and permitted unprivileged namespaces; an
included enforcement test that cannot activate is a failure, not a pass.

## What changed on the Mac

`--sandbox native` now selects `macos-workspace-v1` on supported Macs. The
Elixir supervisor prepares a protected per-workspace signing cache; the Rust
supervisor independently verifies the signed App Sandbox worker before shell
execution. Failed setup never retries unsandboxed. Trusted execution remains
the default, and approval policy remains separate.

The user selected native Mac execution after reviewing the process-cleanup gap.
File and network restrictions are enforced, but detached `setsid`/`setpgid`
children can survive cancellation, timeout, or owner death and keep writing
inside the workspace. Their App Sandbox restrictions persist. This accepted
limit is documented in the CLI and tool description; do not silently describe
macOS cleanup as equivalent to Linux confinement.

The cache is under `IPSE_HOME/sandbox/macos`, defaulting to
`~/.ipse/sandbox/macos`, with owner-only permissions and a 32-generation cap.
It validates manifests, digests, signatures, exact entitlements, ownership,
permissions, links, and expected entries. Preparation uses persistent locks,
staged signing, and atomic publication. The active application, helper, and
cache cannot overlap the writable workspace. Install a bundle outside the
workspace to use native mode on Ipse's own checkout.

Commands for the same workspace generation share data and an OS app container.
Temporary-home cleanup is best effort, and OS-managed containers persist.
Per-process limits cover core files, descriptors, regular-file size, and CPU;
there is no aggregate memory/disk or private process quota. Homebrew and
`/usr/local` tool roots are readable. Toolchains installed elsewhere may be
unavailable; the backend does not expand permissions automatically.

Key implementation files are `lib/ipse/macos_sandbox.ex`,
`native/ipse-macos-sandbox.rs`, `lib/ipse/runner.ex`, and `native/ipse-runner.rs`.
Cache fixtures are in `test/macos_sandbox_cache_test.exs`; actual Mac enforcement
is in `test/macos_sandbox_test.exs` and `test/support/macos_native_probe.rs`.
Fresh-package checks now exercise native Mac file denial and ordinary timeout
cleanup through `scripts/verify-release.exs`.

## Verification before transfer

On macOS 26.7.2 arm64, source build, both Elixir 1.18/1.20 formatter checks,
warnings-as-errors compilation, credential-free default and native CLI demos,
and fresh-package checks passed. The final full suite passed 122 tests with
seven Linux enforcement tests excluded, including all nine Mac enforcement tests.
Sixteen cache tests are fake-helper fixtures, separate from actual OS checks.
Fresh-package verification used isolated HOME/IPSE_HOME and no development
toolchain on PATH. No live model inference or release publication occurred.

The [final CI run for `3c349f5`](https://github.com/lexlapax/ipse/actions/runs/38758452442)
passed both platforms: build, formatting, warnings-as-errors compilation,
ordinary tests, demo, packaging, and fresh-home bundled verification. The Mac
also passed the Rust policy-parser test, all nine production enforcement tests,
and the experimental signed-helper file/network probe. Compilation from the
local Homebrew tool root passed; CI verified denial of its working toolchain
outside the fixed readable roots. CI does not run Linux native enforcement;
repeat that check on Serenity using the command above.
See [the detailed evidence](../2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-native-backend-2026-10-15).

## Continue from Serenity

Fix concrete Linux regressions first, then review the first incomplete P0
acceptance item in the plan. Broader account eligibility and usage-limit behavior
remain open; fixtures do not establish live account access. Windows, MCP,
subagents, and remote execution remain future work, not authorized additions.

Keep the core in Elixir/OTP and Rust limited to OS helpers. Built-in Mac
`codesign` is approved; no new dependency, private API, deprecated
`sandbox-exec`, or VM was added. Follow the dependency inventory and approval
policy for future additions.

Pull source and documentation only. Do not transfer Mac credentials, token files,
session journals, caches, app containers, `_build`, or release archives. Use
Serenity's existing login or sign in there if a live check is needed; never
silently switch provider or API billing. Commit and push verified focused work
after reviewing developer/operator docs and checking links, as `AGENTS.md` requires.
