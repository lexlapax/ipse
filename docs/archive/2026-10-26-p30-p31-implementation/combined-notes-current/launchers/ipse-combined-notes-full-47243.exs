graph = "_build/combined-notes-assets-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.require_file("test/support/headless_typed_root_transition.exs")
