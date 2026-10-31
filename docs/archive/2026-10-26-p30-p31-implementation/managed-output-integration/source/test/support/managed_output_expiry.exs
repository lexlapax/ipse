ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("provider_fixture.ex", __DIR__))

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

[root, "save"] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "work")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
{:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
owner = self()

server =
  Task.async(fn ->
    receive do
      {:note_key, key} ->
        {:ok, socket} = :gen_tcp.accept(listener, 20_000)
        {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
        send(owner, {:expiry_first_body, Jason.decode!(bytes)})

        body =
          Jason.encode!(%{
            "model" => "synthetic",
            "message" => %{
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [
                %{
                  "type" => "function",
                  "function" => %{
                    "name" => "ext__knowledge__read",
                    "arguments" => %{"key" => key}
                  }
                }
              ]
            },
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

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
    end
  end)

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
active_config = :sys.get_state(source).config
assert :ok = Ipse.Session.close_confirmed(source)

Code.require_file("managed_output_literal.exs", __DIR__)
ordinary = Enum.find(page["records"], &(&1["value"]["category"] == "ordinary"))

deadline =
  Ipse.Test.ManagedOutputLiteral.shorten(active_config, cwd, dir, ordinary["key"], 5000)

assert {:ok, consumer} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
consumer_id = Ipse.Session.info(consumer).id

send(server.pid, {:note_key, ordinary["key"]})
assert :ok = Ipse.Session.prompt(consumer, "Read the exact current ordinary note.")
assert_receive {:expiry_first_body, first_body}, 5000
assert Jason.encode!(first_body) =~ ordinary["value"]["text"]

observed =
  Enum.reduce_while(1..100, false, fn _, _ ->
    {:ok, current} = Ipse.Journal.load(dir, consumer_id)

    if Enum.count(current, &(&1["type"] == "managed_read_observed")) == 5 do
      {:halt, true}
    else
      Process.sleep(10)
      {:cont, false}
    end
  end)

assert observed and System.system_time(:millisecond) < deadline

assert_receive {:ipse, ^consumer, {:tool_result, "ext__knowledge__read", text}}, 12_000
assert Jason.decode!(text)["status"] == "withheld"
refute text =~ ordinary["value"]["text"]
assert_receive {:ipse, ^consumer, {:done, :error}}, 5000
assert System.system_time(:millisecond) >= deadline
assert {:ok, events} = Ipse.Journal.load(dir, consumer_id)
read = events |> Enum.filter(&(&1["type"] == "managed_read_observed")) |> List.last()
[dependency] = read["dependencies"]
assert dependency["version"] == 4
assert dependency["subject"]["validity"]["valid_until_ms"] == deadline

[raw] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_invocation_result" and
        get_in(&1, ["descriptor", "stage"]) == "invoke.tool")
  )

assert Jason.encode!(raw["value"]) =~ ordinary["value"]["text"]

[intent] =
  Enum.filter(
    events,
    &(&1["type"] == "managed_output_release_intent" and
        &1["parent_invocation_id"] == raw["invocation_id"])
  )

[admission] =
  Enum.filter(
    events,
    &(&1["type"] == "managed_output_release_result" and &1["release_id"] == intent["release_id"])
  )

assert admission["decision"] == "withdrawn"

assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 1
refute Enum.any?(events, &(&1["type"] == "extension_inference_intent"))

assert {:ok, saved} = Ipse.Session.Saved.restore(events, consumer_id)
assert Enum.any?(saved.messages, &(&1["role"] == "tool" and &1["content"] == text))
Task.await(server, 5000)
assert :ok = Ipse.Session.close_confirmed(consumer)
IO.puts("NATIVE_MANAGED_OUTPUT_LITERAL_EXPIRY_PASSED")
