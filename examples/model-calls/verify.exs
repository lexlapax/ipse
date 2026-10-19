Code.require_file("proof.exs", __DIR__)
[artifact | selection] = System.argv()

thinking =
  case selection do
    [] -> nil
    ["none"] -> "none"
  end

IO.puts(:json.encode(IpseModelExample.Proof.run(Path.expand(artifact), thinking)))
