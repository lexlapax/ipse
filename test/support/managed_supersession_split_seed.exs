# Synthetic rows seeded through actual Core; filler rows have no source authority.
Code.require_file("../ipse/extension/collection_managed_pages_test.exs", __DIR__)

defmodule Ipse.Test.ManagedSupersessionSplitSeed do
  import ExUnit.Assertions
  alias Ipse.JSON
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.Collection.{ManagedPages, Migration}
  alias Ipse.Test.ManagedPagesFixture, as: F

  def publish(c, old, new, scope) do
    old_change = hd(old.request["changes"])
    new_change = hd(new.request["changes"])
    "note." <> old_lineage = old_change["key"]
    "note." <> new_lineage = new_change["key"]
    old_n = String.to_integer(old_lineage, 16)
    new_n = String.to_integer(new_lineage, 16)
    {low, high} = Enum.min_max([old_n, new_n])
    boundary = div(low + high, 2)
    assert boundary > low + 1000 and high > boundary + 1000
    fence = F.id(boundary)
    low_fill = for i <- 1..96, do: div(low, 2) + i
    high_fill = for i <- 1..96, do: boundary + i
    left_old = old_n < boundary
    groups = [{ManagedPages.zero(:anchor), low_fill, left_old}, {fence, high_fill, not left_old}]
    first = old.now_ms
    pack_hash = fn h -> Base.url_encode64(Base.decode16!(h, case: :lower), padding: false) end

    old_live =
      Enum.map(
        [
          old_lineage,
          JSON.sha256(Migration.encode(old_change["value"])),
          JSON.digest([old.recipe]),
          old.policy_sha256
        ],
        pack_hash
      ) ++
        [F.base36(first), nil, 2, 0]

    anchor = %{"clocks" => [first, nil, nil, nil], "choice" => nil, "retirement" => nil}

    assert {:ok, core} =
             ProjectIdentity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               scope,
               fn _ -> :ok end,
               fn cap, catalog ->
                 result =
                   Collection.execute_managed(
                     c.root,
                     c.namespace,
                     old.request,
                     scope.operation_id,
                     JSON.digest([old.recipe]),
                     fn witness, _read ->
                       anchor_pages =
                         for {f, nums, contains_old} <- groups do
                           rows =
                             Map.new(
                               Enum.take(nums, if(contains_old, do: 95, else: 96)),
                               &{F.id(&1), F.row()}
                             )

                           rows =
                             if contains_old, do: Map.put(rows, old_lineage, anchor), else: rows

                           {f, rows}
                         end

                       live_pages =
                         for {f, nums, contains_old} <- groups do
                           count = if contains_old, do: 24, else: 25

                           rows =
                             nums
                             |> Enum.take(count)
                             |> Enum.with_index()
                             |> Map.new(fn {n, i} ->
                               {id, row} = F.live(n, first)

                               deadline =
                                 if contains_old,
                                   do:
                                     if(i == 0, do: Bitwise.bsl(1, 41), else: Bitwise.bsl(1, 50)),
                                   else: first + 1

                               {id, List.replace_at(row, 5, F.base36(deadline))}
                             end)

                           rows =
                             if contains_old,
                               do:
                                 Map.put(
                                   rows,
                                   ManagedPages.live_identity(old_change["key"]),
                                   old_live
                                 ),
                               else: rows

                           if contains_old,
                             do:
                               assert(
                                 ManagedPages.weight(:live, rows) ==
                                   ManagedPages.profile(:live).capacity
                               )

                           {if(f == ManagedPages.zero(:anchor),
                              do: ManagedPages.zero(:live),
                              else: "00" <> f
                            ), rows}
                         end

                       extras =
                         for {kind, pages} <- [anchor: anchor_pages, live: live_pages],
                             {page_fence, rows} <- pages do
                           key = ManagedPages.page_key(kind, page_fence)
                           {:ok, body} = ManagedPages.pack(kind, page_fence, rows)
                           {:ok, value} = ManagedPages.seal(cap, witness, key, body)
                           %{"key" => key, "expected_revision" => 0, "value" => value}
                         end

                       {:ok, format} =
                         ManagedPages.seal(
                           cap,
                           witness,
                           ManagedPages.format_key(),
                           ManagedPages.format_body()
                         )

                       extras =
                         extras ++
                           [
                             %{
                               "key" => ManagedPages.format_key(),
                               "expected_revision" => 0,
                               "value" => format
                             }
                           ]

                       {:ok, Map.update!(old.request, "changes", &(&1 ++ extras)),
                        %{"version" => 2}}
                     end
                   )

                 assert {:ok, core} = result
                 {:ok, view} = Collection.open_view(c.root, c.namespace)

                 {:ok, read} =
                   Collection.view_read(view, %{"op" => "get_many", "keys" => [old_change["key"]]})

                 assert :ok = Collection.close_view(view)

                 first_publication = %{
                   version: 1,
                   namespace: c.namespace,
                   format: "managed-metadata-v3",
                   fence_id: catalog["fence_id"],
                   operation_id: scope.operation_id,
                   root_sha256: read["witness"]["root_sha256"]
                 }

                 {:first_publication, first_publication, core}
               end
             )

    core
  end
end
