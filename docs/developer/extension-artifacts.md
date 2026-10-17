# Extension artifact contract

P22A1 implements inert local directory snapshots in `Ipse.Extensions.Manifest`
and `Ipse.Extensions.Store`. The [SDK/lifecycle design](extensions.md) remains the
target beyond the implemented [session hooks](extension-hooks.md) and
[typed invocations](extension-invocations.md). Import
remains inert; explicit scoped selections can execute reviewed workers through
the SDK below. Configuration and CLI procedures are described in
[operator extensions](../operator/extensions.md).
See [operator status](../operator/extensions.md) before trying installation.

## Descriptor and identity

The source directory contains UTF-8 `extension.json` (at most 16 KiB). Every
object rejects duplicate keys, including nested schemas. The closed format is:

```json
{
  "format": 1,
  "id": "example/annotation",
  "version": "0.1.0",
  "sdk": 1,
  "protocol": 1,
  "backend": "elixir_worker",
  "entrypoint": "Example.Annotation",
  "license_file": "LICENSE",
  "capabilities": ["transform.prompt"],
  "options_schema": {"type": "object", "additionalProperties": false},
  "runtime": {
    "elixir": ">= 1.18.0",
    "otp": [27],
    "platforms": ["aarch64-apple-darwin"]
  },
  "files": [
    {"path": "LICENSE", "bytes": 0, "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
    {"path": "ebin/Elixir.Example.Annotation.beam", "bytes": 0, "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}
  ]
}
```

This illustrative descriptor uses empty files, not runnable code. Authors must
declare actual hashes, license bytes, compiled entrypoint and tested runtime
targets. Platform identifiers are exact `:erlang.system_info(:system_architecture)`
strings; inspect the target rather than copying the illustration. OTP admission
uses major versions, not an ABI promise. Elixir requirements use `Version`.
Import permits incompatible artifacts for storage; activation must call
`Manifest.compatible?/1` again and refuse incompatible code.
The optional `requires` object declares [typed service requirements](extension-services.md),
not executable dependency discovery. Import validates aliases/version/schemas;
activation resolves only explicit operator routes to already selected targets.

Artifact identity is SHA-256 of the **original manifest bytes**, which bind every
declared file's hash and length. Whitespace changes create a different identity.
IDs/versions are descriptive, not a mutable lookup alias. Files number 2–64,
each at most 8 MiB, totaling at most 32 MiB. Paths are portable ASCII relative
paths of at most 256 bytes/eight components; traversal, backslashes, absolute
paths, manifest replacement and file/directory prefix collisions are rejected.
The license and named entrypoint BEAM must be declared. Validation never loads
or inspects BEAM code; syntactically valid manifests do not certify safe code,
licensing, dependencies or functional compatibility.

