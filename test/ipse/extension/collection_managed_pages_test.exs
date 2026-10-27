defmodule Ipse.Test.ManagedPagesFixture do
  alias Ipse.Extension.Collection.Directory
  alias Ipse.Extension.Collection.ManagedPages, as: Pages
  alias Ipse.JSON

  def hash(value), do: JSON.sha256(to_string(value))
  def id(n), do: Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(64, "0")

  def row,
    do: %{
      "clocks" => [1_798_761_600_000, 1_806_537_600_000, nil, nil],
      "choice" => nil,
      "retirement" => nil
    }

  def capsule(lineage, policy \\ %{"kind" => "session"}) do
    verb =
      %{"pin" => "pin", "ordinary" => "ordinary", "session" => "forget", "duration" => "duration"}[
        policy["kind"]
      ]

    %{
      "version" => 2,
      "kind" => "native_management",
      "lineage" => lineage,
      "event_id" => String.duplicate("a", 32),
      "display_sha256" => hash("display"),
      "challenge" => "0123456789abcdef",
      "target_key" => "note." <> lineage,
      "target_value_sha256" => hash("value"),
      "observed_at_ms" => Pages.safe(),
      "policy" => policy,
      "reason" => String.duplicate("r", 64),
      "input_sha256" => hash(verb <> " 0123456789abcdef")
    }
  end

  def full(lineage),
    do: %{
      "record_key" => "note." <> lineage,
      "record_value_sha256" => hash("old"),
      "at_ms" => Pages.safe()
    }

  def live(n, first \\ 1_798_761_600_000) do
    key = "note." <> id(n)
    h = fn v -> Base.url_encode64(Base.decode16!(hash(v), case: :lower), padding: false) end

    {Pages.live_identity(key),
     [
       h.(n),
       h.("value#{n}"),
       h.("recipe"),
       h.("policy"),
       base36(first),
       base36(first + 7_776_000_000),
       0,
       0
     ]}
  end

  def base36(n), do: Integer.to_string(n, 36) |> String.downcase()

  def summary(generation),
    do: %{
      "version" => 3,
      "project" => hash("namespace"),
      "generation" => generation,
      "floor" => 0,
      "floor_anchor" => nil
    }

  def witness(generation, operation) do
    s = summary(generation)

    if generation == 0 do
      %{
        "version" => 2,
        "root" => s,
        "root_state" => "absent",
        "root_bytes" => nil,
        "root_sha256" => nil,
        "manifest_sha256" => nil,
        "operation_id" => operation
      }
    else
      pointer = s |> Map.put("version", 5) |> Map.put("manifest", hash("manifest#{generation}"))
      bytes = Pages.bytes(pointer)

      %{
        "version" => 2,
        "root" => s,
        "root_state" => "present",
        "root_bytes" => bytes,
        "root_sha256" => JSON.sha256(bytes),
        "manifest_sha256" => pointer["manifest"],
        "operation_id" => operation
      }
    end
  end

  def record(key, value, generation, operation) do
    bytes = Pages.bytes(value)

    %{
      "key" => key,
      "value" => value,
      "revision" => generation,
      "operation_id" => operation,
      "sha256" => JSON.sha256(bytes),
      "bytes" => byte_size(bytes)
    }
  end

  def read(records, generation) do
    {:ok, tree} = Directory.index(Enum.sort(Map.keys(records)))
    w = witness(generation, String.duplicate("b", 32))

    fn request ->
      {:ok, cost} = Directory.cost(request)
      count = Process.get(:managed_fixture_units, 0)
      Process.put(:managed_fixture_units, count + cost)
      if count + cost > 32, do: raise("fixture budget exceeded")

      if is_binary(request) do
        {:ok, records[request]}
      else
        {:ok, _, nil, neighbors} = Directory.select(tree, request, w["root_state"])
        pointer = if w["root_bytes"], do: Jason.decode!(w["root_bytes"])

        {:ok,
         %{
           "version" => 1,
           "summary" => w["root"],
           "directory" => request["request"],
           "state" => neighbors["state"],
           "neighbors" =>
             Map.new(Map.delete(neighbors, "state"), fn {slot, key} ->
               {slot, records[key] && Map.delete(records[key], "value")}
             end),
           "witness" => %{
             "version" => 2,
             "root_state" => w["root_state"],
             "root" => pointer,
             "root_sha256" => w["root_sha256"],
             "manifest_sha256" => w["manifest_sha256"]
           }
         }}
      end
    end
  end
