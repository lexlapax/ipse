path = "_build/headless-diagnostic-sol-20261029/lib/ipse/session/invocation.ex"
source = File.read!(path)
needle = "    with parent when is_map(parent) <- s.invocation.parent,\n         true <- output_timely?(s),"
insert = """
    if request["op"] == "collection.managed" do
      binding = extension_effect_binding(s, request)
      prerequisites = case binding do
        {:ok, value} -> Ipse.Session.ManagedToolUse.publication_prerequisites?(s, request, value)
        _ -> false
      end
      flags = %{
        "protected" => protected,
        "approval" => approval,
        "timely" => output_timely?(s),
        "interrupted" => s.invocation.interrupted,
        "live" => Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
        "allowed" => Actions.allowed?(s.invocation.parent["identity"], request, s.invocation.results),
        "readable" => Actions.readable?(request, s.invocation.effect_sources, s.invocation.results),
        "binding" => inspect(binding |> elem(0)),
        "new_capture" => Ipse.Extension.ManagedCollectionCall.new_capture?(request),
        "prerequisites" => prerequisites
      }
      IO.puts("HEADLESS_DIAGNOSTIC " <> Jason.encode!(flags))
    end

"""
case :binary.matches(source, needle) do
  [{_, _}] -> File.write!(path, String.replace(source, needle, insert <> needle, global: false))
  _ -> raise "ambiguous instrumentation point"
end
