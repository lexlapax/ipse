Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/knowledge/records.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/knowledge/contracts.ex", __DIR__)

defmodule Ipse.Extension.CollectionNormalizerTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.{Normalizer, Migration}
  alias Ipse.Extension.{Collection, ManagedRecipe}
  alias IpseKnowledge.Knowledge.{Contracts, Records}
  alias Ipse.JSON
  @day 86_400_000

  defp proof do
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
      "quote_sha256" => JSON.sha256(quote),
      "content_sha256" => JSON.sha256(quote),
      "receipt_sha256" => JSON.sha256("synthetic normalizer input")
    }
  end

  defp options(
         kind \\ "literal_source",
         text \\ "Acme has owner Alex",
         category \\ "ordinary",
         now \\ 0
       ) do
    p = proof()

    {:ok, key, value} =
      Records.capture(
        %{
          "text" => text,
          "category" => category,
          "reason" => "selected span",
          "event_at_ms" => nil
        },
        p,
        10 * @day
      )

    constraint =
      Contracts.operator()["publication"][if(kind == "proposal", do: "pending", else: "note")]

    age = if(kind == "proposal", do: 7 * @day, else: if(category == "ordinary", do: 90 * @day))

    recipe = %{
      "version" => 1,
      "kind" => kind,
      "key_prefix" => if(kind == "proposal", do: "pending.", else: "note."),
      "constraints_sha256" => JSON.digest([constraint]),
      "evidence_path" => ["evidence", "sources"],
      "lineage_path" => ["lineage"],
      "text_path" => ["text"],
      "category_path" => [if(kind == "proposal", do: "assigned_category", else: "category")],
      "rules" => [%{"category" => category, "max_age_ms" => age, "origins" => [p["origin"]]}],
      "override_prefix" => "override."
    }

    %{
      request: %{
        "op" => "commit",
        "expected_generation" => 0,
        "advance_floor" => true,
        "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]
      },
      recipe: recipe,
      constraints: constraint,
      verified_sources: [p],
      policy_sha256: JSON.sha256("reviewed policy"),
      now_ms: now
    }
  end

  defp witness(options),
    do: %{
      "root" => %{
        "version" => 3,
        "project" => JSON.sha256("namespace"),
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil
      },
      "manifest_sha256" => nil,
      "operation_id" => Ipse.Usage.id(),
      "original_request_sha256" => JSON.digest([options.request]),
      "recipe_sha256" => JSON.digest([options.recipe])
    }

  # A deliberately synthetic in-memory reader. Native transaction/admission is
  # tested separately below; these values attest no source or filesystem origin.
  defp normalize(options, values \\ %{}) do
    read = fn key ->
      case values[key] do
        nil -> {:ok, nil}
        value -> {:ok, %{"key" => key, "revision" => 1, "value" => value}}
      end
    end

    Normalizer.normalize(witness(options), read, options)
  end

  defp metadata(normalized),
    do: Map.new(Enum.drop(normalized["changes"], 1), &{&1["key"], &1["value"]})

  defp anchors(values),
    do: Map.filter(values, fn {key, _} -> String.starts_with?(key, "host.validity.anchor.") end)

  test "actual host clock and canonical value bind both metadata pages; worker clock is ignored" do
    opts = options()
    assert ManagedRecipe.valid?(opts.recipe)
    assert {:ok, normalized, receipt} = normalize(opts)
    assert length(normalized["changes"]) == 3
    assert hd(normalized["changes"]) == hd(opts.request["changes"])
    assert receipt["first_admitted_ms"] == 0
    assert receipt["valid_until_ms"] == 90 * @day
    assert receipt["eligibility"] == "current"

    live =
      normalized["changes"] |> List.last() |> get_in(["value", "entries"]) |> Map.values() |> hd()

    assert live["record_value_sha256"] ==
             JSON.sha256(Migration.encode(hd(opts.request["changes"])["value"]))

    refute Map.has_key?(hd(live["sources"]), "quote")
  end

  test "ordinary source cannot renew through prune, persistent classification or a longer policy" do
    assert {:ok, first, _} = normalize(options())
    retained = first |> metadata() |> anchors()
    current = options("literal_source", "Acme has owner Alex", "current", 89 * @day)
    assert {:ok, _, receipt} = normalize(current, retained)
    assert receipt["valid_until_ms"] == 90 * @day

    assert {:error, :managed_normalization_refused} =
             normalize(%{current | now_ms: 90 * @day}, retained)

    longer = put_in(options(), [:recipe, "rules", Access.at(0), "max_age_ms"], 365 * @day)
    assert {:ok, _, receipt} = normalize(longer, retained)
    assert receipt["valid_until_ms"] == 90 * @day
  end

  test "pending paraphrases share their first deadline and cannot extend an earlier policy" do
    original = options("proposal", "Alex owns Acme")
    original = put_in(original, [:recipe, "rules", Access.at(0), "max_age_ms"], @day)
    assert {:ok, first, _} = normalize(original)
    retained = first |> metadata() |> anchors()
    later = options("proposal", "Acme is owned by Alex", "ordinary", @day - 1)
    assert {:ok, _, receipt} = normalize(later, retained)
    assert receipt["eligibility"] == "never_current"
    assert receipt["valid_until_ms"] == @day
    assert {:error, :managed_normalization_refused} = normalize(%{later | now_ms: @day}, retained)
  end

  test "a pending paraphrase does not consume the later supported literal's observation window" do
    assert {:ok, first, _} = normalize(options("proposal", "Alex owns Acme"))
    retained = first |> metadata() |> anchors()

    assert {:ok, _, receipt} =
             normalize(
               options("literal_source", "Acme has owner Alex", "ordinary", 8 * @day),
               retained
             )

    assert receipt["first_admitted_ms"] == 8 * @day
    assert receipt["valid_until_ms"] == 98 * @day
  end

  test "a narrowed persistent baseline survives another prune and cannot become persistent again" do
    assert {:ok, first, _} =
             normalize(options("literal_source", "Acme has owner Alex", "current"))

    retained = first |> metadata() |> anchors()

    assert {:ok, narrowed, receipt} =
             normalize(
               options("literal_source", "Acme has owner Alex", "ordinary", @day),
               retained
             )

    assert receipt["valid_until_ms"] == 90 * @day
    retained = narrowed |> metadata() |> anchors()

    assert {:error, :managed_normalization_refused} =
             normalize(
               options("literal_source", "Acme has owner Alex", "current", 90 * @day),
               retained
             )
  end

  test "an earlier wall clock cannot precede an existing source observation" do
    assert {:ok, first, _} =
             normalize(options("literal_source", "Acme has owner Alex", "ordinary", @day))

    assert {:error, :managed_normalization_refused} =
             normalize(options(), first |> metadata() |> anchors())

    assert {:ok, first, _} = normalize(options("proposal", "Alex owns Acme", "ordinary", @day))

    assert {:error, :managed_normalization_refused} =
             normalize(options(), first |> metadata() |> anchors())
  end

  test "experimental unprotected metadata pages cannot acquire the new floor guarantee" do
    assert {:ok, first, _} = normalize(options())
    retained = first |> metadata() |> anchors()
    assert {:ok, _, _} = normalize(options(), retained)
    legacy = Map.new(retained, fn {key, value} -> {key, Map.put(value, "version", 1)} end)
    assert {:error, :managed_normalization_refused} = normalize(options(), legacy)
  end

  test "untyped legacy overrides, orphan live entries, receipt changes and overflow refuse" do
    opts = options()
    lineage = Records.lineage(proof())

    assert {:error, :managed_normalization_refused} =
             normalize(opts, %{("override." <> lineage) => %{"policy" => %{"kind" => "pin"}}})

    assert {:ok, first, _} = normalize(opts)
    assert {:error, :managed_normalization_refused} = normalize(opts, metadata(first))

    assert {:error, :managed_normalization_refused} =
             normalize(%{
               opts
               | verified_sources: [%{proof() | "receipt_sha256" => JSON.sha256("changed")}]
             })

    assert {:error, :managed_normalization_refused} =
             normalize(%{opts | now_ms: 9_007_199_254_740_991})

    assert {:error, :managed_normalization_refused} = normalize(%{opts | policy_sha256: "bad"})
  end

  test "gapped, wrong-shard and full anchor pages cannot evict a retained lineage" do
    opts = options()
    lineage = Records.lineage(proof())
    shard = binary_part(lineage, 0, 2)

    page = fn ordinal, rows ->
      %{
        "version" => 2,
        "kind" => "anchor",
        "shard" => shard,
        "page" => ordinal,
        "entries" => rows
      }
    end

    rows =
      Map.new(1..16, fn n ->
        {shard <> String.pad_leading(n |> Integer.to_string(16) |> String.downcase(), 62, "0"),
         [0, 90 * @day, nil, nil, nil]}
      end)

    full =
      Map.new(0..7, fn ordinal ->
        shifted =
          Map.new(rows, fn {id, row} ->
            {binary_part(id, 0, 2) <>
               String.pad_leading(
                 (ordinal * 16 + String.to_integer(binary_part(id, 2, 62), 16))
                 |> Integer.to_string(16)
                 |> String.downcase(),
                 62,
                 "0"
               ), row}
          end)

        {"host.validity.anchor.#{shard}.#{ordinal}", page.(ordinal, shifted)}
      end)

    assert {:error, :managed_normalization_refused} = normalize(opts, full)

    last_key = "host.validity.anchor.#{shard}.7"
    last_identity = full[last_key]["entries"] |> Map.keys() |> Enum.sort() |> List.last()
    one_slot = update_in(full, [last_key, "entries"], &Map.delete(&1, last_identity))
    assert {:ok, inserted, receipt} = normalize(opts, one_slot)
    assert receipt["anchor_key"] == last_key
    assert map_size(metadata(inserted)[last_key]["entries"]) == 16

    assert {:error, :managed_normalization_refused} =
             normalize(opts, %{"host.validity.anchor.#{shard}.1" => page.(1, rows)})

    wrong = put_in(page.(0, rows), ["shard"], "zz")

    assert {:error, :managed_normalization_refused} =
             normalize(opts, %{"host.validity.anchor.#{shard}.0" => wrong})

    assert Enum.all?(full, fn {_, value} -> byte_size(Migration.encode(value)) <= 6144 end)
  end

  test "live page exhaustion refuses while the last free slot remains usable" do
    opts = options()
    assert {:ok, first, _} = normalize(opts)
    live_page = List.last(first["changes"])["value"]
    template = live_page["entries"] |> Map.values() |> hd()
    shard = live_page["shard"]

    rows =
      Enum.reduce_while(0..50_000, [], fn n, rows ->
        key = "synthetic.live.#{n}"
        id = JSON.sha256(key)
        candidate_shard = id |> binary_part(0, 3) |> String.to_integer(16) |> rem(512)

        if candidate_shard == String.to_integer(shard, 16) do
          rows = [{id, %{template | "record_key" => key}} | rows]
          if length(rows) == 16, do: {:halt, rows}, else: {:cont, rows}
        else
          {:cont, rows}
        end
      end)

    assert length(rows) == 16

    full =
      rows
      |> Enum.chunk_every(4)
      |> Enum.with_index()
      |> Map.new(fn {entries, page} ->
        {"host.validity.live.#{shard}.#{page}",
         %{live_page | "page" => page, "entries" => Map.new(entries)}}
      end)

    assert {:error, :managed_normalization_refused} = normalize(opts, full)
    last_key = "host.validity.live.#{shard}.3"
    {last_id, _} = hd(Enum.to_list(full[last_key]["entries"]))
    free = update_in(full, [last_key, "entries"], &Map.delete(&1, last_id))
    assert {:ok, inserted, receipt} = normalize(opts, free)
    assert receipt["live_key"] == last_key
    assert map_size(metadata(inserted)[last_key]["entries"]) == 4
    assert Enum.all?(full, fn {_, page} -> byte_size(Migration.encode(page)) <= 6144 end)
  end

  test "malformed retained live source classifications cannot become current" do
    opts = options()
    assert {:ok, first, _} = normalize(opts)
    page_change = List.last(first["changes"])
    {_, template} = hd(Enum.to_list(page_change["value"]["entries"]))
    target_shard = String.to_integer(page_change["value"]["shard"], 16)

    other_key =
      Enum.find_value(0..50_000, fn n ->
        key = "synthetic.record.#{n}"
        shard = key |> JSON.sha256() |> binary_part(0, 3) |> String.to_integer(16) |> rem(512)
        if shard == target_shard, do: key
      end)

    assert is_binary(other_key)
    id = JSON.sha256(other_key)

    healthy = %{
      page_change["value"]
      | "entries" => %{id => Map.put(template, "record_key", other_key)}
    }

    assert {:ok, _, _} = normalize(opts, %{page_change["key"] => healthy})

    for {kind, origin} <- [
          {"tool.outcome", "interactive_operator"},
          {"input.original", "unattended_input"}
        ] do
      value = put_in(healthy, ["entries", id, "sources", Access.at(0), "kind"], kind)
      value = put_in(value, ["entries", id, "sources", Access.at(0), "origin"], origin)

      assert {:error, :managed_normalization_refused} =
               normalize(opts, %{page_change["key"] => value})
    end

    invalid_key =
      Enum.find_value(0..50_000, fn n ->
        key = "invalid\nkey.#{n}"
        shard = key |> JSON.sha256() |> binary_part(0, 3) |> String.to_integer(16) |> rem(512)
        if shard == target_shard, do: key
      end)

    assert is_binary(invalid_key)
    healthy_row = healthy["entries"][id]

    for entry <- [
          Map.put(healthy_row, "valid_until_ms", nil),
          Map.put(healthy_row, "record_key", invalid_key),
          healthy_row
          |> Map.put("category", "current")
          |> Map.put("eligibility", "never_current")
          |> Map.put("valid_until_ms", nil),
          Map.put(healthy_row, "version", 1)
        ] do
      key_hash = JSON.sha256(entry["record_key"])
      value = %{healthy | "entries" => %{key_hash => entry}}

      assert {:error, :managed_normalization_refused} =
               normalize(opts, %{page_change["key"] => value})
    end
  end

  test "actual native collection atomically writes host metadata and keeps expiry suppression after removal" do
    parent = Path.join(System.tmp_dir!(), "ipse-normalizer-native-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "collections")
    namespace = JSON.sha256("normalizer native namespace")
    opts = options()

    run = fn options ->
      Collection.execute_managed(
        root,
        namespace,
        options.request,
        Ipse.Usage.id(),
        JSON.digest([options.recipe]),
        fn witness, read -> Normalizer.normalize(witness, read, options) end
      )
    end

    assert {:ok, result} = run.(opts)
    assert result["receipt"]["floor"] == 1
    assert result["normalization"]["version"] == 2
    assert result["normalization"]["valid_until_ms"] == 90 * @day

    backup_root = Path.join(parent, "empty-backup")

    assert {:ok, %{"descriptor" => old_backup}} =
             Collection.execute(
               backup_root,
               namespace,
               %{"op" => "export", "generation" => 0, "after" => nil, "limit" => 32},
               Ipse.Usage.id()
             )

    assert {:failed, %{"code" => "collection_import_floor"}} =
             Collection.execute(
               root,
               namespace,
               %{"op" => "import.open", "expected_generation" => 1, "descriptor" => old_backup},
               Ipse.Usage.id()
             )

    key = hd(opts.request["changes"])["key"]
    live_key = result["normalization"]["live_key"]

    assert {:ok, _} =
             Collection.execute(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => true,
                 "changes" => [
                   %{"key" => key, "expected_revision" => 1, "value" => nil},
                   %{"key" => live_key, "expected_revision" => 1, "value" => nil}
                 ]
               },
               Ipse.Usage.id()
             )

    opts = %{opts | now_ms: 90 * @day, request: Map.put(opts.request, "expected_generation", 2)}
    assert {:error, :managed_normalization_refused} = run.(opts)

    assert {:ok, %{"generation" => 2, "floor" => 2, "operations" => 2, "records" => 1}} =
             Collection.execute(root, namespace, %{"op" => "status"}, Ipse.Usage.id())
  end
end
