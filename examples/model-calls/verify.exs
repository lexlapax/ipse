Code.require_file("proof.exs", __DIR__)
[artifact | selection] = System.argv()

{thinking, output} =
  case selection do
    [] -> {nil, :text}
    ["none"] -> {"none", :text}
    ["json"] -> {nil, :json_schema}
    ["json", "none"] -> {"none", :json_schema}
  end

IO.puts(:json.encode(IpseModelExample.Proof.run(Path.expand(artifact), thinking, output)))
