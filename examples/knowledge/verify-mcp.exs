Code.require_file("mcp-proof.exs", __DIR__)
[artifact] = System.argv()
IO.puts(Jason.encode!(IpseKnowledgeExample.MCPProof.run(Path.expand(artifact))))