Options reuse the bounded JSON Schema subset in
[MCP schema policy](mcp.md#schema-subset), backed by existing JSONSchex with no
external loader. Capability strings are declarations, not grants. The session
host negotiates its supported capabilities explicitly. The optional `exports`
field declares inert version-1 tool/command/service descriptors and is required
for the corresponding `invoke.*` capability; see the
[catalog contract](extension-invocations.md#inert-declarations). Imported artifacts
cannot claim the built-in backend or cause arbitrary host atom creation.

## Store behavior

`Store.import(source_directory, store_directory)` captures declared regular files
and verifies lengths/digests before publication. Unlisted source files are ignored
and never copied. Private random staging directories, 0700 directories, 0600 files,
sync writes and atomic rename prevent ordinary partial imports becoming visible.
The existing native helper provides a persistent per-digest advisory lock; busy
imports fail rather than overwrite. Unlock releases the OS lock and preserves its
inode. An interrupted import can leave an inert `.staging-*` directory; it is
never an installed artifact and is not automatically resumed or executed.

The result is `{:ok, %{digest: digest, manifest: manifest, path: path}}`.
`Store.lookup(store_directory, digest)` revalidates the original bytes, every
declared file and the installed inventory. Missing, changed, extra or symlinked
files fail; an existing invalid digest directory is never repaired or overwritten.
The digest does not prove authenticity or grant trust. Installation, operator
trust and session activation remain distinct records.

Store roots are dedicated operator-controlled directories. Root and descendant
symlinks are rejected; ancestors of the explicitly selected root are trusted.
Private permissions and locks protect ordinary cooperative operations, not an
adversarial same-user writer racing filesystem checks or modifying loaded code.
Content-addressed immutability is enforced by the API and revalidation, not an OS
sandbox or read-only mount. Installed inventory inspection is capped at 1,024
entries after directory listing; filesystem listing itself uses OTP's ordinary
directory API. Worker ownership/sandboxing is a separate boundary.

## Verification

`mix test test/extensions_store_test.exs --trace` exercises inert import,
idempotence, pinning/source changes, schema/size/path/hash refusal, nested duplicate
keys, symlinks, store corruption, extra files and lock contention/inode identity.
These fixtures do not yet establish worker execution, trust configuration,
activation, resume or extension-only development. Follow
[testing evidence](testing.md#extension-artifact-foundation-2026-10-16).

## Independent worker SDK

P22A2 adds `Ipse.Extension` and `Ipse.Extensions.Worker` as a developer API.
`Worker.start(owner: owner_pid, store: private_store, digest: digest,
trusted: digest, options: options)` explicitly admits execution; omitting or
mismatching `trusted` refuses startup. This argument is a caller assertion, not a
persisted trust record, signature or project authorization. The session/config
host supplies it only after operator policy validation. Import/inspect/list CLI
commands remain inert; the session host admits explicit hooks and typed invocations.

Admission revalidates the installed snapshot, runtime compatibility and options
schema. The worker launches the current ERTS with existing Elixir/Jason/Ipse
code paths and the selected artifact in a separate VM using the current clean
boot script. Executable module loading waits for `initialize`; it starts Elixir,
not Ipse's application/session tree. Neither code-path changes nor module-name atom
creation happen in the host. The OS helper clears inherited environment, preserving
only the selected caller PATH and baseline LANG; the ERTS launcher derives its
own runtime variables. No credentials, auth
configuration, provider continuation or Session state is passed.

An extension implements:

```elixir
@behaviour Ipse.Extension

def describe, do: %{"sdk" => 1, "capabilities" => ["transform.prompt"]}
def init(options), do: {:ok, options}
def handle("transform.prompt", payload, state), do: {:ok, payload, state}
```

`describe/0` returns a JSON object with SDK 1 and capabilities exactly matching
the reviewed manifest, including exact normalized `exports` for invocation
artifacts. Missing exports normalize to empty for code without `invoke.*` exports,
including transform-only and text-consumer artifacts.
This executable handshake is not a pre-execution certificate: startup intent
precedes loading/describe/init. `init/1` receives validated options once; its private
state stays in that worker. `handle/3` receives a declared capability string and
bounded JSON object, returning a JSON object plus new private state. Arbitrary
runtime terms are permitted only in private state. Public objects use the
existing schema adapter's 16 KiB/depth/string/collection bounds; PIDs, functions,
references, structs and atom-keyed maps cannot cross the bridge.

After startup call `Worker.call(pid, "initialize", options)` with the exact
admitted options, then `Worker.call(pid, declared_stage, payload, timeout_ms)`.
Calls default to five seconds; explicit deadlines are 1–30,000 ms. Initialization
must finish before other stages; duplicate initialization and undeclared stages
are refused. One call may be active; competing calls receive `:extension_busy`.
The protocol uses 32-bit length-prefixed JSON objects (32 KiB envelope maximum),
protocol version 1 and monotonically increasing call IDs. Nested duplicate keys,
incorrect IDs/versions, malformed/non-JSON returns and unexpected stdout fail
closed. Binary standard I/O is required; Erlang `-noinput` must not be used.
Stdout is exclusively the protocol channel; stderr is discarded, never printed
as a callback error. Total native stdout/stderr traffic is capped at 64 MiB per
worker lifetime. These bounds do not constitute an OS memory quota or permission
sandbox for trusted executable code.

The owner is monitored while idle or active. Owner death, deadline expiry,
process exit and protocol failure close the owned native stdio process group;
failed callbacks are not restarted/replayed. `Worker.close(pid)` reports the
native helper's cleanup result. Worker status formatting includes only readiness,
sequence and traffic counters, never options/payloads. The raw Worker bridge is
a developer building block; Session adapters impose stage-specific admission,
effect and recovery rules. [Hooks](extension-hooks.md) commit prompt/display
projections; [invocations](extension-invocations.md) use typed catalogs and finite
[host actions](extension-host-calls.md), including questions, tools, services and
context. [Text consumers](text-streams.md#worker-clients) use a separate read-only
resource lifetime and serializable handle, with no host-action interpretation.
Lifecycle observation, broader nested jobs and the independent installed-package
proof remain [P22 work](../plan.md#p22-extension-scaffold-and-lifecycle-hooks).

`test/extensions_worker_test.exs` compiles a uniquely named independent artifact
with the existing Elixir compiler in a separate VM. It verifies inert import,
explicit trust, options, initialization, separate process/module identity,
credential exclusion, JSON/capability bounds, callback failure/timeout/contention
and owner death. It does not prove an OS sandbox or session resume contract.