end

defmodule Ipse.Extension.CollectionManagedPagesTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.ManagedPages, as: Pages
  alias Ipse.Test.ManagedPagesFixture, as: F

  test "immutable descriptor charges actual format envelope and both global geometries" do
    d = Pages.descriptor()
    assert d["version"] === 3 and d["codec"] == "IMB2"
    assert d["retirement"] == ["native-literal-note-v1", "exact-target-v1"]
    assert d["management"] == "native-management-v1"
    assert Pages.encoded_size(<<>>) == 75
    assert Pages.encoded_size(Pages.format_body()) <= 6144

    for kind <- [:anchor, :live] do
      p = Pages.profile(kind)
      assert p.capacity >= 5 * p.maximum
      assert p.floor == div(p.capacity + 1 - p.maximum, 2)
      assert p.floor >= 2 * p.maximum
      assert p.row_cap * p.minimum > p.capacity
    end

    assert Pages.profile(:anchor).maximum == 337
    assert Pages.profile(:live).maximum == 183
  end

  test "production capsule and both retirement syntaxes preserve exact closed bytes but grant no authority" do
    id = F.id(5)

    for policy <- [
          %{"kind" => "pin"},
          %{"kind" => "ordinary"},
          %{"kind" => "session"},
          %{"kind" => "duration", "duration_ms" => Pages.safe()}
        ],
        retirement <- [nil, %{"target_kind" => "native_literal_note", "at_ms" => 23}, F.full(id)] do
      row = %{F.row() | "choice" => F.capsule(id, policy), "retirement" => retirement}
      assert {:ok, raw} = Pages.pack(:anchor, Pages.zero(:anchor), %{id => row})
      assert {:ok, %{entries: %{^id => ^row}}} = Pages.unpack(:anchor, Pages.zero(:anchor), raw)
      assert {:error, _} = Pages.open(nil, %{}, %{})
    end

    row = %{F.row() | "choice" => F.capsule(id)}

    for choice <- [
          Map.put(row["choice"], "kind", "candidate_native_management"),
          Map.put(row["choice"], "extra", true),
          Map.put(row["choice"], "lineage", F.id(6)),
          Map.put(row["choice"], "input_sha256", F.hash("forget 0123456789abcdef\n")),
          Map.put(row["choice"], "reason", String.duplicate("é", 33))
        ] do
      assert {:error, _} =
               Pages.pack(:anchor, Pages.zero(:anchor), %{id => %{row | "choice" => choice}})
    end
  end

  test "live pages retain all four hashes exact clocks and changing historical policies" do
    rows =
      Map.new(1..20, fn n ->
        {id, row} = F.live(n)

        row =
          List.replace_at(
            row,
            3,
            Base.url_encode64(Base.decode16!(F.hash("policy#{n}"), case: :lower), padding: false)
          )

        {id, row}
      end)

    assert {:ok, raw} = Pages.pack(:live, Pages.zero(:live), rows)
    assert {:ok, %{entries: ^rows}} = Pages.unpack(:live, Pages.zero(:live), raw)
    {id, row} = F.live(21)

    for bad <- [
          List.replace_at(row, 4, "01"),
          List.replace_at(row, 4, "A"),
          List.replace_at(row, 5, nil),
          List.replace_at(row, 6, 1.0),
          List.replace_at(row, 1, "bad")
        ] do
      assert {:error, _} = Pages.pack(:live, Pages.zero(:live), %{id => bad})
    end
  end

  test "canonical integers flags prefixes dictionaries truncations and historical tags refuse" do
    id = F.id(1)
    row = %{F.row() | "choice" => F.capsule(id), "retirement" => F.full(id)}
    assert {:ok, raw} = Pages.pack(:anchor, Pages.zero(:anchor), %{id => row})

    for n <- 0..(byte_size(raw) - 1),
        do:
          assert({:error, _} = Pages.unpack(:anchor, Pages.zero(:anchor), binary_part(raw, 0, n)))

    assert {:error, _} = Pages.unpack(:anchor, Pages.zero(:anchor), raw <> <<0>>)
    <<"IMB", 2, 2, rest::binary>> = raw
    assert {:error, _} = Pages.unpack(:anchor, Pages.zero(:anchor), <<"IMB", 2, 1>> <> rest)
    assert {:error, _} = Pages.unpack(:anchor, Pages.zero(:anchor), <<"IMB", 1, 2>> <> rest)
    assert {:error, _} = Pages.unpack(:anchor, Pages.zero(:anchor), raw, id)
    assert {:ok, empty} = Pages.pack(:anchor, Pages.zero(:anchor), %{})
    assert {:error, _} = Pages.unpack(:anchor, Pages.zero(:anchor), empty, id)

    for n <- [0, 127, 128, Bitwise.bsl(1, 49) - 1, Bitwise.bsl(1, 49), Pages.safe()] do
      assert {^n, <<>>} = Pages.take_clock(Pages.clock(n), Pages.fixed?(n))
    end

    assert catch_error(Pages.take_clock(<<128, 0>>, false))
    assert catch_error(Pages.take_clock(<<0::56>>, true))
  end

  test "global virtual bytes precede compression and count and maximum shapes stay exact" do
    id = F.id(1)
    clocks = [Bitwise.bsl(1, 49), Bitwise.bsl(1, 50), Bitwise.bsl(1, 49), Bitwise.bsl(1, 50)]

    row = %{
      "clocks" => clocks,
      "choice" => F.capsule(id, %{"kind" => "duration", "duration_ms" => Pages.safe()}),
      "retirement" => F.full(id)
    }

    assert Pages.row_weight(:anchor, id, row) == 337
    {live_id, live} = F.live(1, Bitwise.bsl(1, 49))
    live = List.replace_at(live, 5, F.base36(Bitwise.bsl(1, 50)))
    assert Pages.row_weight(:live, live_id, live) == 183
    small = %{"clocks" => [0, nil, nil, nil], "choice" => nil, "retirement" => nil}
    assert Pages.row_weight(:anchor, id, small) == 37

    assert {:ok, _} =
             Pages.pack(:anchor, Pages.zero(:anchor), Map.new(1..122, &{F.id(&1), small}))

    assert {:error, _} =
             Pages.pack(:anchor, Pages.zero(:anchor), Map.new(1..128, &{F.id(&1), small}))
  end
