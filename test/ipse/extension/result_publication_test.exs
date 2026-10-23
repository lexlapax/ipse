defmodule Ipse.Extension.ResultPublicationTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.ResultPublication
  alias Ipse.Extension.ResultPublication.Output
  alias Ipse.Extension.{Catalog, Config, Registry, Artifact, Worker}

  @invocation String.duplicate("a", 32)
  @output String.duplicate("b", 64)

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-result-publication-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    capabilities =
      ~w(invoke.tool invoke.command invoke.service event.job transform.prompt host.actions invoke.result.pages)

    descriptor = %{
      "id" => "fixture",
      "description" => "Synthetic publication fixture",
      "arguments_schema" => %{"type" => "object"},
      "result_schema" => %{"type" => "object"}
    }

    exports = %{
      "version" => 1,
      "tools" => [descriptor],
      "commands" => [descriptor],
      "services" => [descriptor],
      "jobs" => [descriptor]
    }

    subscriptions = [
      %{
        "id" => "fixture",
        "handler" => "fixture",
        "event" => "prompt.effective_committed",
        "event_version" => 1,
        "view" => "metadata",
        "mode" => "job",
        "schedule" => "before_request",
        "required" => true
      }
    ]

    artifacts =
      for sdk <- [1, 2], into: %{} do
        module = "Publication.Fixture#{sdk}_#{System.unique_integer([:positive])}"
        source = Path.join(root, "source#{sdk}")
        File.mkdir_p!(Path.join(source, "ebin"))
        caps = if sdk == 2, do: capabilities, else: capabilities -- ["invoke.result.pages"]

        description = %{
          "sdk" => sdk,
          "capabilities" => caps,
          "exports" => exports,
          "subscriptions" => subscriptions
        }

        fixture = Path.join(root, "fixture#{sdk}.ex")

        File.write!(fixture, """
        defmodule #{module} do
          @behaviour Ipse.Extension
          alias Ipse.Extension.ResultPublication
          def describe, do: #{inspect(description, limit: :infinity)}
          def init(options) do
            if options["mode"] == "wrong_description", do: wire(1, Map.put(describe(), "sdk", #{if sdk == 1, do: 2, else: 1}))
            {:ok, options}
          end
          def handle(stage, payload, state) do
            mode = state["mode"]
            cond do
              mode == "inline" ->
                {:ok, reply} = ResultPublication.prepare(%{"ok" => true})
                {:ok, reply, state}
              mode == "actions" and stage != "host.actions" ->
                {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "fixture"}}, state}
              mode in ["raw_bad_offset", "raw_bad_hash", "raw_bad_count", "raw_bad_eof", "raw_bad_full", "raw_offer"] ->
                bytes = if mode == "raw_bad_full", do: "{}", else: Jason.encode!(%{"items" => List.duplicate(String.duplicate("x", 8192), 3)})
                offer = %{"api_version" => 1, "kind" => "result_producer", "output" =>
                  %{"version" => 1, "byte_count" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}}
                offer = if mode == "raw_bad_count", do: put_in(offer, ["output", "byte_count"], 0), else: offer
                offer = if mode == "raw_bad_full", do: put_in(offer, ["output", "sha256"], String.duplicate("0", 64)), else: offer
                wire(2, offer)
                <<size::32>> = IO.binread(:stdio, 4)
                request = Jason.decode!(IO.binread(:stdio, size))
                size = min(4096, byte_size(bytes))
                chunk = binary_part(bytes, 0, size)
                response = %{"api_version" => 1, "kind" => "result_chunk", "output" =>
                  %{"version" => 1, "output_id" => request["payload"]["output_id"], "offset" => 0,
                    "next" => size, "complete" => size == byte_size(bytes), "data_base64" => Base.encode64(chunk),
                    "sha256" => Ipse.JSON.sha256(chunk)}}
                response = case mode do
                  "raw_bad_offset" -> put_in(response, ["output", "offset"], 1)
                  "raw_bad_hash" -> put_in(response, ["output", "sha256"], String.duplicate("0", 64))
                  "raw_bad_eof" -> put_in(response, ["output", "complete"], true)
                  _ -> response
                end
                wire(request["id"], response)
                Process.sleep(:infinity)
              true ->
                {:ok, reply} = ResultPublication.prepare(%{"items" => List.duplicate(String.duplicate("雪", 2730), 3)})
                {:ok, reply, Map.put(state, "ignored_domain_state", payload)}
            end
          end
          defp wire(id, result) do
            bytes = Jason.encode!(%{"protocol" => 1, "id" => id, "result" => result})
            IO.binwrite(:stdio, <<byte_size(bytes)::32, bytes::binary>>)
          end
        end
        """)

        {output, status} =
          System.cmd(
            System.find_executable("elixirc"),
            ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(source, "ebin"), fixture],
            stderr_to_stdout: true
          )

        assert status == 0, output
        File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

        manifest = %{
          "format" => 1,
          "id" => "publication/fixture#{sdk}",
          "version" => "0.1.0",
          "sdk" => sdk,
          "protocol" => 1,
          "backend" => "elixir_worker",
          "entrypoint" => module,
          "license_file" => "LICENSE",
          "capabilities" => caps,
          "exports" => exports,
          "subscriptions" => subscriptions,
          "options_schema" => %{
            "type" => "object",
            "properties" => %{"mode" => %{"type" => "string"}},
            "additionalProperties" => false
          },
          "runtime" => %{
            "elixir" => ">= 1.18.0",
            "otp" => [String.to_integer(System.otp_release())],
            "platforms" => [to_string(:erlang.system_info(:system_architecture))]
          },
          "files" =>
            for path <- ["LICENSE", "ebin/Elixir.#{module}.beam"] do
              bytes = File.read!(Path.join(source, path))
              %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
            end
        }

        File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
        assert {:ok, _} = Artifact.decode(Jason.encode!(manifest))
        store = Path.join([root, "home#{sdk}", "extensions", "artifacts"])
        assert {:ok, artifact} = Artifact.import(source, store)

        {sdk,
         %{
           store: store,
           digest: artifact.digest,
           manifest: manifest,
           home: Path.join(root, "home#{sdk}")
         }}
      end

    %{artifacts: artifacts}
  end

  defp ready(c, sdk \\ 2, options \\ %{}) do
    artifact = c.artifacts[sdk]

    assert {:ok, worker} =
             Worker.start(
               owner: self(),
               store: artifact.store,
               digest: artifact.digest,
               trusted: artifact.digest,
               options: options
             )

    assert {:ok, description} = Worker.call(worker, "initialize", options)
    assert description["sdk"] == sdk
    worker
  end

  defp request(offset, changes \\ %{}),
    do:
      Map.merge(
        %{
          "api_version" => 1,
          "invocation_id" => @invocation,
          "output_id" => @output,
          "offset" => offset,
          "limit" => 4096
        },
        changes
      )

  defp drain(output, producer, chunks \\ []) do
    payload = request(producer.offset)
    assert {:ok, response, next} = ResultPublication.chunk(output, producer, payload)
    assert {:ok, independently_checked} = ResultPublication.accept(producer, payload, response)
    assert Map.delete(independently_checked, :hash_context) == Map.delete(next, :hash_context)
    assert byte_size(Jason.encode!(response)) <= 12_000
    assert :ok = Ipse.Extension.validate(response)
    chunk = Base.decode64!(response["output"]["data_base64"])

    if next.complete,
      do: IO.iodata_to_binary(Enum.reverse([chunk | chunks])),
      else: drain(output, next, [chunk | chunks])
  end

  test "preparation retains small inline wrappers and freezes larger aggregate values" do
    assert {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"ok" => true}}} =
             ResultPublication.prepare(%{"ok" => true})

    for value <- [
          %{"items" => Enum.to_list(1..129)},
          %{"items" => List.duplicate(String.duplicate("x", 8192), 2)}
        ] do
      assert {:ok, %Output{} = output} = ResultPublication.prepare(value)
      assert output.byte_count == byte_size(output.bytes)
      assert output.sha256 == Ipse.JSON.sha256(output.bytes)

      assert {:ok, ^value} =
               Ipse.Extension.ResultDocument.decode(output.bytes, %{"type" => "object"})
    end

    for invalid <- [
          [],
          %{"private" => self()},
          %{"huge" => String.duplicate("x", 8193)},
          %{bad: true}
        ] do
      assert {:error, :invalid_result_document} = ResultPublication.prepare(invalid)
    end
  end

  test "fixed pages retain exact near-cap bytes across JSON and UTF8 boundaries" do
    prefix = %{"items" => List.duplicate(String.duplicate("x", 8192), 511), "pad" => ""}
    size = byte_size(Jason.encode!(prefix))
    value = Map.put(prefix, "pad", String.duplicate("y", 4 * 1024 * 1024 - size))
    assert {:ok, %Output{} = output} = ResultPublication.prepare(value)
    assert output.byte_count == 4 * 1024 * 1024
    assert {:ok, offer} = ResultPublication.offer(output)
    assert {:ok, producer} = ResultPublication.open(offer, @invocation)
    assert drain(output, producer) == output.bytes
  end

  test "offers and request identity are closed, bounded and fixed-stride" do
    assert {:ok, output} = ResultPublication.prepare(%{"items" => Enum.to_list(1..129)})
    assert {:ok, offer} = ResultPublication.offer(output)
    assert {:ok, producer} = ResultPublication.open(offer, @invocation)

    for invalid <- [
          Map.put(offer, "extra", true),
          put_in(offer, ["output", "byte_count"], 0),
          put_in(offer, ["output", "byte_count"], 4 * 1024 * 1024 + 1),
          put_in(offer, ["output", "sha256"], "invalid")
        ] do
      assert {:error, :invalid_result_document} = ResultPublication.open(invalid, @invocation)
    end

    for changes <- [
          %{"offset" => 1},
          %{"limit" => 1},
          %{"invocation_id" => String.duplicate("c", 32)},
          %{"output_id" => "bad"},
          %{"extra" => true},
          %{"api_version" => 2}
        ] do
      assert {:error, :invalid_result_document} =
               ResultPublication.request(producer, request(0, changes))
    end
  end

  test "fragment validation rejects changed IDs, hashes, offsets, count, EOF and later reads" do
    assert {:ok, output} =
             ResultPublication.prepare(%{
               "items" => List.duplicate(String.duplicate("x", 8192), 2)
             })

    assert {:ok, offer} = ResultPublication.offer(output)
    assert {:ok, producer} = ResultPublication.open(offer, @invocation)
    payload = request(0)
    assert {:ok, response, next} = ResultPublication.chunk(output, producer, payload)

    for changes <- [
          %{"output_id" => String.duplicate("c", 64)},
          %{"offset" => 1},
          %{"next" => 4095},
          %{"complete" => true},
          %{"sha256" => String.duplicate("0", 64)},
          %{"version" => 2},
          %{"extra" => true},
          %{"data_base64" => Base.encode64("short")}
        ] do
      assert {:error, :invalid_result_document} =
               ResultPublication.accept(
                 producer,
                 payload,
                 Map.update!(response, "output", &Map.merge(&1, changes))
               )
    end

    assert {:error, :invalid_result_document} =
             ResultPublication.request(
               next,
               request(4096, %{"output_id" => String.duplicate("c", 64)})
             )

    assert {:error, :invalid_result_document} = ResultPublication.request(next, payload)

    small = %Output{bytes: "{}", byte_count: 2, sha256: Ipse.JSON.sha256("{}")}
    assert {:ok, small_offer} = ResultPublication.offer(small)
    assert {:ok, small_state} = ResultPublication.open(small_offer, @invocation)
    assert {:ok, final, ended} = ResultPublication.chunk(small, small_state, payload)
    assert final["output"]["next"] == 2
    assert ended.complete
    assert {:error, :invalid_result_document} = ResultPublication.request(ended, request(2))
    wrong_digest = put_in(small_offer, ["output", "sha256"], String.duplicate("0", 64))
    assert {:ok, wrong_state} = ResultPublication.open(wrong_digest, @invocation)

    assert {:error, :invalid_result_document} =
             ResultPublication.accept(wrong_state, payload, final)
  end

  test "SDK pair validation and exact Registry identity derive from the installed manifest", c do
    artifact = c.artifacts[2]
    assert "invoke.result.pages" in Catalog.capabilities()
    assert Catalog.sdk_capabilities?(2, artifact.manifest["capabilities"])
    refute Catalog.sdk_capabilities?(1, artifact.manifest["capabilities"])

    refute Catalog.sdk_capabilities?(
             2,
             artifact.manifest["capabilities"] -- ["invoke.result.pages"]
           )

    assert {:ok, _} = Artifact.decode(Jason.encode!(artifact.manifest))

    for invalid <- [
          Map.put(artifact.manifest, "sdk", 1),
          Map.update!(artifact.manifest, "capabilities", &(&1 -- ["invoke.result.pages"]))
        ] do
      assert {:error, :invalid_extension_manifest} = Artifact.decode(Jason.encode!(invalid))
    end

    source = %{
      scope: "operator",
      path: "/synthetic/publication.json",
      data: %{
        "extensions" => [
          %{
            "instance" => "fixture",
            "artifact" => artifact.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 0,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => artifact.digest,
            "capabilities" => artifact.manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    assert {:ok, catalog} = Config.resolve([source], [])
    assert {:ok, [entry]} = Registry.prepare(catalog, artifact.home)
    assert entry.identity["sdk"] == 2
    assert Registry.valid_identity?(entry.identity)
    assert :ok = Registry.revalidate(%{extensions: [entry]})
    refute Registry.valid_identity?(Map.put(entry.identity, "sdk", 1))
    changed = put_in(entry, [:identity, "sdk"], 1)
    assert {:error, _} = Registry.revalidate(%{extensions: [changed]})
  end

  test "SDK-2 worker drains frozen output, denies domain callbacks and closes normally", c do
    worker = ready(c)
    assert {:error, :invalid_extension_request} = Worker.call(worker, "result.output", request(0))
    assert {:ok, offer} = Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})
    assert offer["kind"] == "result_producer"

    assert {:error, :invalid_extension_request} =
             Worker.call(worker, "host.actions", %{"invocation_id" => @invocation})

    assert {:error, :invalid_extension_request} =
             Worker.call(worker, "invoke.command", %{"invocation_id" => @invocation})

    assert {:error, :invalid_extension_request} = Worker.call(worker, "result.output", request(1))

    chunks =
      Enum.reduce(0..div(offer["output"]["byte_count"] - 1, 4096), [], fn index, chunks ->
        assert {:ok, response} = Worker.call(worker, "result.output", request(index * 4096))
        [Base.decode64!(response["output"]["data_base64"]) | chunks]
      end)

    bytes = IO.iodata_to_binary(Enum.reverse(chunks))
    assert Ipse.JSON.sha256(bytes) == offer["output"]["sha256"]

    assert {:ok, %{"items" => items}} =
             Ipse.Extension.ResultDocument.decode(bytes, %{"type" => "object"})

    assert items == List.duplicate(String.duplicate("雪", 2730), 3)

    assert {:error, :invalid_extension_request} =
             Worker.call(worker, "result.output", request(byte_size(bytes)))

    assert :ok = Worker.close(worker)
  end

  test "ordinary host.actions retains original eligibility, recovered actions do not", c do
    worker = ready(c, 2, %{"mode" => "actions"})

    assert {:ok, %{"kind" => "host_call"}} =
             Worker.call(worker, "invoke.command", %{"invocation_id" => @invocation})

    assert {:error, :invalid_extension_request} =
             Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})

    assert {:error, :invalid_extension_request} =
             Worker.call(worker, "host.actions", %{"invocation_id" => String.duplicate("c", 32)})

    assert {:error, :invalid_extension_request} = Worker.call(worker, "host.actions", 17)

    assert {:ok, %{"kind" => "result_producer"}} =
             Worker.call(worker, "host.actions", %{"invocation_id" => @invocation})

    assert :ok = Worker.close(worker)
    worker = ready(c, 2, %{"mode" => "inline"})

    assert {:ok, %{"kind" => "result"}} =
             Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})

    assert {:error, :invalid_extension_request} =
             Worker.call(worker, "host.actions", %{"invocation_id" => @invocation})

    assert :ok = Worker.close(worker)

    for stage <- ~w(host.actions invoke.service event.job transform.prompt) do
      worker = ready(c)
      ref = Process.monitor(worker)
      assert {:error, _} = Worker.call(worker, stage, %{"invocation_id" => @invocation})
      assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
    end
  end

  test "SDK-1 and SDK-2 inline responses retain their bounded contracts", c do
    for sdk <- [1, 2],
        stage <- ~w(invoke.tool invoke.service event.job transform.prompt host.actions) do
      worker = ready(c, sdk, %{"mode" => "inline"})

      assert {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"ok" => true}}} =
               Worker.call(worker, stage, %{"invocation_id" => @invocation})

      assert :ok = Worker.close(worker)
    end

    worker = ready(c, 1)
    ref = Process.monitor(worker)
    assert {:error, _} = Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
  end

  test "Worker independently refuses forged terminal output without Bootstrap cooperation", c do
    for mode <- ~w(raw_bad_offset raw_bad_hash raw_bad_eof raw_bad_full) do
      worker = ready(c, 2, %{"mode" => mode})
      ref = Process.monitor(worker)

      assert {:ok, %{"kind" => "result_producer"}} =
               Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})

      assert {:error, :invalid_extension_output} =
               Worker.call(worker, "result.output", request(0))

      assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
    end

    worker = ready(c, 2, %{"mode" => "raw_bad_count"})
    ref = Process.monitor(worker)

    assert {:error, :invalid_extension_output} =
             Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})

    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
    worker = ready(c, 1, %{"mode" => "raw_offer"})
    ref = Process.monitor(worker)

    assert {:error, :invalid_extension_output} =
             Worker.call(worker, "invoke.tool", %{"invocation_id" => @invocation})

    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
  end

  test "Worker requires the description SDK to equal its pinned manifest SDK", c do
    for sdk <- [1, 2] do
      artifact = c.artifacts[sdk]
      options = %{"mode" => "wrong_description"}

      assert {:ok, worker} =
               Worker.start(
                 owner: self(),
                 store: artifact.store,
                 digest: artifact.digest,
                 trusted: artifact.digest,
                 options: options
               )

      ref = Process.monitor(worker)
      assert {:error, :invalid_extension_output} = Worker.call(worker, "initialize", options)
      assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
    end
  end
end
