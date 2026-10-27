# Same-view collection observation foundation

This is a scoped component receipt, not P31 acceptance. The internal
`Collection.ObservedRead` returns a public `get`, `snapshot`, or bounded visible
`scan` value with the exact root witness read from the same checked view. It is
not used by `CollectionCall`, Session, the Knowledge worker, or a provider
route. It does not grant permission or establish current eligibility. The
[lineage design and private prototype](observation-lineage-design.md) describe
the remaining work and the independently found stale-generation issue.

The public scan selector excludes `host.validity.*` metadata before value IO.
The native lock rechecks the view's exact root and the requested generation
before reading selected values. A stale generation refuses rather than
returning the generic scan's conflict result. `get` and `snapshot` preserve
their generic public value shape; successful visible scans match generic visible
pagination. View versions 2 and 3 and indexes over the existing 4 MiB bound
refuse. Snapshot's public probe must be readable if present, even when a generic
metadata-only snapshot would succeed. A witness is historical after view close;
it is not a live root, identity, consent, source or lineage certificate.
Cooperative protected storage and trusted same-BEAM host processes remain the
scope; hostile same-user rewrite or external ABA is not qualified here.

The reviewed [v2 patch](observed-visible-scan-prototype-v2.patch) has SHA-256
`992fedb9503a3f3524aa60fd1f32c4f1ef1193aad200cab2b4ffdff7c475e66d`.
Its checked bases matched the working source before application. The applied
source and focused test hashes were:

| File | SHA-256 |
| --- | --- |
| `lib/ipse/extension/collection.ex` | `4aa238c832b83dbfe36fab221015014728ba911d36dc8cfac7cdf01cc9744d03` |
| `lib/ipse/extension/collection/directory.ex` | `7a6f94f5d0c21e341c926afa1c69208b304536c584256d0b07819dc5003db65e` |
| `lib/ipse/extension/collection/read_view.ex` | `246f8fcb385d484f9f4f54e8b4d5eee01b5869983f663a7fd68f6c3963df3f00` |
| `lib/ipse/extension/collection/observed_read.ex` | `74b6094a25d93dac1e20f54939aed3dc438f8988e56af182f53df49778f170ab` |
| `test/ipse/extension/collection_observed_read_test.exs` | `ebd6a148ebe65d4de120f6d68617508cb3dbc3a11e01247937d5ecca1ea054bb` |
| `test/ipse/extension/collection_read_view_test.exs` | `bf11d3a9410aae2f5d68d5fa56367d883a8d5f3cba412dd6db426c99d3e1d0b1` |
| `test/ipse/extension/collection_directory_test.exs` | `8af5cbc2644607cfb9a903bf0c3ac941cb1558a54f1659a9ae25ba7bfce16d7b` |

The new fixed-source author graph was copied from the working tree, including
other uncommitted work; the table identifies the exact affected source and test
bytes rather than claiming a clean committed revision. It compiled 143 project
files with `MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp mix compile
--warnings-as-errors`. Initial dependency compilation emitted upstream warnings.
The author command below passed 40 tests (seed 20270310):

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp mix test --no-compile test/ipse/extension/collection_observed_read_test.exs test/ipse/extension/collection_read_view_test.exs test/ipse/extension/collection_directory_test.exs --seed 20270310 --max-cases 1
```

The retained [author log](observed-visible-scan-final.log) has SHA-256
`74ff7519455cccae9bbd6614134782123f23ac7348afdaf34a46875561eb00ba`.
An independent copied graph verified the exact five patched source/test hashes,
reviewed the original stale-before-read finding and passed the same three
suites, 40 tests (seed 20270309). Its
[rerun log](observed-visible-scan-independent.log) has SHA-256
`35a94e000fda55605e439dc729b3f5c6728ef91d95a3a3cfdf8dfb358628d0df`;
its command included `ERL_FLAGS='+S 2:2'` and otherwise used the same test
paths, `--no-compile` and `--max-cases 1` with that seed. Both runs excluded
native-sandbox, macOS-sandbox, macOS-filesystem and memory-scope tags.

**Both positive runs used a test-only helper override**, SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`,
that admits this host's otherwise unsupported 7.2.11 kernel in private test
graphs. They do not qualify that kernel, filesystem, installed runtime or live
model. Controls covered native owner loss during a scan, stale generation with
a corrupt selected object, root change between pages, public pagination, and
reserved metadata whose corrupt value must not be read. The independent audit
also checked cursor/limit combinations against the first prototype; these are
not proof of a complete Session/replay/authority protocol.

Before using an observation downstream, the host still needs durable
receipt-to-result binding and replay, conservative worker/session lineage,
current project and policy checks, source eligibility, exact root revalidation
and an authority-holding send/effect barrier. The foundation must not be used
as a substitute for any of them.
