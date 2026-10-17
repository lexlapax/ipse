defmodule Ipse.Lifecycle.AnswerTest do
  use ExUnit.Case, async: true
  alias Ipse.Lifecycle.{Answer, Source, Event}

  test "one occurrence has private views and content-free shared diagnostic metadata" do
    id = Ipse.Usage.id()
    {:ok, effective} = Source.build(id, 0, %{"type" => "synthetic"})

    record =
      Answer.build(
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        %{
          "role" => "assistant",
          "content" => "private original",
          "provider_data" => %{"secret" => "native secret"}
        },
        "private presented",
        effective
      )

    assert Answer.valid?(record)
    {:ok, source} = Source.build(id, 1, record)
    {:ok, original} = Event.project(source, record, "answer.original")
    {:ok, presented} = Event.project(source, record, "answer.presented")
    assert original["data"]["text"] == "private original"
    assert presented["data"]["text"] == "private presented"
    assert original["event_id"] == presented["event_id"]
    {:ok, wrapper} = Ipse.Observability.Event.build(source, record, 1, 0)
    assert Ipse.Observability.Event.valid?(wrapper)
    assert wrapper["group"] == "stream"
    assert wrapper["event"]["correlations"]["causing_event_id"] == effective["event_id"]
    refute Jason.encode!(wrapper) =~ "private"
    refute Jason.encode!(wrapper) =~ "sha256"
    refute Jason.encode!(original) =~ "native secret"
  end

  test "an unavailable private view keeps counts and hashes without a truncated substitute" do
    id = Ipse.Usage.id()
    {:ok, effective} = Source.build(id, 0, %{"type" => "synthetic"})

    record =
      Answer.build(
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        %{"role" => "assistant", "content" => String.duplicate("a", 8193)},
        "small",
        effective
      )

    assert Answer.valid?(record)
    {:ok, source} = Source.build(id, 1, record)

    assert {:error, :private_lifecycle_view_too_large} =
             Event.project(source, record, "answer.original")

    assert {:ok, %{"data" => %{"text" => "small"}}} =
             Event.project(source, record, "answer.presented")

    assert {:ok, %{"data" => %{"original_bytes" => 8193}}} =
             Event.project(source, record, "metadata")

    refute Answer.valid?(Map.put(record, "original_bytes", 1))
    refute Answer.valid?(Map.put(record, "presented", "forged"))
    refute Answer.valid?(Map.put(record, "private_extra", "no"))
  end
end
