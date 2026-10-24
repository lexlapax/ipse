# Machine identification during ChatGPT sign-in

Requested 2026-10-24 while the session-permission candidate was under verification.
Starting point: `58fdf4a`. Current procedure belongs to
[terminal usage](../../operator/usage.md#select-a-provider); runtime ownership is
in [architecture](../../developer/architecture.md).

The developer requested a machine-qualified name such as `ipse@serenity`.
The [official registration protocol](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
read on this date, distinguishes the application hint from the browser's editable
registration name. The implementation therefore displays a short local hostname
and suggests that label during new registration, preserving the existing OAuth
parameters and returning client/host identity. It does not automatically rename
an existing registration or send an undocumented name parameter.

The hostname comes from OTP, without a shell command or new dependency. Domain
suffixes are omitted; absent, oversized or unsafe names use `ipse@unknown-host`.
No credentials, token record, host UUID, scope or callback behavior changes.

Local OAuth/setup fixtures pass: 39 tests, seed 579899, 0.7 seconds, including
new/returning output, stable application hint, hostname bounds and fallback.
This is fixture evidence; no new real browser sign-in was performed. The combined
candidate still requires full source/native, installed and hosted verification.
