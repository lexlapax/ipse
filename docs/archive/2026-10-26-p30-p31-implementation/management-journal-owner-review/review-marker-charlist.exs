graph = "_build/management-journal-owner-v2-sol-20261029"
for path <- Path.wildcard(graph <> "/lib/*/ebin"), do: Code.prepend_path(path)
root = Path.join(System.tmp_dir!(), "ipse-management-marker-charlist-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower))
File.mkdir!(root)
File.chmod!(root, 0o700)
try do
  for key <- [~c"native_journal_layout", ~c"release_receipt_layout"] do
    metadata = %{key => "native-journal-v1"}
    false = Ipse.Journal.native_owner_required?(metadata)
    {:ok, id} = Ipse.Journal.create(root, metadata)
    {:ok, [%{"metadata" => persisted}]} = Ipse.Journal.load(root, id)
    true = Ipse.Journal.native_owner_required?(persisted)
    false = File.exists?(Path.join(root, id <> ".lock"))
    IO.inspect(%{key: List.to_string(key), create: :ok, persisted_native_owner_required: true, lock_file: false}, label: "UNFENCED_CHARLIST_MARKER_REPRODUCED")
  end
  IO.puts("No native helper, model, or network invoked")
after
  File.rm_rf!(root)
end
