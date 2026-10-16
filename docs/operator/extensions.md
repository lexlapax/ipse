# Extensions

P22–P25 implementation is authorized and underway. Inert import/inspection and
scoped selection configuration are available. **Session hook activation is still
pending**: selecting an enabled extension refuses chat/run explicitly. Ordinary
sessions with no enabled instances retain their behavior and resume fingerprints.

## Import and inspect

```sh
./bin/ipse extension import /path/to/reviewed-local-artifact
./bin/ipse extension inspect DIGEST
```

These local commands need no credentials or model. They copy/verify an artifact
under `IPSE_HOME/extensions/artifacts` (default `~/.ipse/extensions/artifacts`)
and print its pinned digest and manifest. Import verifies declared file lengths
and hashes; it never executes code, builds, installs dependencies, downloads,
grants trust or enables hooks. Incompatible artifacts can be stored. Review actual
code, licenses, dependencies and options before granting trust; a digest establishes
identity, not safety or authenticity. Do not add artifacts to Ipse's code path.
See the [author contract](../developer/extension-artifacts.md).

## Configure selections

Top-level `extensions` and operator-only `extension_trust` extend version-1
[configuration](configuration.md). For example, a disabled instance:

```json
{
  "version": 1,
  "extension_trust": [{
    "artifact": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "capabilities": ["transform.prompt"],
    "allow_project": false,
    "allow_children": false
  }],
  "extensions": [{
    "instance": "annotation",
    "artifact": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "enabled": false,
    "options": {},
    "order": 10,
    "lifetime": "persistent"
  }]
}
```

Replace the illustrative digest with the reviewed artifact's exact digest.
Trust declarations are separate from instances. Project configuration cannot
supply trust, including an empty declaration; `--trust-project-config` does not
relax that ceiling. A project instance can be selected only if operator trust
permits `allow_project`. `allow_children`, capabilities and optional `expires_at`
(Unix seconds) declare future activation constraints; this data-only increment
does not start workers or implement expiry/revocation timers. Options must be
bounded JSON objects; their artifact schema is checked at executable admission.
Do not put credentials in options; provider credentials remain separate.

Instances merge by `instance`; nearer definitions replace the whole earlier
instance. Order is ascending `order`, then instance ID. Limits are eight effective
instances and sixteen trust declarations. `ipse config` displays provenance and
option digests, without printing option contents. An absent artifact is not
installed automatically. Unknown built-in references cannot execute code.

`--extension INSTANCE` selects a configured instance temporarily with lifetime
`session`, without rewriting configuration. Repeat it for multiple instances.
`--no-extensions` disables all configured instances; it cannot be combined with
`--extension`. A persistent selection is an explicit operator configuration edit,
not a side effect of loading a skill or generating code. At present, chat/run
refuses enabled selections until session integration is implemented; use
`ipse config --extension INSTANCE` to inspect the proposed selection or
`--no-extensions` to run without it. There is no live activation/hot reload or
extension resume support yet. These flags do not stop already running sessions.

## Recovery and developer execution

Changing source files after import does not change the installed snapshot.
Missing/corrupt/extra installed files refuse verification; import will not
overwrite an existing invalid digest directory. A busy import lock fails safely;
retry after the other importer exits. Lock files remain in place to preserve
inode identity. After interruption, `.staging-*` directories in the dedicated
store are inert. Inspect/remove abandoned staging only with no importer running;
never delete active lock files. No automatic garbage collector or repair command
exists yet.

The explicit [developer worker API](../developer/extension-artifacts.md#independent-worker-sdk)
can execute a reviewed artifact in a separate Elixir VM using a caller trust
assertion. It inherits no credential environment, but trusted code still has the
operator's OS/filesystem access. Private permissions, worker ownership, deadlines
and cancellation do not themselves provide an OS sandbox. The
[plan](../plan.md#p22-extension-scaffold-and-lifecycle-hooks) tracks session hooks,
durable identity/projections, observability and remaining proofs.
