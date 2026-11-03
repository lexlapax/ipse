# Signed native forget/rejection recapture controls — 2026-11-03

Two existing native-review controls passed after the pending-read containment was
committed. They use trusted synthetic source members. They do not establish an
actual original source Session, a bundled-worker recapture, a real model or human
review, installed behavior, legacy public override authority, or general P31
completion.

The first control performs native-reviewed Core forgetting, then asks the real
signed `NormalizerV3` path to recapture the same support. Normalization refuses,
the signed suppression remains, and an import request carrying the earlier
snapshot's floor and deleted note is refused by the floor check. The second
performs native-reviewed candidate rejection after capture
revocation, then the same signed normalizer refuses the exact candidate while
the shared source/anchor and other records remain. Those assertions are the
fixtures' scoped behavior; neither test proves a worker's handling of a legacy
`override.*` value.

The isolated source snapshot was committed
`d0dcaf03fa64da0eef3fe3eefa064a748e88d5a5`, without duplicate archive material,
under `/tmp/ipse-native-recapture-d0dc.2VrTDm3l`. Dependencies were copied to
the snapshot and it used its own build, `IPSE_HOME` and temporary directory.
Two test-runner files were overlaid solely to remove their subprocess `HOME`
overrides. Their source fixture scripts and the committed runtime were unchanged.

The isolated build passed with
`IPSE_BUILD_COMMIT=d0dcaf03fa64da0eef3fe3eefa064a748e88d5a5 ./dev/build.sh`.
The command

```sh
mix test test/ipse/session/managed_lifecycle_test.exs:5 test/ipse/session/pending_rejection_test.exs:9 --include native_sandbox --max-cases 1 --seed 797151
```

passed **2 tests**, with 5 excluded, in 16.5 seconds. Both commands used the
snapshot's isolated `IPSE_HOME` and `TMPDIR` and `ERL_FLAGS='+S 2:2 +A 2'`,
with loopback access for Mix. No failure occurred in these build or test runs.

Selected tested source and overlay SHA-256 values:

```text
b8647f801ffba66a28b899bd8d8550813fc64d331083b6f7176c539271143e7d  test/ipse/session/managed_lifecycle_test.exs (runner overlay)
05ba40dd1aa6c93232639c047b7e4ce42384d927866c815a80356fa52dd877f2  test/ipse/session/pending_rejection_test.exs (runner overlay)
febd5f974a491ce48cbbc2cec436134e95dead86f275f1601e4aa697f8be41b6  test/support/managed_literal_forget.exs
fa43b89492b837c0d5490eb7bf8c451575081c4b670cf15041757e5a19ebd683  test/support/pending_rejection.exs
dce67f134851789ccba1fd49a33eacd42444371a99c9e0e89e14c881a98e46c1  test/ipse/extension/collection_normalizer_v3_integration_test.exs
b5ad0e5378ed5e067e5755b03c045b2c71dc85881e3499fbf581e4cd5db31462  lib/ipse/extension/collection/normalizer_v3.ex
8120252a2dcca1649d327c1e5472d025b5ebd0555a9243d51030604445c9e3e1  lib/ipse/extension/managed_read.ex
f230734a0a34487ce29bb55394f1dab178407885a34403d8160ab374b6c8d11c  test/support/operator_pty.rs
```

Logs remain in `/tmp`:

```text
8f64bcef07363a6232fbb4d5148fa7aa58668179ee37839e9fe9599ff407d7d6  ipse-native-recapture-build.log
c8409a8b70bc03af780c48dc9adc0d960018fc055f2e66a85338eaf09538ba9f  ipse-native-recapture-controls.log
```

These are selected file hashes and a committed-base identity, not a complete
pre/post inventory of the generated build or native helpers.
