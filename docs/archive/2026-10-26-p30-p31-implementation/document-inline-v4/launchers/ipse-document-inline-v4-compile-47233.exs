source = "_build/document-inline-v4-sol-20261029"
target = "_build/document-inline-v4-complete-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
files = (Path.wildcard("lib/**/*.ex") ++ Path.wildcard("extensions/bundled/**/*.ex")) |> Enum.sort()
for file <- files do
  File.mkdir_p!(Path.dirname(target <> "/" <> file))
  File.cp!(file, target <> "/" <> file)
end
hashes = Enum.map(files, fn file ->
  hash = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
  hash <> "  " <> file <> "\n"
end)
File.write!(target <> "/host-inputs.sha256", hashes)
ebin = target <> "/_build/dev/lib/ipse/ebin"
Path.wildcard(ebin <> "/Elixir.Ipse*.beam") |> Enum.each(&File.rm!/1)
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Mix.start()
Code.compiler_options(ignore_module_conflict: true)
{:ok, modules, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile_to_path(Enum.map(files, &(target <> "/" <> &1)), ebin, return_diagnostics: true)
{:ok, [{:application, :ipse, properties}]} = :file.consult(String.to_charlist(ebin <> "/ipse.app"))
properties = Keyword.put(properties, :modules, Enum.sort(modules))
File.write!(ebin <> "/ipse.app", :io_lib.format("~tp.~n", [{:application, :ipse, properties}]))
true = hashes === Enum.map(files, fn file ->
  hash = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
  hash <> "  " <> file <> "\n"
end)
IO.puts("Current #{length(files)} host/bundled sources compiled with zero diagnostics; #{length(modules)} modules in exact application inventory")
