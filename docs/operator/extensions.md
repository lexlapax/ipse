# Extension installation status

P22–P25 implementation is authorized and underway. The first increment adds an
inert local artifact store for developer integration. There is **no extension
install/enable CLI or session activation yet**. Ordinary chat, approvals and
recovery behavior are unchanged. Do not copy an extension onto Ipse's code path.

The current Elixir API is `Ipse.Extensions.Store.import(source_directory,
store_directory)`; `lookup(store_directory, digest)` verifies a pinned installation.
The dedicated store must be private and controlled by the operator. Import copies
only manifest-declared files, verifies hashes and does not execute code, install
dependencies, download files, enable hooks or grant permissions. It can store
artifacts incompatible with the current runtime; executable admission will be a
separate check. See the [artifact contract](../developer/extension-artifacts.md)
for authors and the [plan](../plan.md#p22-extension-scaffold-and-lifecycle-hooks)
for remaining work.

Keep the returned digest for exact identity. Changing source files after import
does not change the installed snapshot. A missing or corrupt installation fails
verification; import will not overwrite it. A busy import lock fails safely and
may be retried after the other importer exits. Lock files remain in place.

After an interrupted import, `.staging-*` directories in the dedicated store are
inert. Inspect and remove abandoned staging only when no importer is running;
never delete active lock files. No automatic garbage collector or repair command
exists yet. Private permissions do not isolate trusted extension code from the
operator's OS account; worker separation will not itself provide an OS sandbox.
