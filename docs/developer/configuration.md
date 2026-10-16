# Configuration contract

`Ipse.Config.resolve/4` loads bounded version-1 JSON using existing Jason and
the existing `Ipse.MCP.Schema`/JSONSchex adapter. JSON is suitable for a small,
data-only closed schema; no YAML parser or executable configuration is needed.
The loader never reads auth, journals, arbitrary environment dumps or credential
values. Environment inputs are a fixed allowlist. Errors omit file contents.

Discovery canonicalizes the workspace, stops at the nearest ancestor `.git`
directory/file, and enumerates root-to-cwd scopes. With no Git boundary it uses
cwd alone. File reads cap bytes independently of stat size; malformed, oversized,
unknown-version/field and escaping project aliases fail closed. Missing default
files are optional; explicit operator paths are required. Project settings require
explicit current-run trust. This authorization does not replace effect approvals.

The schema also accepts validated named `profiles` and `roles`; see the
[profile contract](model-profiles.md). All profile definitions and assignments
participate in resume fingerprints. The result contains effective string-keyed settings, field provenance, source
path/canonical path/scope/SHA-256 and a canonical fingerprint over effective
settings and source descriptors. Field provenance is excluded from the fingerprint
so equivalent explicit overrides do not invalidate resume. Source content drift,
including whitespace, does invalidate it conservatively. No raw file is journaled
or inserted into model context. The CLI converts only fixed known field names to
runtime keys, and persists the manifest in session metadata.

`Session.info/1` exposes the non-secret manifest. Resume compares fingerprints
before acquiring work or requesting inference. Legacy metadata without a manifest
accepts only a config with no loaded files, retaining existing provider/model/
sandbox/MCP/delegation checks. Embedded Session callers may omit configuration;
the CLI always resolves it. Instruction refresh deliberately does not reload
execution configuration. An operator starts a new session after policy changes.

See [operator configuration](../operator/configuration.md) for supported fields,
limits, flags and examples. Fixtures cover precedence, nearest-repository scope,
project trust, aliases, malformed files, secret exclusion, local CLI inspection,
durable metadata, source drift and idle resume without replay.

## Extension selection data

P22A3 adds top-level `extensions` and `extension_trust`, validated through
`Ipse.Extensions.Config` and the existing schema adapter. Closed instance/trust
records, bounds, whole-instance scoped replacement and deterministic ordering are
specified in [operator extensions](../operator/extensions.md#configure-selections).
Only operator sources may declare trust; enabled project instances require the
matching operator artifact ceiling with `allow_project`. CLI instance selection
is temporary, while `--no-extensions` disables selections. Validation/discovery
never opens an artifact, invokes code or installs it. Activation must separately
revalidate hashes/runtime/options, capabilities, child scope, trust/lease expiry
and revocation before invoking callbacks. The CLI currently refuses enabled
selections explicitly because session activation is still pending.

Config JSON now rejects duplicate keys recursively using Jason's ordered decoder
behind the existing artifact decoder. Fingerprints include resolved extension
selection, options and trust when nonempty; unchanged no-extension configurations
retain their earlier fingerprint exactly. Inspection/journal manifests replace
option contents with a canonical SHA-256, retaining selection identity and source
provenance. This is not credential encryption: operator configuration remains a
data file, and credentials must not be placed in extension options.
