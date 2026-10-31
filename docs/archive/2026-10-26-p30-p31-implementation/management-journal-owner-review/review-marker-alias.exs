graph = "_build/management-journal-owner-v2-sol-20261029"
for path <- Path.wildcard(graph <> "/lib/*/ebin"), do: Code.prepend_path(path)
alias Ipse.Journal
root = Path.join(System.tmp_dir!(), "ipse-management-marker-alias-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower))
File.mkdir!(root)
File.chmod!(root, 0o700)
try do
  for key <- [:native_journal_layout, :release_receipt_layout] do
    metadata = %{key => "native-journal-v1"}
    false = Journal.native_owner_required?(metadata)
    {:ok, id} = Journal.create(root, metadata)
    {:ok, [%{"metadata" => persisted}]} = Journal.load(root, id)
    true = Journal.native_owner_required?(persisted)
    true = persisted[Atom.to_string(key)] == "native-journal-v1"
    false = File.exists?(Path.join(root, id <> ".lock"))
    IO.inspect(%{key: key, create: :ok, persisted_native_owner_required: true, lock_file: false}, label: "UNFENCED_MARKER_ALIAS_REPRODUCED")
  end
  {:error, :journal_lock_owner_required} = Journal.create(root, %{"native_journal_layout" => "native-journal-v1"})
  IO.puts("STRING_KEY_NEGATIVE_REFUSED; no native helper, model, or network invoked")
after
  File.rm_rf!(root)
end
