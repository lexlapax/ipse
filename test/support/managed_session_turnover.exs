# Real Session reviews and sources; future expiry is a separate explicit as-of component.
defmodule Ipse.Test.ManagedSessionTurnover do
  import ExUnit.Assertions
  alias Ipse.JSON
  alias Ipse.Extension.{ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead

  def run(config, cwd, home, root, events, mode, record_turnover) do
    selected_mode = if mode == "ordinary", do: "ordinary", else: "temporal"

    intent =
      Enum.find(
        events,
        &(&1["type"] == "managed_supersession_intent" and &1["facts"]["mode"] == selected_mode)
      )

    assert intent

    review =
      Enum.find(
        events,
        &(&1["type"] == "managed_supersession_review" and
            &1["operation_id"] == intent["operation_id"])
      )

    result =
      Enum.find(
        events,
        &(&1["type"] == "managed_supersession_result" and
            &1["operation_id"] == intent["operation_id"])
      )

    facts = intent["facts"]
    normalization = result["outcome"]["publication"]["normalization"]
    assert result["status"] == "settled"
    recipe = facts["context"]["recipe"]
    admission = config.semantic_admission
    pin = admission["pin"]
    collection = SemanticAdmission.collection_root(home)
    source_hash = JSON.digest([get_in(facts, ["target", "value", "evidence", "sources"])])

    frame =
      if record_turnover do
        Code.require_file("../../dev/knowledge/managed_v3_turnover_native.exs", __DIR__)
        Ipse.Development.ManagedV3TurnoverNative.frame(System.system_time(:millisecond))
      end

    if record_turnover do
      deadline = normalization["history_valid_until_ms"]

      event =
        Ipse.Development.ManagedV3TurnoverNative.event(
          frame,
          "actual_native_review_and_supersession",
          review["review"]["observed_at_ms"],
          %{
            "clock_kind" => "actual_wall_clock",
            "review_sha256" => JSON.digest([review["review"]]),
            "source_sha256" => source_hash,
            "source_scope" => "native_reviewed_session_fixture",
            "history_deadline_actual_ms" => deadline,
            "history_deadline_virtual_ms" =>
              Ipse.Development.ManagedV3TurnoverNative.virtual(frame, deadline)
          }
        )

      IO.puts("TURNOVER_EVENT=" <> Jason.encode!(event))
    end

    if mode == "history_expiry" do
      Code.require_file(
        "../ipse/extension/collection_normalizer_v3_integration_test.exs",
        __DIR__
      )

      Code.require_file("managed_history_expiry.exs", __DIR__)

      c = %{
        home: home,
        cwd: cwd,
        binding: admission["binding"],
        root: collection,
        namespace: pin["namespace"]
      }

      constraints = admission["policy"]["settings"]["constraints"][recipe["constraints_sha256"]]

      options = fn record ->
        %{
          request: %{
            "op" => "commit",
            "expected_generation" => 0,
            "advance_floor" => true,
            "changes" => [
              %{"key" => record["key"], "expected_revision" => 0, "value" => record["value"]}
            ]
          },
          recipe: recipe,
          constraints: constraints,
          verified_sources: record["value"]["evidence"]["sources"],
          policy_sha256: pin["policy_sha256"],
          now_ms: System.system_time(:millisecond)
        }
      end

      old = options.(facts["target"])
      new = options.(facts["replacement"])

      assert {:ok, successor} =
               ProjectIdentity.with_existing_domain_auth(
                 home,
                 cwd,
                 admission["binding"],
                 %{namespace: pin["namespace"], format: "managed-metadata-v3"},
                 fn cap, catalog ->
                   ObservedRead.managed_record(
                     collection,
                     pin["namespace"],
                     %{"op" => "get_record", "key" => facts["replacement"]["key"]},
                     cap,
                     catalog,
                     recipe
                   )
                 end
               )

      directory = Path.join(root, "explicit-as-of-journal")

      assert {:ok, id} =
               Ipse.Journal.create(directory, %{"kind" => "explicit_as_of_history_component"})

      assert {:ok, writer} = Ipse.Journal.Writer.start(directory, id, self())

      try do
        Ipse.Test.ManagedHistoryExpiry.run(c, old, new, facts["context"], successor, writer)
      after
        assert :ok = Ipse.Journal.Writer.close(writer)
      end

      if record_turnover do
        deadline = normalization["history_valid_until_ms"]
        assert deadline > System.system_time(:millisecond)

        event =
          Ipse.Development.ManagedV3TurnoverNative.event(
            frame,
            "signed_history_expired",
            deadline,
            %{
              "clock_kind" => "explicit_synthetic_as_of",
              "real_wall_after_ms" => System.system_time(:millisecond),
              "source_sha256" => source_hash,
              "source_scope" => "native_reviewed_session_fixture"
            }
          )

        IO.puts("TURNOVER_EVENT=" <> Jason.encode!(event))
      end
    end

    refute File.exists?(Path.join(root, "unexpected-model"))
  end
end
