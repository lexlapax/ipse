defmodule Ipse.ReleaseOldHelperFixtureModel do
  def complete(_, _, _, _),
    do: {:ok, %{"role" => "assistant", "content" => "fixture answer"}, %{}}
end

Process.flag(:trap_exit, true)
{:ok, _} = Application.ensure_all_started(:ipse)
root = System.fetch_env!("IPSE_RELEASE_TEST_ROOT")
id = System.fetch_env!("IPSE_RELEASE_TEST_SESSION")

opts = [
  config: %{
    provider: :demo,
    provider_module: Ipse.ReleaseOldHelperFixtureModel,
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

case Ipse.Session.start_link(opts) do
  {:error, "usage: ipse-runner " <> _} ->
    IO.puts("OLD_RESUME_HELPER_REFUSED_UNKNOWN_COMMAND")

  {:error, reason} ->
    IO.puts("UNEXPECTED_REFUSAL " <> inspect(reason))
    exit(:unexpected_refusal)

  {:ok, session} ->
    Ipse.Session.close_confirmed(session)
    exit(:unsafe_fallback)
end
