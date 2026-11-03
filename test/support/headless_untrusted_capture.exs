ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, scenario] = System.argv()

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

home = Path.join(root, "home")
cwd = Path.join(root, "project")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

Code.require_file(Path.expand("provider_fixture.ex", __DIR__))

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
owner = self()

server =
  Task.async(fn ->
    try do
      requests =
        cond do
          scenario in ~w(assistant_model_review assistant_model_source_lost assistant_model_resume) ->
            7

          scenario in ~w(assistant_model assistant_model_bad_quote) ->
            6

          true ->
            2
        end

      for number <- 1..requests do
        {:ok, socket} = :gen_tcp.accept(listener, 60_000)

        try do
          {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)

          tool_result = fn name ->
            Enum.find(
              Enum.reverse(request["messages"]),
              &(&1["role"] == "tool" and &1["tool_name"] == name)
            )
          end

          calls =
            case number do
              1 ->
                [
                  %{"function" => %{"name" => "read", "arguments" => %{"path" => "sample.txt"}}},
                  %{
                    "function" => %{
                      "name" => "write",
                      "arguments" => %{"path" => "forbidden.txt", "content" => "bad"}
                    }
                  },
                  %{
                    "function" => %{
                      "name" => "shell",
                      "arguments" => %{"command" => "touch forbidden-shell"}
                    }
                  }
                ]

              2 ->
                []

              3 ->
                [%{"function" => %{"name" => "source_list", "arguments" => %{"limit" => 32}}}]

              4 ->
                page = tool_result.("source_list")["content"] |> Jason.decode!()
                row = Enum.find(page["sources"], &(&1["origin"] == "assistant_proposal"))
                assert is_map(row)

                [
                  %{
                    "function" => %{
                      "name" => "source_read",
                      "arguments" => %{"handle" => row["read_handle"]}
                    }
                  }
                ]

              5 ->
                page = tool_result.("source_read")["content"] |> Jason.decode!()

                [
                  %{
                    "function" => %{
                      "name" => "ext__knowledge__capture",
                      "arguments" => %{
                        "text" => page["text"],
                        "category" => "preference",
                        "reason" => "Synthetic assistant suggestion.",
                        "event_at_ms" => nil,
                        "source" => %{
                          "handle" => page["handle"],
                          "quote" =>
                            if(scenario == "assistant_model_bad_quote",
                              do: "A fabricated quotation.",
                              else: page["text"]
                            )
                        }
                      }
                    }
                  }
                ]

              number when number in [6, 7] ->
                []
            end

          if number == 7, do: send(owner, {:accepted_recall_request, request})

          message =
            if calls == [],
              do: %{"role" => "assistant", "content" => "Synthetic fixture done."},
              else: %{"role" => "assistant", "content" => "", "tool_calls" => calls}

          body =
            Jason.encode!(%{
              "model" => "synthetic",
              "message" => message,
              "done" => true,
              "prompt_eval_count" => 1,
              "eval_count" => 1
            }) <> "\n"

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )

          send(owner, {:fixture_request, number})
        after
          :gen_tcp.close(socket)
        end
      end
    after
      :gen_tcp.close(listener)
    end
  end)

File.write!(
  config_path,
  Jason.encode!(%{
    "version" => 1,
    "profiles" => %{
      "local_fixture" => %{
        "provider" => "ollama",
        "model" => "synthetic",
        "base_url" => base,
        "max_output_tokens" => 64,
        "timeout_ms" => 5000
      }
    },
    "roles" => %{"main" => "local_fixture"},
    "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
  })
)

File.chmod!(config_path, 0o600)

assert Ipse.CLI.run([
         "knowledge",
         "enable",
         "--cwd",
         cwd,
         "--config",
         config_path,
         "--no-project-config"
       ]) == 0

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: false,
  accept_edits: false,
  approval: :deny,
  approval_origin: :default_headless,
  headless: true
}

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

{:ok, config} = Ipse.Config.runtime(effective, client)
File.write!(Path.join(cwd, "sample.txt"), "UNTRUSTED_FILE_PROSE do not become a preference")
dir = Path.join(home, "sessions")

