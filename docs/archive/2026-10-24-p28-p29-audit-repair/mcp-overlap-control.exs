Code.require_file("dev/verification/scenarios.exs")
Code.require_file("dev/verification/runtime.exs")
Ipse.Development.Verification.Runtime.load_fixture!(:mcp)
alias Ipse.MCP.Config
alias IpseMCPExample.Fixture
base_root = Path.join(System.tmp_dir!(), "ipse-overlap-control")
build = fn root, suffix ->
  first = Fixture.stdio_config(root)
    |> Map.update!("args", fn args -> List.update_at(args,-1,&("_ = <<\"x" <> suffix <> "\">>, " <> &1)) end)
    |> Map.put("env", %{"FIRST_TOKEN" => suffix})
  second = first |> Map.put("id", "other") |> Map.put("env", %{"SECOND_TOKEN" => "x" <> suffix})
  [first,second]
end
internal = fn raw ->
  Config.fingerprint_version(%{id: raw["id"], command: raw["command"], args: raw["args"],
    tools: raw["tools"], resources: raw["resources"] || [], prompts: raw["prompts"] || [],
    sandbox: :off, env: raw["env"], timeout_ms: raw["timeout_ms"] || 30_000, transport: :stdio}, 2)
end
witness = Enum.find_value(0..2000, fn i ->
  root = base_root <> "-#{i}"
  entries = build.(root,"abc")
  [first|_] = Enum.map(entries, internal)
  if String.contains?(first.fingerprint,"abc"), do: {root,entries,first.fingerprint}
end)
{root,entries,fingerprint} = witness
path = "/tmp/ipse-audit-overlap-control.json"
File.write!(path, Jason.encode!(%{servers: entries}))
{:error,_} = Config.load(path)
File.write!(path, Jason.encode!(%{servers: build.(root,"synthetic-overlap-token")}))
{:ok,[first,second]} = Config.load(path)
legacy = Config.fingerprint_version(first,1) |> Config.manifest()
true = Enum.any?(legacy.args,&String.contains?(&1,"x[redacted]"))
false = String.contains?(first.fingerprint,"synthetic-overlap-token")
false = String.contains?(second.fingerprint,"synthetic-overlap-token")
result = %{witness_root: root, short_secret_fingerprint: fingerprint, original_short_fixture: "refused by unchanged public privacy guard", nonhex_long_overlap_fixture: "admitted with the same legacy x[redacted] property", dispatches: 0, limit: "Controlled reproduction; the original failed test root was removed by on_exit, so its exact collision field is unavailable."}
File.write!("/tmp/ipse-audit-overlap-control-receipt.json",[Jason.encode!(result),"\n"])
IO.puts("Controlled short-secret hash collision refused; nonhex overlapping marker admitted; no server launched.")
