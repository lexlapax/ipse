ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{Journal, JSON, Session}
alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}

{:ok, _} = Application.ensure_all_started(:ipse)
[root, day_arg] = System.argv()
day = String.to_integer(day_arg)
assert day in [364, 386]
Code.require_file("managed_clock_lifecycle.exs", __DIR__)
Code.require_file("provider_fixture.ex", __DIR__)
Ipse.Test.ManagedClockLifecycle.check_stdio_clock(root)

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

home = Path.join(root, "home")
cwd = Path.join(root, "work")
seed = root |> Path.join("clock-late-seed.json") |> File.read!() |> Jason.decode!()
source = Path.join([home, "sessions", seed["session_id"] <> ".jsonl"])
assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
assert binding === seed["binding"]
control_root = SemanticAdmission.control_root(home)
assert {:ok, before} = Consent.existing_snapshot(control_root, binding["project_id"])
now = System.system_time(:millisecond)
assert now >= seed["seed_wall_ms"] + day * 86_400_000
assert now < seed["seed_wall_ms"] + (day + 1) * 86_400_000
config_path = Path.join(home, "config.json")

if day == 364 do
  assert now < before["policy"]["expires_at_ms"]
  assert {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
  assert {:ok, {_, port}} = :inet.sockname(listener)
  :ok = :gen_tcp.close(listener)
  base = "http://127.0.0.1:#{port}"

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

  assert Ipse.CLI.run([
           "knowledge",
           "enable",
           "--cwd",
           cwd,
           "--config",
           config_path,
           "--no-project-config"
         ]) == 0

  assert {:ok, renewed} = Consent.existing_snapshot(control_root, binding["project_id"])
  assert renewed["epoch"] == before["epoch"] + 1

  File.write!(
    Path.join(root, "clock-renewal-route.json"),
    Jason.encode!(%{
      "port" => port,
      "new_epoch" => renewed["epoch"],
      "old_expiry_ms" => before["policy"]["expires_at_ms"],
      "new_expiry_ms" => renewed["policy"]["expires_at_ms"]
    }),
    [:exclusive]
  )
else
  route = root |> Path.join("clock-renewal-route.json") |> File.read!() |> Jason.decode!()
  assert now > route["old_expiry_ms"] and now < route["new_expiry_ms"]
  assert before["epoch"] == route["new_epoch"]
  assert before["policy"]["expires_at_ms"] == route["new_expiry_ms"]

  assert {:ok, listener} =
           :gen_tcp.listen(route["port"], [
             :binary,
             active: false,
             ip: {127, 0, 0, 1},
             reuseaddr: true
           ])

  owner = self()

  server =
    Task.async(fn ->
      try do
        for number <- 1..2 do
          {:ok, socket} = :gen_tcp.accept(listener, 30_000)

          try do
            {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
            send(owner, {:synthetic_request, number, Jason.decode!(bytes)})

            body =
              Jason.encode!(%{
                "model" => "synthetic",
                "message" => %{"role" => "assistant", "content" => "Synthetic answer."},
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
          after
            :gen_tcp.close(socket)
          end
        end
      after
        :gen_tcp.close(listener)
      end
    end)

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

  assert {:ok, effective} =
           Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

  assert {:ok, config} = Ipse.Config.runtime(effective, client)
  assert config.provider == :ollama and config.base_url == "http://127.0.0.1:#{route["port"]}"
  dir = Path.join(home, "sessions")

  assert {:ok, session} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
           )

  id = Session.info(session).id
  assert :ok = Session.prompt(session, "What current statement has the operator saved?")

  request =
    receive do
      {:synthetic_request, 1, body} -> body
      {:ipse, ^session, {:error, reason}} -> flunk("recall refused: #{inspect(reason)}")
    after
      20_000 -> flunk("synthetic recall request was not dispatched")
    end

  assert Jason.encode!(request) =~ seed["current"]["value"]["text"]
  assert_receive {:ipse, ^session, {:done, :ok}}, 20_000
  assert :ok = Session.close_confirmed(session)
  assert {:ok, events} = Journal.load(dir, id)
  assert [dispatch] = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
  prior = Enum.take_while(events, &(&1 != dispatch))
  [original_source] = seed["current"]["value"]["evidence"]["sources"]

  assert Enum.any?(prior, fn event ->
           event["type"] == "managed_read_observed" and
             Enum.any?(event["dependencies"], fn dependency ->
               subject = dependency["subject"]
               validity = subject["validity"] || %{}

               dependency["policy_generation"] == before["epoch"] and
                 subject["kind"] == "record_observation" and
                 subject["key"] == seed["current"]["key"] and
                 validity["status"] == "eligible" and
                 %{
                   "id" => original_source["occurrence_id"],
                   "version" => original_source["version_id"]
                 } in (validity["source_versions"] || [])
             end)
         end)

  assert {:ok, _} = Session.Saved.restore(events, id)

  assert {:ok, %{"release_claim" => "signed_release_claim"}} =
           Session.Saved.inspect_saved(dir, id)

  held = source <> ".held"
  false = File.exists?(held)
  File.rename!(source, held)

  try do
    assert {:ok, stale_session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
             )

    stale_id = Session.info(stale_session).id
    assert :ok = Session.prompt(stale_session, "What current statement is available now?")

    stale_request =
      receive do
        {:synthetic_request, 2, body} ->
          body

        {:ipse, ^stale_session, {:error, reason}} ->
          flunk("stale recall refused: #{inspect(reason)}")
      after
        20_000 -> flunk("stale recall request was not dispatched")
      end

    refute Jason.encode!(stale_request) =~ seed["current"]["value"]["text"]
    assert_receive {:ipse, ^stale_session, {:done, :ok}}, 20_000
    assert :ok = Session.close_confirmed(stale_session)
    assert {:ok, stale_events} = Journal.load(dir, stale_id)
    assert [_] = Enum.filter(stale_events, &(&1["type"] == "inference_dispatch_intent"))
    assert {:ok, _} = Session.Saved.restore(stale_events, stale_id)
  after
    if File.exists?(held) and not File.exists?(source), do: File.rename!(held, source)
  end

  assert [:ok, :ok] = Task.await(server, 10_000)
  assert JSON.sha256(File.read!(source)) == seed["source_sha256"]

  assert {:ok, %{"release_claim" => "signed_release_claim"}} =
           Session.Saved.inspect_saved(dir, seed["session_id"])

  File.write!(
    Path.join(root, "clock-renewal-recall.json"),
    Jason.encode!(%{
      "synthetic_requests" => 2,
      "old_note_in_request" => true,
      "missing_source_withheld" => true,
      "annual_workload_qualification" => false
    }),
    [:exclusive]
  )
end

IO.puts("NATIVE_RENEWAL_RECALL_PASSED=#{day}")
