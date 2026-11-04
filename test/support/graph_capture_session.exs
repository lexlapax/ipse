import ExUnit.Assertions
alias Ipse.{Session, Journal}
alias Ipse.Extension.{Artifact, Config, Registry}
[root, graph_artifact] = System.argv()
:ok = Application.load(:ipse)
runtime = Application.app_dir(:ipse)
true = File.regular?(Path.join(runtime, "ebin/Elixir.Ipse.Extension.Bootstrap.beam"))
true = File.regular?(Path.join(runtime, "priv/ipse-runner"))
{:ok, modules} = :application.get_key(:ipse, :modules)

true =
  Enum.all?(modules, &File.regular?(Path.join(runtime, "ebin/" <> Atom.to_string(&1) <> ".beam")))

false = Code.ensure_loaded?(IpseKnowledge.Graph)
home = Path.join(root, "private/home")
System.put_env("HOME", home)
System.put_env("IPSE_HOME", Path.join(home, ".ipse"))
{:ok, _} = Application.ensure_all_started(:ipse)
home = Path.join(home, ".ipse")
cwd = Path.join(root, "private/workspace")
File.mkdir_p!(cwd)
File.mkdir_p!(home)
File.chmod!(home, 0o700)

defmodule GraphScriptedProvider do
  import ExUnit.Assertions

  def complete(config, messages, tools, _emit) do
    assert Enum.any?(tools, fn tool ->
             (get_in(tool, ["function", "name"]) || tool["name"]) == "ext__graph__capture"
           end)

    send(config.test_pid, {:scripted_main_call, self()})

    if Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "graph-capture")) do
      {:ok, %{"role" => "assistant", "content" => "Synthetic relationship control finished."},
       %{}}
    else
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "graph-capture",
             "type" => "function",
             "function" => %{
               "name" => "ext__graph__capture",
               "arguments" => Jason.encode!(config.capture_args)
             }
           }
         ]
       }, %{}}
    end
  end
end

