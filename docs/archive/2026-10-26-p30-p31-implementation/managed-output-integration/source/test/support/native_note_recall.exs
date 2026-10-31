ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("provider_fixture.ex", __DIR__))

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

defmodule NativeNoteRecall do
  import ExUnit.Assertions

  def server do
    owner = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          for number <- 1..3 do
            {:ok, socket} = :gen_tcp.accept(listener, 40_000)

            try do
              {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
              send(owner, {:native_recall_body, number, self(), Jason.decode!(bytes)})
              if number == 3, do: receive(do: (:release -> :ok))

              body =
                Jason.encode!(%{
                  "model" => "synthetic",
                  "message" => %{
                    "role" => "assistant",
                    "content" => "Synthetic native recall answer #{number}."
                  },
                  "done" => true,
                  "prompt_eval_count" => 1,
                  "eval_count" => 1
                }) <> "\n"

              result =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )

              assert result == :ok or
                       (number == 3 and result in [{:error, :closed}, {:error, :einval}])
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  def body(session, number, dir) do
    receive do
      {:native_recall_body, ^number, server, body} -> {server, body}
      {:ipse, ^session, {:error, reason}} -> flunk("native recall refused: " <> inspect(reason))
    after
      12_000 ->
        {:ok, events} = Ipse.Journal.load(dir, Ipse.Session.info(session).id)

        flunk(
          "native recall body #{number} unavailable; events=" <>
            Jason.encode!(diagnostics(events)) <>
            "; phase=" <> inspect(Ipse.Session.info(session).phase)
        )
    end
  end

  def diagnostics(events),
    do:
      Enum.map(events, fn e ->
        Map.take(e, ~w(type stage status error reason))
        |> Map.merge(%{
          "op" => get_in(e, ["request", "op"]),
          "inner" => get_in(e, ["request", "request", "op"]),
          "outcome" => if(is_map(e["outcome"]), do: e["outcome"]["status"], else: e["outcome"]),
          "code" => if(is_map(e["outcome"]), do: get_in(e, ["outcome", "value", "code"]))
        })
      end)

  def chronology(events, expected) do
    jobs =
      Enum.filter(
        events,
        &(&1["type"] == "extension_invocation_intent" and
            get_in(&1, ["descriptor", "stage"]) == "event.job")
      )

    assert length(jobs) == expected

    assert Enum.all?(
             jobs,
             &(&1["version"] == 3 and
                 get_in(&1, ["semantic_binding", "class"]) == "collection.read")
           )

    for dispatch <- Enum.filter(events, &(&1["type"] == "inference_dispatch_intent")) do
      before = Enum.take_while(events, &(&1 != dispatch))
      turn = dispatch["turn_id"]

      completed =
        Enum.flat_map(before, fn event ->
          if event["type"] == "extension_event_intent" and event["turn_id"] == turn do
            Enum.filter(
              before,
              &(&1["type"] == "extension_event_result" and
                  &1["delivery_id"] == event["delivery_id"] and
                  &1["outcome"] in ~w(completed failed) and &1["cleanup_confirmed"])
            )
          else
            []
          end
        end)

      assert length(completed) == 1
    end
  end
end

[root, "save"] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "work")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
{base, server} = NativeNoteRecall.server()
config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{
    "version" => 1,
    "profiles" => %{
      "recall" => %{
        "provider" => "ollama",
        "model" => "synthetic",
        "base_url" => base,
        "max_output_tokens" => 64,
        "timeout_ms" => 5000
      }
    },
    "roles" => %{"main" => "recall"},
    "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
  })
)

File.chmod!(config_path, 0o600)
cli_args = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
assert Ipse.CLI.run(["knowledge", "enable"] ++ cli_args) == 0

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: true,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

