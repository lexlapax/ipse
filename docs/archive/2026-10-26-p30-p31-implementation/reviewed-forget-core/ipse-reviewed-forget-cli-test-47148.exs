Path.wildcard("_build/reviewed-forget-cli-sol-20261029/lib/*/ebin")
|> Enum.each(&Code.prepend_path/1)
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(autorun: false, seed: 20261029,
  exclude: [:test], include: [:gate_cli, :reviewed_forget_gate])
Code.require_file("test/ipse/extension/collection_deadline_gate_test.exs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
