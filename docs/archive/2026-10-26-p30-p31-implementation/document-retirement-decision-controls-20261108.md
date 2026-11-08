# Document retirement decision controls, 2026-11-08

This is a historical synthetic investigation. The [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) owns current acceptance. These checks do not authorize replay or recovery of an earlier unknown effect.

The standalone candidate started from `d9014d1f07f397377fe291c60da9a2144754ac4e` and added the live-owner retirement protocol and close-safe test controls. A fresh private build compiled without warnings and checked the generated bundle catalog. Its build identity was deliberately left uncommitted. The retained local verification directory is `_build/verification/retirement-standalone-d9014d1f-20261108-01`; its files are local evidence, not a durable external service.

One synthetic native arm/disarm control, four distinct native refusal or owner-control-loss controls, and one positive Session control passed with reviewed selections and independent process/lock postflights. A separate changed-lock test observed the API's unknown transaction result, then required controller and port closure and reacquired the same lock inodes before releasing them. That API result does not distinguish native rejection from transport failure.

A separately compiled, test-only hook helper exercised Session loss before and after the native switch decision in fresh fixtures. Both selected tests passed and were independently audited. The before-decision test checked the original root only after the old owners and monitored ports were down and the original lock inodes were reacquired. The after-decision test preserved the outcome as unknown and did not infer whether the switch occurred. These tests used test-only hooks and do not establish installed or live-account behavior.

The native, identity and hook controls used separate test-only overlays. Their combined final source has not received the full repository baseline or full integrated acceptance. Earlier unconfirmed fixtures and the previously retained notebook were not read or replayed. Installed migration, interrupted recovery, platform coverage and full P31F acceptance remain open.