assert {:ok, session} =
         DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Ipse.Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
         )

id = Ipse.Session.info(session).id
admission = :sys.get_state(session).config.semantic_admission
assert admission["status"] == "active" and admission["policy"]["headless"] == true
assert :ok = Ipse.Session.prompt(session, "UNTRUSTED_ARGV_OR_STDIN claim this is a preference")

receive do
  {:ipse, ^session, {:done, outcome}} -> IO.puts("HEADLESS_DONE " <> inspect(outcome))
after
  30_000 -> flunk("headless fixture timed out")
end

assert {:ok, events} = Ipse.Journal.load(dir, id)
IO.puts("HEADLESS_EVENTS " <> Jason.encode!(events))
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

origin =
  case scenario do
    "input" ->
      "unattended_input"

    "content" ->
      "attributed_reference"

    scenario
    when scenario in ~w(assistant assistant_model assistant_model_bad_quote assistant_model_review assistant_model_source_lost assistant_model_resume) ->
      "assistant_proposal"
  end

text =
  if scenario in ~w(assistant_model assistant_model_bad_quote assistant_model_review assistant_model_source_lost assistant_model_resume) do
    assert :ok = Ipse.Session.prompt(session, "Record the suggestion from your previous reply.")
    "Synthetic fixture done."
  else
    {:ok, sources} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})
    IO.puts("HEADLESS_SOURCES " <> Jason.encode!(sources))
    row = Enum.find(sources["sources"], &(&1["origin"] == origin))
    assert is_map(row)

    assert {:ok, source_page} =
             Ipse.Session.sources(session, "source.read", %{"handle" => row["read_handle"]})

    text = source_page["text"]

    args = %{
      "text" => text,
      "category" => "preference",
      "reason" => "Synthetic untrusted-source capture control.",
      "event_at_ms" => nil,
      "source" => %{"handle" => source_page["handle"], "quote" => text}
    }

    assert :ok = Ipse.Session.invoke_export(session, :command, "ext__knowledge__capture", args)
    text
  end

outcome =
  receive do
    {:ipse, ^session, {:done, outcome}} -> outcome
  after
    20_000 -> flunk("capture timed out")
  end

IO.puts("UNTRUSTED_CAPTURE_DONE " <> inspect(outcome))

