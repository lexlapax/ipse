graph = "_build/combined-notes-assets-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
[root] = System.argv()
[journal] = Path.wildcard(root <> "/home/sessions/*.jsonl")
before = :crypto.hash(:sha256, File.read!(journal))
Code.require_file("docs/archive/2026-10-26-p30-p31-implementation/own-root-transition/sources/inspect.exs")
true = before === :crypto.hash(:sha256, File.read!(journal))
IO.puts("Original combined-cohort journal unchanged by inspection")
