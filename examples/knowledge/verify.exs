Code.require_file("proof.exs", __DIR__)
[artifacts] = System.argv()
IO.puts(Jason.encode!(IpseKnowledgeExample.Proof.run(Path.expand(artifacts))))
