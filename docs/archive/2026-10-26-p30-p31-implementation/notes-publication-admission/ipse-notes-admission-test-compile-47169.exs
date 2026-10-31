Path.wildcard("_build/notes-publication-admission-sol-20261029/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
ExUnit.start(autorun: false, seed: 20261029, exclude: [:test], include: [:notes_admission_shape])
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile(
  ~w(test/ipse/extension/notes_publication_admission_test.exs test/ipse/extension/managed_collection_call_test.exs), return_diagnostics: true)
IO.puts("Final notes test source has empty compile/runtime diagnostics; only strengthened shape case runs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
