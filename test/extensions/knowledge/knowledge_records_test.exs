Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/knowledge/records.ex", __DIR__)

defmodule IpseKnowledge.Knowledge.RecordsTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Knowledge.Records, as: R
  @day 86_400_000

  defp proof(origin \\ "interactive_operator", quote \\ "Acme has owner Alex") do
    kind =
      case origin do
        "native_operator_answer" -> "input.operator_answer"
        "assistant_proposal" -> "answer.original"
        "typed_host_outcome" -> "tool.outcome"
        _ -> "input.original"
      end

    %{
      "version" => 1,
      "session_id" => String.duplicate("1", 32),
      "occurrence_id" => String.duplicate("2", 32),
      "version_id" => String.duplicate("3", 32),
      "kind" => kind,
      "origin" => origin,
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(quote),
      "quote" => quote,
      "quote_sha256" => Ipse.JSON.sha256(quote),
      "content_sha256" => Ipse.JSON.sha256(quote),
      "receipt_sha256" => Ipse.JSON.sha256("synthetic trusted-function input")
    }
  end

  defp attrs(text \\ "Acme has owner Alex", category \\ "ordinary"),
    do: %{
      "text" => text,
      "category" => category,
      "reason" => "selected source span",
      "event_at_ms" => nil
    }

  test "exact native observations create attributed notes with the selected retention" do
    assert {:ok, "note." <> _, value} = R.capture(attrs(), proof(), 0)
    assert IpseKnowledge.Notes.valid?(value)
    assert value["expires_at_ms"] == 90 * @day
    assert value["evidence"]["sources"] == [proof()]
    assert {:ok, _, persistent} = R.capture(attrs("Acme has owner Alex", "current"), proof(), 0)
    assert persistent["expires_at_ms"] == nil
  end

  test "retention metadata preserves separate native evidence in a closed publication wrapper" do
    p = proof()

    override = %{
      "version" => 1,
      "lineage" => R.lineage(p),
      "policy" => %{"kind" => "session"},
      "reason" => "operator selection",
      "updated_at_ms" => 0
    }

    assert {:ok, stored} = R.override_record(override, p)
    assert stored["evidence"]["sources"] == [p]
    assert {:ok, ^override} = R.saved_override(stored, override["lineage"])
    assert {:ok, nil} = R.saved_override(nil, override["lineage"])

    for origin <- ~w(unattended_input assistant_proposal typed_host_outcome) do
      assert {:error, :invalid_retention_evidence} = R.override_record(override, proof(origin))
    end

    for damaged <- [
          override,
          Map.put(stored, "permission", true),
          put_in(stored, ["evidence", "sources"], []),
          put_in(stored, ["override", "updated_at_ms"], -1)
        ] do
      assert {:error, :invalid_saved_override} = R.saved_override(damaged, override["lineage"])
    end

    assert {:error, :invalid_saved_override} = R.saved_override(stored, String.duplicate("f", 64))
  end

  test "saved ordinary and duration deadlines cap every paraphrase and classification" do
    p = proof()

    for policy <- [%{"kind" => "ordinary"}, %{"kind" => "duration", "duration_ms" => @day}],
        category <- ~w(ordinary preference current),
        text <- [p["quote"], "Alex owns Acme"] do
      override = %{
        "version" => 1,
        "lineage" => R.lineage(p),
        "policy" => policy,
        "reason" => "operator chose shorter retention",
        "updated_at_ms" => 0
      }

      deadline = if policy["kind"] == "ordinary", do: 90 * @day, else: @day

      assert {:skipped, :expired_lineage} =
               R.capture(attrs(text, category), p, deadline, override)

      assert {:ok, _, value} = R.capture(attrs(text, category), p, deadline - 1, override)
      assert value["expires_at_ms"] == deadline
      if value["kind"] == "proposal", do: assert(value["assigned_category"] == "ordinary")
    end

    override = %{
      "version" => 1,
      "lineage" => R.lineage(p),
      "policy" => %{"kind" => "duration", "duration_ms" => 30 * @day},
      "reason" => "operator retention",
      "updated_at_ms" => 0
    }

    assert {:ok, _, pending} = R.capture(attrs("Alex owns Acme"), p, 0, override)
    assert pending["expires_at_ms"] == 7 * @day
  end

  test "unattended input, assistant text and a native answer's unsupported premise stay pending" do
    for origin <- ~w(unattended_input assistant_proposal) do
      assert {:ok, "pending." <> _, value} = R.capture(attrs(), proof(origin), 0)
      assert value["state"] == "pending"
      assert value["expires_at_ms"] == 7 * @day
      assert hd(value["evidence"]["sources"])["origin"] == origin
    end

    assert {:ok, "pending." <> _, _} =
             R.capture(
               attrs("The operator confirmed Alex owns Acme"),
               proof("native_operator_answer", "2"),
               0
             )
  end

  test "typed tool completion supports only its literal outcome and cannot become a preference" do
    p = proof("typed_host_outcome", ~s({"status":"completed","tool":"shell"}))
    assert {:ok, "note." <> _, _} = R.capture(attrs(p["quote"]), p, 0)
    assert {:ok, "pending." <> _, _} = R.capture(attrs("All tests passed"), p, 0)
    assert {:ok, "pending." <> _, _} = R.capture(attrs(p["quote"], "preference"), p, 0)
  end

  test "paraphrasing and category changes retain claim/evidence overrides without TTL renewal" do
    p = proof()
    lineage = R.lineage(p)

    override = %{
      "version" => 1,
      "lineage" => lineage,
      "policy" => %{"kind" => "session"},
      "reason" => "operator chose session only",
      "updated_at_ms" => 0
    }

    assert {:suppressed, ^override} = R.capture(attrs(), p, @day, override)

    assert {:suppressed, ^override} =
             R.capture(attrs("Alex is Acme's owner", "preference"), p, @day, override)

    expired = %{override | "policy" => %{"kind" => "ordinary"}}
    assert {:skipped, :expired_lineage} = R.capture(attrs(), p, 90 * @day, expired)

    assert {:error, :invalid_capture} =
             R.capture(attrs(), p, 0, %{override | "lineage" => Ipse.JSON.sha256("other claim")})
  end

  test "file content, changed spans, unknown origin and extra input fields cannot enter capture" do
    for p <- [
          %{proof() | "kind" => "tool.content", "origin" => "attributed_reference"},
          %{proof() | "path" => "private/file.txt"},
          %{proof() | "end_byte" => 1},
          %{proof() | "origin" => "worker_says_native"},
          %{proof() | "quote_sha256" => Ipse.JSON.sha256("changed")}
        ] do
      assert {:error, :invalid_capture} = R.capture(attrs(), p, 0)
    end

    assert {:error, :invalid_capture} = R.capture(Map.put(attrs(), "allow", true), proof(), 0)
  end

  test "maximum selected UTF-8 span fits a note and oversized escaped proposals refuse explicitly" do
    quote = String.duplicate("λ", 512)
    assert {:ok, _, note} = R.capture(attrs(quote), proof("interactive_operator", quote), 0)
    assert byte_size(Jason.encode!(note)) <= 6144
    oversized = attrs(String.duplicate("\n", 2048))
    assert {:error, :capture_capacity} = R.capture(oversized, proof("assistant_proposal"), 0)
  end
end
