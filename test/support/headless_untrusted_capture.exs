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
      for number <- 1..2 do
        {:ok, socket} = :gen_tcp.accept(listener, 30_000)

        try do
          {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          _request = Jason.decode!(bytes)

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

receive do
  {:ipse, ^session, {:done, outcome}} -> IO.puts("HEADLESS_DONE " <> inspect(outcome))
after
  30_000 -> flunk("headless fixture timed out")
end

assert {:ok, events} = Ipse.Journal.load(dir, id)
IO.puts("HEADLESS_EVENTS " <> Jason.encode!(events))
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
{:ok, sources} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})
IO.puts("HEADLESS_SOURCES " <> Jason.encode!(sources))

origin =
  case scenario do
    "input" -> "unattended_input"
    "content" -> "attributed_reference"
    "assistant" -> "assistant_proposal"
  end

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

receive do
  {:ipse, ^session, {:done, outcome}} -> IO.puts("UNTRUSTED_CAPTURE_DONE " <> inspect(outcome))
after
  20_000 -> flunk("capture timed out")
end

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
refute File.exists?(Path.join(cwd, "forbidden.txt"))
refute File.exists?(Path.join(cwd, "forbidden-shell"))
assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("UNTRUSTED_CAPTURE_#{String.upcase(scenario)}_PASSED")
