files = ~w(profiles evidence store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress adapters documents documents/zip documents/docx documents/parser_stage documents/pdf corpus)
files = Enum.map(files, &("extensions/knowledge/src/" <> &1 <> ".ex"))
case Kernel.ParallelCompiler.compile(files, return_diagnostics: true) do
  {:ok, _, []} -> :ok
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
  other -> raise inspect(other)
end
case System.argv() do
  [] -> :ok
  names -> ExUnit.configure(exclude: [:test], include: Enum.map(names, &{String.to_atom(&1), true}))
end
baseline = File.read!("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-v4-pinned-read/source/extensions/knowledge/src/evidence.ex")
baseline = String.replace(baseline, "defmodule IpseKnowledge.Evidence do", "defmodule IpseKnowledge.EvidenceBaseline do", global: false)
Code.compile_string(baseline)
Code.require_file("/tmp/ipse-v4-span-compare-test.exs")

