Code.require_file("complete-result-proof.exs", __DIR__)
[artifacts] = System.argv()
IO.puts(Jason.encode!(IpseKnowledgeExample.CompleteResultProof.run(Path.expand(artifacts))))
