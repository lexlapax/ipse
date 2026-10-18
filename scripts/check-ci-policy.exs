paths =
  case System.argv() do
    [] -> Path.wildcard(".github/workflows/*.{yml,yaml}")
    paths -> paths
  end

errors =
  for path <- paths,
      {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
      [_, action] <- [Regex.run(~r/^\s*(?:-\s*)?uses:\s+(\S+)/, line)],
      not String.starts_with?(action, "./"),
      not Regex.match?(~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@[0-9a-f]{40}\z/, action),
      do: "#{path}:#{number}: external actions require a full commit SHA"

if errors == [] do
  IO.puts("CI action references are pinned")
else
  Enum.each(errors, &IO.puts(:stderr, &1))
  System.halt(1)
end
