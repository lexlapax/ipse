Application.ensure_all_started(:ipse)
Code.require_file(Path.join(Application.app_dir(:ipse, "priv"), "subagent-demo.exs"))
Ipse.SubagentDemo.run()
