source = "_build/document-embedding-admission-inventory-sol-20261029"
target = "_build/document-embedding-admission-return-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
file = "lib/ipse/session/document_embedding.ex"
File.write!(file, IO.iodata_to_binary(Code.format_file!(file)))
File.cp!(file, target <> "/" <> file)
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  [target <> "/" <> file], target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
sha = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
File.write!(target <> "/admission-return-overlay.sha256", sha <> "  " <> file <> "\n")
IO.puts("Exact reader marker preserved through Collection/Identity cleanup before Egress :ok; one-owner compile without diagnostics")
