# Extension artifact contract

P22A1 implements inert local directory snapshots in `Ipse.Extensions.Manifest`
and `Ipse.Extensions.Store`. The [SDK/lifecycle design](extensions.md) remains the
target for activation; this increment does not execute extensions or alter sessions.
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
external loader. Capability strings are declarations, not grants. The future
host must negotiate its supported capabilities explicitly. Imported artifacts
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
