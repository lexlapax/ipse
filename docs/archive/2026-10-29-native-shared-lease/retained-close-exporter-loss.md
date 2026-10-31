# Retained collector exporter-loss follow-up

2026-10-29. This narrowly follows the frozen [retained-close section](retained-close-infrastructure.md).
The inert four-lease collector now polls all retained exporter pidfds while
waiting for its close request. Previously an exporter dying after collection
could leave the collector holding its transferred locks until its deadline.
The change is a prompt cleanup improvement; it does not make exporter death a
confirmed operation or prove closure of an operator reader or guardian.

The affected real Unix-socket controls passed: a normal four-lock close still
settles, and killing a three-slot exporter after collection causes the inert
collector to exit and drop its copies. Its three independent contenders then
acquire; the separate surviving exporter continues to hold its lock until it
actually exits. The [separate source, binary and log manifest](evidence/retained-close-v4/manifest.sha256)
preserves this cohort. The earlier v3 manifest and failed/positive logs remain
unchanged. The focused controls ran outside the sandbox's Unix-socket
restriction, on the available Linux host.

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o /tmp/ipse-retained-export-helper-v4
rustc --edition=2021 -D warnings dev/fixtures/transaction_lease_export.rs -o /tmp/ipse-retained-export-fixture-v5
```

The fixture's `--retained-close <new-private-directory> <helper> normal` and
`exporter-lost` modes produced the two markers in `control.log`. No terminal,
Session header/resume, managed action, or user-facing gate was enabled or
qualified by this follow-up. The generic source-set capacity, operator all-copy
close, host owner controls, Writer barrier and management journal are still open.
