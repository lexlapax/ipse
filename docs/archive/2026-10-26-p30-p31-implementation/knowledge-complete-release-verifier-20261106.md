# Knowledge-complete release verifier — 2026-11-06

Historical synthetic verification. The [plan](../../plan.md) owns current
acceptance status; the [testing manual](../../developer/testing.md) describes
current verification practice.

The prior hosted Linux knowledge-complete check failed because it compared the
entire Session journal across close and resume, including the valid signed
release lifecycle. The repaired verifier retains the pre-close and pre-resume
byte/event prefixes and permits only the authenticated owner-bound release
suffixes. It checks the current signed release claim on the Linux layout and
the unchanged journal on the legacy layout. It retains the complete-result,
citation, contradiction, idle, no-model-request and named-module checks. The
named-module check is not an exhaustive artifact inventory, and this proof does
not separately count Research worker callbacks.

Three pure tests pass for the release checks and harness declaration. On the
`546869c8` runtime, separately built synthetic Corpus, Graph and Research
artifacts passed both the source proof and the PDF-enabled installed-package
proof. Each used fresh private state, retained the original result, verified
source/SDK/artifact pins after execution and reported zero model requests.
Both observed signed first-close and resume claims. Independent host checks
found their owned process groups gone and the Input lock and TCP 39657 free.
These passes do not retroactively repair the original hosted failure or prove
macOS, newer runtime changes, live accounts or full P31 acceptance.

The source result log SHA-256 is
`8c0f0ae7cff7e75379b0395469225d93949ebfae13cd2fa0ceff17ac806d0f7a`;
the installed result log SHA-256 is
`edd5987d4d3b5b402e605e3556fdf440e96c115d4d893df487317c09bd6ac4bf`.
Both status receipts hash to
`b285f2b06561d106ceb490c58e6ab2eae9e72f9869ee78eac769d0733da9e2e0`.
The installed archive SHA-256 is
`9d6ade8ef734471e0d762e2b880cf6f0047c3aa9c03b82c8fb6346b0551392ed`.
