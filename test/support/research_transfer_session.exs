import ExUnit.Assertions
alias Ipse.{Session, Journal}
alias Ipse.Extension.{Artifact, Config, Registry}
[root, research_artifact] = System.argv()
:ok = Application.load(:ipse)
runtime = Application.app_dir(:ipse)
true = File.regular?(Path.join(runtime, "ebin/Elixir.Ipse.Extension.Bootstrap.beam"))
true = File.regular?(Path.join(runtime, "priv/ipse-runner"))
{:ok, app} = :application.get_key(:ipse, :modules)

true =
  Enum.all?(
    app,
    &File.regular?(
      Path.join(
        runtime,
        "ebin/Elixir." <> (Atom.to_string(&1) |> String.replace_prefix("Elixir.", "")) <> ".beam"
      )
    )
  )

false = Code.ensure_loaded?(IpseKnowledge.Research)
home = Path.join(root, "private/home")
System.put_env("HOME", home)
System.put_env("IPSE_HOME", Path.join(home, ".ipse"))
{:ok, _} = Application.ensure_all_started(:ipse)
home = Path.join(home, ".ipse")
cwd = Path.join(root, "private/workspace")
File.mkdir_p!(cwd)
File.mkdir_p!(home)
File.chmod!(home, 0o700)

defmodule NoResearchModel do
  def complete(_, _, _, _), do: raise("provided transfer attempted inference")
end

defmodule TransferJourney do
  import ExUnit.Assertions
  alias Ipse.Session

  def command(pid, name, args, approvals \\ true) do
    :ok = Session.invoke_export(pid, :command, name, args)
    await(pid, approvals, 0, System.monotonic_time(:millisecond) + 20_000)
  end

  defp await(pid, allow, count, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        assert :ok = Ipse.Extension.State.validate(proposed["request"])
        assert proposed["request"]["scope"] == "project"
        assert is_binary(proposed["artifact_sha256"])
        :ok = Session.approve(pid, ref, allow)
        await(pid, allow, count + 1, deadline)

      {:ipse, ^pid, {:approval, _, _, _}} ->
        flunk("unexpected non-State approval")

      {:ipse, ^pid, {:done, :ok}} ->
        assert %{"value" => result} = Session.info(pid).extension_result
        {result, count}

      {:ipse, ^pid, {:done, status}} ->
        flunk("command failed public status #{status}")

      {:ipse, ^pid, {:error, reason}} ->
        flunk("command error class #{inspect(reason, limit: 3)}")

      _ ->
        await(pid, allow, count, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("bounded command did not settle")
    end
  end
end

artifacts =
  for {instance, path} <- [
        {"research", research_artifact},
        {"corpus", Path.join(runtime, "priv/extension-bundles/corpus-state-documents")}
      ],
      into: %{} do
    {:ok, artifact} = Artifact.import(path, Path.join(home, "extensions/artifacts"))
    {instance, artifact}
  end

research_options =
  JSON.decode!(
    File.read!(
      Path.expand("../../extensions/knowledge/options/research-state-retained.json", __DIR__)
    )
  )

corpus_options = research_options |> Map.put("search", %{}) |> Map.put("fetch", %{})

source = %{
  scope: "operator",
  path: Path.join(home, "fixture.json"),
  data: %{
    "extensions" =>
      for {instance, artifact} <- artifacts do
        %{
          "instance" => instance,
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => if(instance == "research", do: research_options, else: corpus_options),
          "order" => 0,
          "lifetime" => "session"
        }
      end,
    "extension_trust" =>
      for {instance, artifact} <- artifacts do
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "state_bindings" => [
            %{
              "version" => 1,
              "instance" => instance,
              "id" => "research-shared",
              "scopes" => ["project"]
            }
          ]
        }
      end
  }
}

{:ok, selected} = Config.resolve([source], [])
{:ok, entries} = Registry.prepare(selected, home)

config = %{
  provider: :demo,
  model: "synthetic",
  provider_module: NoResearchModel,
  home: home,
  extensions: entries,
  approval: :ask,
  approval_origin: :interactive,
  headless: false,
  compact: false
}

options = [config: config, cwd: cwd, state_dir: Path.join(home, "sessions"), subscriber: self()]
{:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, options})
id = Session.info(pid).id

