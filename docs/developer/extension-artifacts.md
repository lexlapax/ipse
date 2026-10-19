# Build an independent extension artifact

An installed extension runs in a worker VM, so its compiled modules do not enter
Ipse's host code path. This chapter takes you through the existing artifact
builder, then explains the manifest, import transaction, and worker protocol you
must preserve when changing the host.

## Build and inspect a package

After building Ipse, compile the local lab in a separate compiler process:

```sh
elixir examples/extension-lab/build.exs --sdk _build/dev/lib/ipse/ebin --output /tmp/ipse-extension-artifacts
```

Inspect `/tmp/ipse-extension-artifacts/lookup/extension.json` and the corresponding
`examples/extension-lab/src/lookup.ex`. The builder writes a license and compiled
BEAM, records their real lengths and SHA-256 digests, and emits runtime constraints
for the current machine. Nothing is installed or enabled by this command.

Follow `examples/extension-lab/build.exs` when creating another package. Supply
an entrypoint implementing `Ipse.Extension`, compile in a separate VM, declare
every runtime file, and write the descriptor after obtaining the final bytes.
Do not copy placeholder hashes or claim another platform without testing it.
The builder's `spec.exs` supplies the same declarations used by executable
`describe/0`, which prevents two handwritten contracts from drifting.

## Descriptor and identity

`Ipse.Extensions.Manifest.decode/1` accepts UTF-8 `extension.json` up to 16 KiB.
Objects reject duplicate keys at every depth. The required fields are:

| Field | Value |
| --- | --- |
| `format`, `sdk`, `protocol` | Integer 1 |
| `id`, `version` | Package identifier and display version |
| `backend` | `elixir_worker` for imported artifacts |
| `entrypoint` | Compiled Elixir module name, handled only in the worker |
| `license_file` | Declared relative license path |
| `capabilities` | Exact declared capability strings |
| `options_schema` | Bounded object schema |
| `runtime` | `elixir` requirement, admitted OTP majors, exact platform strings |
| `files` | Relative path, byte count, and SHA-256 for each file |

Optional `exports`, `requires`, and `subscriptions` add
[catalogs](extension-invocations.md), [service dependencies](extension-services.md),
and [notifications, jobs, or feeds](extension-events.md). These are inert data.
Capability declarations are requirements, not operator grants. Unknown operations
or unsupported declaration shapes fail validation.

Artifact identity is SHA-256 of the original manifest bytes. Because those bytes
bind the file inventory, changing code, options schemas, or even manifest
whitespace creates a new identity. Display versions do not select mutable code.

