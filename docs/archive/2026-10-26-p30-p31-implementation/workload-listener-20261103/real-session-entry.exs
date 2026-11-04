ExUnit.start(autorun: false)
import ExUnit.Assertions

alias Ipse.{Config, Journal, Session}

Code.require_file("/dev/shm/ipse-workload-listener-20261103/dev/fixtures/synthetic_ollama.exs")
provider = Ipse.Development.SyntheticOllama

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

root = System.fetch_env!("IPSE_LISTENER_SMOKE_ROOT")
true = Path.type(root) == :absolute
home = Path.join(root, "home")
cwd = Path.join(root, "work")
File.mkdir!(home)
File.mkdir!(cwd)
File.chmod!(home, 0o700)
File.chmod!(cwd, 0o700)
System.put_env("IPSE_HOME", home)
{:ok, _} = Application.ensure_all_started(:ipse)

{:ok, reservation} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
{:ok, {_, port}} = :inet.sockname(reservation)
:ok = :gen_tcp.close(reservation)
base = "http://127.0.0.1:#{port}"

path = Path.join(home, "config.json")
doc = %{
  "version" => 1,
  "profiles" => %{"fixture" => %{"provider" => "ollama", "model" => "synthetic", "base_url" => base, "max_output_tokens" => 64, "timeout_ms" => 5000}},
  "roles" => %{"main" => "fixture"},
  "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
}
File.write!(path, Jason.encode!(doc))
File.chmod!(path, 0o600)

client = %{
  workspace: cwd, home: home, auth_dir: Path.join(home, "auth"), operator_home: root,
  mcp_config: nil, base_url: nil, operator_questions: true, accept_edits: false,
  approval: :ask, approval_origin: :interactive, headless: false
}

{:ok, effective} = Config.resolve(cwd, home, [config: path, project_config: false], %{})
{:ok, config} = Config.runtime(effective, client)
assert config.provider == :ollama and config.model == "synthetic" and config.base_url == base
{:ok, server} = provider.start(port, self(), 1, 1)
dir = Path.join(home, "sessions")
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self(), owner: self()]
{:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
:ok = Ipse.Session.Lock.track_session(session)
id = Session.info(session).id
prompt = provider.prompt(1)
assert :ok = Session.prompt(session, prompt)

assert_receive {:synthetic_provider_request, 1, digest, request_bytes, reference}, 20_000
assert Ipse.JSON.sha256?(digest) and request_bytes > 0 and is_boolean(reference)
assert_receive {:ipse, ^session, {:done, :ok}}, 20_000
assert :ok = Task.await(server, 5_000)
assert :ok = Session.close_confirmed(session)
assert {:ok, before_resume} = Journal.load(dir, id)
assert Enum.count(before_resume, &(&1["type"] == "input_received")) == 1
assert Enum.count(before_resume, &(&1["type"] == "inference_dispatch_intent")) == 1
assert Enum.count(before_resume, &(&1["type"] == "turn_finished" and &1["status"] == "ok")) == 1
assert {:ok, _} = Session.Saved.restore(before_resume, id)

assert {:ok, resumed} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(opts, :id, id)})
assert {:ok, after_resume} = Journal.load(dir, id)
assert Enum.take(after_resume, length(before_resume)) == before_resume
assert Enum.count(after_resume, &(&1["type"] == "inference_dispatch_intent")) == 1
refute_receive {:synthetic_provider_request, _, _, _, _}, 100
assert :ok = Session.close_confirmed(resumed)
IO.puts("SYNTHETIC_LISTENER_SESSION_SMOKE_OK reference_observed=#{reference}")
