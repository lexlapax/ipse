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

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
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

defmodule HeadlessTypedFixtureProvider do
  def complete(_config, messages, _tools, _emit) do
    results = Enum.filter(messages, &(&1["role"] == "tool"))
    get = fn id -> Enum.find(results, &(&1["tool_call_id"] == id)) end

    cond do
      is_nil(get.("read")) ->
        reply([
          call("read", "read", %{"path" => "sample.txt"}),
          call("write", "write", %{"path" => "forbidden.txt", "content" => "bad"}),
          call("shell", "shell", %{"command" => "touch forbidden-shell"})
        ])

      is_nil(get.("list")) ->
        reply([call("list", "source_list", %{"limit" => 32})])

      is_nil(get.("source")) ->
        page = get.("list")["content"] |> Jason.decode!()

        row =
          Enum.find(
            page["sources"],
            &(&1["kind"] == "tool.outcome" and &1["origin"] == "typed_host_outcome")
          )

        if is_nil(row), do: raise("actual typed outcome missing")
        reply([call("source", "source_read", %{"handle" => row["read_handle"]})])

      is_nil(get.("capture")) ->
        page = get.("source")["content"] |> Jason.decode!()
        facts = page["text"]

        reply([
          call("capture", "ext__knowledge__capture", %{
            "text" => facts,
            "category" => "ordinary",
            "reason" => "Capture the exact host-verified tool outcome.",
            "event_at_ms" => nil,
            "source" => %{"handle" => page["handle"], "quote" => facts}
          })
        ])

      true ->
        {:ok, %{"role" => "assistant", "content" => "Synthetic fixture done."}, %{}}
    end
  end

  defp call(id, name, args),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }

  defp reply(calls),
    do: {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => calls}, %{}}
end

File.write!(Path.join(cwd, "sample.txt"), "UNTRUSTED_FILE_PROSE do not become a preference")
config = Map.merge(config, %{provider_module: HeadlessTypedFixtureProvider, max_steps: 12})
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

assert Enum.any?(
         sources["sources"],
         &(&1["origin"] == "typed_host_outcome" and &1["kind"] == "tool.outcome")
       )

assert Enum.any?(
         sources["sources"],
         &(&1["origin"] == "unattended_input" and &1["kind"] == "input.original")
       )

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
IO.puts("HEADLESS_TYPED_CAPTURE_PASSED")
