# Read-only package dependency inventory; not an authorization or proof of
# runtime dlopen closure. Resolves virtual providers conservatively to all
# installed candidates, without validating version constraints.
{out, 0} = System.cmd("/usr/bin/pacman", ["-Qi"], env: [{"LC_ALL", "C"}], stderr_to_stdout: true)
blocks = String.split(out, ~r/\n\s*\n/, trim: true)

parse = fn block ->
  Enum.reduce(String.split(block, "\n"), {%{}, nil}, fn line, {map, key} ->
    case Regex.run(~r/^([A-Za-z][A-Za-z ]+?)\s*:\s*(.*)$/, line) do
      [_, k, v] ->
        {Map.put(map, k, v), k}

      _ ->
        if key && Regex.match?(~r/^\s+\S/, line),
          do: {Map.update!(map, key, &(&1 <> " " <> String.trim(line))), key},
          else: {map, nil}
    end
  end)
  |> elem(0)
end

entries = Enum.map(blocks, parse) |> Enum.filter(&Map.has_key?(&1, "Name"))
by_name = Map.new(entries, &{&1["Name"], &1})
normalize = fn value -> value |> String.split(~r/[<>=]/, parts: 2) |> hd() end

values = fn item, key ->
  case item[key] do
    nil -> []
    "None" -> []
    value -> String.split(value, ~r/\s+/, trim: true)
  end
end

providers =
  Enum.reduce(entries, %{}, fn entry, acc ->
    Enum.reduce(values.(entry, "Provides"), acc, fn value, m ->
      Map.update(m, normalize.(value), [entry["Name"]], &[entry["Name"] | &1])
    end)
  end)

roots = if System.argv() == [], do: ~w(btrfs-progs util-linux device-mapper docker), else: System.argv()

walk = fn walk, queue, seen, missing, ambiguous ->
  case queue do
    [] ->
      {seen, missing, ambiguous}

    [name | rest] ->
      cond do
        MapSet.member?(seen, name) ->
          walk.(walk, rest, seen, missing, ambiguous)

        item = by_name[name] ->
          {next, miss, amb} =
            Enum.reduce(values.(item, "Depends On"), {[], missing, ambiguous}, fn dependency,
                                                                                  {ns, ms, as_} ->
              bare = normalize.(dependency)

              options =
                cond do
                  Map.has_key?(by_name, bare) -> [bare]
                  true -> Map.get(providers, bare, []) |> Enum.uniq() |> Enum.sort()
                end

              case options do
                [] -> {ns, MapSet.put(ms, dependency), as_}
                [_] -> {options ++ ns, ms, as_}
                _ -> {options ++ ns, ms, Map.put(as_, dependency, options)}
              end
            end)

          walk.(walk, next ++ rest, MapSet.put(seen, name), miss, amb)

        true ->
          walk.(walk, rest, seen, MapSet.put(missing, name), ambiguous)
      end
  end
end

{closure, missing, ambiguous} = walk.(walk, roots, MapSet.new(), MapSet.new(), %{})

requirements =
  closure
  |> MapSet.to_list()
  |> Enum.flat_map(&values.(by_name[&1], "Depends On"))
  |> Enum.uniq()
  |> Enum.sort()

{unmet, status} =
  System.cmd("/usr/bin/pacman", ["-T" | requirements],
    env: [{"LC_ALL", "C"}],
    stderr_to_stdout: true
  )

for name <- Enum.sort(MapSet.to_list(closure)) do
  item = by_name[name]
  IO.puts("#{name}\t#{item["Version"]}\t#{item["Licenses"]}")
end

IO.puts(
  :stderr,
  "count=#{MapSet.size(closure)} unresolved=#{inspect(Enum.sort(MapSet.to_list(missing)))}"
)

IO.puts(:stderr, "pacman_deptest_status=#{status} unmet=#{inspect(String.trim(unmet))}")

for {dep, candidates} <- Enum.sort(ambiguous),
    do: IO.puts(:stderr, "ambiguous=#{dep} providers=#{Enum.join(candidates, ",")}")
