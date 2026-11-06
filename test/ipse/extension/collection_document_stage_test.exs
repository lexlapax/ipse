defmodule Ipse.Extension.Collection.DocumentStageTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}
  alias Ipse.Extension.Collection.{DocumentStage, Profile}

  setup do
    native_tmp = System.get_env("IPSE_DOCUMENT_NATIVE_TMPDIR") || System.tmp_dir!()
    directory = Path.join(native_tmp, "ipse-document-stage-" <> Usage.id())
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      root: Path.join(directory, "collections"),
      ns: Ipse.Extension.CollectionStore.namespace(JSON.sha256("project")),
      owner: %{
        "project_id" => JSON.sha256("project"),
        "identity_sha256" => JSON.sha256("identity"),
        "session_id" => Usage.id(),
        "invocation_id" => Usage.id()
      }
    }
  end

  defp execute(c, request, id \\ Usage.id()),
    do: DocumentStage.execute(c.root, c.ns, request, id, c.owner)

  defp generation(c) do
    {:ok, s} = execute(c, %{"op" => "snapshot"})
    s["generation"]
  end

  defp call(c, request), do: execute(c, Map.put(request, "generation", generation(c)))

  defp open(c, bytes, slot, epoch, revision \\ 0) do
    call(c, %{
      "op" => "value.open",
      "slot" => slot,
      "epoch" => epoch,
      "key" => "packed.block",
      "expected_revision" => revision,
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes)
    })
  end

  defp stage(c, bytes, slot, epoch, revision \\ 0) do
    assert {:ok, _} = open(c, bytes, slot, epoch, revision)

    for {part, index} <- Enum.with_index(chunks(bytes)) do
      request = %{
        "op" => "value.append",
        "slot" => slot,
        "epoch" => epoch,
        "offset" => index * 6144,
        "data" => part
      }

      assert DocumentStage.request?(Map.put(request, "generation", generation(c)))
      assert {:ok, _} = call(c, request)
    end

    assert {:ok, _} = call(c, %{"op" => "value.seal", "slot" => slot, "epoch" => epoch})
  end

  defp chunks(bytes) do
    Stream.unfold(bytes, fn
      "" ->
        nil

      rest ->
        n = min(byte_size(rest), 6144)

        n =
          if String.valid?(binary_part(rest, 0, n)),
            do: n,
            else: Enum.find((n - 1)..max(n - 3, 0)//-1, &String.valid?(binary_part(rest, 0, &1)))

        {binary_part(rest, 0, n), binary_part(rest, n, byte_size(rest) - n)}
    end)
    |> Enum.to_list()
  end

  defp get(c, key),
    do:
      Collection.execute_profile(
        c.root,
        c.ns,
        %{"op" => "get", "key" => key},
        Usage.id(),
        Profile.documents()
      )

  defp inline(body, key, revision \\ 0) do
    %{
      "op" => "value.put_inline",
      "key" => key,
      "expected_revision" => revision,
      "data" => body,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body)
    }
  end

  @tag :document_layout_native
  test "layout authenticates original physical parts independently of logical read slices", c do
    body = Jason.encode!(%{"text" => String.duplicate("Résumé 🌌 ", 80)})
    {first, second} = String.split_at(body, 17)
    large = Jason.encode!(%{"paragraphs" => List.duplicate(String.duplicate("🌌", 1000), 10)})
    points = String.codepoints(large)
    ten = points |> Enum.chunk_every(div(length(points) + 9, 10)) |> Enum.map(&Enum.join/1)
    assert length(ten) == 10

    packed = fn bytes, parts ->
      %{
        "version" => 1,
        "kind" => "document_value",
        "byte_count" => byte_size(bytes),
        "sha256" => JSON.sha256(bytes),
        "parts" => parts
      }
    end

    values = %{
      "layout.one" => packed.(body, [body]),
      "layout.two" => packed.(body, [first, second]),
      "layout.ten" => packed.(large, ten),
      "layout.other" => %{"v" => 1},
      "layout.invalid" => packed.("broken", ["broken"]),
      "host.stage.0.ready" => packed.(body, [body])
    }

    assert {:ok, seeded} =
             Collection.execute_profile(
               c.root,
               c.ns,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" =>
                   Enum.map(values, fn {key, value} ->
                     %{"key" => key, "value" => value, "expected_revision" => 0}
                   end)
               },
               Usage.id(),
               Profile.documents()
             )

    pointer = Path.join([c.root, c.ns, "root.json"])
    before = File.read!(pointer)

    layouts =
      for key <- ~w(layout.one layout.two layout.ten), into: %{} do
        assert {:ok, result} = call(c, %{"op" => "value.layout", "key" => key})
        layout = result["layout"]
        value = values[key]
        physical = Ipse.Extension.Collection.Migration.encode(value)
        assert layout["record_sha256"] == JSON.sha256(physical)
        assert layout["record_bytes"] == byte_size(physical)
        assert layout["sha256"] == value["sha256"] and layout["byte_count"] == value["byte_count"]
        assert layout["recipe"] == "document_packed_layout_v1" and layout["version"] === 1

        {expected, _} =
          Enum.map_reduce(value["parts"], 0, fn part, offset ->
            {%{
               "offset" => offset,
               "byte_count" => byte_size(part),
               "sha256" => JSON.sha256(part)
             }, offset + byte_size(part)}
          end)

        assert layout["parts"] === expected
        assert byte_size(Jason.encode!(result)) <= 4096
        assert {:ok, page} = call(c, %{"op" => "value.read", "key" => key, "offset" => 0})
        assert page["sha256"] == layout["sha256"]
        {key, layout}
      end

    assert layouts["layout.one"]["sha256"] == layouts["layout.two"]["sha256"]
    refute layouts["layout.one"]["record_sha256"] == layouts["layout.two"]["record_sha256"]

    assert length(layouts["layout.one"]["parts"]) == 1 and
             length(layouts["layout.two"]["parts"]) == 2

    for key <- ~w(layout.one layout.two) do
      assert {:ok, %{"data" => ^body, "next" => nil}} =
               call(c, %{"op" => "value.read", "key" => key, "offset" => 0})
    end

    assert {:ok, %{"layout" => nil}} = call(c, %{"op" => "value.layout", "key" => "absent"})
    foreign_owner = Map.put(c.owner, "project_id", JSON.sha256("foreign layout project"))

    foreign = %{
      c
      | ns: CollectionStore.namespace(foreign_owner["project_id"]),
        owner: foreign_owner
    }

    assert {:ok, %{"layout" => nil}} =
             call(foreign, %{"op" => "value.layout", "key" => "layout.one"})

    for key <- ~w(layout.other layout.invalid host.stage.0.ready) do
      assert {:error, :document_store_refused} = call(c, %{"op" => "value.layout", "key" => key})
    end

    assert {:error, :document_store_refused} =
             execute(c, %{
               "op" => "value.layout",
               "key" => "layout.one",
               "generation" => seeded["generation"] - 1
             })

    assert File.read!(pointer) == before and generation(c) == seeded["generation"]

    object =
      Path.join([c.root, c.ns, "objects", layouts["layout.one"]["record_sha256"] <> ".json"])

    File.write!(object, "{}")

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.layout", "key" => "layout.one"})

    assert File.read!(pointer) == before and generation(c) == seeded["generation"]
    legacy = %{c | ns: JSON.sha256("legacy layout namespace")}

    assert {:ok, _} =
             Collection.execute(
               legacy.root,
               legacy.ns,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => "legacy", "expected_revision" => 0, "value" => %{"v" => 1}}
                 ]
               },
               Usage.id()
             )

    assert {:error, :document_store_refused} =
             execute(legacy, %{"op" => "value.layout", "key" => "legacy", "generation" => 1})
  end

  @tag :document_layout_protocol
  test "layout requests and maximum typed receipts keep SDK limits and reject forged part progress",
       c do
    alias Ipse.Extension.CollectionStore
    maximum = 9_007_199_254_740_991
    key = String.duplicate("a", 96)

    request = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => %{"op" => "value.layout", "key" => key, "generation" => maximum}
    }

    assert CollectionStore.validate(request) == :ok
    refute CollectionStore.mutating?(request)

    parts =
      for n <- 0..9,
          do: %{"offset" => n * 6144, "byte_count" => 6144, "sha256" => String.duplicate("f", 64)}

    layout = %{
      "version" => 1,
      "recipe" => "document_packed_layout_v1",
      "revision" => maximum,
      "record_sha256" => String.duplicate("d", 64),
      "record_bytes" => 65_536,
      "sha256" => String.duplicate("e", 64),
      "byte_count" => 61_440,
      "parts" => parts
    }

    result = %{
      "version" => 3,
      "project" => c.ns,
      "generation" => maximum,
      "floor" => maximum,
      "floor_anchor" => Usage.id(),
      "key" => key,
      "layout" => layout
    }

    id = Usage.id()

    wrap = fn result ->
      %{
        "version" => 1,
        "operation_id" => id,
        "request_sha256" => JSON.digest([request]),
        "result" => result
      }
    end

    assert CollectionStore.valid_outcome?(request, "ok", wrap.(result), id)
    outcome = %{"status" => "ok", "value" => wrap.(result)}

    payload = %{
      "api_version" => 1,
      "invocation_id" => Usage.id(),
      "operation_id" => id,
      "step" => 528,
      "outcome" => outcome
    }

    assert :ok = Ipse.Extension.validate(payload)
    frame = %{"protocol" => 1, "id" => maximum, "stage" => "host.actions", "payload" => payload}
    assert byte_size(Jason.encode!(frame)) <= 16_384

    for malformed <- [
          Map.put(layout, "version", 1.0),
          Map.put(layout, "parts", tl(parts)),
          Map.put(layout, "parts", Enum.reverse(parts)),
          put_in(layout, ["parts", Access.at(0), "offset"], 1),
          Map.put(layout, "byte_count", 61_439),
          Map.put(layout, "owner", "forged")
        ] do
      refute CollectionStore.valid_outcome?(
               request,
               "ok",
               wrap.(%{result | "layout" => malformed}),
               id
             )
    end

    for invalid <- [
          put_in(request, ["request", "key"], "host.stage.0.ready"),
          put_in(request, ["request", "generation"], 1.0),
          put_in(request, ["request", "profile"], "notes-v1")
        ] do
      refute CollectionStore.validate(invalid) == :ok
    end

    IO.puts(
      "DOCUMENT_LAYOUT_PROTOCOL " <>
        Jason.encode!(%{
          result_bytes: byte_size(Jason.encode!(result)),
          worker_request_bytes: byte_size(Jason.encode!(frame)),
          mutation: false
        })
    )
  end

  @tag :inline_document
  test "inline publication preserves complete original bytes in one bounded native operation",
       c do
    body = "{ \"text\" : \"" <> String.duplicate("x", 8177) <> "\" }"
    assert byte_size(body) == 8192
    assert {:ok, snapshot} = execute(c, %{"op" => "snapshot"})

    assert snapshot["document_store"] == %{
             "version" => 2,
             "inline_bytes" => 8192,
             "write_parts" => 2
           }

    before = snapshot["generation"]
    assert {:ok, receipt} = call(c, inline(body, "inline.exact"))
    assert receipt["generation"] == before + 1
    assert receipt["record"]["sha256"] == JSON.sha256(body)
    assert {:ok, %{"record" => row}} = get(c, "inline.exact")
    assert Enum.join(row["value"]["parts"]) == body
    assert row["value"]["byte_count"] == 8192

    invalid = [
      Map.put(inline(body, "inline.bad"), "byte_count", 8191),
      Map.put(inline(body, "inline.bad"), "sha256", JSON.sha256("forged")),
      Map.put(inline(body, "inline.bad"), "quota", 192 * 1024 * 1024),
      inline("{\"a\":1,\"a\":2}", "inline.bad"),
      inline("{\"x\":\"" <> String.duplicate("x", 8192) <> "\"}", "inline.bad")
    ]

    for request <- invalid do
      refute DocumentStage.request?(Map.put(request, "generation", generation(c)))
      assert {:error, :document_store_refused} = call(c, request)
    end

    assert generation(c) == receipt["generation"]
    assert {:ok, %{"record" => nil}} = get(c, "inline.bad")
  end

  @tag :inline_document
  @tag :document_decision_restoration
  test "inline prepared values remain private until one consuming CAS and retain owner fencing",
       c do
    assert {:ok, old} = call(c, inline("{\"v\":0}", "inline.left"))
    refs = for slot <- 0..1, do: %{"slot" => slot, "epoch" => Usage.id()}

    for {ref, key, revision} <- [
          {Enum.at(refs, 0), "inline.left", old["generation"]},
          {Enum.at(refs, 1), "inline.right", 0}
        ] do
      request = Map.merge(inline("{\"v\":1}", key, revision), ref)
      assert {:ok, receipt} = call(c, %{request | "op" => "value.prepare_inline"})
      assert receipt["stage"]["state"] == "sealed"

      assert {:ok, %{"record" => %{"value" => header}}} =
               get(c, "host.stage.#{ref["slot"]}.header")

      assert header["parts"] == 0
      assert {:ok, %{"record" => nil}} = get(c, "host.stage.#{ref["slot"]}.part.0")
    end

    assert {:ok, %{"record" => left}} = get(c, "inline.left")
    assert Enum.join(left["value"]["parts"]) == "{\"v\":0}"
    assert {:ok, %{"record" => nil}} = get(c, "inline.right")
    alien = put_in(c.owner["session_id"], Usage.id())
    assert {:error, :document_store_refused} = call(alien, %{"op" => "commit", "stages" => refs})
    before = generation(c)
    assert {:ok, receipt} = call(c, %{"op" => "commit", "stages" => refs})
    assert receipt["generation"] == before + 1

    for key <- ["inline.left", "inline.right"] do
      assert {:ok, %{"record" => row}} = get(c, key)
      assert row["revision"] == receipt["generation"]
      assert Enum.join(row["value"]["parts"]) == "{\"v\":1}"
    end

    assert {:error, :document_store_refused} = call(c, %{"op" => "commit", "stages" => refs})
    assert generation(c) == receipt["generation"]
  end

  defp fused(body, ref, offset, data, publish, revision \\ 0) do
    Map.merge(ref, %{
      "op" => "value.write_parts",
      "key" => "packed.block",
      "expected_revision" => revision,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "offset" => offset,
      "data" => data,
      "publish" => publish
    })
  end

  @tag :fused_document
  @tag :fused_document_large
  test "fused parts publish complete original bytes in one CAS per bounded packet", c do
    body =
      "{ \"paragraphs\" : [" <>
        Enum.map_join(1..12, ", ", fn n ->
          Jason.encode!("#{n}:" <> String.duplicate("é", 2500))
        end) <> "] }"

    ref = %{"slot" => 0, "epoch" => Usage.id()}
    before = generation(c)
    packets = chunks(body) |> Enum.chunk_every(2)

    offset =
      Enum.reduce(Enum.with_index(packets), 0, fn {data, i}, offset ->
        request = fused(body, ref, offset, data, true) |> Map.put("generation", generation(c))
        assert DocumentStage.request?(request)

        assert :ok =
                 Ipse.Extension.validate(%{
                   "api_version" => 1,
                   "kind" => "host_call",
                   "request" => %{
                     "op" => "collection.store",
                     "scope" => "project",
                     "request" => request
                   }
                 })

        assert {:ok, receipt} = execute(c, request)
        next = offset + Enum.sum(Enum.map(data, &byte_size/1))
        assert receipt["write"]["offset"] == next

        if i < length(packets) - 1 do
          assert receipt["write"]["state"] == "open"
          assert {:ok, %{"record" => nil}} = get(c, "packed.block")
        else
          assert receipt["write"]["state"] == "published"
          assert receipt["write"]["revision"] == receipt["generation"]
        end

        next
      end)

    assert offset == byte_size(body)
    assert generation(c) == before + length(packets)
    assert {:ok, %{"record" => row}} = get(c, "packed.block")
    assert Enum.join(row["value"]["parts"]) == body
    assert {:ok, %{"record" => nil}} = get(c, "host.stage.0.header")
    for n <- 0..9, do: assert({:ok, %{"record" => nil}} = get(c, "host.stage.0.part.#{n}"))
  end

  @tag :document_deadline_scope
  test "inherited trusted deadlines cannot be cleared or extended and the scope restores exactly",
       c do
    key = {DocumentStage, :publish_before_ms}
    guard_key = {DocumentStage, :publication_guard}
    prior = Process.get(key)
    prior_guard = Process.get(guard_key)
    parent = self()
    tracer = spawn(fn -> deadline_trace(parent) end)
    Code.ensure_loaded!(Collection)
    assert 1 = :erlang.trace_pattern({Collection, :execute_profile_before, 6}, true, [])
    :erlang.trace(self(), true, [:call, :set_on_spawn, {:tracer, tracer}])
    on_exit(fn -> Process.exit(tracer, :kill) end)

    try do
      inherited = System.system_time(:millisecond) + 60_000

      next_request = fn ->
        generation = generation(c)
        Map.put(inline("{\"v\":1}", "inline.nested", generation), "generation", generation)
      end

      Process.put(key, inherited)
      assert {:ok, _} = execute(c, next_request.())
      assert_receive {:deadline_seen, ^inherited}, 1000
      assert Process.get(key) == inherited

      assert {:ok, _} =
               DocumentStage.execute(c.root, c.ns, next_request.(), Usage.id(), c.owner,
                 publish_before_ms: inherited + 60_000
               )

      assert_receive {:deadline_seen, ^inherited}, 1000
      earlier = inherited - 30_000

      assert {:ok, _} =
               DocumentStage.execute(c.root, c.ns, next_request.(), Usage.id(), c.owner,
                 publish_before_ms: earlier
               )

      assert_receive {:deadline_seen, ^earlier}, 1000
      assert Process.get(key) == inherited
      blocked = next_request.()
      Process.put(key, System.system_time(:millisecond) - 1)
      assert {:error, :document_store_refused} = execute(c, blocked)
      Process.put(key, :invalid)
      assert {:error, :document_store_refused} = execute(c, blocked)
      Process.put(key, inherited)
      inherited_guard = fn _, _ -> :ok end
      Process.put(guard_key, inherited_guard)
      assert {:error, :document_store_refused} = execute(c, blocked)
      assert Process.get(guard_key) === inherited_guard
      Process.delete(guard_key)
      refute_receive {:deadline_seen, _}, 30
      Process.delete(key)

      assert {:ok, _} =
               DocumentStage.execute(c.root, c.ns, next_request.(), Usage.id(), c.owner,
                 publish_before_ms: inherited
               )

      assert_receive {:deadline_seen, ^inherited}, 1000
      assert Process.get(key) == nil
      assert {:ok, %{"record" => row}} = get(c, "inline.nested")
      assert Enum.join(row["value"]["parts"]) == "{\"v\":1}"
      assert {:ok, _} = execute(c, next_request.())
    after
      :erlang.trace(self(), false, [:call, :set_on_spawn])
      :erlang.trace_pattern({Collection, :execute_profile_before, 6}, false, [])
      if is_nil(prior), do: Process.delete(key), else: Process.put(key, prior)

      if is_nil(prior_guard),
        do: Process.delete(guard_key),
        else: Process.put(guard_key, prior_guard)

      send(tracer, :stop)
    end
  end

  defp deadline_trace(parent) do
    receive do
      {:trace, _, :call, {Collection, :execute_profile_before, args}} ->
        send(parent, {:deadline_seen, List.last(args)})
        deadline_trace(parent)

      :stop ->
        :ok

      _ ->
        deadline_trace(parent)
    end
  end

  @tag :fused_document
  test "fused preparation fences owner, mode, offsets and final digest until one consuming CAS",
       c do
    body = Jason.encode!(%{"paragraphs" => List.duplicate(String.duplicate("x", 4096), 4)})
    ref = %{"slot" => 1, "epoch" => Usage.id()}
    [first, last] = chunks(body) |> Enum.chunk_every(2)
    assert {:ok, _} = call(c, fused(body, ref, 0, first, false))
    offset = Enum.sum(Enum.map(first, &byte_size/1))
    before = generation(c)

    for request <- [
          fused(body, ref, offset + 1, last, false),
          fused(body, ref, offset, last, true),
          fused(body, %{ref | "epoch" => Usage.id()}, offset, last, false),
          fused(body, ref, offset, Enum.map(last, &String.replace(&1, "x", "y")), false),
          Map.merge(ref, %{"op" => "value.seal"})
        ] do
      assert {:error, :document_store_refused} = call(c, request)
    end

    alien = put_in(c.owner["session_id"], Usage.id())
    assert {:error, :document_store_refused} = call(alien, fused(body, ref, offset, last, false))
    assert generation(c) == before
    assert {:ok, receipt} = call(c, fused(body, ref, offset, last, false))
    assert receipt["write"]["state"] == "sealed"
    assert {:ok, %{"record" => nil}} = get(c, "packed.block")
    assert {:ok, inspected} = call(c, Map.merge(ref, %{"op" => "stage.inspect"}))
    assert inspected["stage"]["write_publish"] === false
    assert {:ok, _} = call(c, %{"op" => "commit", "stages" => [ref]})
    assert {:ok, %{"record" => row}} = get(c, "packed.block")
    assert Enum.join(row["value"]["parts"]) == body
    assert {:error, :document_store_refused} = call(c, fused(body, ref, offset, last, false))
  end

  @tag :fused_document
  test "fused closed requests and expired stages refuse without publication while abort stays available",
       c do
    invalid = "{\"a\":1,\"a\":2}"
    ref = %{"slot" => 2, "epoch" => Usage.id()}
    before = generation(c)
    assert {:error, :document_store_refused} = call(c, fused(invalid, ref, 0, [invalid], true))
    assert generation(c) == before
    body = Jason.encode!(%{"paragraphs" => List.duplicate(String.duplicate("x", 4096), 4)})
    [first, last] = chunks(body) |> Enum.chunk_every(2)
    request = fused(body, ref, 0, first, true)

    for bad <- [
          Map.put(request, "data", List.duplicate("x", 3)),
          Map.put(request, "data", [String.duplicate("x", 6145)]),
          Map.put(request, "quota", 1)
        ] do
      refute DocumentStage.request?(Map.put(bad, "generation", before))
      assert {:error, :document_store_refused} = call(c, bad)
    end

    assert {:ok, _} = call(c, request)
    assert {:ok, %{"record" => header}} = get(c, "host.stage.2.header")

    assert {:ok, _} =
             Collection.execute_profile(
               c.root,
               c.ns,
               %{
                 "op" => "commit",
                 "expected_generation" => generation(c),
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => "host.stage.2.header",
                     "expected_revision" => header["revision"],
                     "value" => Map.put(header["value"], "expires_at_ms", 0)
                   }
                 ]
               },
               Usage.id(),
               Profile.documents()
             )

    before = generation(c)
    offset = Enum.sum(Enum.map(first, &byte_size/1))
    assert {:error, :document_store_refused} = call(c, fused(body, ref, offset, last, true))
    assert generation(c) == before
    assert {:ok, _} = call(c, Map.merge(ref, %{"op" => "value.abort"}))
    assert {:error, :document_store_refused} = call(c, fused(body, ref, offset, last, true))
    assert {:ok, %{"record" => nil}} = get(c, "packed.block")
  end

  @tag :inline_document
  @tag :inline_deadline
  test "trusted deadline refuses before publication and does not leak to a later ordinary call",
       c do
    request = Map.put(inline("{\"v\":1}", "inline.deadline"), "generation", generation(c))
    deadline = System.system_time(:millisecond) - 1

    assert {:error, :document_store_refused} =
             DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner,
               publish_before_ms: deadline
             )

    assert {:ok, %{"record" => nil}} = get(c, "inline.deadline")

    before = generation(c)

    assert {:ok, _} =
             DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner,
               publish_before_ms: System.system_time(:millisecond) + 30_000
             )

    assert generation(c) == before + 1
    assert {:ok, %{"record" => row}} = get(c, "inline.deadline")
    assert Enum.join(row["value"]["parts"]) == "{\"v\":1}"
    assert Process.get({DocumentStage, :publish_before_ms}) == nil
    assert {:ok, _} = call(c, inline("{\"v\":2}", "inline.ordinary"))

    assert {:error, :document_store_refused} =
             DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner, quota: 1)
  end

  @tag :document_decision_expiry
  test "expiry while the synced pointer is held refuses selection and preserves the old value",
       c do
    assert {:ok, old} = call(c, inline("{\"v\":0}", "inline.staged"))
    pointer = Path.join([c.root, c.ns, "root.json"])
    before = File.read!(pointer)

    request =
      inline("{\"v\":1}", "inline.staged", old["generation"])
      |> Map.put("generation", old["generation"])

    observer = self()
    token = make_ref()
    handler = "document-decision-expiry-" <> Usage.id()
    deadline = System.system_time(:millisecond) + 1000

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        fn _, _, _, _ ->
          if Process.get({Collection, :switch_deadline}) == deadline do
            send(observer, {:document_pointer_staged, self(), System.system_time(:millisecond)})

            receive do
              {:release_document_pointer, ^token} -> :ok
            after
              5000 -> :ok
            end
          end
        end,
        nil
      )

    task =
      Task.async(fn ->
        DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner,
          publish_before_ms: deadline
        )
      end)

    try do
      assert_receive {:document_pointer_staged, peer, staged_at}, 3000
      assert staged_at < deadline
      assert File.read!(pointer) == before
      Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
      send(peer, {:release_document_pointer, token})
      assert {:unknown, :collection_publication_unconfirmed} = Task.await(task, 5000)
      assert File.read!(pointer) == before
      assert {:ok, %{"record" => row}} = get(c, "inline.staged")
      assert Enum.join(row["value"]["parts"]) == "{\"v\":0}"
    after
      :telemetry.detach(handler)
      Task.shutdown(task, :brutal_kill)
    end
  end

  @tag :document_decision_restoration
  test "large value crosses bounded parts, remains unselected until one consuming CAS and slots reuse",
       c do
    body =
      Jason.encode!(%{"paragraphs" => for(n <- 1..9, do: "#{n}:" <> String.duplicate("x", 4096))})

    assert byte_size(body) > 32_768
    epoch = Usage.id()
    stage(c, body, 0, epoch)
    assert {:ok, %{"record" => nil}} = get(c, "packed.block")

    assert {:ok, %{"record" => %{"value" => %{"state" => "sealed"}}}} =
             get(c, "host.stage.0.header")

    for n <- 0..6, do: assert({:ok, %{"record" => nil}} = get(c, "host.stage.0.part.#{n}"))

    request = %{
      "op" => "commit",
      "stages" => [%{"slot" => 0, "epoch" => epoch}],
      "generation" => generation(c)
    }

    operation = Usage.id()
    assert {:ok, receipt} = execute(c, request, operation)
    assert {:ok, %{"record" => nil}} = get(c, "host.stage.0.header")
    assert {:ok, %{"record" => nil}} = get(c, "host.stage.0.ready")
    assert {:ok, %{"record" => row}} = get(c, "packed.block")
    assert row["revision"] == receipt["generation"]
    assert {:error, :document_store_refused} = execute(c, request, operation)

    result =
      Stream.unfold(0, fn
        nil ->
          nil

        offset ->
          assert {:ok, page} =
                   call(c, %{"op" => "value.read", "key" => "packed.block", "offset" => offset})

          assert page["sha256"] == JSON.sha256(body)
          assert Ipse.Extension.validate(page) == :ok
          {page["data"], page["next"]}
      end)
      |> Enum.join()

    assert result == body

    next = Jason.encode!(%{"text" => "replacement"})
    next_epoch = Usage.id()
    stage(c, next, 0, next_epoch, receipt["generation"])

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.abort", "slot" => 0, "epoch" => epoch})

    assert {:ok, %{"record" => old}} = get(c, "packed.block")
    assert old["revision"] == receipt["generation"]

    assert {:ok, replacement} =
             call(c, %{"op" => "commit", "stages" => [%{"slot" => 0, "epoch" => next_epoch}]})

    assert generation(c) > receipt["generation"]
    assert {:ok, %{"record" => current}} = get(c, "packed.block")
    assert current["revision"] == replacement["generation"]
  end

  test "offset, changed owner, malformed body and digest refuse without selected publication",
       c do
    body = Jason.encode!(%{"text" => "exact"})
    epoch = Usage.id()
    assert {:ok, _} = open(c, body, 1, epoch)
    before = generation(c)

    append = %{
      "op" => "value.append",
      "slot" => 1,
      "epoch" => epoch,
      "offset" => 1,
      "data" => body
    }

    assert {:error, :document_store_refused} = call(c, append)
    alien = put_in(c.owner["identity_sha256"], JSON.sha256("other"))
    assert {:error, :document_store_refused} = call(alien, %{append | "offset" => 0})
    assert generation(c) == before

    assert {:ok, _} =
             call(c, %{append | "offset" => 0, "data" => String.replace(body, "exact", "forge")})

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.seal", "slot" => 1, "epoch" => epoch})

    assert {:ok, %{"record" => nil}} = get(c, "packed.block")
    assert {:ok, _} = call(c, %{"op" => "value.abort", "slot" => 1, "epoch" => epoch})
    assert {:ok, %{"record" => nil}} = get(c, "host.stage.1.part.0")

    invalid = "{\"a\":1,\"a\":2}"
    invalid_epoch = Usage.id()
    assert {:ok, _} = open(c, invalid, 1, invalid_epoch)

    assert {:ok, _} =
             call(c, %{
               "op" => "value.append",
               "slot" => 1,
               "epoch" => invalid_epoch,
               "offset" => 0,
               "data" => invalid
             })

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.seal", "slot" => 1, "epoch" => invalid_epoch})

    assert {:ok, %{"record" => nil}} = get(c, "packed.block")
  end

  test "closed requests retain generic SDK bounds and fixed slot geometry", c do
    base = %{
      "op" => "value.open",
      "slot" => 0,
      "epoch" => Usage.id(),
      "key" => "packed.block",
      "expected_revision" => 0,
      "byte_count" => 2,
      "sha256" => JSON.sha256("{}"),
      "generation" => 0
    }

    assert DocumentStage.request?(base)

    for invalid <- [
          Map.put(base, "quota", 192 * 1024 * 1024),
          Map.put(base, "slot", 16),
          Map.put(base, "key", "host.stage.0.header"),
          Map.put(base, "byte_count", 61_441)
        ] do
      refute DocumentStage.request?(invalid)
      assert {:error, :document_store_refused} = execute(c, invalid)
    end

    refute DocumentStage.request?(%{
             "op" => "value.append",
             "slot" => 0,
             "epoch" => Usage.id(),
             "offset" => 0,
             "data" => String.duplicate(<<1>>, 6144),
             "generation" => 0
           })
  end

  @tag :document_decision_restoration
  test "expired slots refuse continuation but explicit admitted reclaim releases every retained part",
       c do
    body = Jason.encode!(%{"text" => "retained"})
    epoch = Usage.id()
    assert {:ok, _} = open(c, body, 2, epoch)

    assert {:ok, _} =
             call(c, %{
               "op" => "value.append",
               "slot" => 2,
               "epoch" => epoch,
               "offset" => 0,
               "data" => body
             })

    assert {:ok, %{"record" => header}} = get(c, "host.stage.2.header")
    assert header["value"]["expires_at_ms"] > System.system_time(:millisecond)

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.reclaim", "slot" => 2, "epoch" => epoch})

    assert {:ok, _} =
             Collection.execute_profile(
               c.root,
               c.ns,
               %{
                 "op" => "commit",
                 "expected_generation" => generation(c),
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => header["key"],
                     "expected_revision" => header["revision"],
                     "value" => Map.put(header["value"], "expires_at_ms", 0)
                   }
                 ]
               },
               Usage.id(),
               Profile.documents()
             )

    before = generation(c)

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.seal", "slot" => 2, "epoch" => epoch})

    assert generation(c) == before
    assert {:ok, listed} = execute(c, %{"op" => "stage.list"})
    assert [%{"slot" => 2, "epoch" => ^epoch, "expires_at_ms" => 0}] = listed["stages"]
    fresh = %{c | owner: %{c.owner | "session_id" => Usage.id(), "invocation_id" => Usage.id()}}
    assert {:ok, _} = call(fresh, %{"op" => "value.reclaim", "slot" => 2, "epoch" => epoch})
    assert {:ok, %{"record" => nil}} = get(c, "host.stage.2.header")
    assert {:ok, %{"record" => nil}} = get(c, "host.stage.2.part.0")
    next_epoch = Usage.id()
    assert {:ok, _} = open(fresh, body, 2, next_epoch)

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "value.abort", "slot" => 2, "epoch" => epoch})

    assert {:ok, _} = call(fresh, %{"op" => "value.abort", "slot" => 2, "epoch" => next_epoch})
  end

  @tag :workspace_publication_guard
  test "the trusted publication callback gates inline, fused and staged commits", c do
    body = Jason.encode!(%{"kind" => "synthetic_source_head"})
    observer = self()

    guard = fn changes, _read ->
      send(observer, {:publication_guard, Enum.map(changes, & &1["key"])})
      {:error, :document_store_refused}
    end

    before = generation(c)
    request = inline(body, "source.fixture.inline") |> Map.put("generation", before)

    assert {:error, :document_store_refused} =
             DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner,
               publication_guard: guard
             )

    assert_receive {:publication_guard, ["source.fixture.inline"]}
    assert generation(c) == before
    assert {:ok, %{"record" => nil}} = get(c, "source.fixture.inline")

    ref = %{"slot" => 0, "epoch" => Usage.id()}

    request =
      fused(body, ref, 0, [body], true)
      |> Map.put("key", "source.fixture.parts")
      |> Map.put("generation", before)

    assert {:error, :document_store_refused} =
             DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner,
               publication_guard: guard
             )

    assert_receive {:publication_guard, keys}
    assert "source.fixture.parts" in keys
    assert generation(c) == before
    assert {:ok, %{"record" => nil}} = get(c, "source.fixture.parts")

    epoch = Usage.id()
    stage(c, body, 1, epoch)
    staged_generation = generation(c)

    request = %{
      "op" => "commit",
      "stages" => [%{"slot" => 1, "epoch" => epoch}],
      "generation" => staged_generation
    }

    assert {:error, :document_store_refused} =
             DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner,
               publication_guard: guard
             )

    assert_receive {:publication_guard, keys}
    assert "packed.block" in keys
    assert generation(c) == staged_generation
    assert {:ok, %{"record" => nil}} = get(c, "packed.block")
  end
end
