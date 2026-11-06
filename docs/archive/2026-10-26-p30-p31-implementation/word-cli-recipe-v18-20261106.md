# Word CLI recipe fixture qualification

Dated **2026-11-06 UTC**. Historical synthetic verification record only.
The [Corpus manual](../../operator/corpus.md) owns current document procedures,
[Testing](../../developer/testing.md) owns contributor checks, and the
[plan](../../plan.md) owns remaining qualification. This focused result does not
replace the [interrupted 489-file regression](source-regression-489-20261106.md)
with a complete baseline.

The frozen regression's document setup case stopped on a stale fixture literal:
it expected extraction recipe `ipse-documents-v17`, while the bundled document
artifact reported `ipse-documents-v18`. The correction changed that expectation
to the current recipe; it did not relax native review, provider selection,
Session, disable or source checks.

After the current normal build completed, one fresh invocation ran:

```sh
mix test --no-compile --no-deps-check --max-cases 1 test/ipse/cli/documents_test.exs:46
```

The selected case exercised **both State and Collection**: native setup, a new
Session, preserved source/provider selections, and disabling the profile.
It passed with **one outer test passed, five excluded**, in **32.2 seconds**,
seed `922581`, exit status zero. No excluded case is claimed as tested here.

The execution used an isolated credential-free home and temporary directory.
The unchanged test and product deadlines were enclosed by a 180-second
coordination bound with a ten-second kill grace. Pre/post runtime, dependency,
`priv` byte inventories, raw links, production sources and selected fixture
sources matched. Mix's test-failure cache was the sole excluded mutable runtime
metadata file. Input, listener and scoped owned-process checks had no holders;
all holder/error/group outputs were empty. A separate actual-host neutral check
passed after the test owner exited. No test or native operation was retried.

Private evidence is retained under
`word-cli-recipe-v18-focused-20261106-01/run-01`. SHA-256 identities:

| Evidence | SHA-256 |
| --- | --- |
| Safe result | `dee3395de2162e6acab6a99333afdc294de24c62d6ddd673f7a9014f0433fe27` |
| Test and postcheck status | `6ddc5cb75feb3501c5c01511972820795586b4786a3c8ffc0aa79c179727b896` |
| Independent neutral status | `3f46889d3da05937469df21a7f6a8dbb845c6952d1e0179635538a977d244e03` |
| Selected test source | `442f24c931ec88aced010e71f58ec79ede9f56e9f58b7f44964412c4e2b3880b` |
| Corrected setup fixture | `16fcf7cb967d606b6b7d620adcd612c7e4cddbcc68ccdc826e6f59d75b192c8b` |

Native review output and private fixture journals are not exported. This check
does not qualify PDF behavior, model quality, paid/live inference, the whole
default suite, or the denied original retained-notebook recall. The earlier
frozen failure and interrupted aggregate remain unchanged.
