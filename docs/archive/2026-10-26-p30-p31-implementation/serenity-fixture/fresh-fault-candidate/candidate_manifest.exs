# Review-only inventory for the generated private candidate. It never executes
# a candidate binary and refuses symlinks except the two known runtime links.
root = System.argv() |> List.first()
if not is_binary(root) or not String.starts_with?(root, "/tmp/ipse-live-candidate."), do: raise("invalid candidate")
allowed = %{"runtime/lib/ipse/priv" => "../../priv", "runtime/lib/telemetry/src" => "../../../project/deps/telemetry/src"}
walk = fn walk, relative ->
  path = Path.join(root, relative)
  File.ls!(path)
  |> Enum.sort()
  |> Enum.flat_map(fn name ->
    rel = if relative == "", do: name, else: Path.join(relative, name)
    file = Path.join(root, rel)
    case File.lstat!(file) do
      %{type: :directory} -> walk.(walk, rel)
      %{type: :regular, links: 1, size: size} when size <= 33_554_432 ->
        [Base.encode16(:crypto.hash(:sha256, File.read!(file)), case: :lower) <> "  " <> rel]
      %{type: :symlink} ->
        target = File.read_link!(file)
        if allowed[rel] != target, do: raise("unexpected symlink #{rel}")
        []
      _ -> raise("unexpected candidate entry #{rel}")
    end
  end)
end
lines = walk.(walk, "")
if length(lines) > 5000, do: raise("candidate entry limit")
File.write!(Path.join(root, "SHA256SUMS"), Enum.join(lines, "\n") <> "\n", [:exclusive])
IO.puts("FILES=#{length(lines)}")
