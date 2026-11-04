root = "/dev/shm/ipse-populated-cache-phase-a0XYcKFw"
Code.prepend_paths(Path.wildcard(root <> "/runtime/*/ebin"))
for {key, _} <- System.get_env(), String.starts_with?(key, "IPSE_"), do: System.delete_env(key)
home = root <> "/focused-home"
File.mkdir_p!(home)
File.chmod!(home, 0o700)
System.put_env("IPSE_HOME", home)
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start()
for name <- ["json_test-candidate.exs", "source_replay_cache_test.exs", "source_window_test.exs", "saved_test.exs"], do: Code.require_file(root <> "/" <> name)
