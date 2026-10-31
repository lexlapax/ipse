manifest = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption/manifest.json"
bytes = File.read!(manifest)
"2b503a998c9eaa03dd3b3a878fd2c2a9dbdcd33e40d35209e05ca896ad16c098" = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
walk = fn walk, value ->
  case value do
    %{"path" => path, "sha256" => sha, "bytes" => size} ->
      actual = File.read!(path)
      ^size = byte_size(actual)
      ^sha = Base.encode16(:crypto.hash(:sha256, actual), case: :lower)
      1
    %{"type" => "symlink", "path" => path, "target" => target} ->
      ^target = File.read_link!(path)
      1
    value when is_map(value) -> Enum.reduce(Map.values(value), 0, &(&2 + walk.(walk, &1)))
    value when is_list(value) -> Enum.reduce(value, 0, &(&2 + walk.(walk, &1)))
    _ -> 0
  end
end
IO.puts("Verified #{walk.(walk, Jason.decode!(bytes))} source/log/evidence/runtime/artifact/ancestor rows; no effects or test reruns.")
