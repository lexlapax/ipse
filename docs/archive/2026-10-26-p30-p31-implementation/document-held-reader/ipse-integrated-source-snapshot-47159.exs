root = File.cwd!()
target = Path.join(root, "_build/p30-p31-integrated-source-20261029")
false = File.exists?(target)
File.mkdir_p!(target)
hash = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
walk = fn walk, path ->
  case File.lstat!(path).type do
    :directory -> File.ls!(path) |> Enum.sort() |> Enum.flat_map(&walk.(walk, Path.join(path, &1)))
    :regular -> [path]
    :symlink -> []
  end
end
paths = ~w(lib extensions/bundled native mix.exs mix.lock .formatter.exs dev/build-native.sh)
before = Enum.flat_map(paths, &walk.(walk, &1)) |> Enum.sort() |> Map.new(&{&1, hash.(&1)})
for path <- paths do
  File.mkdir_p!(Path.dirname(Path.join(target, path)))
  File.cp_r!(path, Path.join(target, path))
end
File.cp_r!("priv", Path.join(target, "priv"))
File.ln_s!(Path.join(root, "deps"), Path.join(target, "deps"))
File.mkdir_p!(Path.join(target, "_build/dev"))
File.cp_r!("_build/dev/lib", Path.join(target, "_build/dev/lib"))
after_hashes = Map.new(Map.keys(before), &{&1, hash.(&1)})
true = before == after_hashes
Enum.each(before, fn {path, sha} -> true = hash.(Path.join(target, path)) == sha end)
manifest = Enum.map(Enum.sort(before), fn {path, sha} -> "#{sha}  #{path}\n" end)
File.write!(Path.join(target, "source.sha256"), manifest)
IO.puts("Frozen #{map_size(before)} source/toolchain inputs unchanged across copy at #{target}")
