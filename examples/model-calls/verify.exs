Code.require_file("proof.exs", __DIR__)
[artifact] = System.argv()
IO.puts(:json.encode(IpseModelExample.Proof.run(Path.expand(artifact))))