An artifact has 2–64 files, each at most 8 MiB and together at most 32 MiB. Paths
are portable ASCII relative paths, at most 256 bytes and eight components. Absolute
paths, traversal, backslashes, manifest replacement, and file/directory prefix
collisions fail. The inventory must include the license and entrypoint BEAM.
Options and descriptor schemas use the [bounded schema subset](mcp.md#schema-subset)
without external schema loading.

`Manifest.compatible?/1` checks Elixir `Version` requirements, OTP major, and exact
`:erlang.system_info(:system_architecture)` strings. Import may store an
incompatible artifact, but activation rechecks and refuses to execute it. A BEAM
file alone is no claim of cross-OTP, native-library, or platform compatibility.
Manifest validation does not execute or inspect compiled code and cannot certify
its safety, licensing, or dependencies.

## Store behavior

Read `Store.import/2` with `test/extensions_store_test.exs`. Import captures only
declared regular files, verifies lengths and hashes, and publishes a private
staging directory with an atomic rename. Directories use 0700 and files 0600.
Synced writes and a per-digest native advisory lock keep cooperative imports from
publishing a normal partial snapshot. A busy import fails. Unlock releases the
OS lock but leaves its inode in place.

The return value is `{:ok, %{digest: digest, manifest: manifest, path: path}}`.
`Store.lookup/2` revalidates manifest bytes, declared files, and installed inventory.
Missing, changed, extra, or symlinked entries fail. It never repairs or overwrites
an invalid digest directory. Interrupted `.staging-*` directories remain inert.

Store roots and descendants reject symlinks. Ancestors of the selected root are
trusted. Inventory inspection has a 1,024-entry cap after ordinary directory
listing. These checks protect ordinary API operations, not malicious same-user
filesystem races. Content addressing is neither publisher authentication nor an
OS read-only mount.

## Independent worker SDK

The public callbacks in `lib/ipse/extension.ex` are:

```elixir
@callback describe() :: object()
@callback init(object()) :: {:ok, term()}
@callback handle(String.t(), object(), term()) :: {:ok, object(), term()}
```

Public `object()` values use string-keyed JSON maps. PIDs, references, functions,
structs, and arbitrary Erlang terms cannot cross the bridge. Private state can
contain ordinary runtime terms. `Ipse.Extension.validate/1` delegates to the shared
bounded JSON adapter, with 16 KiB encoded-object, string, depth, and collection
limits. A string is at most 8 KiB, nesting depth is at most 12, and a map or list
has at most 128 members. Schemas independently allow at most 32 KiB encoded,
depth eight, and 256 schema nodes. Keep the full enclosing callback object within
its limit rather than budgeting only the domain value.

A raw developer call to `Worker.start/1` supplies `owner`, `store`, `digest`,
`trusted`, and schema-valid `options`. `trusted` must equal the selected digest.
It is a caller assertion; Session supplies it only after configuration/trust
admission. Initialize with `Worker.call(pid, "initialize", options)` using those
exact options before calling a declared stage. `describe/0` must match SDK,
capabilities, and normalized exports/requirements/subscriptions exactly.

Only one call may be active. Competing calls return `:extension_busy`. Calls
default to five seconds; explicit deadlines are 1–30,000 ms. Duplicate
initialization and undeclared stages refuse. Session adapters may impose narrower
stage-specific deadlines and result schemas.

## Worker boundary

`Worker` launches current ERTS with a clean boot and the existing Elixir,
Jason, Ipse SDK, JSONSchex, and ex_json_pointer code paths plus the selected
artifact. It starts Elixir, not Ipse's application tree. Executable module loading
waits for initialization. The host does not create module atoms from artifact
identifiers or load the worker's BEAMs.

The native launcher clears inherited environment, selecting only caller PATH and
baseline LANG before ERTS derives its own runtime variables. Options and the
purpose-specific payload cross the boundary; credentials, provider continuation,
and Session state do not. Package execution remains trusted OS-level code.

Protocol 1 uses 32-bit length-prefixed JSON objects, at most 32 KiB per envelope,
and monotonically increasing call IDs. Stdout belongs exclusively to the protocol.
Use binary standard IO; `-noinput` is incompatible. Unexpected stdout, duplicate
JSON keys, wrong versions/IDs, and malformed results fail closed. Stderr is
discarded rather than copied into diagnostics. Total stdout/stderr traffic is
capped at 64 MiB per worker lifetime.

Owner death, timeout, process exit, or protocol failure closes the owned native
stdio process group. Calls are not restarted. `Worker.close/1` reports the native
cleanup result; resource leases preserve actual cleanup receipts even when the
callback fails. Process disappearance alone cannot prove descendant cleanup.
Status formatting exposes readiness and counters, not options or payloads.

## Exercise an incompatible package

In a scratch copy of a built artifact, change its runtime platform and rebuild
its manifest identity through the builder. Confirm inert storage can succeed
while activation refuses before executable initialization. Then change a declared
file after import and confirm lookup refuses it. Use fixture files rather than
editing a real installed store.

```sh
mix test test/extensions_store_test.exs test/extensions_worker_test.exs
```

Store tests establish inert import, path/schema/hash limits, corruption refusal,
and locking. Worker tests compile independent modules and check explicit trust,
handshake, environment exclusion, deadlines, protocol failure, contention, and
owner death. Continue with [hooks](extension-hooks.md) or
[invocations](extension-invocations.md) to learn how Session journals execution.
