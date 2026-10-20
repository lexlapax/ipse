Code.require_file("lifecycle-proof.exs", __DIR__)
[artifact, kind] = System.argv()

report =
  if kind == "selection",
    do: IpseKnowledgeExample.LifecycleProof.selection(Path.expand(artifact)),
    else: IpseKnowledgeExample.LifecycleProof.run(Path.expand(artifact), kind)

IO.puts(JSON.encode!(report))
