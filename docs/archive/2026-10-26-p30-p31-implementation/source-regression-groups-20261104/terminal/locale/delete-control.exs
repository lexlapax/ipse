[root, out] = System.argv()
File.mkdir!(root)
for name <- ["Case.txt", "case.txt", "café.txt", "cafe\u0301.txt", "memory.txt", "me\u200Bmory.txt"] do
  File.write!(Path.join(root, name), "synthetic")
end
result = case File.rm_rf(root) do
  {:ok, removed} -> %{"status" => "ok", "removed_count" => length(removed)}
  {:error, code, _path} -> %{"status" => "error", "code" => Atom.to_string(code)}
end
value = %{"native_encoding" => Atom.to_string(:file.native_name_encoding()), "delete" => result, "root_remains" => File.exists?(root), "application_started" => false, "session_started" => false}
File.write!(out, JSON.encode!(value), [:exclusive])
