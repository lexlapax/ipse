ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, "headless"] = System.argv()

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
      for number <- 1..7 do
        {:ok, socket} = :gen_tcp.accept(listener, 30_000)

        try do
          {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          messages = request["messages"]

          tool_result = fn name ->
            Enum.find(Enum.reverse(messages), &(&1["role"] == "tool" and &1["tool_name"] == name))
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
                [%{"function" => %{"name" => "source_list", "arguments" => %{"limit" => 32}}}]

              3 ->
                page = tool_result.("source_list")["content"] |> Jason.decode!()

                row =
                  Enum.find(
                    page["sources"],
                    &(&1["kind"] == "tool.outcome" and &1["origin"] == "typed_host_outcome")
                  )

                if is_nil(row), do: raise("actual typed outcome missing")

                [
                  %{
                    "function" => %{
                      "name" => "source_read",
                      "arguments" => %{"handle" => row["read_handle"]}
                    }
                  }
                ]

              4 ->
                page = tool_result.("source_read")["content"] |> Jason.decode!()
                facts = page["text"]

                [
                  %{
                    "function" => %{
                      "name" => "ext__knowledge__capture",
                      "arguments" => %{
                        "text" => facts,
                        "category" => "ordinary",
                        "reason" => "Exact host-verified outcome.",
                        "event_at_ms" => nil,
                        "source" => %{"handle" => page["handle"], "quote" => facts}
                      }
                    }
                  }
                ]

              5 ->
                assert Enum.any?(messages, fn message ->
                         is_binary(message["content"]) and
                           String.contains?(
                             message["content"],
                             "Host historical metadata notice:"
                           )
                       end)

                assert is_map(tool_result.("ext__knowledge__capture"))
                [%{"function" => %{"name" => "source_list", "arguments" => %{"limit" => 32}}}]

              6 ->
                page = tool_result.("source_list")["content"] |> Jason.decode!()

                row =
                  Enum.find(
                    page["sources"],
                    &(&1["kind"] == "tool.outcome" and &1["origin"] == "typed_host_outcome")
                  )

                assert is_map(row)

                [
                  %{
                    "function" => %{
                      "name" => "source_read",
                      "arguments" => %{"handle" => row["read_handle"]}
                    }
                  }
                ]

              7 ->
                assert is_map(tool_result.("source_read"))
                []
            end

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

outcome =
  receive do
    {:ipse, ^session, {:done, outcome}} -> outcome
  after
    30_000 -> flunk("headless fixture timed out")
  end

IO.puts("HEADLESS_DONE " <> inspect(outcome))
assert outcome == :ok
assert Task.await(server, 5_000) == Enum.map(1..7, &{:fixture_request, &1})

{:messages, notifications} = Process.info(self(), :messages)

source_notices =
  for {:ipse, ^session, {:tool_result, name, preview}} <- notifications,
      name in ~w(source_list source_read source_quote),
      do: {name, preview}

assert Enum.map(source_notices, &elem(&1, 0)) ==
         ~w(source_list source_read source_list source_read)

assert Enum.all?(
         source_notices,
         &(elem(&1, 1) == "Source tool result withheld from terminal preview.")
       )

for {:ipse, ^session, {:tool, name, arguments}} <- notifications,
    name in ~w(source_list source_read source_quote),
    do: assert(arguments == %{})

IO.puts("HEADLESS_SOURCE_PREVIEWS_STATUS_ONLY")

assert {:ok, events} = Ipse.Journal.load(dir, id)
IO.puts("HEADLESS_EVENTS " <> Jason.encode!(events))

assert Enum.any?(
         events,
         &(&1["type"] == "managed_output_release_result" and &1["decision"] == "historical_write")
       )

assert Enum.any?(
         events,
         &(&1["type"] == "managed_preflight_result" and
             get_in(&1, ["projection", "type"]) == "managed_root_transition")
       )

refute Enum.any?(events, &(&1["type"] == "managed_preflight_refused"))
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
{:ok, sources} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})
IO.puts("HEADLESS_SOURCES " <> Jason.encode!(sources))

assert Enum.any?(
         sources["sources"],
         &(&1["origin"] == "typed_host_outcome" and &1["kind"] == "tool.outcome")
       )

assert Enum.any?(
         sources["sources"],
         &(&1["origin"] == "unattended_input" and &1["kind"] == "input.original")
       )

assert Enum.count(sources["sources"], &(&1["kind"] == "input.original")) == 1

assert Enum.any?(
         sources["sources"],
         &(&1["origin"] == "attributed_reference" and &1["kind"] == "tool.content")
       )

refute File.exists?(Path.join(cwd, "forbidden.txt"))
refute File.exists?(Path.join(cwd, "forbidden-shell"))
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
             "limit" => 4
           },
           Ipse.Usage.id()
         )

IO.puts("HEADLESS_ROOT " <> Jason.encode!(%{"snapshot" => snapshot, "page" => page}))
assert [record] = page["records"]
assert [proof] = record["value"]["evidence"]["sources"]
assert proof["origin"] == "typed_host_outcome" and proof["kind"] == "tool.outcome"
assert proof["session_id"] == id
control = Ipse.Extension.SemanticAdmission.control_root(home)
assert {:ok, consent} = Ipse.Extension.Consent.snapshot(control, admission["pin"]["project_id"])
IO.puts("HEADLESS_CONSENT " <> Jason.encode!(consent))

intent =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_intent" and
        get_in(&1, ["request", "op"]) == "collection.managed")
  )

assert is_map(intent) and consent["operations"][intent["operation_id"]]["status"] == "settled"
assert consent["operations"][intent["operation_id"]]["headless"] == true
assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("HEADLESS_TYPED_CAPTURE_FULL_TURN_PASSED")