defmodule GraphSessionJourney do
  import ExUnit.Assertions
  alias Ipse.Session

  def command(pid, name, args, allow \\ true) do
    :ok = Session.invoke_export(pid, :command, name, args)
    await(pid, allow, 0, 0, System.monotonic_time(:millisecond) + 20_000)
  end

  def prompt(pid, allow) do
    :ok =
      Session.prompt(pid, "Capture a supported relationship from the existing synthetic source.")

    await(pid, allow, 0, 0, System.monotonic_time(:millisecond) + 20_000)
  end

  defp await(pid, allow, approvals, calls, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        assert :ok = Ipse.Extension.State.validate(proposed["request"])
        assert proposed["request"]["scope"] == "project"
        :ok = Session.approve(pid, ref, allow)
        await(pid, allow, approvals + 1, calls, deadline)

      {:ipse, ^pid, {:approval, ref, "ext__graph__capture", args}} ->
        assert args["store"] == "notes" and args["source_id"] == "test-source"
        assert args["extraction"] == "given" and :ok == Ipse.Extension.validate(args)
        :ok = Session.approve(pid, ref, true)
        await(pid, allow, approvals, calls, deadline)

      {:ipse, ^pid, {:approval, _, _, _}} ->
        flunk("unexpected approval kind")

      {:scripted_main_call, _} ->
        await(pid, allow, approvals, calls + 1, deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        {Session.info(pid).extension_result, approvals, calls}

      {:ipse, ^pid, {:done, status}} ->
        flunk("unexpected public done status #{status}")

      {:ipse, ^pid, {:error, _}} ->
        flunk("unexpected public Session error")

      _ ->
        await(pid, allow, approvals, calls, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("bounded Session control did not settle")
    end
  end

  def seed(pid) do
    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "test-source",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Synthetic graph source",
        "text" => "Cedar uses Blue.",
        "uri" => "provided:test",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }
    }

    {%{"value" => %{"status" => "ok"}}, approvals, 0} = command(pid, "ext__graph__source", args)
    assert approvals > 0
  end

  def query(pid) do
    {%{"value" => value}, 0, 0} =
      command(pid, "ext__graph__query", %{
        "store" => "notes",
        "entity" => "Cedar",
        "depth" => 1,
        "max_nodes" => 128,
        "max_edges" => 256,
        "top_k" => 10,
        "as_of_ms" => nil
      })

    value
  end

  def inspect_source(pid) do
    {%{"value" => value}, 0, 0} =
      command(pid, "ext__graph__source", %{
        "store" => "notes",
        "action" => "inspect",
        "args" => %{"source_id" => "test-source"}
      })

    value["coverage"]
  end

  def assert_tool(events) do
    assert Enum.any?(
             events,
             &(&1["type"] == "extension_invocation_intent" and
                 get_in(&1, ["descriptor", "stage"]) == "invoke.tool" and
                 get_in(&1, ["descriptor", "name"]) == "ext__graph__capture")
           )
  end

  def approve_first_state(pid, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "ext__graph__capture", args}} ->
        assert args["store"] == "notes" and args["source_id"] == "test-source"
        :ok = Session.approve(pid, ref, true)
        approve_first_state(pid, deadline)

      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        assert :ok == Ipse.Extension.State.validate(proposed["request"])
        :ok = Session.approve(pid, ref, true)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("unknown boundary approval was not reached")
    end
  end

  def snapshot(home) do
    home
    |> Path.join("extension-state-v1/**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path -> {Path.relative_to(path, home), Ipse.JSON.sha256(File.read!(path))} end)
  end

  def delta(root, label, before, after_state) do
    result = %{
      "before" => before,
      "after" => after_state,
      "created" => Enum.count(after_state, fn {key, _} -> not Map.has_key?(before, key) end),
      "modified" =>
        Enum.count(after_state, fn {key, value} ->
          Map.has_key?(before, key) and before[key] != value
        end),
      "deleted" => Enum.count(before, fn {key, _} -> not Map.has_key?(after_state, key) end)
    }

    File.write!(Path.join(root, "state-" <> label <> ".json"), Jason.encode!(result) <> "\n", [
      :exclusive,
      :sync
    ])
  end
end

{:ok, artifact} = Artifact.import(graph_artifact, Path.join(home, "extensions/artifacts"))

options = %{
  "version" => 1,
  "stores" => %{"notes" => %{"kind" => "state", "scope" => "project", "partition" => "notes"}},
  "search" => %{},
  "fetch" => %{},
  "retrieval" => %{},
  "embedding" => %{},
  "rerank" => %{},
  "extraction" => %{"given" => %{"kind" => "explicit", "version" => 1}}
}

source = %{
  scope: "operator",
  path: Path.join(home, "fixture.json"),
  data: %{
    "extensions" => [
      %{
        "instance" => "graph",
        "artifact" => artifact.digest,
        "enabled" => true,
        "options" => options,
        "order" => 0,
        "lifetime" => "session"
      }
    ],
    "extension_trust" => [
      %{
        "artifact" => artifact.digest,
        "capabilities" => artifact.manifest["capabilities"],
        "allow_project" => false,
        "allow_children" => false,
        "state_bindings" => [
          %{
            "version" => 1,
            "instance" => "graph",
            "id" => "graph-capture-shared",
            "scopes" => ["project"]
          }
        ]
      }
    ]
  }
}

{:ok, selected} = Config.resolve([source], [])
{:ok, entries} = Registry.prepare(selected, home)

relation = %{
  "subject" => "Cedar",
  "predicate" => "uses",
  "object" => "Blue",
  "polarity" => "positive",
  "inferred" => false,
  "valid_from_ms" => nil,
  "valid_to_ms" => nil,
  "quote" => "Cedar uses Blue."
}

capture = %{
  "store" => "notes",
  "extraction" => "given",
  "source_id" => "test-source",
  "generation" => 1,
  "relations" => [relation]
}

config = %{
  provider: :demo,
  model: "synthetic",
  provider_module: GraphScriptedProvider,
  test_pid: self(),
  capture_args: capture,
  home: home,
  extensions: entries,
  approval: :ask,
  approval_origin: :interactive,
  headless: false,
  compact: false
}

session_options = [
  config: config,
  cwd: cwd,
  state_dir: Path.join(home, "sessions"),
  subscriber: self()
]

{:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, session_options})
id = Session.info(pid).id
GraphSessionJourney.seed(pid)
before_state = GraphSessionJourney.snapshot(home)
true = map_size(before_state) > 0
{_, approvals, 2} = GraphSessionJourney.prompt(pid, true)
GraphSessionJourney.delta(root, "positive", before_state, GraphSessionJourney.snapshot(home))
assert approvals > 0