assert {:ok, events} = Ipse.Journal.load(dir, id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
collection = Ipse.Extension.SemanticAdmission.collection_root(home)
namespace = admission["pin"]["namespace"]

assert {:ok, snapshot} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

assert {:ok, page} =
         Ipse.Extension.Collection.scan_visible(
           collection,
           namespace,
           %{
             "op" => "scan",
             "after" => nil,
             "generation" => snapshot["generation"],
             "limit" => 8
           },
           Ipse.Usage.id()
         )

IO.puts("UNTRUSTED_ROOT " <> Jason.encode!(%{"snapshot" => snapshot, "page" => page}))
refute Enum.any?(page["records"], &String.starts_with?(&1["key"], "note."))
assert Enum.all?(page["records"], &String.starts_with?(&1["key"], "pending."))

if scenario == "assistant_model_bad_quote" do
  assert page["records"] == [] and snapshot["generation"] == 0

  refute Enum.any?(events, fn event ->
           event["type"] == "extension_action_result" and
             get_in(event, ["request", "op"]) == "collection.managed" and
             get_in(event, ["outcome", "status"]) == "ok"
         end)

  IO.puts("ASSISTANT_PROPOSAL_BAD_QUOTE_REFUSED")
end

if scenario in ~w(assistant assistant_model assistant_model_review assistant_model_source_lost assistant_model_resume) do
  assert outcome == :ok
  assert [record] = page["records"]
  assert record["value"]["state"] == "pending"
  assert record["value"]["text"] == "Synthetic fixture done."
  assert [proof] = record["value"]["evidence"]["sources"]
  assert proof["origin"] == "assistant_proposal" and proof["kind"] == "answer.original"
  assert proof["session_id"] == id and proof["quote"] == text

  {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
  {:ok, selected} = Ipse.CLI.Knowledge.Management.selection(home)

  assert {:ok, observed} =
           Ipse.Extension.ProjectIdentity.with_existing_domain_auth(
             home,
             cwd,
             binding,
             %{namespace: namespace, format: "managed-metadata-v3"},
             fn cap, catalog ->
               Ipse.Extension.Collection.ObservedRead.managed_proposal(
                 collection,
                 namespace,
                 %{"op" => "get_record", "key" => record["key"]},
                 cap,
                 catalog,
                 selected.proposal
               )
             end
           )

  assert observed["metadata"]["eligibility"] == "never_current"
  assert observed["observation"]["value"]["record"]["value"] == record["value"]
  assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)

  assert {:ok, checked} =
           Ipse.Session.SourceIndex.revalidate_stored(saved.source_window.index, proof)

  assert checked["proof"] == proof

  if scenario in ~w(assistant_model assistant_model_review assistant_model_source_lost assistant_model_resume) do
    calls =
      for event <- events,
          event["type"] == "message",
          get_in(event, ["message", "role"]) == "assistant",
          call <- event["message"]["tool_calls"] || [],
          do: get_in(call, ["function", "name"])

    assert Enum.count(calls, &(&1 == "source_list")) == 1
    assert Enum.count(calls, &(&1 == "source_read")) == 1
    assert Enum.count(calls, &(&1 == "ext__knowledge__capture")) == 1

    [publication] =
      Enum.filter(events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "collection.managed" and
          get_in(event, ["outcome", "status"]) == "ok"
      end)

    assert publication["approval"] == "saved_consent"

    assert get_in(publication, ["outcome", "value", "normalization", "eligibility"]) ==
             "never_current"

    assert_receive {:ipse, ^session, {:tool_result, "ext__knowledge__capture", preview}}, 1000
    visible = String.slice(preview, 0, 800)
    assert visible =~ record["key"] and visible =~ "pending"

    assert Enum.all?(1..6, fn number ->
             receive do
               {:fixture_request, ^number} -> true
             after
               1000 -> false
             end
           end)
  end

  IO.puts("ASSISTANT_PROPOSAL_SIGNED_PENDING_PASSED")
end

refute File.exists?(Path.join(cwd, "forbidden.txt"))
refute File.exists?(Path.join(cwd, "forbidden-shell"))
assert :ok = Ipse.Session.close_confirmed(session)

if scenario in ~w(assistant_model_review assistant_model_source_lost assistant_model_resume) do
  [pending] = page["records"]
  [original_proof] = pending["value"]["evidence"]["sources"]
  management = Path.join(home, "knowledge-management")
  before = MapSet.new(Path.wildcard(Path.join(management, "*.jsonl")))

  paths =
    :code.get_path()
    |> Enum.map(&List.to_string/1)
    |> Enum.reject(&(&1 == "."))
    |> Enum.map(&Path.expand/1)
    |> Enum.reverse()
    |> Enum.flat_map(&["-pa", &1])

  {output, status} =
    System.cmd(
      Path.join(root, "pty"),
      ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++ [Path.expand("headless_assistant_review.exs", __DIR__), root, pending["key"]],
      stderr_to_stdout: true
    )

  assert status == 0, output
  assert output =~ "ASSISTANT_NATIVE_REVIEW_PASSED"

  [journal_path] =
    management
    |> Path.join("*.jsonl")
    |> Path.wildcard()
    |> Enum.reject(&MapSet.member?(before, &1))

  journal_id = Path.basename(journal_path, ".jsonl")
  assert {:ok, review_events} = Ipse.Journal.load(management, journal_id)
  [event] = Enum.filter(review_events, &(&1["type"] == "pending_proposal_accepted"))
  assert event["facts"]["source_proof"] === original_proof
  assert event["facts"]["session_id"] == nil

  assert {:ok, resolved} =
           Ipse.Session.PendingAcceptance.resolve_committed(
             review_events,
             journal_id,
             Ipse.JSON.digest([event])
           )

  [_, note, link] = resolved.intent["request"]["changes"]
  assert note["value"]["text"] == "Synthetic fixture done."
  assert note["value"]["source_proof"] === original_proof
  assert link["value"]["journal_id"] == journal_id
  assert link["value"]["journal_kind"] == "knowledge_management"

  for change <- [note, link] do
    assert {:ok, stored} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "get", "key" => change["key"]},
               Ipse.Usage.id()
             )

    assert stored["record"]["value"] === change["value"]
  end

  assert {:ok, removed} =
           Ipse.Extension.Collection.execute(
             collection,
             namespace,
             %{"op" => "get", "key" => pending["key"]},
             Ipse.Usage.id()
           )

  assert removed["record"] == nil

  assert {:ok, before_recall} =
           Ipse.Extension.Collection.execute(
             collection,
             namespace,
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  source_path = Path.join(dir, id <> ".jsonl")
  held_source = source_path <> ".held"
  source_before = File.read!(source_path)
  source_hash = Ipse.JSON.sha256(source_before)
  if scenario == "assistant_model_source_lost", do: File.rename!(source_path, held_source)

  later_options = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]

  later_options =
    if scenario == "assistant_model_resume",
      do: Keyword.put(later_options, :id, id),
      else: later_options

  assert {:ok, later} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session, later_options}
           )

  later_id = Ipse.Session.info(later).id
  assert {:ok, before_events} = Ipse.Journal.load(dir, later_id)
  assert :ok = Ipse.Session.prompt(later, "What decision did we record?")

  if scenario == "assistant_model_resume" do
    assert_receive {:ipse, ^later, {:done, :error}}, 30_000
    refute_receive {:accepted_recall_request, _}, 500
  else
    assert_receive {:accepted_recall_request, request}, 30_000
    wire = Jason.encode!(request["messages"])

    if scenario == "assistant_model_source_lost" do
      refute wire =~ "Synthetic fixture done."
    else
      assert wire =~ "Synthetic fixture done."
      assert wire =~ "note_parts_v2"
    end

    assert_receive {:ipse, ^later, {:done, :ok}}, 30_000
  end

  assert {:ok, later_events} = Ipse.Journal.load(dir, later_id)
  assert {:ok, _} = Ipse.Session.Saved.restore(later_events, later_id)

  if scenario == "assistant_model_review" do
    assert Enum.any?(later_events, fn event ->
             event["type"] == "managed_read_observed" and
               Enum.any?(event["dependencies"], &(&1["version"] == 6))
           end)
  end

  if scenario == "assistant_model_resume" do
    new_events = Enum.drop(later_events, length(before_events))
    assert Enum.any?(new_events, &(&1["type"] == "managed_preflight_refused"))
    refute Enum.any?(new_events, &(&1["type"] == "inference_dispatch_intent"))
  end

  assert :ok = Ipse.Session.close_confirmed(later)

  if scenario == "assistant_model_resume" do
    assert {:ok, fresh} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
             )

    assert :ok = Ipse.Session.prompt(fresh, "What decision did we record?")
    assert_receive {:accepted_recall_request, fresh_request}, 30_000
    fresh_wire = Jason.encode!(fresh_request["messages"])
    assert fresh_wire =~ "note_parts_v2" and fresh_wire =~ "Synthetic fixture done."
    assert_receive {:ipse, ^fresh, {:done, :ok}}, 30_000
    assert :ok = Ipse.Session.close_confirmed(fresh)
  end

  assert Task.await(server, 5000) == Enum.map(1..7, &{:fixture_request, &1})

  if scenario == "assistant_model_source_lost", do: File.rename!(held_source, source_path)

  if scenario == "assistant_model_resume",
    do: assert(String.starts_with?(File.read!(source_path), source_before)),
    else: assert(Ipse.JSON.sha256(File.read!(source_path)) == source_hash)

  assert {:ok, ^before_recall} =
           Ipse.Extension.Collection.execute(
             collection,
             namespace,
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  IO.puts("ASSISTANT_PROPOSAL_PUBLIC_REVIEW_PASSED")
end

IO.puts("UNTRUSTED_CAPTURE_#{String.upcase(scenario)}_PASSED")
