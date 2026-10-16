Application.ensure_all_started(:ipse)
Code.require_file(Path.join(Application.app_dir(:ipse, "priv"), "self-development-demo.exs"))
Ipse.SelfDevelopmentDemo.run()
