files = ~w(profiles evidence store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress adapters documents documents/zip documents/docx documents/parser_stage documents/pdf corpus)
files = Enum.map(files, &("extensions/knowledge/src/" <> &1 <> ".ex"))
files = Enum.map(files, fn p -> if String.ends_with?(p, "/producer_progress.ex"), do: "/tmp/ipse-v4-progress-diagnostic.ex", else: p end)
case Kernel.ParallelCompiler.compile(files, return_diagnostics: true) do
  {:ok, _, []} -> :ok
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
  other -> raise inspect(other)
end
case System.argv() do
  [] -> :ok
  names -> ExUnit.configure(exclude: [:test], include: Enum.map(names, &{String.to_atom(&1), true}))
end
Code.require_file("/tmp/ipse-v4-test-diagnostic.exs")
