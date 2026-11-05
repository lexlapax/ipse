Code.require_file("../../../dev/knowledge/native_notes_seed.ex", __DIR__)

defmodule Ipse.Development.NativeNotesSeedTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.NativeNotesSeed, as: Seed

  test "the complete initial population preserves the native daily ceiling and required mix" do
    plan = Seed.plan("initial")
    actions = Enum.flat_map(plan, & &1["actions"])
    captures = Enum.filter(actions, &(&1["op"] == "capture"))
    assert length(captures) == 2000
    assert length(actions) == 2100

    assert Enum.frequencies_by(captures, & &1["category"]) == %{
             "ordinary" => 1900,
             "preference" => 50,
             "current" => 50
           }

    pins = Enum.filter(actions, &(&1["op"] == "pin"))
    assert Enum.map(pins, & &1["number"]) == Enum.to_list(1..100)
    assert Enum.all?(captures, &(&1["number"] > 100 or &1["category"] == "ordinary"))
    assert Enum.all?(plan, &(length(&1["actions"]) in 1..8))
    assert Enum.map(plan, & &1["day"]) |> Enum.uniq() == Enum.to_list(0..20)

    assert Enum.group_by(plan, & &1["day"])
           |> Enum.all?(fn {_, segments} ->
             Enum.sum(Enum.map(segments, &length(&1["actions"]))) == 100
           end)

    assert Enum.map(captures, & &1["number"]) == Enum.to_list(1..2000)
  end

  test "the independent smoke plan spans fresh days and all native categories without claiming the full seed" do
    assert [first, second] = Seed.plan("smoke")
    assert first["day"] == 0 and second["day"] == 1
    assert length(first["actions"]) == 4 and length(second["actions"]) == 4
    assert Enum.frequencies_by(first["actions"], & &1["op"]) == %{"capture" => 3, "pin" => 1}
    assert Enum.all?(second["actions"], &(&1["category"] == "ordinary"))
  end

  test "recorded time summaries ignore deadlines and invalid values while retaining nested maxima" do
    events = [
      %{"checked_at_ms" => 5, "deadline_ms" => 999, "nested" => [%{"observed_at_ms" => 8}]},
      %{"checked_at_ms" => 7, "created_at_ms" => -1, "other" => %{"observed_at_ms" => 3}},
      %{"checked_at_ms" => "future", "finished_at_ms" => 9_007_199_254_740_992}
    ]

    assert Seed.recorded_times(events) == %{
             "events" => 3,
             "maxima_ms" => %{"checked_at_ms" => 7, "observed_at_ms" => 8}
           }

    assert Seed.recorded_times([]) == %{"events" => 0, "maxima_ms" => %{}}
  end

  test "the optional synthetic fixture route is explicit and restricted to loopback" do
    config = Seed.fixture_config(42_123)
    assert config["roles"]["main"] == "synthetic"
    assert config["profiles"]["synthetic"]["provider"] == "ollama"
    assert config["profiles"]["synthetic"]["base_url"] == "http://127.0.0.1:42123"
    assert config["inference_services"]["local"]["origins"] == ["http://127.0.0.1:42123"]

    for invalid <- [0, 65_536, -1, "42123"],
        do: assert_raise(FunctionClauseError, fn -> Seed.fixture_config(invalid) end)
  end

  test "the native maximum plan is one genuine statement capture, not a padded record write" do
    assert Seed.plan("maximum") == [
             %{
               "day" => 0,
               "actions" => [%{"op" => "capture", "number" => 1, "category" => "ordinary"}]
             }
           ]
  end

  test "proof JSON escaping is the binding native statement size limit" do
    for category <- ~w(ordinary preference current) do
      geometry = Seed.maximum_geometry(1_800_000_000_000, category)
      assert geometry["source_bytes"] == 999
      assert geometry["proof_encoded_bytes"] == 2048
      assert geometry["next_escape_proof_bytes"] == 2049
      assert geometry["predicted_note_value_bytes"] < geometry["record_ceiling_bytes"]

      assert geometry["all_source_lengths_upper_bound_bytes"] ==
               geometry["predicted_note_value_bytes"]

      statement = Seed.maximum_statement(geometry["json_escape_count"])
      next = Seed.maximum_statement(geometry["json_escape_count"] + 1)
      assert byte_size(statement) == byte_size(next)
      assert byte_size(Jason.encode!(next)) == byte_size(Jason.encode!(statement)) + 1

      assert {:ok, ^category, ^statement} =
               Ipse.Session.OperatorAssertion.parse_command("/remember #{category} " <> statement)

      assert {:ok, ^category, ^next} =
               Ipse.Session.OperatorAssertion.parse_command("/remember #{category} " <> next)
    end

    assert Seed.maximum_geometry(1_800_000_000_000)["predicted_note_value_bytes"] == 4062
  end

  test "native source overflow refuses before an assertion can be prepared" do
    assert {:error, :operator_assertion_refused} =
             Ipse.Session.OperatorAssertion.parse_command(
               "/remember ordinary " <> String.duplicate("x", 1025)
             )

    for invalid <- [-1, 999],
        do: assert_raise(FunctionClauseError, fn -> Seed.maximum_statement(invalid) end)

    assert {:ok, "ordinary", text} =
             Ipse.Session.OperatorAssertion.parse_command(
               "/remember ordinary " <> String.duplicate("x", 1024)
             )

    assert byte_size(text) == 1024
    refute Seed.maximum_geometry(1_800_000_000_000)["geometry_only"] == false
  end

  test "small refusals use a bound inline invocation result without a paged seal" do
    hash = Ipse.JSON.sha256("native payload protocol fixture")

    identity =
      Map.new(
        ~w(artifact artifact_sha256 options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 source_sha256 host_sha256),
        &{&1, hash}
      )
      |> Map.merge(%{
        "instance" => "fixture",
        "services" => [],
        "scope" => "operator",
        "sdk" => 2,
        "protocol" => 1,
        "capabilities" => ~w(invoke.command invoke.result.pages),
        "order" => 1,
        "lifetime" => "session",
        "expires_at" => nil,
        "generation" => 1,
        "allow_children" => false,
        "runtime" => %{
          "architecture" => "fixture",
          "elixir" => "1.18.5",
          "erts" => "15",
          "otp" => "27"
        }
      })

    descriptor = %{
      "id" => "capture",
      "description" => "Synthetic refusal protocol",
      "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
      "result_schema" => %{"type" => "object"},
      "instance" => "fixture",
      "stage" => "invoke.command",
      "name" => "ext__fixture__capture"
    }

    intent =
      Ipse.Extension.Invocation.intent(
        identity,
        descriptor,
        %{},
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        nil,
        nil,
        "operator_request"
      )

    value = %{"status" => "refused", "code" => "source_refused"}

    assert {:ok, result} =
             Ipse.Extension.Invocation.build_result(intent, %{
               "api_version" => 1,
               "kind" => "result",
               "value" => value
             })

    refute Map.has_key?(result, "delivery")
    assert Ipse.Extension.Invocation.result_intent(result) === intent
    assert {:ok, ^value} = Seed.maximum_inline_refusal(intent, result)

    for invalid <- [
          Map.put(result, "value", %{}),
          Map.put(result, "text_sha256", hash),
          Map.put(result, "payload_sha256", hash),
          Map.put(result, "invocation_id", Ipse.Usage.id()),
          Map.put(result, "version", 4),
          Map.update!(result, "payload", &Map.put(&1, "arguments", %{"changed" => true}))
        ] do
      assert {:error, :maximum_inline_refusal_unavailable} =
               Seed.maximum_inline_refusal(intent, invalid)
    end

    assert {:error, :maximum_inline_refusal_unavailable} =
             Seed.maximum_inline_refusal(nil, result)
  end

  test "absent capture-only management storage is explicit and is not a native measurement" do
    root = Path.join(System.tmp_dir!(), "ipse-native-seed-absence-" <> Ipse.Usage.id())
    File.mkdir!(root)
    path = Path.join(root, "knowledge-management")
    actions = [%{"op" => "capture", "number" => 1, "category" => "ordinary"}]

    try do
      assert {:ok, absence} = Seed.absent_management_storage(path, actions)
      assert absence["presence"] == "absent"
      assert absence["native_allocation"] == nil
      assert absence["missing_dimensions"] == ~w(logical_bytes allocated_bytes entries)
      refute Map.has_key?(absence, "allocated_bytes")

      assert {:error, :native_seed_management_storage_unavailable} =
               Seed.absent_management_storage(path, actions ++ [%{"op" => "pin", "number" => 1}])

      assert {:error, :native_seed_management_storage_unavailable} =
               Seed.absent_management_storage(path, [])

      File.mkdir!(path)

      assert {:error, :native_seed_management_storage_unavailable} =
               Seed.absent_management_storage(path, actions)

      File.rmdir!(path)
      File.ln_s!("does-not-exist", path)

      assert {:error, :native_seed_management_storage_unavailable} =
               Seed.absent_management_storage(path, actions)

      File.rm!(path)
    after
      File.rmdir!(root)
    end
  end
end
