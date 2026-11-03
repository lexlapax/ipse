[path, mode] = System.argv()
true = mode in ~w(baseline candidate)
{:ok, %{events: events, tail: :none}} = Ipse.Journal.read_path(path)
[_, id] = Regex.run(~r/ipse-recall-profile-source-([a-f0-9]{32})\.jsonl\z/, path)

if mode == "baseline" do
  Code.compiler_options(ignore_module_conflict: true)

  for path <-
        ~w(lib/ipse/session/managed_reference.ex lib/ipse/session/managed_lineage.ex lib/ipse/session/saved.ex) do
    {source, 0} = System.cmd("git", ["show", "830a12c:#{path}"])
    Code.compile_string(source, "baseline-#{Path.basename(path)}")
  end
end

{context_us, {:ok, context}} = :timer.tc(fn -> Ipse.Session.Saved.context(events) end)
{saved_us, {:ok, saved}} = :timer.tc(fn -> Ipse.Session.Saved.restore(events, id) end)

stable =
  update_in(saved, [:source_window], fn window ->
    index = window.index |> Map.from_struct() |> Map.drop([:secret, :window_id])
    window |> Map.from_struct() |> Map.put(:index, index)
  end)

for {name, value} <- [{"context", context}, {"saved", stable}] do
  hash =
    :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
    |> Base.encode16(case: :lower)

  IO.puts("#{name}=#{hash}")
end

IO.puts("context_us=#{context_us} saved_us=#{saved_us}")
