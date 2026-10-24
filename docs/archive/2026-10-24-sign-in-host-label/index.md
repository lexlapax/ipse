# Machine identification during ChatGPT sign-in

Requested 2026-10-24 while session permissions were under verification, starting
from `58fdf4a`. Current procedure belongs to
[terminal usage](../../operator/usage.md#select-a-provider); ownership belongs to
[architecture](../../developer/architecture.md).

The requested authorization label is machine-qualified, for example
`ipse@serenity`. New registrations now send the bounded short-hostname label as
`agent_name_hint`, and print the same sampled value in the terminal. The browser
can edit the suggestion. Returning authorization omits that hint and preserves
the issued client ID and opaque host UUID. No registration is silently replaced
or renamed on returning login.

The [official registration protocol](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
read on this date, documents the hint as editable display metadata and recommends
an app name consistent across installations. Ipse intentionally adds the machine
qualifier to its consistent `ipse` prefix to satisfy the requested distinction.
It uses the documented hint, not a new hostname parameter or private endpoint.
The label is not an authentication identity or permission grant.

The hostname comes from OTP, without a shell or new dependency. Domain suffixes
are omitted; absent, oversized or unsafe names use `ipse@unknown-host`. Scopes,
PKCE/state/nonce, callback handling, credential storage and identity validation
remain unchanged. The name is sampled once per login so URL and terminal agree.

The first `8ee16dc` implementation printed the label and suggested typing it in
the browser while retaining a constant hint. Its Auth/setup fixtures passed 39
cases (seed 579899, 0.7 seconds), and its full source/installed checks passed.
That terminal-only behavior was superseded because it did not set the requested
browser default. The updated OAuth/setup, permission and terminal set passes 76
cases, including the machine-qualified initial hint and absent returning hint.

No new real browser authorization was performed. Fixture evidence proves request
construction and existing validation paths, not a new account/server acceptance
trial. The [combined receipt](../2026-10-24-approval-implementation/verification.json)
tracks exact candidates and final source, installed and hosted gates separately.
