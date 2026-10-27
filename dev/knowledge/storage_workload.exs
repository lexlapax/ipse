Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("storage_workload.ex", __DIR__)
Code.require_file("storage_continuation.exs", __DIR__)
Code.require_file("storage_annual.exs", __DIR__)

case System.argv() do
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
