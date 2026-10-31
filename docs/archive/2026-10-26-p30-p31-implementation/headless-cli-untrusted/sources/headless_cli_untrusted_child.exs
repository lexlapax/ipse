{:ok, _} = Application.ensure_all_started(:ipse)
System.halt(Ipse.CLI.run(System.argv()))
