# Signed planner component fixture: the read closure is synthetic, not Core publication.
unless Code.ensure_loaded?(Ipse.Test.ManagedPagesFixture) do
  Code.require_file("collection_managed_pages_test.exs", __DIR__)
end

defmodule Ipse.Extension.CollectionSupersessionSplitTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.ProjectIdentity, as: Identity
  alias Ipse.Extension.Collection.ManagedPages, as: Pages
  alias Ipse.Extension.Collection.ManagedPages.Planner
  alias Ipse.Test.ManagedPagesFixture, as: F
  @tag :supersession_splits

  test "two independently full leaves split in each signed tree within the existing read and receipt budgets" do
    base = Path.join(System.tmp_dir!(), "ipse-supersession-splits-" <> Usage.id())

    for path <- [base, base <> "/home", base <> "/work"] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    {:ok, binding} = Identity.admit(base <> "/home", base <> "/work", :folder)

    scope = %{
      namespace: F.hash("namespace"),
      format: "managed-metadata-v3",
      operation_id: Usage.id(),
      initialize: true
    }

    assert {:ok, old} =
             Identity.with_domain_publication(
               base <> "/home",
               base <> "/work",
               binding,
               scope,
               fn _ -> :ok end,
               fn cap, catalog ->
                 first = 1_798_761_600_000
                 big = Bitwise.bsl(1, 50)
                 small = Bitwise.bsl(1, 41)

                 anchors = [
                   {Pages.zero(:anchor), Map.new(1..96, &{F.id(&1), F.row()})},
                   {F.id(101), Map.new(101..196, &{F.id(&1), F.row()})}
                 ]

                 first_live =
                   Map.new(1..25, fn n ->
                     {id, row} = F.live(n, first)
                     deadline = if n == 1, do: nil, else: if(n == 2, do: small, else: big)

                     row =
                       row
                       |> List.replace_at(5, if(deadline, do: F.base36(deadline)))
                       |> List.replace_at(6, if(deadline, do: 0, else: 2))

                     {id, row}
                   end)

                 assert Pages.weight(:live, first_live) == Pages.profile(:live).capacity

                 second_live =
                   Map.new(101..125, fn n ->
                     {id, row} = F.live(n, first)
                     {id, List.replace_at(row, 5, F.base36(first + 1))}
                   end)

                 live = [
                   {Pages.zero(:live), first_live},
                   {Pages.live_identity("note." <> F.id(101)), second_live}
                 ]

                 records =
                   for {kind, pages} <- [anchor: anchors, live: live],
                       {fence, rows} <- pages,
                       into: %{} do
                     key = Pages.page_key(kind, fence)
                     {:ok, body} = Pages.pack(kind, fence, rows)
                     {:ok, value} = Pages.seal(cap, F.witness(0, scope.operation_id), key, body)
                     {key, F.record(key, value, 1, scope.operation_id)}
                   end

                 witness = %{
                   version: 1,
                   namespace: scope.namespace,
                   format: scope.format,
                   fence_id: catalog["fence_id"],
                   operation_id: scope.operation_id,
                   root_sha256: F.hash("trusted fixture root")
                 }

                 {:first_publication, witness, records}
               end
             )

    next = %{scope | operation_id: Usage.id(), initialize: false}

    assert {:ok, :checked} =
             Identity.with_domain_publication(
               base <> "/home",
               base <> "/work",
               binding,
               next,
               fn _ -> :ok end,
               fn cap, _ ->
                 Process.put(:managed_fixture_units, 0)
                 real = F.read(old, 1)
                 table = :ets.new(__MODULE__, [:set, :private])

                 try do
                   read = fn request ->
                     case :ets.lookup(table, request) do
                       [{^request, result}] ->
                         result

                       [] ->
                         result = real.(request)
                         :ets.insert(table, {request, result})
                         result
                     end
                   end

                   old_anchor = %{F.row() | "retirement" => F.full(F.id(200))}

                   assert {:ok, anchor} =
                            Planner.plan(
                              cap,
                              :anchor,
                              [{F.id(1), old_anchor}, {F.id(200), F.row()}],
                              read
                            )

                   {old_id, old_row} = F.live(1)

                   old_row =
                     old_row
                     |> List.replace_at(5, F.base36(Bitwise.bsl(1, 50)))
                     |> List.replace_at(6, 4)
                     |> List.replace_at(7, 2)

                   {new_id, new_row} = F.live(200)

                   assert {:ok, live} =
                            Planner.plan(cap, :live, [{old_id, old_row}, {new_id, new_row}], read)

                   assert length(anchor.changes) == 4 and length(live.changes) == 4
                   assert Process.get(:managed_fixture_units) <= 32

                   {:ok, anchors} =
                     Planner.seal_changes(cap, F.witness(1, next.operation_id), anchor)

                   {:ok, lives} = Planner.seal_changes(cap, F.witness(1, next.operation_id), live)
                   extras = anchors ++ lives
                   assert length(extras) == 8 and Enum.all?(extras, &is_map(&1["value"]))
                   digest = JSON.sha256("fixture")
                   max = Pages.safe()

                   receipt = %{
                     "version" => 3,
                     "kind" => "native_literal_supersession",
                     "action_sha256" => digest,
                     "native_review_sha256" => digest,
                     "old_lineage" => digest,
                     "new_lineage" => digest,
                     "history_valid_until_ms" => max,
                     "first_admitted_ms" => max,
                     "valid_until_ms" => max,
                     "publish_before_ms" => max,
                     "metadata_refs" => Enum.map(extras, fn e -> [e["key"], max, digest] end)
                   }

                   assert byte_size(Jason.encode!(receipt)) <= 2048
                   {:ok, :checked}
                 after
                   :ets.delete(table)
                 end
               end
             )
  end
end
