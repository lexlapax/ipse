Code.require_file("../../../dev/knowledge/interaction.exs", __DIR__)

defmodule Ipse.Development.Knowledge.InteractionTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Knowledge.Interaction, as: I

  defp enabled do
    {s, _} = I.new("project", "chat-1", 0) |> I.enable()
    I.new_session(s, "chat-2")
  end

  test "enablement pins the current conversation; revocation invalidates its publication" do
    s = I.new("project", "chat-1", 0)
    {selected, notice} = I.enable(s)
    assert notice =~ "next new session"
    refute selected.current
    assert I.new_session(selected, "new").current
    refute I.disable(I.new_session(selected, "new")).active
    {reenabled, _} = I.new_session(selected, "new") |> I.disable() |> I.enable()
    refute reenabled.current
  end

  test "only explicitly rendered codes accept the displayed version without changing provenance" do
    {:ok, s, id} = I.propose(enabled(), "Use archive storage", :run_input)
    assert {:error, :operator_channel_required} = I.render(s, id, :stdin)
    {:ok, rendered, card} = I.render(s, id, :simulated_verified_terminal)
    assert card.origin == :run_input
    assert {:error, _} = I.accept(rendered, "yes", :simulated_verified_terminal)
    assert {:error, _} = I.accept(rendered, card.command, :stdin)
    {:ok, accepted, event} = I.accept(rendered, card.command, :simulated_verified_terminal)
    assert event.original_origin == :run_input
    assert event.permissions_granted == []
    assert {:error, _} = I.accept(accepted, card.command, :simulated_verified_terminal)
  end

  test "stale, cross-client, expired, disabled and ceiling-blocked acceptances refuse" do
    {:ok, s, id} = I.propose(enabled(), "Pin the chosen policy", :assistant)
    {:ok, s, card} = I.render(s, id, :simulated_verified_terminal)
    {:ok, corrected} = I.correct(s, id, "Corrected policy")

    for invalid <- [
          corrected,
          I.new_session(s, "other-chat"),
          I.advance(s, 7 * 86_400_000),
          I.disable(s),
          I.mode(s, :planning),
          I.mode(s, :read_only),
          %{s | project: "other-project"}
        ] do
      assert {:error, _} = I.accept(invalid, card.command, :simulated_verified_terminal)
    end

    {:ok, redisplayed, _fresh} = I.render(s, id, :simulated_verified_terminal)
    assert {:error, _} = I.accept(redisplayed, card.command, :simulated_verified_terminal)
  end

  test "multiple cards cannot infer a target from a bare affirmative" do
    {:ok, s, a} = I.propose(enabled(), "Use the first strategy", :assistant)
    {:ok, s, b} = I.propose(s, "Use the second strategy", :assistant)
    {:ok, s, first} = I.render(s, a, :simulated_verified_terminal)
    {:ok, s, _second} = I.render(s, b, :simulated_verified_terminal)
    assert {:error, _} = I.accept(s, "yes", :simulated_verified_terminal)
    {:ok, s, _} = I.accept(s, first.command, :simulated_verified_terminal)
    assert s.candidates[b].status == :pending
  end

  test "candidate origin binds its project before any rendering" do
    {:ok, s, id} = I.propose(enabled(), "Project-bound choice", :assistant)
    changed = %{s | project: "other-project"}
    assert {:error, _} = I.render(changed, id, :simulated_verified_terminal)
    assert {:error, _} = I.correct(changed, id, "Rewritten in another project")
  end

  test "a same-client session transition still invalidates every displayed code" do
    {:ok, s, id} = I.propose(enabled(), "A pending choice", :assistant)
    {:ok, s, card} = I.render(s, id, :simulated_verified_terminal)
    resumed = I.new_session(s, s.client)
    assert {:error, _} = I.accept(resumed, card.command, :simulated_verified_terminal)
    {:ok, resumed, fresh} = I.render(resumed, id, :simulated_verified_terminal)
    assert {:ok, _, _} = I.accept(resumed, fresh.command, :simulated_verified_terminal)
  end

  test "correction cannot exceed the aggregate pending byte quota" do
    {s, ids} =
      Enum.reduce(1..64, {enabled(), []}, fn _, {s, ids} ->
        {:ok, s, id} = I.propose(s, "a", :assistant)
        {s, [id | ids]}
      end)

    {s, accepted, refused} =
      Enum.reduce(ids, {s, 0, 0}, fn id, {s, accepted, refused} ->
        case I.correct(s, id, String.duplicate("x", 6_144)) do
          {:ok, next} -> {next, accepted + 1, refused}
          {:error, _} -> {s, accepted, refused + 1}
        end
      end)

    assert accepted > 0 and accepted < 64
    assert refused == 64 - accepted
    payload = Map.new(s.candidates, fn {id, c} -> {id, Map.delete(c, :render)} end)
    assert byte_size(JSON.encode!(payload)) <= 262_144
  end

  test "saturated proposals reserve status-transition bytes before rendering" do
    s =
      Enum.reduce(1..64, enabled(), fn _, s ->
        {:ok, s, _} = I.propose(s, "a", :assistant)
        s
      end)

    s =
      Enum.reduce(Map.keys(s.candidates), s, fn id, s ->
        reserved =
          Map.new(s.candidates, fn {key, c} ->
            {key, c |> Map.delete(:render) |> Map.put(:status, :accepted)}
          end)

        size = min(6_144, 262_144 - byte_size(JSON.encode!(reserved)) + 1)
        {:ok, s} = I.correct(s, id, String.duplicate("x", size))
        s
      end)

    s =
      Enum.reduce(Map.keys(s.candidates), s, fn id, s ->
        {:ok, s, card} = I.render(s, id, :simulated_verified_terminal)
        {:ok, s, _} = I.accept(s, card.command, :simulated_verified_terminal)
        s
      end)

    payload = Map.new(s.candidates, fn {id, c} -> {id, Map.delete(c, :render)} end)
    assert byte_size(JSON.encode!(payload)) == 262_144
  end

  test "consumption never discards a stricter mode selected after draft acceptance" do
    for {enclosing, current, expected} <- [
          {:ordinary, :read_only, :read_only},
          {:ordinary, :planning, :planning},
          {:planning, :read_only, :read_only},
          {:read_only, :ordinary, :read_only}
        ] do
      {:ok, s} = I.draft(I.mode(enabled(), enclosing), "Inspect the evidence")
      {:ok, s} = I.accept_draft(s, s.draft.id, s.draft.version)
      {:ok, s, _} = s |> I.mode(current) |> I.consume()
      assert s.mode == expected
    end
  end

  test "draft replacement invalidates acceptance and is consumed once under its enclosing mode" do
    {:ok, s} = I.draft(I.mode(enabled(), :planning), "Read the ledger")
    original = s.draft
    {:ok, s} = I.replace(s, "Read the ledger\nand explain the missing evidence")
    assert {:error, _} = I.accept_draft(s, original.id, original.version)
    {:ok, s} = I.accept_draft(s, s.draft.id, s.draft.version)
    {:ok, s, submitted} = I.consume(s)
    assert submitted == "Read the ledger\nand explain the missing evidence"
    assert s.mode == :planning
    assert {:error, _} = I.consume(s)
  end

  test "cancel records intent status without repeating abandoned content" do
    {:ok, s} = I.draft(enabled(), "Write cancelled-canary.txt")
    {:ok, s, notice} = I.cancel(s)
    refute notice =~ "cancelled-canary"
    assert s.draft.status == :cancelled
    assert {:error, _} = I.accept_draft(s, s.draft.id, s.draft.version)
    assert {:error, _} = I.consume(s)
    assert {:ok, _} = I.draft(s, "Read README.md")
  end

  test "pending capacity and UTF-8 bounds refuse instead of evicting items" do
    s =
      Enum.reduce(1..64, enabled(), fn _, s ->
        {:ok, s, _} = I.propose(s, "a", :assistant)
        s
      end)

    assert {:error, _} = I.propose(s, "overflow", :assistant)
    assert map_size(s.candidates) == 64
    assert {:error, _} = I.propose(enabled(), <<255>>, :assistant)
    assert {:error, _} = I.propose(enabled(), String.duplicate("x", 6_145), :assistant)
  end
end
