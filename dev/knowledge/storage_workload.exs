Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("storage_workload.ex", __DIR__)
Code.require_file("storage_continuation.exs", __DIR__)
Code.require_file("storage_annual.exs", __DIR__)

case System.argv() do
  ["--native-calendar", intake] ->
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    Code.require_file("native_notes_seed.ex", __DIR__)
    Code.require_file("native_notes_workload.ex", __DIR__)
    plan = Ipse.Development.NativeNotesWorkload.calendar(String.to_integer(intake))
    IO.puts(Jason.encode!(Map.drop(plan, ["days", "final_records"])))

  ["--native-operation-floor"] ->
    for interpretation <- [:mixed_operations, :complete_cycles] do
      report =
        Ipse.Development.StorageWorkload.native_operation_floor(365, 10_000, interpretation)

      IO.puts(Jason.encode!(report))
    end

  ["--check"] ->
    Ipse.Development.StorageWorkload.check()

  args ->
    if Enum.any?(
         args,
         &(&1 == "--segmented" or &1 == "--resume" or String.starts_with?(&1, "--resume="))
       ) do
      Ipse.Development.StorageAnnual.run(args)
    else
      Ipse.Development.StorageWorkload.run(args)
    end
end
