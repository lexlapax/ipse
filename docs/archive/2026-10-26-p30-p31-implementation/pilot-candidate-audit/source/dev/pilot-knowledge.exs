Code.require_file("knowledge/pilot.exs", __DIR__)

with "chatgpt" <- System.get_env("IPSE_KNOWLEDGE_PILOT_CONFIRM"),
     home = System.get_env("IPSE_HOME") || Path.join(System.user_home!(), ".ipse"),
     {:ok, effective} <- Ipse.Config.resolve(File.cwd!(), home, project_config: false),
     true <- effective.settings["provider"] == "chatgpt",
     true <- effective.extensions["instances"] == [],
     {:ok, config} <-
       Ipse.Config.runtime(effective, %{
         workspace: File.cwd!(),
         home: home,
         operator_home: home,
         auth_dir: Path.join(home, "auth"),
         mcp_config: nil,
         base_url: nil,
         operator_questions: false,
         approval: :deny
       }),
     {:ok, audit_file} <-
       Ipse.Development.Knowledge.Pilot.open_audit(
         System.get_env("IPSE_KNOWLEDGE_PILOT_AUDIT_DIR")
       ) do
  IO.puts(
    JSON.encode!(%{
      event: "pilot_plan",
      provider: "chatgpt",
      model: config.model,
      maximum_calls: 120,
      sessions: 3,
      turns_per_session: 20,
      published: 0,
      private_candidate_audit: not is_nil(audit_file),
      data: "synthetic exposed development tasks; not held-out quality evidence"
    })
  )

  result =
    try do
      Ipse.Development.Knowledge.Pilot.run(
        config,
        &Ipse.Provider.request_complete/4,
        &IO.puts(JSON.encode!(&1)),
        if(audit_file, do: &Ipse.Development.Knowledge.Pilot.write_audit(audit_file, &1))
      )
    after
      if audit_file, do: File.close(audit_file)
    end

  case result do
    {:ok, _, count} ->
      IO.puts(JSON.encode!(%{status: "completed", calls: count, published: 0}))

    {:error, reason, _, count} ->
      IO.puts(
        JSON.encode!(%{status: "failed", reason: reason, attempted_calls: count, published: 0})
      )

      System.halt(1)
  end
else
  _ ->
    IO.puts(
      "Pilot refused: explicitly confirm chatgpt; retain configured ChatGPT route without extensions or shared budgets; any audit directory must be new and writable."
    )

    System.halt(1)
end
