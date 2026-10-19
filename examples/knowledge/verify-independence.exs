Code.require_file("proof.exs", __DIR__)
[artifacts] = System.argv()
IO.puts(JSON.encode!(IpseKnowledgeExample.Proof.independence(Path.expand(artifacts))))
