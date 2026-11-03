ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, key] = System.argv()
home = Path.join(root, "home")
System.put_env("IPSE_HOME", home)

assert Ipse.CLI.run([
         "knowledge",
         "review",
         key,
         "--cwd",
         Path.join(root, "project"),
         "--config",
         Path.join(home, "config.json"),
         "--no-project-config"
       ]) == 0

IO.puts("ASSISTANT_NATIVE_REVIEW_PASSED")
