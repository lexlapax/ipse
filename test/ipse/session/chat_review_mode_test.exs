defmodule Ipse.Session.ChatReviewModeTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Mode
  alias Ipse.Session.ChatReviewHandoff
  alias Ipse.Session.ChatReviewHandoff.Handle
  @slot {ChatReviewHandoff, :handoff}

  # Constructed private state exercises projection only; it grants no review authority.
  defp handle(mode, state \\ :claimed) do
    ref = make_ref()
    Process.put(@slot, %{ref: ref, mode: mode, state: state})
    %Handle{owner: self(), ref: ref}
  end

  test "live normal mode replaces stale planning flags without changing service choices" do
    assert {:ok, mode} = Mode.capture(%{approval: :ask, approval_origin: :interactive})

    startup = %{
      approval: :ask,
      approval_origin: :interactive,
      execution_mode: :planning,
      planning_cli_start: true,
      accept_edits: true,
      provider: :local,
      model: "fixture-model",
      base_url: "http://127.0.0.1:9999",
      billing: :fixture
    }

    assert {:ok, config} = ChatReviewHandoff.runtime_config(handle(mode), startup)
    assert {:ok, ^mode} = Mode.capture(config)
    assert config.execution_mode == "normal"
    assert config.planning_cli_start === false
    assert config.accept_edits === false

    assert Map.take(config, [:provider, :model, :base_url, :billing]) ===
             Map.take(startup, [:provider, :model, :base_url, :billing])
  end

  test "explicit broad approval remains the current policy while session grants reset" do
    assert {:ok, mode} = Mode.capture(%{approval: :allow, approval_origin: :yes})
    assert {:ok, config} = ChatReviewHandoff.runtime_config(handle(mode, :closed), %{})
    assert config.approval === :allow
    assert config.approval_origin === "yes"
    assert config.accept_edits === false
    assert {:ok, ^mode} = Mode.capture(config)
  end

  test "foreign owners, stale references and spent handles cannot project configuration" do
    assert {:ok, mode} = Mode.capture(%{})
    active = handle(mode)
    task = Task.async(fn -> ChatReviewHandoff.runtime_config(active, %{}) end)
    assert {:error, :chat_review_unavailable} = Task.await(task)

    assert {:error, :chat_review_unavailable} =
             ChatReviewHandoff.runtime_config(%{active | ref: make_ref()}, %{})

    assert {:error, :chat_review_unavailable} =
             ChatReviewHandoff.runtime_config(handle(mode, :attempted), %{})
  end

  test "missing or prohibited captured modes fail closed" do
    assert {:ok, planning} = Mode.capture(%{execution_mode: :planning})

    assert {:error, :chat_review_unavailable} =
             ChatReviewHandoff.runtime_config(handle(planning), %{})

    ref = make_ref()
    Process.put(@slot, %{ref: ref, state: :claimed})

    assert {:error, :chat_review_unavailable} =
             ChatReviewHandoff.runtime_config(%Handle{owner: self(), ref: ref}, %{})

    assert {:error, :chat_review_unavailable} =
             ChatReviewHandoff.runtime_config(handle(%{}), %{})
  end
end
