if System.get_env("IPSE_DRAFT_ABORT_PROTOCOL_CHILD") == "1" do
  defmodule IpseKnowledge.DraftAbortProtocolTest do
    use ExUnit.Case, async: true
    alias IpseKnowledge.Store.Collection, as: C
    @profile %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
    @id String.duplicate("a", 32)

    defp head(kind \\ "source") do
      %{
        "version" => 1,
        "status" => "active",
        "head_id" => @id,
        "revision" => 7,
        "unit" => 2,
        "maintenance_epoch" => 1,
        "retirement_epoch" => nil,
        "slots" => if(kind == "source", do: [0, 1, 2], else: [0, 1]),
        "active" => nil,
        "prepared" => [],
        "plan_sha256" => String.duplicate("b", 64),
        "body_sha256" => String.duplicate("c", 64),
        "unit_limit" => 8,
        "kind" => kind
      }
    end

    defp reply({:call, request, state}, result, progress \\ nil) do
      assert :ok =
               Ipse.Extension.validate(%{
                 "api_version" => 1,
                 "op" => "host.call",
                 "request" => request
               })

      wrapped = %{
        "version" => if(progress, do: 2, else: 1),
        "operation_id" => String.duplicate("d", 32),
        "request_sha256" => Ipse.JSON.digest([request]),
        "result" => result
      }

      wrapped = if progress, do: Map.put(wrapped, "progress", progress), else: wrapped
      C.resume(state, %{"status" => "ok", "value" => wrapped})
    end

    defp boot(p, epoch \\ 2, status \\ "idle") do
      C.start(@profile, :progress_abort, %{"head_id" => @id, "kind" => p["kind"]})
      |> reply(%{
        "generation" => 10,
        "document_store" => %{
          "version" => 4,
          "inline_bytes" => 8192,
          "write_parts" => 2,
          "progress" => 1,
          "maintenance_epoch" => epoch,
          "maintenance_status" => status
        }
      })
    end

    defp pending(p), do: boot(p) |> reply(%{"generation" => 10, "progress" => p})

    defp ref(slot),
      do: %{"slot" => slot, "epoch" => String.duplicate(Integer.to_string(slot + 1), 32)}

    test "closed abort grammar does not accept arbitrary keys, profile or kind" do
      args = %{"head_id" => @id, "kind" => "source"}

      for bad <- [
            Map.put(args, "key", "source.unrelated"),
            Map.put(args, "kind", "job"),
            Map.put(args, "head_id", "../foreign")
          ] do
        assert {:done, {:error, :invalid_collection_draft_abort, %{}}} =
                 C.start(@profile, :progress_abort, bad)
      end

      assert {:done, {:error, :invalid_collection_draft_abort, %{}}} =
               C.start(
                 %{"kind" => "state", "scope" => "project", "partition" => "notes"},
                 :progress_abort,
                 args
               )
    end

    test "an empty head requires one real retirement with the captured epoch" do
      p = head()
      pending = {:call, request, _} = pending(p)

      assert request["request"] === %{
               "op" => "progress.retire",
               "generation" => 10,
               "maintenance_epoch" => 2,
               "progress" => %{
                 "version" => 1,
                 "action" => "retire",
                 "head_id" => @id,
                 "revision" => 7
               }
             }

      retired = %{
        p
        | "revision" => 11,
          "status" => "retired",
          "slots" => [],
          "retirement_epoch" => 2
      }

      assert {:done, {:ok, value}} = reply(pending, %{"generation" => 11}, retired)
      assert value["status"] === "aborted" and value["cleanup_operations"] === 1
      assert value["maintenance_epoch"] === 1 and value["retirement_epoch"] === 2
      assert value["coverage"]["reads_used"] === 2 and value["coverage"]["effects_used"] === 1
    end

    test "a two-stage projection retains native identity and new revision for the second effect" do
      p = %{head("projection") | "prepared" => [ref(0), ref(1)]}
      first = {:call, request, _} = pending(p)
      assert request["request"]["op"] === "value.abort"
      assert Map.take(request["request"], ~w(slot epoch)) === ref(0)

      reduced = %{
        p
        | "revision" => 11,
          "status" => "retiring",
          "prepared" => [ref(1)],
          "retirement_epoch" => 2
      }

      second = {:call, request, _} = reply(first, %{"generation" => 11}, reduced)
      assert request["request"]["generation"] === 11
      assert request["request"]["maintenance_epoch"] === 2
      assert request["request"]["progress"]["revision"] === 11
      assert Map.take(request["request"], ~w(slot epoch)) === ref(1)

      retired = %{
        reduced
        | "revision" => 12,
          "status" => "retired",
          "prepared" => [],
          "slots" => []
      }

      assert {:done, {:ok, value}} = reply(second, %{"generation" => 12}, retired)
      assert value["cleanup_operations"] === 2 and value["native_generation"] === 12
      assert value["progress"]["maintenance_epoch"] === 1
    end

    test "active maintenance and an older retirement epoch refuse before any mutation" do
      assert {:done, {:error, :document_draft_abort_refused, %{}}} = boot(head(), 2, "active")
      p = %{head() | "status" => "retiring", "retirement_epoch" => 1}
      assert {:done, {:error, :document_draft_abort_refused, %{}}} = pending(p)
      pending_read = boot(head())

      assert {:done, {:error, :document_draft_abort_refused, %{}}} =
               reply(pending_read, %{"generation" => 10, "progress" => head("projection")})
    end

    test "a partial known refusal is visibly incomplete and unknown has no replay token" do
      p = %{head("projection") | "prepared" => [ref(0), ref(1)]}

      reduced = %{
        p
        | "revision" => 11,
          "status" => "retiring",
          "prepared" => [ref(1)],
          "retirement_epoch" => 2
      }

      {:call, _, state} = pending(p) |> reply(%{"generation" => 11}, reduced)

      assert {:done, {:error, :document_draft_abort_incomplete, %{}}} =
               C.resume(state, %{"status" => "failed"})

      assert {:stop, :unknown_effect} = C.resume(state, %{"status" => "unknown"})
    end

    test "a response cannot renew the opening epoch, remove unrelated references or invent completion" do
      p = %{head("projection") | "prepared" => [ref(0), ref(1)]}
      first = pending(p)

      reduced = %{
        p
        | "revision" => 11,
          "status" => "retiring",
          "prepared" => [ref(1)],
          "retirement_epoch" => 2
      }

      for bad <- [
            Map.put(reduced, "maintenance_epoch", 2),
            Map.put(reduced, "prepared", []),
            %{reduced | "status" => "retired", "slots" => [], "prepared" => []},
            Map.put(reduced, "body_sha256", String.duplicate("e", 64))
          ] do
        assert {:stop, :unknown_effect} = reply(first, %{"generation" => 11}, bad)
      end
    end
  end
