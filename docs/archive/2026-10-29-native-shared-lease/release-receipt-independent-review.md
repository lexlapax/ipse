# Independent review of the signed release contract

2026-10-29. This scoped review covers the frozen
[pure release-receipt contract](release-receipt-contract.md), not native cleanup
or durable publication. Its source and runtime manifests verified locally and
the recorded five pure tests passed. The archive remains untracked until the
eventual commit. No files were modified by the reviewer.

The reviewer reproduced an adoption gap: scanning a valid owner-A intent
followed by an owner-B marker still returns A's historical intent, and its old
signature verifies. Rejecting an old intent newly appended after B is not enough
to prevent delayed old sidecar adoption. A consumer needs an explicit latest
owner/current-intent selection check distinct from historical inspection.

Three more issues need repair or precise semantics:

- The public key is base64-decoded before its encoded length is bounded, so a
  large intent field can allocate proportionately. Check exact encoded field
  lengths before decoding.
- A `lifecycle_recording_stopped` event during an active epoch leaves that
  epoch active in the receipt scanner, but close emits no closure. Neither nil
  nor epoch-bound intent is then accepted. Define a safe explicit unknown policy
  or supported binding for this state and test it.
- Canonical base64url is enforced, but equivalent JSON whitespace/key ordering
  is accepted. Documentation must distinguish those encodings unless canonical
  JSON bytes are required and tested.

A valid signature remains only a trusted signer's claim. Native release,
sidecar durability, publisher cleanup and actual Session integration remain open.
