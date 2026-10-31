root = "docs/archive/2026-10-26-p30-p31-implementation/management-review-input"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn p -> p |> File.read!() |> String.split("\n",trim: true) |> Enum.map(fn r -> [h,f] = String.split(r,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "6c4fdd20275c02399413d340c89bddaa8ee5e54a6c146ed5289f26688d21cee7"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
{:ok,source_rows} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
sources = Map.new(source_rows,fn {p,b} -> {List.to_string(p),b} end)
graph = "_build/management-review-input-sol-20261029/lib"
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows,fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
walk = fn f,p -> case File.lstat!(p).type do :regular -> [Path.expand(p)]; :directory -> Enum.flat_map(File.ls!(p),fn n -> f.(f,Path.join(p,n)) end); :symlink -> [] end end
true = Enum.sort(Enum.map(rows,fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(walk.(walk,graph))
beams = Path.wildcard(root <> "/beams/*.beam")
Enum.each(beams,fn p -> true = File.read!(p) == File.read!(Path.join(graph,"ipse/ebin/" <> Path.basename(p))) end)
true = File.read!(root <> "/ipse-runner") == File.read!(graph <> "/ipse/priv/ipse-runner")
true = sha.(File.read!(root <> "/ipse-runner")) == "0fa53f914f711f1f8de3682335e510e15a28acd2db07870d1a869209d6276416"
true = :binary.match(File.read!(root <> "/ipse-runner"),"IPSE_TEST_") == :nomatch
prior = parse.("docs/archive/2026-10-26-p30-p31-implementation/management-display-deadline-repair/runtime.sha256") |> Map.new()
true = Enum.sort(Map.keys(prior)) == Enum.sort(Enum.map(rows,&elem(&1,0)))
delta = for {p,h} <- rows, prior[p] != h, do: p
true = Enum.sort(delta) == ["./ipse/ebin/Elixir.Ipse.CLI.Knowledge.Management.beam", "./ipse/ebin/Elixir.Ipse.Runner.ManagementTerminal.beam", "./ipse/ebin/Elixir.Ipse.Runner.Review.beam", "./ipse/ebin/Elixir.Ipse.Runner.beam", "./ipse/ebin/Elixir.Ipse.Session.Resources.beam", "./ipse/priv/ipse-runner"]
terminal = sources["lib/ipse/runner/management_terminal.ex"]
true = File.read!(root <> "/instrumentation/management-expired-instrumented.ex") == String.replace(terminal,"permit_deadline = System.monotonic_time(:millisecond) + 30_000", "permit_deadline = System.monotonic_time(:millisecond) - 1")
management = sources["lib/ipse/cli/knowledge/management.ex"]
first = "Review.with_management_input(\"forget\", prepared[\"facts\"], handle, fn permit ->"
last = "            end)\n          end\n        end)\n\n      management_display_completion(result, overall, wall)"
instrumented = management |> String.replace(first,"Ipse.Test.ManagementDisplayProbe.foreign_handle(handle, prepared[\"facts\"])\n            review_result = " <> first) |> String.replace(last,"            end)\n            Ipse.Test.ManagementDisplayProbe.replay_handle(handle, prepared[\"facts\"])\n            review_result\n          end\n        end)\n\n      management_display_completion(result, overall, wall)")
true = File.read!(root <> "/instrumentation/management-handles-instrumented.ex") == instrumented
IO.inspect(%{manifest_entries: length(entries), frozen_sources: map_size(sources), physical_runtime_files: length(rows), retained_beams: length(beams), runtime_delta: Enum.sort(delta), final_instrumentation_exact: true, production_test_markers_absent: true},label: "MANAGEMENT_REVIEW_INPUT_OK")