else
  defmodule IpseKnowledge.DraftAbortProtocolIsolationTest do
    use ExUnit.Case, async: false

    @tag timeout: 120_000
    test "draft abort protocol controls keep Knowledge modules outside the host" do
      before = :code.is_loaded(IpseKnowledge.Store.Collection)
      root = Path.join(System.tmp_dir!(), "ipse-draft-abort-protocol-" <> Ipse.Usage.id())
      File.mkdir!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      artifact = Path.join(root, "corpus")

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "--erl",
            "+S 1:1",
            "extensions/knowledge/build.exs",
            "--sdk",
            Application.app_dir(:ipse, "ebin"),
            "--output",
            artifact,
            "--package",
            "corpus",
            "--preset",
            "collection-documents"
          ],
          stderr_to_stdout: true
        )

      assert status === 0, output

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      script =
        "ExUnit.start(autorun: false); Code.require_file(#{inspect(Path.expand(__ENV__.file))}); " <>
          "result = ExUnit.run(); if result.failures != 0, do: System.halt(1); IO.puts(\"DRAFT_ABORT_PROTOCOL_PASS\")"

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 1:1"] ++ paths ++ ["-pa", Path.join(artifact, "ebin"), "-e", script],
          stderr_to_stdout: true,
          env: [{"IPSE_DRAFT_ABORT_PROTOCOL_CHILD", "1"}]
        )

      assert status === 0, output
      assert output =~ "DRAFT_ABORT_PROTOCOL_PASS"
      assert :code.is_loaded(IpseKnowledge.Store.Collection) === before
      IO.write(output)
    end
  end
end