provided = %{
  "source_id" => "external:provided",
  "title" => "Release",
  "text" => "Résumé 雪: Ada owns release after audit.",
  "uri" => "https://example.invalid/provided",
  "observed_at_ms" => 10,
  "event_at_ms" => nil,
  "expires_at_ms" => nil
}

args = %{"store" => "notes", "source" => provided, "quote" => "Ada owns release after audit."}

try do
  {denied, 1} = TransferJourney.command(pid, "ext__research__retain", args, false)
  assert denied["status"] == "refused"

  {query, 0} =
    TransferJourney.command(pid, "ext__corpus__query", %{
      "store" => "notes",
      "retrieval" => "words",
      "rerank" => nil,
      "query" => "release",
      "top_k" => 3,
      "as_of_ms" => 20
    })

  assert query["evidence"] == []
  {retained, approvals} = TransferJourney.command(pid, "ext__research__retain", args)
  assert retained["status"] == "ok" and approvals > 0
  target = "research.provided:" <> Ipse.JSON.sha256(provided["text"])
  assert retained["coverage"]["source_id"] == target

  query_args = %{
    "store" => "notes",
    "retrieval" => "words",
    "rerank" => nil,
    "query" => "release",
    "top_k" => 3,
    "as_of_ms" => 20
  }

  {query, 0} = TransferJourney.command(pid, "ext__corpus__query", query_args)
  assert query["status"] == "ok"
  assert [candidate] = query["evidence"]
  origin = candidate["citation"]["origin"]
  assert origin["kind"] == "provided" and origin["historical"] == false
  assert origin["receipt"] == retained["coverage"]["derivation"]
  assert origin["receipt"]["source_id"] == provided["source_id"]
  assert origin["receipt"]["start_byte"] == byte_size("Résumé 雪: ")

  {inspect, 0} =
    TransferJourney.command(pid, "ext__corpus__source", %{
      "store" => "notes",
      "action" => "inspect",
      "args" => %{"source_id" => target}
    })

  {forgotten, forget_approvals} =
    TransferJourney.command(pid, "ext__corpus__source", %{
      "store" => "notes",
      "action" => "forget",
      "args" => %{"source_id" => target, "expected_revision" => inspect["coverage"]["revision"]}
    })

  assert forgotten["status"] == "ok" and forget_approvals > 0
  :ok = Session.close_confirmed(pid)
  {:ok, fresh} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, options})

  try do
    {refused, 0} =
      TransferJourney.command(
        fresh,
        "ext__research__retain",
        args
        |> put_in(["source", "source_id"], "alias:other")
        |> put_in(["source", "uri"], "provided:alias")
        |> Map.put("quote", "Résumé 雪")
      )

    assert refused["status"] == "refused"
    {empty, 0} = TransferJourney.command(fresh, "ext__corpus__query", query_args)
    assert empty["evidence"] == []
  after
    :ok = Session.close_confirmed(fresh)
  end

  {:ok, events} = Journal.load(options[:state_dir], id)

  intents =
    Enum.with_index(events)
    |> Enum.filter(fn {event, _} -> event["type"] == "extension_action_intent" end)

  results =
    Enum.with_index(events)
    |> Enum.filter(fn {event, _} -> event["type"] == "extension_action_result" end)

  for {result, result_index} <- results do
    assert Enum.any?(intents, fn {intent, index} ->
             index < result_index and intent["operation_id"] == result["operation_id"]
           end)
  end

  refute Enum.any?(events, &(&1["type"] in ~w(request_intent mcp_action_intent)))
  assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
  before = File.read!(Path.join(options[:state_dir], id <> ".jsonl"))

  {:ok, resumed} =
    DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(options, :id, id)})

  :ok = Session.close_confirmed(resumed)
  {:ok, after_events} = Journal.load(options[:state_dir], id)
  assert Enum.count(after_events, &(&1["type"] == "extension_action_intent")) == length(intents)
  assert String.starts_with?(File.read!(Path.join(options[:state_dir], id <> ".jsonl")), before)

  IO.puts(
    "ordinary_state_journey=pass denied_write_empty=true approved_transfer=true corpus_quote_origin=true forget_alias_fresh_session_blocked=true journal_before_effect=true saved_restore=true no_replay=true model_calls=0 tty_reads=0"
  )
after
  if Process.alive?(pid), do: Session.close_confirmed(pid)
end
