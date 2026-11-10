defmodule Ipse.Session.ReferenceBoundTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, JSON, Session, Usage}
  alias Ipse.Session.{ManagedLineage, ManagedReference}

  defmodule Model do
    def complete(config, _, _, _) do
      send(config.test_owner, {:request, config.test_label})
      {:ok, %{"role" => "assistant", "content" => "Synthetic answer."}, %{}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-reference-bound-" <> Usage.id())
    dir = Path.join(root, "sessions")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: dir}
  end

  test "a reference over the occurrence bound is refused before it is journaled", c do
    {pid, label} = start(c)
    id = Session.info(pid).id
    limits = ManagedReference.limits()

    # The smallest set of record observations whose encoding passes the
    # occurrence byte bound while its count stays inside the count bound.
    dependencies =
      Enum.reduce_while(1..limits["occurrence_dependencies"], [], fn index, acc ->
        acc = [dependency(index) | acc]

        if byte_size(Jason.encode!(acc)) > limits["occurrence_dependency_bytes"],
          do: {:halt, acc},
          else: {:cont, acc}
      end)

    assert length(dependencies) < limits["occurrence_dependencies"]
    assert byte_size(Jason.encode!(dependencies)) > limits["occurrence_dependency_bytes"]

    :sys.replace_state(pid, fn s ->
      assert %ManagedLineage{unavailable: false} = s.managed_lineage
      refute is_nil(s.reference)

      %{
        s
        | managed_lineage: published(s.managed_lineage, dependencies),
          extension_contributions: %{
            "knowledge" => [
              %{
                "id" => "synthetic",
                "priority" => 0,
                "text" => "Synthetic publisher",
                "provenance" => %{"instance" => "knowledge"}
              }
            ]
          }
      }
    end)

    assert :ok = Session.prompt(pid, "first")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    refute_receive {:request, ^label}, 100
    assert %ManagedLineage{unavailable: false} = :sys.get_state(pid).managed_lineage
    assert :ok = Session.close_confirmed(pid)

    {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] in ~w(reference_admitted reference_envelope)))
    assert %{"status" => "error"} = Enum.find(events, &(&1["type"] == "turn_finished"))
    assert {:ok, _} = Session.Saved.restore(events, id)

    {resumed, resumed_label} = start(c, id)
    assert :ok = Session.prompt(resumed, "second")
    assert_receive {:request, ^resumed_label}, 5_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(resumed)

    {:ok, events} = Journal.load(c.dir, id)

    assert ["error", "ok"] ==
             for(%{"type" => "turn_finished", "status" => status} <- events, do: status)
  end

  # One committed worker invocation that read the given managed records and
  # published context, as the host records it.
  defp published(lineage, dependencies) do
    invocation = Usage.id()
    operation = Usage.id()

    events = [
      %{
        "type" => "extension_invocation_intent",
        "invocation_id" => invocation,
        "descriptor" => %{"stage" => "invoke.tool"},
        "identity" => %{"instance" => "knowledge"}
      },
      %{
        "type" => "managed_read_observed",
        "operation_id" => operation,
        "dependencies" => dependencies
      },
      %{
        "type" => "extension_action_result",
        "parent_invocation_id" => invocation,
        "operation_id" => operation,
        "request" => %{"op" => "collection.call"},
        "outcome" => %{"status" => "ok"}
      },
      %{
        "type" => "extension_action_result",
        "parent_invocation_id" => invocation,
        "operation_id" => Usage.id(),
        "request" => %{"op" => "context.publish"},
        "outcome" => %{"status" => "ok"}
      },
      %{"type" => "extension_invocation_result", "invocation_id" => invocation}
    ]

    # The synthetic invocation carries no host output release, so the output
    # layout is set aside while it is recorded.
    state =
      Enum.reduce(events, %{lineage | output_layout: nil}, fn event, state ->
        assert {:ok, %ManagedLineage{unavailable: false} = state} =
                 ManagedLineage.advance(state, event, [], [])

        state
      end)

    %{state | output_layout: lineage.output_layout}
  end

  # A current-record observation shaped like the one a recalled note binds.
  defp dependency(index) do
    key = "note." <> JSON.sha256("note #{index}")

    links =
      Enum.sort_by(
        for n <- 1..4 do
          %{
            "key" => "link." <> JSON.sha256("link #{index} #{n}"),
            "revision" => 1,
            "value_sha256" => JSON.sha256("link value #{index} #{n}")
          }
        end,
        &JSON.digest([&1])
      )

    dependency = %{
      "version" => 4,
      "project_id" => JSON.sha256("project"),
      "namespace" => JSON.sha256("namespace"),
      "pin_sha256" => JSON.sha256("pin"),
      "policy_generation" => 1,
      "collection" => %{
        "project" => JSON.sha256("namespace"),
        "generation" => 1,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_state" => "present",
        "root_sha256" => JSON.sha256("root"),
        "manifest_sha256" => JSON.sha256("manifest")
      },
      "subject" => %{
        "kind" => "record_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => JSON.sha256("result #{index}"),
        "publication_policy_sha256" => JSON.sha256("policy"),
        "record" => %{"key" => key, "revision" => 1, "value_sha256" => JSON.sha256(key)},
        "validity" => %{
          "recipe_sha256" => JSON.sha256("recipe"),
          "lineage" => JSON.sha256(key),
          "source_versions" => [],
          "valid_until_ms" => nil,
          "status" => "eligible",
          "dependencies" => links
        }
      }
    }

    assert ManagedReference.dependency?(dependency)
    dependency
  end

  defp start(c, id \\ nil) do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      home: Path.join(c.root, "home"),
      test_owner: self(),
      test_label: make_ref(),
      approval: :allow,
      approval_origin: :yes,
      headless: true,
      compact: false
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    {pid, config.test_label}
  end
end
