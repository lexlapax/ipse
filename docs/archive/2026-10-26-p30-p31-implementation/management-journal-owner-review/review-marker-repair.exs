graph = "_build/management-journal-owner-v3-sol-20261029"
for path <- Path.wildcard(graph <> "/lib/*/ebin"), do: Code.prepend_path(path)
root = Path.join(System.tmp_dir!(), "ipse-management-marker-repair-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower))
false = File.exists?(root)
try do
  for key <- [:native_journal_layout, :release_receipt_layout, ~c"native_journal_layout", ~c"release_receipt_layout", "native_journal_layout"] do
    {:error, :journal_lock_owner_required} = Ipse.Journal.create(root, %{key => "native-journal-v1"})
    false = File.exists?(root)
    IO.inspect(%{key: to_string(key), input_type: (if is_atom(key), do: :atom, else: (if is_list(key), do: :charlist, else: :string)), create: :refused, directory_exists: false}, label: "ORIGINAL_ALIAS_NOW_REFUSED")
  end
  IO.puts("Original counterexamples repaired before directory creation; no native helper, model, or network invoked")
after
  File.rm_rf!(root)
end
