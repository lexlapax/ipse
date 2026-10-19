Code.require_file("proof.exs", __DIR__)
[artifact] = System.argv()
IO.puts(:json.encode(IpseEmbeddingExample.Proof.run(Path.expand(artifact))))
