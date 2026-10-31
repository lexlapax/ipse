# Create a fresh synthetic two-literal upgrade fixture with a retained runtime.
# The caller selects the historical graph explicitly; this is not a gate override.
{root_arg, graph_arg, mode} =
  case System.argv() do
    [root, graph] -> {root, graph, "pair"}
    [root, graph, mode] when mode in ["wide", "split"] -> {root, graph, mode}
  end

root = Path.expand(root_arg)
graph = Path.expand(graph_arg)
false = File.exists?(root)
true = File.dir?(graph)
File.mkdir!(root)
File.chmod!(root, 0o700)
driver = Path.join(root, "pty")

{output, status} =
  System.cmd(
    "rustc",
    ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
    stderr_to_stdout: true
  )

if status != 0, do: raise(output)

paths = Path.wildcard(Path.join(graph, "*/ebin")) |> Enum.flat_map(&["-pa", &1])

{output, status} =
  System.cmd(
    driver,
    ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
      paths ++ [Path.expand("test/support/managed_literal_ab_seed.exs"), root, mode],
    stderr_to_stdout: true
  )

IO.write(output)
System.halt(status)
