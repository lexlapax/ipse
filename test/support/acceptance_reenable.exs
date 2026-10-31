ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[home, cwd] = System.argv()
config = Path.join(home, "acceptance-test-config.json")

File.write!(
  config,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
)

File.chmod!(config, 0o600)
System.put_env("IPSE_HOME", home)

assert 0 ==
         Ipse.CLI.run([
           "knowledge",
           "enable",
           "--cwd",
           cwd,
           "--config",
           config,
           "--no-project-config"
         ])

IO.puts("ACCEPTANCE_REAL_CONSENT_ENABLED")
