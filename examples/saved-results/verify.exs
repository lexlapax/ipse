Code.require_file("proof.exs", __DIR__)
[artifact] = System.argv()
IO.puts(Jason.encode!(IpseSavedResultsExample.Proof.run(Path.expand(artifact))))
