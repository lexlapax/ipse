for {module, file} <- [
      {IpseKnowledge.Notes, "notes.ex"},
      {IpseKnowledge.Knowledge.Records, "knowledge/records.ex"},
      {IpseKnowledge.Knowledge.Contracts, "knowledge/contracts.ex"}
    ] do
  unless Code.ensure_loaded?(module),
    do: Code.require_file(Path.expand("../../../extensions/knowledge/src/" <> file, __DIR__))
end

Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Test.NormalizerV3Fixture do
  alias Ipse.Extension.Collection.{Directory, ManagedPages}
  alias IpseKnowledge.Knowledge.{Contracts, Records}
  alias Ipse.JSON
  @day 86_400_000
  def hash(value), do: JSON.sha256(to_string(value))
  def namespace, do: hash("normalizer-v3")

  def proof do
    quote = "Acme has owner Alex"

    %{
      "version" => 1,
      "session_id" => String.duplicate("1", 32),
      "occurrence_id" => String.duplicate("2", 32),
      "version_id" => String.duplicate("3", 32),
      "kind" => "input.original",
      "origin" => "interactive_operator",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(quote),
      "quote" => quote,
      "quote_sha256" => hash(quote),
      "content_sha256" => hash(quote),
      "receipt_sha256" => hash("synthetic trusted source member")
    }
  end

  def options(kind \\ "literal_source", category \\ "ordinary", now \\ 0) do
    source = proof()
    text = if kind == "proposal", do: "Acme may appoint Alex", else: source["quote"]

    {:ok, key, value} =
      Records.capture(
        %{
          "text" => text,
          "category" => category,
          "reason" => "selected span",
          "event_at_ms" => nil
        },
        source,
        10 * @day
      )

    constraint =
      Contracts.operator()["publication"][if(kind == "proposal", do: "pending", else: "note")]

    recipe = Ipse.Test.ManagedPolicy.recipe(kind, constraint)

    %{
      request: %{
        "op" => "commit",
        "expected_generation" => 0,
        "advance_floor" => true,
        "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]
      },
      recipe: recipe,
      constraints: constraint,
      verified_sources: [source],
      policy_sha256: hash("reviewed historical policy"),
      now_ms: now
    }
  end

  def witness(opts, generation, operation) do
    summary = %{
      "version" => 3,
      "project" => namespace(),
      "generation" => generation,
      "floor" => 0,
      "floor_anchor" => nil
    }

    pointer =
      summary |> Map.put("version", 5) |> Map.put("manifest", hash("manifest#{generation}"))

    raw = if generation > 0, do: ManagedPages.bytes(pointer)

    %{
      "version" => 2,
      "root" => summary,
      "root_state" => if(generation == 0, do: "absent", else: "present"),
      "root_bytes" => raw,
      "root_sha256" => if(raw, do: hash(raw)),
      "manifest_sha256" => if(raw, do: pointer["manifest"]),
      "operation_id" => operation,
      "original_request_sha256" => JSON.digest([opts.request]),
      "recipe_sha256" => JSON.digest([opts.recipe])
    }
  end

  def record(key, value, generation, operation) do
    raw = ManagedPages.bytes(value)

    %{
      "key" => key,
      "revision" => generation,
      "operation_id" => operation,
      "sha256" => hash(raw),
      "bytes" => byte_size(raw),
      "value" => value
    }
  end

  def read(records, witness) do
    {:ok, tree} = Directory.index(Enum.sort(Map.keys(records)))

    fn request ->
      {:ok, cost} = Directory.cost(request)
      n = Process.get(:v3_read_units, 0) + cost
      Process.put(:v3_read_units, n)
      if n > 32, do: raise("actual fixture read budget exceeded")

      if is_binary(request) do
        {:ok, records[request]}
      else
        {:ok, _, nil, slots} = Directory.select(tree, request, witness["root_state"])
        pointer = if witness["root_bytes"], do: Jason.decode!(witness["root_bytes"])

        refs =
          Map.new(Map.delete(slots, "state"), fn {slot, key} ->
            {slot, records[key] && Map.delete(records[key], "value")}
          end)

        {:ok,
         %{
           "version" => 1,
           "summary" => witness["root"],
           "directory" => request["request"],
           "state" => slots["state"],
           "neighbors" => refs,
           "witness" => %{
             "version" => 2,
             "root_state" => witness["root_state"],
             "root" => pointer,
             "root_sha256" => witness["root_sha256"],
             "manifest_sha256" => witness["manifest_sha256"]
           }
         }}
      end
    end
  end

  def id(n), do: Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(64, "0")

  def anchor(clocks \\ [0, 90 * @day, nil, nil]),
    do: %{"clocks" => clocks, "choice" => nil, "retirement" => nil}

  def seed(cap, witness, anchors, live \\ %{}, anchor_pages \\ nil, live_pages \\ nil) do
    pages =
      (anchor_pages || [{ManagedPages.zero(:anchor), anchors}])
      |> Enum.map(fn {fence, rows} -> {:anchor, fence, rows} end)

    pages =
      pages ++
        Enum.map(live_pages || [{ManagedPages.zero(:live), live}], fn {fence, rows} ->
          {:live, fence, rows}
        end)

    pairs =
      Enum.map(pages, fn {kind, fence, rows} ->
        {:ok, body} = ManagedPages.pack(kind, fence, rows)
        key = ManagedPages.page_key(kind, fence)
        {:ok, value} = ManagedPages.seal(cap, witness, key, body)
        {key, record(key, value, 1, witness["operation_id"])}
      end)

    {:ok, format} =
      ManagedPages.seal(cap, witness, ManagedPages.format_key(), ManagedPages.format_body())

    Map.put(
      Map.new(pairs),
      ManagedPages.format_key(),
      record(ManagedPages.format_key(), format, 1, witness["operation_id"])
    )
  end
