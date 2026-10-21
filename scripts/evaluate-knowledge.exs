Code.require_file("../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../dev/verification/runtime.exs", __DIR__)
Ipse.Development.Verification.Runtime.evaluation_main(System.argv())