end

defmodule Ipse.Extension.CollectionManagedPagesNativeTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection.ManagedPages, as: Pages
  alias Ipse.Extension.Collection.ManagedPages.Planner
  alias Ipse.Extension.ProjectIdentity, as: Identity
  alias Ipse.Test.ManagedPagesFixture, as: F
  @moduletag :managed_pages_native

  # Identity locks/tags are actual native operations. Collection observations in
  # this component fixture are explicit trusted callbacks, not C publication proof.
  setup do
    base = Path.join(System.tmp_dir!(), "ipse-managed-pages-" <> Ipse.Usage.id())

    for path <- [base, base <> "/home", base <> "/work"] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    {:ok, binding} = Identity.admit(base <> "/home", base <> "/work", :folder)
    on_exit(fn -> File.rm_rf!(base) end)

    %{
      home: base <> "/home",
      cwd: base <> "/work",
      binding: binding,
      scope: %{
        namespace: F.hash("namespace"),
        format: "managed-metadata-v3",
        operation_id: Ipse.Usage.id(),
        initialize: true
      }
    }
  end

  test "actual Identity signer binds raw body key kind operation and global generation", c do
    assert {:ok, records} =
             first(c, fn cap ->
               w = F.witness(0, c.scope.operation_id)
               id = F.id(7)
               {:ok, body} = Pages.pack(:anchor, Pages.zero(:anchor), %{id => F.row()})

               {:ok, value} =
                 Pages.seal(cap, w, Pages.page_key(:anchor, Pages.zero(:anchor)), body)

               {:ok, format} = Pages.seal(cap, w, Pages.format_key(), Pages.format_body())

               records = %{
                 Pages.page_key(:anchor, Pages.zero(:anchor)) =>
                   F.record(
                     Pages.page_key(:anchor, Pages.zero(:anchor)),
                     value,
                     1,
                     c.scope.operation_id
                   ),
                 Pages.format_key() =>
                   F.record(Pages.format_key(), format, 1, c.scope.operation_id)
               }

               read = F.read(records, 1)
               {:ok, o} = read.(%{"op" => "neighbors", "request" => request(id)})
               r = records[Pages.page_key(:anchor, Pages.zero(:anchor))]
               assert {:ok, %{entries: %{^id => _}}} = Pages.open(cap, r, o)
               assert {:ok, _} = Pages.open_format(cap, records[Pages.format_key()])

               changed_value = Map.update!(value, "data", &(&1 <> "A"))
               changed = F.record(r["key"], changed_value, 1, c.scope.operation_id)

               {:ok, changed_observation} =
                 F.read(Map.put(records, r["key"], changed), 1).(%{
                   "op" => "neighbors",
                   "request" => request(id)
                 })

               assert {:error, _} = Pages.open(cap, changed, changed_observation)

               assert {:error, _} =
                        Pages.open(
                          cap,
                          r,
                          put_in(o, ["neighbors", "selected", "bytes"], r["bytes"] + 1)
                        )

               assert {:error, _} =
                        Pages.open(cap, r, put_in(o, ["witness", "root", "generation"], 2))

               Process.put(:escaped_managed_pages_cap, cap)

               for forged <- [
                     Map.put(r, "operation_id", Ipse.Usage.id()),
                     Map.put(r, "revision", 2)
                   ] do
                 changed = Map.put(records, r["key"], forged)

                 {:ok, bad} =
                   F.read(changed, 2).(%{"op" => "neighbors", "request" => request(id)})

                 assert {:error, _} = Pages.open(cap, forged, bad)
               end

               records
             end)

    Process.put(:managed_fixture_units, 0)
    {:ok, escaped_o} = F.read(records, 1).(%{"op" => "neighbors", "request" => request(F.id(7))})

    assert {:error, _} =
             Pages.open(
               Process.get(:escaped_managed_pages_cap),
               records[Pages.page_key(:anchor, Pages.zero(:anchor))],
               escaped_o
             )

    scope = %{c.scope | operation_id: Ipse.Usage.id(), initialize: false}

    assert {:ok, :checked} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               scope,
               fn _ -> :ok end,
               fn cap, _ ->
                 w = F.witness(9, scope.operation_id)
                 id = F.id(9)
                 {:ok, body} = Pages.pack(:anchor, Pages.zero(:anchor), %{id => F.row()})

                 {:ok, value} =
                   Pages.seal(cap, w, Pages.page_key(:anchor, Pages.zero(:anchor)), body)

                 r =
                   F.record(
                     Pages.page_key(:anchor, Pages.zero(:anchor)),
                     value,
                     10,
                     scope.operation_id
                   )

                 {:ok, o} =
                   F.read(%{r["key"] => r}, 10).(%{"op" => "neighbors", "request" => request(id)})

                 assert {:ok, _} = Pages.open(cap, r, o)
                 wrong = Map.put(r, "revision", 2)

                 {:ok, bad} =
                   F.read(%{wrong["key"] => wrong}, 10).(%{
                     "op" => "neighbors",
                     "request" => request(id)
                   })

                 assert {:error, _} = Pages.open(cap, wrong, bad)

                 assert {:error, _} =
                          Pages.seal(
                            cap,
                            Map.put(w, "operation_id", c.scope.operation_id),
                            r["key"],
                            body
                          )

                 {:ok, :checked}
               end
             )

    assert map_size(records) == 2
  end

  test "authenticated but underfull old nonsingle leaf refuses before local repair", c do
    assert {:ok, :checked} =
             first(c, fn cap ->
               records = seed(cap, c.scope.operation_id, [{0, 1..1}, {2, 2..61}])
               read = F.read(records, 1)
               {:ok, o} = read.(%{"op" => "neighbors", "request" => request(F.id(1))})

               assert {:error, _} =
                        Pages.open(cap, records[Pages.page_key(:anchor, Pages.zero(:anchor))], o)

               assert {:error, _} = Planner.plan(cap, :anchor, [{F.id(1), nil}], read)
               :checked
             end)
  end

  test "bounded actual directory refs support disjoint growth and exact removed revisions", c do
    assert {:ok, old} =
             first(c, fn cap ->
               seed(cap, c.scope.operation_id, [{0, 1..96}, {97, 97..192}, {193, 193..288}])
             end)

    scope = %{c.scope | operation_id: Ipse.Usage.id(), initialize: false}

    assert {:ok, :checked} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               scope,
               fn _ -> :ok end,
               fn cap, _ ->
                 Process.put(:managed_fixture_units, 0)

                 edits =
                   for n <- [1, 200],
                       do:
                         {F.id(n),
                          %{
                            F.row()
                            | "choice" => F.capsule(F.id(n)),
                              "retirement" => F.full(F.id(n))
                          }}

                 assert {:ok, plan} = Planner.plan(cap, :anchor, edits, F.read(old, 1))
                 assert plan.old_pages <= 4 and length(plan.changes) <= 6
                 assert Process.get(:managed_fixture_units) <= 12

                 assert {:ok, changes} =
                          Planner.seal_changes(cap, F.witness(1, scope.operation_id), plan)

                 assert Enum.all?(changes, &(&1["expected_revision"] in [0, 1]))

                 assert {:error, _} =
                          Planner.seal_changes(cap, F.witness(2, scope.operation_id), plan)

                 {:ok, :checked}
               end
             )

    merge = %{c | scope: %{c.scope | namespace: F.hash("merge"), operation_id: Ipse.Usage.id()}}

    assert {:ok, merge_old} =
             first(merge, fn cap ->
               seed(cap, merge.scope.operation_id, [{0, 1..46}, {47, 47..92}])
             end)

    merge_scope = %{merge.scope | operation_id: Ipse.Usage.id(), initialize: false}

    assert {:ok, :checked} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               merge_scope,
               fn _ -> :ok end,
               fn cap, _ ->
                 Process.put(:managed_fixture_units, 0)

                 assert {:ok, plan} =
                          Planner.plan(
                            cap,
                            :anchor,
                            [{F.id(1), nil}, {F.id(2), nil}],
                            F.read(merge_old, 1)
                          )

                 assert plan.old_pages == 2 and length(plan.changes) == 2
                 assert Enum.any?(plan.changes, &(&1.body == nil and &1.expected_revision == 1))

                 assert {:ok, changes} =
                          Planner.seal_changes(cap, F.witness(1, merge_scope.operation_id), plan)

                 assert Enum.any?(changes, &(&1["value"] == nil and &1["expected_revision"] == 1))
                 {:ok, :checked}
               end
             )
  end

  test "native absence initializes one zero leaf but present missing sentinel and bad maps refuse",
       c do
    assert {:ok, :checked} =
             first(c, fn cap ->
               Process.put(:managed_fixture_units, 0)

               assert {:ok, plan} =
                        Planner.plan(cap, :anchor, [{F.id(1), F.row()}], F.read(%{}, 0))

               assert plan.old_pages == 0 and length(plan.changes) == 1

               assert {:ok, [_]} =
                        Planner.seal_changes(cap, F.witness(0, c.scope.operation_id), plan)

               assert {:error, _} = Planner.plan(cap, :anchor, [{F.id(1), nil}], F.read(%{}, 0))

               assert {:error, _} =
                        Planner.plan(
                          cap,
                          :anchor,
                          [{F.id(1), F.row()}, {F.id(1), F.row()}],
                          F.read(%{}, 0)
                        )

               malformed = fn _ -> {:ok, %{"version" => 1, "state" => "uninitialized"}} end
               assert {:error, _} = Planner.plan(cap, :anchor, [{F.id(1), F.row()}], malformed)
               missing = seed(cap, c.scope.operation_id, [{1, 1..60}])
               Process.put(:managed_fixture_units, 0)

               assert {:error, _} =
                        Planner.plan(cap, :anchor, [{F.id(1), F.row()}], F.read(missing, 1))

               :checked
             end)
  end

  test "live split retains exact historical hash dictionaries and refuses a changed root", c do
    assert {:ok, old} =
             first(c, fn cap ->
               rows = Map.new(1..25, &F.live/1)
               key = Pages.page_key(:live, Pages.zero(:live))
               {:ok, body} = Pages.pack(:live, Pages.zero(:live), rows)
               {:ok, value} = Pages.seal(cap, F.witness(0, c.scope.operation_id), key, body)
               %{key => F.record(key, value, 1, c.scope.operation_id)}
             end)

    scope = %{c.scope | operation_id: Ipse.Usage.id(), initialize: false}

    assert {:ok, :checked} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               scope,
               fn _ -> :ok end,
               fn cap, _ ->
                 Process.put(:managed_fixture_units, 0)
                 {id, row} = F.live(26)

                 recipe =
                   Base.url_encode64(Base.decode16!(F.hash("second-recipe"), case: :lower),
                     padding: false
                   )

                 row = List.replace_at(row, 2, recipe)
                 assert {:ok, plan} = Planner.plan(cap, :live, [{id, row}], F.read(old, 1))
                 assert plan.old_pages == 1 and length(plan.changes) == 2
                 assert Process.get(:managed_fixture_units) == 5

                 assert {:ok, changes} =
                          Planner.seal_changes(cap, F.witness(1, scope.operation_id), plan)

                 records =
                   Map.new(changes, fn change ->
                     {change["key"],
                      F.record(change["key"], change["value"], 2, scope.operation_id)}
                   end)

                 read = F.read(records, 2)

                 request = %{
                   "op" => "neighbors",
                   "request" => %{
                     "version" => 1,
                     "prefix" => Pages.prefix(:live),
                     "fence_bytes" => 33,
                     "needle" => id
                   }
                 }

                 {:ok, o} = read.(request)
                 selected = records[o["neighbors"]["selected"]["key"]]
                 assert {:ok, %{entries: entries}} = Pages.open(cap, selected, o)
                 assert entries[id] == row
                 changed = put_in(o, ["summary", "generation"], 3)
                 assert {:error, _} = Pages.open(cap, selected, changed)

                 assert {:error, _} =
                          Task.async(fn -> Pages.open(cap, selected, o) end) |> Task.await()

                 {:ok, :checked}
               end
             )
  end

  defp first(c, fun) do
    Identity.with_domain_publication(c.home, c.cwd, c.binding, c.scope, fn _ -> :ok end, fn cap,
                                                                                            catalog ->
      Process.put(:managed_scope_id, c.scope.operation_id)
      Process.put(:managed_fixture_units, 0)
      value = fun.(cap)

      witness = %{
        version: 1,
        namespace: c.scope.namespace,
        format: c.scope.format,
        fence_id: catalog["fence_id"],
        operation_id: c.scope.operation_id,
        root_sha256: F.hash("trusted fixture root")
      }

      {:first_publication, witness, value}
    end)
  end

  defp seed(cap, operation, pages) do
    Map.new(pages, fn {fence, range} ->
      key = Pages.page_key(:anchor, F.id(fence))
      {:ok, body} = Pages.pack(:anchor, F.id(fence), Map.new(range, &{F.id(&1), F.row()}))
      {:ok, value} = Pages.seal(cap, F.witness(0, operation), key, body)
      {key, F.record(key, value, 1, operation)}
    end)
  end

  defp request(id),
    do: %{"version" => 1, "prefix" => Pages.prefix(:anchor), "fence_bytes" => 32, "needle" => id}
end
