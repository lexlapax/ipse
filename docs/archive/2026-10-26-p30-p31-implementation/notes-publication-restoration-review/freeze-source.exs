root = "docs/archive/2026-10-26-p30-p31-implementation/notes-publication-restoration-review"
paths = ~w(
  lib/ipse/extension/collection.ex
  lib/ipse/extension/collection/profile.ex
  lib/ipse/extension/collection/normalizer.ex
  lib/ipse/extension/collection/normalizer_v3.ex
  lib/ipse/extension/collection/managed_retention.ex
  lib/ipse/extension/managed_collection_call.ex
  lib/ipse/extension/collection_call.ex
  lib/ipse/extension/managed_recipe.ex
  lib/ipse/extension/collection_policy.ex
  lib/ipse/extension/consent.ex
  lib/ipse/extension/project_identity.ex
  lib/ipse/extension/semantic_admission.ex
  lib/ipse/extension/semantic_consent.ex
  lib/ipse/runner/transaction.ex
  native/ipse-transaction.rs
  lib/ipse/session/invocation.ex
  lib/ipse/session/managed_tool_use.ex
  lib/ipse/session/operator_assertion.ex
  lib/ipse/session/input.ex
  lib/ipse/session/resources.ex
  lib/ipse/session/managed_use.ex
  lib/ipse/session/stored_sources.ex
  lib/ipse/session.ex
  lib/ipse/cli/terminal.ex
  lib/ipse/cli/knowledge.ex
  extensions/knowledge/src/knowledge.ex
  extensions/knowledge/src/knowledge/contracts.ex
  extensions/knowledge/src/knowledge/records.ex
)
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
before = Map.new(paths, &{&1, File.read!(&1)})
true = before == Map.new(paths, &{&1, File.read!(&1)})
false = File.exists?(root <> "/source.tar")
:ok = :erl_tar.create(String.to_charlist(root <> "/source.tar"), Enum.map(Enum.sort(before), fn {p, b} -> {String.to_charlist(p), b} end), [])
File.write!(root <> "/source.sha256", Enum.map(Enum.sort(before), fn {p, b} -> "#{sha.(b)}  #{p}\n" end), [:exclusive])
{:ok, members} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
true = before == Map.new(members, fn {p, b} -> {List.to_string(p), b} end)
File.write!(root <> "/manifest.sha256", Enum.map(~w(source.tar source.sha256 freeze-source.exs), fn p -> "#{sha.(File.read!(root <> "/" <> p))}  #{p}\n" end), [:exclusive])
IO.inspect(%{source_files: map_size(before), source_only: true, manifest_sha256: sha.(File.read!(root <> "/manifest.sha256")), runtime_or_test_execution: false}, label: "NOTES_RESTORATION_SOURCE_SNAPSHOT")