assert [
         %{
           "subject" => "Cedar",
           "object" => "Blue",
           "basis" => [%{"quote" => "Cedar uses Blue.", "generation" => 1}]
         }
       ] = GraphSessionJourney.query(pid)["claims"]

:ok = Session.close_confirmed(pid)
{:ok, events} = Journal.load(session_options[:state_dir], id)
GraphSessionJourney.assert_tool(events)
assert {:ok, _} = Session.Saved.restore(events, id)

for {mode, args, allow} <- [
      {:generation, Map.put(capture, "generation", 2), true},
      {:denial, put_in(capture, ["relations", Access.at(0), "polarity"], "negative"), false}
    ] do
  current = Keyword.put(session_options, :config, Map.put(config, :capture_args, args))
  {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, current})
  child_id = Session.info(pid).id
  before = GraphSessionJourney.inspect_source(pid)
  before_state = GraphSessionJourney.snapshot(home)
  {_, approvals, 2} = GraphSessionJourney.prompt(pid, allow)
  assert approvals == if(mode == :generation, do: 0, else: 1)
  after_source = GraphSessionJourney.inspect_source(pid)
  assert before == after_source
  assert before_state == GraphSessionJourney.snapshot(home)

  GraphSessionJourney.delta(
    root,
    Atom.to_string(mode),
    before_state,
    GraphSessionJourney.snapshot(home)
  )

  assert length(GraphSessionJourney.query(pid)["claims"]) == 1
  :ok = Session.close_confirmed(pid)
  {:ok, events} = Journal.load(current[:state_dir], child_id)
  GraphSessionJourney.assert_tool(events)
  assert {:ok, _} = Session.Saved.restore(events, child_id)
end

{:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, session_options})
unknown_id = Session.info(pid).id
guard = Session.Lock.for_owner(pid)
true = is_pid(guard)
guard_monitor = Process.monitor(guard)
monitor = Process.monitor(pid)
observer = self()

hook = fn
  0, {:in, {:"$gen_call", _, {:extension_action_commit, _, event}}}, _ ->
    if get_in(event, ["request", "op"]) == "state.put" and
         get_in(event, ["outcome", "status"]) == "ok" do
      send(observer, {:actual_state_commit_interrupted, self(), event["operation_id"]})
      Process.exit(self(), :kill)
    end

    0

  state, _, _ ->
    state
end

:ok = :sys.install(pid, {hook, 0})
before_state = GraphSessionJourney.snapshot(home)
:ok = Session.prompt(pid, "Capture a supported relationship from the existing synthetic source.")

GraphSessionJourney.approve_first_state(pid, System.monotonic_time(:millisecond) + 20_000)

operation =
  receive do
    {:actual_state_commit_interrupted, ^pid, operation} -> operation
  after
    20_000 -> flunk("actual State result boundary was not reached")
  end

receive do
  {:DOWN, ^monitor, :process, ^pid, :killed} -> :ok
after
  5_000 -> flunk("Session teardown unconfirmed")
end

receive do
  {:DOWN, ^guard_monitor, :process, ^guard, _} -> :ok
after
  10_000 -> flunk("tracked cleanup unconfirmed")
end

GraphSessionJourney.delta(root, "unknown", before_state, GraphSessionJourney.snapshot(home))

{:ok, unknown_events} = Journal.load(session_options[:state_dir], unknown_id)

assert Enum.any?(
         unknown_events,
         &(&1["type"] == "extension_action_intent" and &1["operation_id"] == operation)
       )

refute Enum.any?(
         unknown_events,
         &(&1["type"] == "extension_action_result" and &1["operation_id"] == operation)
       )

assert {:ok, _} = Session.Saved.restore(unknown_events, unknown_id)
intents = Enum.filter(unknown_events, &(&1["type"] == "extension_action_intent"))

{:ok, resumed} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Session, Keyword.put(session_options, :id, unknown_id)}
  )

assert Session.info(resumed).phase == :idle
:ok = Session.close_confirmed(resumed)
{:ok, after_events} = Journal.load(session_options[:state_dir], unknown_id)
assert Enum.filter(after_events, &(&1["type"] == "extension_action_intent")) == intents
assert {:ok, _} = Session.Saved.restore(after_events, unknown_id)

IO.puts(
  "graph_state_main_tool=pass positive=true generation_refused=true denial_preserved=true interrupted_actual_state_result=true saved=true idle_no_replay=true live_service_calls=0 tty_reads=0"
)
