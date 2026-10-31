{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.Extension.Collection, as: C
alias Ipse.JSON
root = Path.join(System.tmp_dir!(), "ipse-held-post-publication-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
collection = Path.join(root, "collections")
project = JSON.sha256("synthetic post-publication budget classification")
id = Ipse.Usage.id()
handler = {:collection_held_read_review, make_ref()}
parent = self()
original = %{"op" => "commit", "expected_generation" => 0, "advance_floor" => true,
  "changes" => [%{"key" => "note.a", "expected_revision" => 0, "value" => %{"text" => "synthetic selected"}}]}
normalized = Map.update!(original, "changes", &(&1 ++ [%{"key" => "host.validity.a", "expected_revision" => 0, "value" => %{"anchor" => 0}}]))
try do
  result = C.execute_managed(collection, project, original, id, JSON.sha256("synthetic recipe"), fn _, read ->
    for _ <- 1..32 do
      {:ok, nil} = read.("missing")
    end
    :ok = :telemetry.attach(handler, [:ipse, :extension, :collection, :staged],
      fn _, _, metadata, {get, caller} ->
        observed = get.("missing")
        send(caller, {:staged_read, metadata, observed})
      end, {read, parent})
    {:ok, normalized, %{}}
  end)
  receive do
    {:staged_read, metadata, observed} -> IO.inspect(%{stage: metadata, read: observed}, label: "AFTER_NORMALIZER_READ")
  after
    5000 -> raise "staged telemetry not observed"
  end
  root_bytes = File.read!(Path.join([collection, project, "root.json"]))
  {:ok, selected} = C.execute(collection, project, %{"op" => "get", "key" => "note.a"}, Ipse.Usage.id())
  {:ok, operation} = C.execute(collection, project, %{"op" => "inspect", "operation_id" => id}, Ipse.Usage.id())
  {:error, :managed_normalization_refused} = result
  true = selected["record"]["value"] == %{"text" => "synthetic selected"}
  true = selected["record"]["revision"] == 1
  true = operation["operation"]["generation"] == 1
  IO.inspect(%{returned: result, physical_root: Jason.decode!(root_bytes), physical_root_sha256: JSON.sha256(root_bytes), selected_record: selected["record"], stored_operation: operation["operation"]}, label: "KNOWN_REFUSAL_AFTER_ACTUAL_PUBLICATION")
after
  :telemetry.detach(handler)
  File.rm_rf!(root)
end
