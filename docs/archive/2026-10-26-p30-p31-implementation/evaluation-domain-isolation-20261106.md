# Evaluation host-domain isolation repair

Dated **2026-11-06 UTC**. Historical synthetic verification record only.
[Testing](../../developer/testing.md) owns current verification procedures and
the [plan](../../plan.md) owns remaining acceptance. This focused result does
not replace the [interrupted 489-file regression](source-regression-489-20261106.md)
with a passing complete baseline.

The frozen regression recorded nine evaluation failures before dispatch:
the evaluation harness correctly refused canonical domain modules already
loaded in the host. Two other test owners had loaded those modules at test-file
compilation time. The repair moved their domain controls into the existing
isolated child-suite pattern. It retained the evaluation harness's host-domain
guard; no purge or weaker acceptance condition was added to that harness.

One fresh current-source invocation then ran the victims and both repaired
owners together, so the result exercised their shared compilation boundary:

```sh
mix test --no-compile --no-deps-check --max-cases 2 \
  test/dev/evaluation/session_test.exs \
  test/extensions/knowledge/selection_shadow_test.exs \
  test/dev/evaluation/protected_answer_test.exs
```

It passed **13 outer tests**, with no failures or exclusions, in **28.8 seconds**,
seed `316078`, exit status zero. These comprise eleven evaluation cases,
including the nine original victims, and two isolation wrappers. The wrappers
separately enforce exact passing child totals of nine selection controls and
nineteen protected-answer controls. Those nested counts are **not added** to the
13-test outer result.

The evaluation cases used synthetic worker artifacts, the demo provider with an
unused model, and a denial-only host approval validator. The isolation wrappers
asserted the canonical domain modules were unloaded before and after their
children. No Input reader, native approval journey, real model service, paid call
or original retained-notebook access ran.

The check used a fresh private home and temporary directory, normal application
startup and unchanged default exclusions. Existing test/product deadlines
remained unchanged under a separate 180-second coordination bound and ten-second
kill grace. Runtime, dependency and `priv` bytes, raw links, production sources
and selected fixture sources matched before/after; Mix's test-failure cache was
the sole excluded mutable runtime metadata. Input, listener and scoped process
checks had no holders and empty output/error/group files. Independent actual-host
neutral checks passed after the test owner exited.

Private evidence is retained under
`evaluation-domain-isolation-focused-20261106-01/run-01`. SHA-256 identities:

| Evidence | SHA-256 |
| --- | --- |
| Safe result | `b64b336ee8dcb1321e7a827cc82569c445f972d9417865b54d2e41d1e9789866` |
| Test and postcheck status | `6ddc5cb75feb3501c5c01511972820795586b4786a3c8ffc0aa79c179727b896` |
| Independent neutral status | `3f46889d3da05937469df21a7f6a8dbb845c6952d1e0179635538a977d244e03` |
| Evaluation test source | `d72ca3563cb51b54f91c68e1e405bfa617f0667c471b906f41fc7ec1dc07989b` |
| Selection isolation owner | `b27741565e96927967709a6c08aee03442cb6b8e9d66555c4907814029e26df8` |
| Protected-answer isolation owner | `ea9ffff68a0a200b0ac8206b4d84c53dcf9dfca52c3a068fd1f7f7059cf3b122` |

No private context, journal, answer or native review value is exported. The
earlier frozen failures and unknown aggregate exit remain unchanged. This result
does not establish a complete source baseline, real-engine quality or the
denied retained recall and dependent day/year qualification.
