root = "docs/archive/2026-10-26-p30-p31-implementation/pending-projection/source"
target = Path.join(System.tmp_dir!(), "ipse-pending-projection-#{System.unique_integer([:positive])}")
File.mkdir_p!(target)
files = Enum.map(~w(extensions/knowledge/src/notes.ex extensions/knowledge/src/knowledge/contracts.ex extensions/knowledge/src/knowledge/records.ex), &Path.join(root, &1))

try do
  case Kernel.ParallelCompiler.compile_to_path(files, target, warnings_as_errors: true, return_diagnostics: true) do
    {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} ->
      IO.puts("pending projection strict compile passed: #{length(modules)} modules")

    result ->
      IO.inspect(result)
      System.halt(1)
  end
after
  File.rm_rf!(target)
end
