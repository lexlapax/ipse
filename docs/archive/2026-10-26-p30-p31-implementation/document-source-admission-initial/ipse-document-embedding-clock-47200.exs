Mix.start()
source = "_build/document-embedding-admission-sol-20261029"
target = "_build/document-embedding-admission-clock-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
files = ~w(lib/ipse/extension/registry.ex lib/ipse/extension/inference.ex lib/ipse/extension/actions.ex lib/ipse/session/document_embedding.ex lib/ipse/inference_dispatch.ex)
Enum.each(files, fn file ->
  File.write!(file, IO.iodata_to_binary(Code.format_file!(file)))
  File.cp!(file, target <> "/" <> file)
end)
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  Enum.map(files, &(target <> "/" <> &1)), target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
rows = Enum.map(files, fn file ->
  sha = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
  sha <> "  " <> file <> "\n"
end)
File.write!(target <> "/admission-clock-overlays.sha256", rows)
IO.puts("Five amended owners compile without diagnostics; parent175-source cohort preserved")
test = "test/ipse/session/document_embedding_test.exs"
File.write!(test, IO.iodata_to_binary(Code.format_file!(test)))
ExUnit.start(autorun: false, seed: 20261029, exclude: [:test], include: [:document_guard_repair])
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile([test], return_diagnostics: true)
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
