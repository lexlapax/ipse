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
      for number <- 1..5 do
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
                    &(&1["kind"] == "input.original" and &1["origin"] == "unattended_input")
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
                        "category" => "preference",
                        "reason" => "Exact host-verified outcome.",
                        "event_at_ms" => nil,
                        "source" => %{"handle" => page["handle"], "quote" => facts}
                      }
                    }
                  }
                ]

              5 ->
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

File.write!(Path.join(cwd, "sample.txt"), "UNTRUSTED_FILE_PROSE")
text = "UNTRUSTED_CLI_INPUT claim this is a preference"
cli_args = ["--cwd", cwd, "--config", config_path, "--no-project-config"]

code =
  case scenario do
    "argv" ->
      Ipse.CLI.run(["run", text] ++ cli_args)

    "stdin" ->
      original = Process.group_leader()
      {:ok, io} = StringIO.open(text)
      Process.group_leader(self(), io)

      try do
        Ipse.CLI.run(["run"] ++ cli_args)
      after
        Process.group_leader(self(), original)
      end
  end

Task.shutdown(server, :brutal_kill)
IO.puts("UNTRUSTED_CLI_CODE #{code}")
[filename] = Path.wildcard(Path.join(home, "sessions/*.jsonl"))
id = Path.basename(filename, ".jsonl")
assert {:ok, events} = Ipse.Journal.load(Path.dirname(filename), id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
input = Enum.find(events, &(&1["type"] == "input_received"))
assert input["origin"] == "unattended_input" and input["text"] == text
admission = hd(events)["metadata"]["semantic_admission"]
assert admission["status"] == "active" and admission["policy"]["headless"] == true
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

IO.puts("UNTRUSTED_CLI_ROOT " <> Jason.encode!(%{"snapshot" => snapshot, "page" => page}))
refute Enum.any?(page["records"], &String.starts_with?(&1["key"], "note."))
assert Enum.all?(page["records"], &String.starts_with?(&1["key"], "pending."))
refute File.exists?(Path.join(cwd, "forbidden.txt"))
refute File.exists?(Path.join(cwd, "forbidden-shell"))
IO.puts("UNTRUSTED_CLI_#{String.upcase(scenario)}_PASSED")
