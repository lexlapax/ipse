# Pending proposal generic-read containment, 2026-11-03

This is isolated synthetic verification of a temporary fail-closed containment,
not compatibility restoration, a full repair of pending-candidate assessment,
or P31 completion. Source is commit `fccaf35c0547cce178dfddfa0c45ee8f006121d4`
plus the six listed overlay files in `/tmp/ipse-pending-source-fccaf.yqjY3rci`.
P31I's unrelated live worktree changes were not overlaid or built.

The original safety control failed on committed source plus its initial test
overlay (`9f57482fcc704bf4fcc662d408dba63891be918dadfae9c9abf73ea3cedbcb4b`).
An operator-admitted test worker retrieved the raw synthetic pending value after
its source journal was temporarily unavailable; the result was `ok` and the
only observed dependency version was 3. The journal was restored with its
original inode and SHA-256. That demonstrates the admitted test-worker path,
not arbitrary pending-key access through the shipped `read` or `assess` tools.
The failing log is `/tmp/ipse-pending-source-control.log`; its retained synthetic
root is `/tmp/ipse-pending-source-fccaf.yqjY3rci/tmp/ipse-collection-sdk-47f0a93116c7fd288790bdb69366bef9`.

The candidate refuses nonempty managed value observations lacking a selected
literal recipe; selected literal/accepted records still require the existing
authenticated current-source path. Empty gets and metadata-only index remain
available. The bundled capture worker checks pending duplicates by exact-prefix
metadata index, and never renews or reads the stored pending value. A returned
scan page containing an unclassified value is refused as a whole. This blocks
generic reads of existing overrides and unrelated managed records too; capture
that requires an override can refuse. Restoring those paths requires a reviewed
same-root classification and remains open. The operator/developer text describes
this temporary effect and tells users not to remove an override as a workaround.

Final checks against the isolated candidate, with fresh synthetic homes and
loopback fixtures:

* `./dev/build.sh` passed with `IPSE_BUILD_COMMIT=fccaf35c0547cce178dfddfa0c45ee8f006121d4`.
* The focused Knowledge capture test passed, seed `797142`, including the
  metadata-only pending duplicate, absent key and longer-prefix collision cases.
* Three actual Session controls passed, seed `797148`, in 24.4 seconds: current
  and absent originals; a genuinely signed five-second expiry; and a custom v2
  historical proposal after its recipe was removed. The latter was built by a
  trusted test-side `Collection.execute_managed`/`Normalizer.normalize` call
  using a real synthetic Session source proof and a synthetic historical policy
  digest; it is not evidence of a currently supported Session v2 publication.
  It covered direct get, a targeted scan, a mixed scan, a proof-shaped unsigned
  literal, and synthetic unrelated/override-shaped values. The last two are
  availability-impact controls, not a native-reviewed override workflow.
* Two existing legacy-reader controls passed, seed `797147`: ordinary legacy
  data before conversion and refusal on an intact managed namespace.
* One existing shipped-artifact current recall/capture Session control passed,
  seed `797144`, with two excluded. This is scoped compatibility, not an installed
  or live-account test.
* Test-environment `mix compile --warnings-as-errors` and changed-file format
  checks passed. Independent whole-document review covered the operator and
  developer manuals, and a sanitized git-backed mirror documentation check passed
  1,096 Markdown files and 9,036 links with zero errors. Final combined-tree
  verification remains open.

Failure history is retained. The first attempted custom v2 live Session fixture
became unknown after a delivered Worker input and before a managed-write intent;
the provider listener later timed out. `Session.Invocation.begin_action` refuses
non-v3 `collection.managed` new capture before its intent, explaining the fixture
mismatch. That Session was not retried. A prior capture-unit iteration failed
only because its outer assertion still expected 11 inner tests after one was
added; the exact count was corrected to 12. Neither failure was hidden.

The final candidate hashes:

```text
8120252a2dcca1649d327c1e5472d025b5ebd0555a9243d51030604445c9e3e1  lib/ipse/extension/managed_read.ex
eca1692657b5cdc69cb3083b7cf3d8aa3fa885af97e8a8fafbdea76d91dfaf1a  extensions/knowledge/src/knowledge.ex
7af57b62f3b11fe8096b1608572d7f37681a734e5dac747d4c1382aa454a25b7  test/ipse/extension/managed_collection_call_session_test.exs
9668162dae93550a4e7b359e53dfe78db888da6fc6cdab5e0a2a875fc7acb1d0  test/extensions/knowledge/knowledge_capture_test.exs
2e6c9e76cfc167296606314c8b9b7f6a99d8b7606cf69f645cd1cbadf9f877f2  docs/operator/knowledge-permissions.md
f4f879d837755ffdca6e813d08b10d71e9d05571570a1abd90cb162e7a2e5450  docs/developer/knowledge-extensions.md
```

Logs, retained under `/tmp`, and SHA-256 values:

```text
e6334dd7e943d6d61f4ad65b2c91ab5b3547f0ee69fd35c9d019c0158a293576  ipse-pending-source-control.log
218c9dfbb7d09652b64ed74f571f98f9d973721d652b448f5d85f569723fb372  ipse-pending-source-repair-capture.log
6b3a3614b23afe9e83449fdaac4264004315e53014cffa76836050c7bca82a7f  ipse-pending-source-containment-build.log
f496f9437f9d28ebb611ed83c63e751b320ac38cae6c565e6b73f0154d1b0188  ipse-pending-source-containment-capture.log
0cdf37f45faa880cf34b50e61f9842660895579cba60b740b10c47606ecc4564  ipse-pending-source-containment-native.log
683cf2000731f35879a4aa2d26d0da1b160115afe443df387b0d8921994ee816  ipse-pending-source-containment-final-v2.log
c97eaa8e0d555acd5fa5566efa51780dbe4eaa66857043fbcfca6ac8f2686b53  ipse-pending-source-containment-legacy.log
56034771e7079685782ca1cad4086dc52bc8a398f1cdfa8f4695182acdec3d98  ipse-pending-source-containment-shipped.log
```

The initial three-case run containing the unsupported v2 Session case failed;
the later three-case run used the host-side historical fixture. The existing
legacy and shipped-artifact tests used earlier versions of the Session test file;
the runtime hashes above did not change. The final source and combined-tree
verification must not be inferred from those focused results.
