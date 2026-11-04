defmodule Ipse.Session.PostReplyCaptureInputsTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session, Usage}
  alias Ipse.Session.{ManagedLineage, ManagedReference}

  defp prepared do
    pin = %{
      "project_id" => JSON.sha256("project"),
      "namespace" => JSON.sha256("namespace"),
      "epoch" => 1
    }

    dependency = %{
      "version" => 3,
      "project_id" => pin["project_id"],
      "namespace" => pin["namespace"],
      "pin_sha256" => JSON.digest([pin]),
      "policy_generation" => 1,
      "collection" => %{
        "project" => pin["namespace"],
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_state" => "absent",
        "root_sha256" => nil,
        "manifest_sha256" => nil
      },
      "subject" => %{
        "kind" => "root_observation",
        "request_sha256" => JSON.sha256("request"),
        "result_sha256" => JSON.sha256("result")
      }
    }

    {:ok, lineage} = ManagedLineage.new(Usage.id())

    state = %{
      managed_lineage: %{lineage | root_observations: %{JSON.digest([dependency]) => true}},
      config: %{semantic_admission: %{"pin" => pin}},
      messages: [],
      invocation: %Session.Invocation{}
    }

    assert ManagedReference.dependency?(dependency)
    {state, dependency}
  end

  defp with_dependencies(state, :reads, deps),
    do: %{state | invocation: %{state.invocation | managed_reads: deps}}

  defp with_dependencies(state, :inherited, deps) do
    id = Usage.id()
    dictionary = Map.new(deps, &{JSON.digest([&1]), &1})
    entry = %{input: Map.keys(dictionary), reads: [], instance: "knowledge", parent: nil}

    %{
      state
      | invocation: %{state.invocation | parent: %{"invocation_id" => id}},
        managed_lineage: %{
          state.managed_lineage
          | dictionary: dictionary,
            invocations: %{id => entry}
        }
    }
  end

  defp with_dependencies(state, :active, deps) do
    message = %{"role" => "assistant", "content" => "Synthetic proposal."}
    producer = %{"kind" => "assistant", "id" => Usage.id(), "parent_id" => nil}

    {:ok, _, reference} =
      ManagedReference.admit(state.managed_lineage.reference, producer, 0, message, deps)

    %{
      state
      | messages: [message],
        managed_lineage: %{state.managed_lineage | reference: reference}
    }
  end

  test "each input channel requires an exact committed root-only classification" do
    {state, root} = prepared()
    assert Session.post_reply_capture_inputs?(state)

    for channel <- [:active, :inherited, :reads] do
      current = with_dependencies(state, channel, [root])
      refute Session.managed_empty?(current)
      assert Session.post_reply_capture_inputs?(current)

      for cache <- [%{}, %{JSON.digest([root]) => "metadata_only"}] do
        refute Session.post_reply_capture_inputs?(%{
                 current
                 | managed_lineage: %{current.managed_lineage | root_observations: cache}
               })
      end

      refute Session.post_reply_capture_inputs?(
               put_in(current, [:config, :semantic_admission, "pin", "epoch"], 2)
             )

      refute Session.post_reply_capture_inputs?(%{
               current
               | managed_lineage: %{current.managed_lineage | unavailable: true}
             })
    end
  end

  test "a valid record dependency in any channel prevents automatic capture" do
    {state, root} = prepared()
    key = "note." <> JSON.sha256("record")

    record =
      root
      |> Map.put("version", 4)
      |> Map.put(
        "collection",
        Map.merge(root["collection"], %{
          "root_state" => "present",
          "generation" => 1,
          "root_sha256" => JSON.sha256("root"),
          "manifest_sha256" => JSON.sha256("manifest")
        })
      )
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => JSON.sha256("record result"),
        "publication_policy_sha256" => JSON.sha256("policy"),
        "record" => %{
          "key" => key,
          "revision" => 1,
          "value_sha256" => JSON.sha256("record value")
        },
        "validity" => %{
          "recipe_sha256" => JSON.sha256("recipe"),
          "lineage" => JSON.sha256("lineage"),
          "source_versions" => [],
          "valid_until_ms" => nil,
          "status" => "eligible",
          "dependencies" => []
        }
      })

    assert ManagedReference.dependency?(record)

    for channel <- [:active, :inherited, :reads] do
      current = with_dependencies(state, channel, [record])

      current = %{
        current
        | managed_lineage: %{
            current.managed_lineage
            | root_observations: %{JSON.digest([root]) => true, JSON.digest([record]) => true}
          }
      }

      refute Session.post_reply_capture_inputs?(current)

      refute Session.post_reply_capture_inputs?(
               with_dependencies(current, :reads, [root, record])
             )
    end
  end
end
