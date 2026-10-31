defmodule Ipse.ReleaseReopenFixtureModel do
  def complete(_, _, _, _),
    do: {:ok, %{"role" => "assistant", "content" => "fixture answer"}, %{}}
end

{:ok, _} = Application.ensure_all_started(:ipse)
root = System.fetch_env!("IPSE_RELEASE_TEST_ROOT")
id = System.fetch_env!("IPSE_RELEASE_TEST_SESSION")

opts = [
  config: %{
    provider: :demo,
    provider_module: Ipse.ReleaseReopenFixtureModel,
    model: "fixture",
    home: root,
    approval: :deny,
    observability: Map.put(Ipse.Observability.defaults(), "mode", "local")
  },
  cwd: root,
  state_dir: Path.join(root, "state"),
  subscriber: self(),
  id: id
]

{:ok, session} = Ipse.Session.start_link(opts)
File.write!(Path.join(root, "reopen.ready"), "ready")
deadline = System.monotonic_time(:millisecond) + 15_000

wait = fn wait ->
  cond do
    File.exists?(Path.join(root, "reopen.stop")) ->
      :ok

    System.monotonic_time(:millisecond) >= deadline ->
      exit(:fixture_timeout)

    true ->
      Process.sleep(10)
      wait.(wait)
  end
end

wait.(wait)
:ok = Ipse.Session.close_confirmed(session)
IO.puts("REOPEN_CHILD_OK")
