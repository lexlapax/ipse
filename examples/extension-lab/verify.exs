Code.require_file("proof.exs", __DIR__)
[artifacts] = System.argv()
report = IpseLab.Proof.run(Path.expand(artifacts))
IO.puts(:json.encode(report))
