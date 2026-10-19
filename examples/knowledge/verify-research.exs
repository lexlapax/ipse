Code.require_file("research-proof.exs", __DIR__)
[artifact] = System.argv()
IO.puts(JSON.encode!(IpseKnowledgeExample.ResearchProof.run(Path.expand(artifact))))
