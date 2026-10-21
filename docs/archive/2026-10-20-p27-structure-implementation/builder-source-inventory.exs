{tracked, 0} = System.cmd("git", ["ls-files", "-z"])
{extra, 0} = System.cmd("git", ["ls-files", "--others", "--exclude-standard", "-z"])
files = String.split(tracked <> extra, <<0>>, trim: true) |> Enum.uniq() |> Enum.filter(fn path ->
  File.regular?(path) and Path.extname(path) in ~w(.ex .exs .rs .sh .toml .json .lock) and
    not String.starts_with?(path, "docs/")
end) |> Enum.sort()
rows = Enum.map(files, fn path ->
 %{"path" => path, "sha256" => Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)}
end)
bytes = JSON.encode!(%{"version" => 1, "files" => rows}) <> "\n"
target = hd(System.argv())
File.write!(target, bytes, [:exclusive])
IO.puts(JSON.encode!(%{"files" => length(rows), "sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}))
