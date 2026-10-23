Code.require_file("verification/scenarios.exs", __DIR__)
Code.require_file("verification/runtime.exs", __DIR__)
Ipse.Development.Verification.Runtime.verification_main(System.argv())
