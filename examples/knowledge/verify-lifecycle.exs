Code.require_file("lifecycle-proof.exs", __DIR__)
[artifact, kind] = System.argv()
IO.puts(JSON.encode!(IpseKnowledgeExample.LifecycleProof.run(Path.expand(artifact), kind)))