{:ok, config} = Ipse.Config.runtime(effective, client)
assert config.provider == :ollama and config.base_url == base
dir = Path.join(home, "sessions")
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
assert {:ok, source} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
source_id = Ipse.Session.info(source).id
assert :sys.get_state(source).config.semantic_admission["status"] == "active"
IO.puts("IPSE_ASSERTION_CLI_READY")
assert Ipse.CLI.Terminal.interact(source, Process.monitor(source), true, nil, cwd) == 0
assert {:ok, source_events} = Ipse.Journal.load(dir, source_id)
assert Enum.count(source_events, &(&1["type"] == "operator_assertion")) == 3
refute Enum.any?(source_events, &(&1["type"] == "inference_dispatch_intent"))
pin = :sys.get_state(source).config.semantic_admission["pin"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

{:ok, snapshot} =
  Ipse.Extension.Collection.execute(
    collection,
    pin["namespace"],
    %{"op" => "snapshot"},
    Ipse.Usage.id()
  )

{:ok, page} =
  Ipse.Extension.Collection.scan_visible(
    collection,
    pin["namespace"],
    %{
      "op" => "scan",
      "after" => nil,
      "generation" => snapshot["generation"],
      "limit" => 4
    },
    Ipse.Usage.id()
  )

assert length(page["records"]) == 3
assert :ok = Ipse.Session.close_confirmed(source)
assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
id = Ipse.Session.info(session).id
assert :ok = Ipse.Session.prompt(session, "What current references are available?")
{_, first} = NativeNoteRecall.body(session, 1, dir)
for row <- page["records"], do: assert(Jason.encode!(first) =~ row["value"]["text"])
assert_receive {:ipse, ^session, {:done, :ok}}, 15_000

assert {:ok, consumer_sources} =
         Ipse.Session.sources(session, "source.list", %{"limit" => 32, "cursor" => nil})

refute Enum.any?(consumer_sources["sources"], &(&1["origin"] == "native_operator_assertion"))
assert {:ok, first_events} = Ipse.Journal.load(dir, id)
NativeNoteRecall.chronology(first_events, 1)
assert Enum.count(first_events, &(&1["type"] == "managed_read_observed")) == 4
refute Enum.any?(first_events, &(&1["type"] in ~w(extension_inference_intent decision_intent)))

preference = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))
assert Ipse.CLI.run(["knowledge", "forget", preference["key"]] ++ cli_args) == 0
assert :ok = Ipse.Session.prompt(session, "Refresh the available current references.")
{_, second} = NativeNoteRecall.body(session, 2, dir)
refute Jason.encode!(second) =~ preference["value"]["text"]

for row <- page["records"],
    row != preference,
    do: assert(Jason.encode!(second) =~ row["value"]["text"])

assert hd(first["messages"]) === hd(second["messages"])
assert first["tools"] === second["tools"]
assert_receive {:ipse, ^session, {:done, :ok}}, 15_000
assert {:ok, second_events} = Ipse.Journal.load(dir, id)
NativeNoteRecall.chronology(second_events, 2)
assert Enum.any?(second_events, &(&1["type"] == "managed_preflight_result"))
assert {:ok, restored} = Ipse.Session.Saved.restore(second_events, id)
assert restored.messages === :sys.get_state(session).messages

journal = Path.join(dir, source_id <> ".jsonl")
File.rename!(journal, journal <> ".held")
assert :ok = Ipse.Session.prompt(session, "Continue with unavailable original sources.")
{held, third} = NativeNoteRecall.body(session, 3, dir)
for row <- page["records"], do: refute(Jason.encode!(third) =~ row["value"]["text"])
assert hd(first["messages"]) === hd(third["messages"])
assert first["tools"] === third["tools"]
assert :ok = Ipse.Session.cancel(session)
assert_receive {:ipse, ^session, {:done, :cancelled}}, 5000
send(held, :release)
Task.await(server, 5000)
File.rename!(journal <> ".held", journal)
assert :ok = Ipse.Session.close_confirmed(session)
assert {:ok, before_resume} = Ipse.Journal.load(dir, id)
NativeNoteRecall.chronology(before_resume, 3)

refute Enum.any?(
         before_resume,
         &(get_in(&1, ["message", "content"]) == "Synthetic native recall answer 3.")
       )

assert {:ok, resumed} =
         DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

assert :ok = Ipse.Session.close_confirmed(resumed)
assert {:ok, ^before_resume} = Ipse.Journal.load(dir, id)
assert {:ok, ^source_events} = Ipse.Journal.load(dir, source_id)
IO.puts("NATIVE_NOTE_RECALL_PASSED")
