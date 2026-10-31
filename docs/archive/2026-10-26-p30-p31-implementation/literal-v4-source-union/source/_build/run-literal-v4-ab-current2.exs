base = Path.expand("_build/session-header-audit2-sol-20261029/lib")
target = Path.expand("_build/literal-v4-ab-current2-sol-20261029/lib")
File.mkdir_p!(Path.dirname(target))
unless File.dir?(target), do: File.cp_r!(base, target)
gate = Path.expand("_build/strict-lifetime-followup-sol-20261029/lib/ipse/ebin")
for name <- ~w(Ipse.Session.Invocation Ipse.Session.ManagedToolUse Ipse.Extension.Collection Ipse.Extension.State Ipse.CLI.Errors Ipse.CLI.Knowledge Ipse.CLI.Knowledge.Management Ipse.CLI.Terminal) do
  file = "Elixir." <> name <> ".beam"
  File.cp!(Path.join(gate,file),Path.join([target,"ipse/ebin",file]))
end
{:ok,{_,[imports: imports]}}=:beam_lib.chunks(String.to_charlist(Path.join(target,"ipse/ebin/Elixir.Ipse.Session.Invocation.beam")),[:imports])
true = {Ipse.Session.ManagedToolUse,:publication_prerequisites?,3} in imports
Code.prepend_paths(Path.wildcard(Path.join(target, "*/ebin")))
{:ok, _} = Application.ensure_all_started(:ipse)
System.put_env("IPSE_LITERAL_AB_ROOT", "/tmp/ipse-literal-v4-ab-46915")
Code.require_file("test/test_helper.exs")
ExUnit.configure(autorun: false, exclude: [:test], include: [literal_v4_ab: true], seed: 46921)
Code.require_file("test/ipse/extension/managed_collection_call_session_test.exs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 2)
