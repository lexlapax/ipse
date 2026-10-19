Code.require_file("recovery-proof.exs", __DIR__)
[artifact] = System.argv()
IO.puts(JSON.encode!(IpseKnowledgeExample.RecoveryProof.run(Path.expand(artifact))))