end

defmodule Ipse.Extension.CollectionNormalizerV3Test do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection.{NormalizerV3, ManagedPages, Migration}
  alias Ipse.Extension.ProjectIdentity, as: Identity
  alias Ipse.Test.NormalizerV3Fixture, as: F
  @day 86_400_000
  @refused {:error, :managed_normalization_refused}
  # Identity admission, catalog changes and tags are real protected native work.
  # All Collection observations are explicit trusted fixtures, never C publishing.
  setup do
    base = Path.join(System.tmp_dir!(), "ipse-normalizer-v3-" <> Ipse.Usage.id())

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
        namespace: F.namespace(),
        format: "managed-metadata-v3",
        operation_id: Ipse.Usage.id(),
        initialize: true
      }
    }
  end

  test "first literal has exact format and signed metadata without trusting worker clocks", c do
    assert {:ok, :checked} =
             first(c, fn cap, catalog ->
               options = F.options()
               w = F.witness(options, 0, c.scope.operation_id)
               assert {:ok, normalized, receipt} = normalize(cap, catalog, options, w, %{})
               assert Process.get(:v3_read_units) == 19
               assert hd(normalized["changes"]) == hd(options.request["changes"])
               extras = tl(normalized["changes"])
               assert length(extras) == 3 and hd(extras)["key"] == ManagedPages.format_key()
               assert receipt["version"] == 3 and receipt["first_admitted_ms"] == 0

               assert receipt["valid_until_ms"] == 90 * @day and
                        receipt["eligibility"] == "current"

               assert byte_size(Migration.encode(receipt)) <= 2048

               assert Enum.map(extras, fn change ->
                        %{
                          "key" => change["key"],
                          "expected_revision" => change["expected_revision"],
                          "value_sha256" => F.hash(Migration.encode(change["value"]))
                        }
                      end) == receipt["metadata_changes"]

               live = List.last(extras)["value"]["data"] |> Base.url_decode64!(padding: false)

               {:ok, %{entries: entries}} =
                 ManagedPages.unpack(:live, ManagedPages.zero(:live), live)

               [row] = Map.values(entries)
               assert Enum.at(row, 4) == "0" and Enum.at(row, 6) == 0 and Enum.at(row, 7) == 0
               assert Enum.at(row, 3) == packed(options.policy_sha256)
               assert Enum.at(row, 2) == packed(Ipse.JSON.digest([options.recipe]))
               :checked
             end)
  end

  test "proposal stays never-current and cannot start the distinct literal clock", c do
    assert {:ok, old} =
             first(c, fn cap, _catalog ->
               opts = F.options("proposal")
               {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())

               F.seed(cap, F.witness(opts, 0, c.scope.operation_id), %{
                 lineage => F.anchor([nil, nil, 0, 7 * @day])
               })
             end)

    assert {:ok, :checked} =
             active(c, fn cap, catalog, operation ->
               opts = F.options("literal_source", "ordinary", 12 * @day)
               w = F.witness(opts, 1, operation)
               assert {:ok, _, r} = normalize(cap, catalog, opts, w, old)
               assert r["first_admitted_ms"] == 12 * @day and r["valid_until_ms"] == 102 * @day
               pending = F.options("proposal", "ordinary", 6 * @day)

               assert {:ok, _, r} =
                        normalize(cap, catalog, pending, F.witness(pending, 1, operation), old)

               assert r["first_admitted_ms"] == 0 and r["valid_until_ms"] == 7 * @day
               assert r["eligibility"] == "never_current"
               expired = %{pending | now_ms: 7 * @day}

               assert @refused ==
                        normalize(cap, catalog, expired, F.witness(expired, 1, operation), old)

               {:ok, :checked}
             end)
  end

  test "retained ordinary baseline survives prune longer policy and persistent relabel", c do
    opts = F.options()
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())

    assert {:ok, old} =
             first(c, fn cap, _ ->
               F.seed(cap, F.witness(opts, 0, c.scope.operation_id), %{lineage => F.anchor()})
             end)

    assert {:ok, :checked} =
             active(c, fn cap, catalog, operation ->
               current = F.options("literal_source", "current", 89 * @day)

               assert {:ok, _, r} =
                        normalize(cap, catalog, current, F.witness(current, 1, operation), old)

               assert r["first_admitted_ms"] == 0 and r["valid_until_ms"] == 90 * @day
               expired = %{current | now_ms: 90 * @day}

               assert @refused ==
                        normalize(cap, catalog, expired, F.witness(expired, 1, operation), old)

               longer =
                 put_in(opts, [:recipe, "rules", Access.at(1), "max_age_ms"], 365 * @day)
                 |> Map.put(:now_ms, 89 * @day)

               assert {:ok, _, r} =
                        normalize(cap, catalog, longer, F.witness(longer, 1, operation), old)

               assert r["valid_until_ms"] == 90 * @day
               {:ok, :checked}
             end)
  end

  test "source request catalog and fixed key refusals leave no successful normalization", c do
    assert {:ok, :checked} =
             first(c, fn cap, catalog ->
               opts = F.options()

               for bad <- [
                     Map.put(opts, :verified_sources, []),
                     put_in(opts, [:request, "advance_floor"], false),
                     put_in(opts, [:request, "changes", Access.at(0), "expected_revision"], 1),
                     Map.put(opts, :domain_cap, nil),
                     Map.put(opts, :catalog, Map.put(catalog, "namespace", F.hash("foreign")))
                   ] do
                 bad = bad |> Map.put_new(:domain_cap, cap) |> Map.put_new(:catalog, catalog)

                 assert @refused ==
                          NormalizerV3.normalize(
                            F.witness(bad, 0, c.scope.operation_id),
                            F.read(%{}, F.witness(bad, 0, c.scope.operation_id)),
                            bad
                          )
               end

               key = hd(opts.request["changes"])["key"]
               {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())

               override = %{
                 ("override." <> lineage) =>
                   F.record("override." <> lineage, %{"legacy" => true}, 1, c.scope.operation_id)
               }

               assert @refused ==
                        normalize(
                          cap,
                          catalog,
                          opts,
                          F.witness(opts, 0, c.scope.operation_id),
                          override
                        )

               existing = %{
                 key =>
                   F.record(key, hd(opts.request["changes"])["value"], 1, c.scope.operation_id)
               }

               assert @refused ==
                        normalize(
                          cap,
                          catalog,
                          opts,
                          F.witness(opts, 0, c.scope.operation_id),
                          existing
                        )

               other =
                 opts
                 |> put_in([:constraints, "key_prefix"], "other.")
                 |> put_in([:recipe, "key_prefix"], "other.")
                 |> put_in([:request, "changes", Access.at(0), "key"], "other." <> lineage)

               other =
                 put_in(
                   other,
                   [:recipe, "constraints_sha256"],
                   Ipse.JSON.digest([other.constraints])
                 )

               assert @refused ==
                        normalize(
                          cap,
                          catalog,
                          other,
                          F.witness(other, 0, c.scope.operation_id),
                          %{}
                        )

               :checked
             end)
  end

  test "present root missing format and unsigned old metadata cannot initialize or adopt", c do
    assert {:ok, :checked} =
             first(c, fn cap, catalog ->
               opts = F.options()
               present = F.witness(opts, 1, c.scope.operation_id)
               assert @refused == normalize(cap, catalog, opts, present, %{})

               unsigned = %{
                 "host.validity.anchor.00.0" =>
                   F.record(
                     "host.validity.anchor.00.0",
                     %{"version" => 2, "entries" => %{}},
                     1,
                     c.scope.operation_id
                   )
               }

               assert @refused == normalize(cap, catalog, opts, present, unsigned)
               active = Map.put(catalog, "state", "active")

               assert @refused ==
                        normalize(
                          cap,
                          active,
                          opts,
                          F.witness(opts, 0, c.scope.operation_id),
                          %{}
                        )

               :checked
             end)
  end

  test "authenticated stored choices and retirement remain unsupported semantic authority", c do
    opts = F.options()
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())

    choice = %{
      "version" => 2,
      "kind" => "native_management",
      "lineage" => lineage,
      "event_id" => String.duplicate("a", 32),
      "display_sha256" => F.hash("review"),
      "challenge" => "0123456789abcdef",
      "target_key" => "note." <> lineage,
      "target_value_sha256" => F.hash("old value"),
      "observed_at_ms" => 0,
      "policy" => %{"kind" => "session"},
      "reason" => "explicit fixture only",
      "input_sha256" => F.hash("forget 0123456789abcdef")
    }

    assert {:ok, stores} =
             first(c, fn cap, _ ->
               for row <- [
                     %{F.anchor() | "choice" => choice},
                     %{
                       F.anchor()
                       | "retirement" => %{"target_kind" => "native_literal_note", "at_ms" => 0}
                     }
                   ] do
                 F.seed(cap, F.witness(opts, 0, c.scope.operation_id), %{lineage => row})
               end
             end)

    assert {:ok, :checked} =
             active(c, fn cap, catalog, operation ->
               for old <- stores do
                 assert @refused ==
                          normalize(cap, catalog, opts, F.witness(opts, 1, operation), old)
               end

               {:ok, :checked}
             end)
  end

  test "changed MAC body and authentic old page moved to another operation refuse", c do
    opts = F.options()
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())

    assert {:ok, old} =
             first(c, fn cap, _ ->
               F.seed(cap, F.witness(opts, 0, c.scope.operation_id), %{lineage => F.anchor()})
             end)

    assert {:ok, :checked} =
             active(c, fn cap, catalog, operation ->
               format = old[ManagedPages.format_key()]

               data =
                 Map.update!(format["value"], "mac", fn _ ->
                   Base.url_encode64(<<0::256>>, padding: false)
                 end)

               changed =
                 Map.put(
                   old,
                   format["key"],
                   F.record(format["key"], data, 1, format["operation_id"])
                 )

               assert @refused ==
                        normalize(cap, catalog, opts, F.witness(opts, 1, operation), changed)

               key = ManagedPages.page_key(:anchor, ManagedPages.zero(:anchor))
               moved = Map.put(old, key, Map.put(old[key], "operation_id", operation))

               assert @refused ==
                        normalize(cap, catalog, opts, F.witness(opts, 1, operation), moved)

               {:ok, :checked}
             end)
  end

  test "a retained live identity refuses even when the public record is absent", c do
    opts = F.options()
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())
    change = hd(opts.request["changes"])
    live_id = ManagedPages.live_identity(change["key"])

    row = [
      packed(lineage),
      packed(F.hash(Migration.encode(change["value"]))),
      packed(Ipse.JSON.digest([opts.recipe])),
      packed(opts.policy_sha256),
      "0",
      Integer.to_string(90 * @day, 36) |> String.downcase(),
      0,
      0
    ]

    assert {:ok, old} =
             first(c, fn cap, _ ->
               F.seed(cap, F.witness(opts, 0, c.scope.operation_id), %{lineage => F.anchor()}, %{
                 live_id => row
               })
             end)

    refute Map.has_key?(old, change["key"])

    assert {:ok, :checked} =
             active(c, fn cap, catalog, operation ->
               assert @refused ==
                        normalize(cap, catalog, opts, F.witness(opts, 1, operation), old)

               assert Process.get(:v3_read_units) == 13
               {:ok, :checked}
             end)
  end

  test "exact minimum shrink plus live split produces five extras four values and one exact deletion",
       c do
    opts = F.options("literal_source", "ordinary", @day)
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(F.proof())
    number = String.to_integer(lineage, 16)
    id = fn n -> Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(64, "0") end
    left = Map.new(1..49, fn n -> {id.(number - n), F.anchor()} end)
    left = Map.put(left, lineage, F.anchor([0, Bitwise.bsl(1, 49), nil, nil]))
    left = Map.put(left, id.(number - 1), F.anchor([16384, 16384 + 90 * @day, nil, nil]))
    assert ManagedPages.weight(:anchor, left) == ManagedPages.profile(:anchor).floor
    right = Map.new(1..100, fn n -> {id.(number + n), F.anchor()} end)

    live =
      Map.new(1..25, fn n ->
        key = ManagedPages.live_identity("note." <> F.id(n))

        {key,
         [
           packed(F.hash("lineage#{n}")),
           packed(F.hash("value#{n}")),
           packed(F.hash("recipe")),
           packed(F.hash("policy")),
           "0",
           Integer.to_string(90 * @day, 36) |> String.downcase(),
           0,
           0
         ]}
      end)

    assert {:ok, old} =
             first(c, fn cap, _ ->
               F.seed(
                 cap,
                 F.witness(opts, 0, c.scope.operation_id),
                 %{},
                 %{},
                 [{ManagedPages.zero(:anchor), left}, {id.(number + 1), right}],
                 [{ManagedPages.zero(:live), live}]
               )
             end)

    assert {:ok, :checked} =
             active(c, fn cap, catalog, operation ->
               assert {:ok, normalized, receipt} =
                        normalize(cap, catalog, opts, F.witness(opts, 1, operation), old)

               extras = tl(normalized["changes"])
               assert length(extras) == 5 and Enum.count(extras, &is_nil(&1["value"])) == 1
               assert Process.get(:v3_read_units) == 24
               deletion = Enum.find(extras, &is_nil(&1["value"]))
               assert deletion["key"] == ManagedPages.page_key(:anchor, id.(number + 1))
               assert deletion["expected_revision"] == 1

               assert Enum.find(receipt["metadata_changes"], &(&1["key"] == deletion["key"]))[
                        "value_sha256"
                      ] == nil

               assert Enum.all?(extras, fn change ->
                        is_nil(change["value"]) or
                          byte_size(Migration.encode(change["value"])) <= 6144
                      end)

               assert byte_size(Migration.encode(receipt)) <= 2048
               {:ok, :checked}
             end)
  end

  defp normalize(cap, catalog, options, witness, records) do
    options = %{
      options
      | request: Map.put(options.request, "expected_generation", witness["root"]["generation"])
    }

    witness = Map.put(witness, "original_request_sha256", Ipse.JSON.digest([options.request]))
    Process.put(:v3_read_units, 0)

    NormalizerV3.normalize(
      witness,
      F.read(records, witness),
      Map.merge(options, %{domain_cap: cap, catalog: catalog})
    )
  end

  defp first(c, fun) do
    Identity.with_domain_publication(c.home, c.cwd, c.binding, c.scope, fn _ -> :ok end, fn cap,
                                                                                            catalog ->
      value = fun.(cap, catalog)

      witness = %{
        version: 1,
        namespace: c.scope.namespace,
        format: c.scope.format,
        fence_id: catalog["fence_id"],
        operation_id: c.scope.operation_id,
        root_sha256: F.hash("trusted synthetic Collection root")
      }

      {:first_publication, witness, value}
    end)
  end

  defp active(c, fun) do
    scope = %{c.scope | operation_id: Ipse.Usage.id(), initialize: false}

    Identity.with_domain_publication(c.home, c.cwd, c.binding, scope, fn _ -> :ok end, fn cap,
                                                                                          catalog ->
      fun.(cap, catalog, scope.operation_id)
    end)
  end

  defp packed(hash), do: Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false)
end
