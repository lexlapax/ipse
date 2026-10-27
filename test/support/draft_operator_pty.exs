ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = hd(System.argv())

defmodule DraftPTYProvider do
  def complete(config, messages, _tools, _) do
    send(config.fixture_owner, {:model, messages})
    {:ok, %{"role" => "assistant", "content" => "synthetic proposed request"}, %{}}
  end
end

{:ok, session} =
  Ipse.Session.start_link(
    config: %{
      provider: :demo,
      model: "synthetic",
      provider_module: DraftPTYProvider,
      fixture_owner: self(),
      home: Path.join(root, "home"),
      approval: :deny,
      compact: false
    },
    cwd: root,
    state_dir: Path.join(root, "state"),
    subscriber: self()
  )

Process.unlink(session)
id = Ipse.Session.info(session).id
owner = self()

reader =
  spawn(fn ->
    loop = fn loop ->
      receive do
        {:read, channel, request} ->
          send(
            owner,
            {:read_result, Ipse.Session.observe_channel(session, channel, request, 30_000)}
          )

          loop.(loop)

        :stop ->
          :ok
      end
    end

    loop.(loop)
  end)

{:ok, channel} = Ipse.Session.open_input_channel(session, reader)
send(reader, {:read, channel, %{"kind" => "prompt"}})
assert_receive {:read_result, {:ok, "rejected original" = rejected, witness}}, 5_000
assert {:ok, rejected_ticket} = Ipse.Session.stage_input(session, channel, rejected, witness)

assert {:error, :invalid_input_witness} =
         Ipse.Session.replace_draft_observed(
           session,
           channel,
           Ipse.Usage.id(),
           1,
           rejected,
           rejected_ticket
         )

assert {:error, :invalid_input_witness} = Ipse.Session.prompt(session, rejected, rejected_ticket)
send(reader, {:read, channel, %{"kind" => "prompt"}})
assert_receive {:read_result, {:ok, "synthetic draft input" = original, original_witness}}, 5_000

assert {:ok, original_ticket} =
         Ipse.Session.stage_input(session, channel, original, original_witness)

assert :ok = Ipse.Session.start_draft_observed(session, channel, original, original_ticket)
assert_receive {:model, _}, 5_000
assert_receive {:ipse, ^session, {:done, :ok}}, 5_000
{:ok, %{id: draft_id, revision: revision}} = Ipse.Session.draft(session)

assert {:error, :invalid_input_witness} =
         Ipse.Session.replace_draft_observed(
           session,
           channel,
           draft_id,
           revision,
           original,
           original_ticket
         )

assert {:ok, %{"render_id" => first}} =
         Ipse.Session.render_draft(session, channel, draft_id, revision)

assert {:error, :invalid_draft_acceptance} =
         Ipse.Session.accept_draft_observed(session, channel, first, "accept forged", make_ref())

assert {:ok, %{"render_id" => _stale}} =
         Ipse.Session.render_draft(session, channel, draft_id, revision)

send(reader, {:read, channel, %{"kind" => "prompt"}})

assert_receive {:read_result, {:ok, "rejected replacement" = rejected_replace, rejected_witness}},
               5_000

assert {:ok, rejected_ticket2} =
         Ipse.Session.stage_input(session, channel, rejected_replace, rejected_witness)

assert {:error, :invalid_input_witness} =
         Ipse.Session.replace_draft_observed(
           session,
           channel,
           draft_id,
           revision + 1,
           rejected_replace,
           rejected_ticket2
         )

assert {:error, :draft_recovery_required} =
         Ipse.Session.prompt(session, rejected_replace, rejected_ticket2)

assert {:error, :invalid_input_witness} =
         Ipse.Session.discard_input(session, channel, rejected_ticket2)

send(reader, {:read, channel, %{"kind" => "prompt"}})

assert_receive {:read_result,
                {:ok, "synthetic proposed request" = replacement, replacement_witness}},
               5_000

assert {:ok, replacement_ticket} =
         Ipse.Session.stage_input(session, channel, replacement, replacement_witness)

assert {:error, :invalid_input_witness} =
         Task.async(fn ->
           Ipse.Session.replace_draft_observed(
             session,
             channel,
             draft_id,
             revision,
             replacement,
             replacement_ticket
           )
         end)
         |> Task.await()

assert :ok =
         Ipse.Session.replace_draft_observed(
           session,
           channel,
           draft_id,
           revision,
           replacement,
           replacement_ticket
         )

assert {:error, :stale_draft} = Ipse.Session.render_draft(session, channel, draft_id, revision)

assert {:ok, %{"render_id" => render}} =
         Ipse.Session.render_draft(session, channel, draft_id, revision + 1)

send(reader, {:read, channel, %{"kind" => "draft", "render_id" => render}})
assert_receive {:read_result, {:ok, text, witness}}, 5_000

assert {:error, :invalid_draft_acceptance} =
         Task.async(fn ->
           Ipse.Session.accept_draft_observed(session, channel, render, text, witness)
         end)
         |> Task.await()

assert {:error, :invalid_draft_acceptance} =
         Ipse.Session.accept_draft_observed(session, channel, Ipse.Usage.id(), text, witness)

assert {:error, :invalid_draft_acceptance} =
         Ipse.Session.accept_draft_observed(session, channel, render, text, witness)

assert {:ok, %{"render_id" => render}} =
         Ipse.Session.render_draft(session, channel, draft_id, revision + 1)

send(reader, {:read, channel, %{"kind" => "draft", "render_id" => render}})
assert_receive {:read_result, {:ok, text, witness}}, 5_000
assert :ok = Ipse.Session.accept_draft_observed(session, channel, render, text, witness)
assert_receive {:model, messages}, 5_000
refute inspect(messages) =~ "synthetic draft input"
assert_receive {:ipse, ^session, {:done, :ok}}, 5_000

assert {:error, :invalid_draft_acceptance} =
         Ipse.Session.accept_draft_observed(session, channel, render, text, witness)

assert :ok = Ipse.Session.close_confirmed(session)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
assert Enum.any?(events, &(&1["type"] == "draft_accepted" and &1["version"] == 2))

assert Enum.any?(
         events,
         &(&1["type"] == "input_received" and &1["origin"] == "interactive_operator" and
             &1["text"] == original)
       )

assert Enum.any?(
         events,
         &(&1["type"] == "draft_replaced" and &1["version"] == 2 and &1["text"] == replacement)
       )

assert {:ok, %{draft: %{status: :consumed}}} = Ipse.Session.Saved.restore(events, id)

for type <- ["input_received", "draft_replaced", "draft_accepted"] do
  forged =
    Enum.map(events, fn event ->
      cond do
        event["type"] != type ->
          event

        type == "input_received" and event["text"] != original ->
          event

        type == "draft_accepted" ->
          put_in(event, ["receipt", "observation", "display_sha256"], String.duplicate("0", 64))

        true ->
          put_in(event, ["observation", "text_sha256"], String.duplicate("0", 64))
      end
    end)

  assert {:error, _} = Ipse.Session.Saved.restore(forged, id)
end

unverified =
  Enum.map(events, fn
    %{"type" => "draft_accepted"} = event ->
      event |> Map.put("version", 1) |> Map.delete("receipt")

    event ->
      event
  end)

assert {:error, _} = Ipse.Session.Saved.restore(unverified, id)

{:ok, second} =
  Ipse.Session.start_link(
    config: %{
      provider: :demo,
      model: "synthetic",
      provider_module: DraftPTYProvider,
      fixture_owner: self(),
      home: Path.join(root, "home"),
      approval: :deny,
      compact: false
    },
    cwd: root,
    state_dir: Path.join(root, "state2"),
    subscriber: self()
  )

Process.unlink(second)

second_reader =
  spawn(fn ->
    receive do
      {:read, ch} ->
        send(
          owner,
          {:second_read, Ipse.Session.observe_channel(second, ch, %{"kind" => "prompt"}, 30_000)}
        )

        receive do: (:stop -> :ok)
    end
  end)

{:ok, second_channel} = Ipse.Session.open_input_channel(second, second_reader)
assert :ok = Ipse.Session.start_draft(second, "another draft")
assert_receive {:model, _}, 5_000
assert_receive {:ipse, ^second, {:done, :ok}}, 5_000
send(second_reader, {:read, second_channel})

assert_receive {:second_read, {:ok, "staged before cancellation" = pending, pending_witness}},
               5_000

assert {:ok, pending_ticket} =
         Ipse.Session.stage_input(second, second_channel, pending, pending_witness)

assert :ok = Ipse.Session.cancel_draft(second)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(second, pending, pending_ticket)
assert :ok = Ipse.Session.close_confirmed(second)

{:ok, third} =
  Ipse.Session.start_link(
    config: %{
      provider: :demo,
      model: "synthetic",
      provider_module: DraftPTYProvider,
      fixture_owner: self(),
      home: Path.join(root, "home"),
      approval: :deny,
      compact: false
    },
    cwd: root,
    state_dir: Path.join(root, "state3"),
    subscriber: self()
  )

Process.unlink(third)

third_reader =
  spawn(fn ->
    loop = fn loop ->
      receive do
        {:read, ch, request} ->
          send(owner, {:third_read, Ipse.Session.observe_channel(third, ch, request, 30_000)})
          loop.(loop)

        :stop ->
          :ok
      end
    end

    loop.(loop)
  end)

{:ok, third_channel} = Ipse.Session.open_input_channel(third, third_reader)
assert :ok = Ipse.Session.start_draft(third, "owner loss draft")
assert_receive {:model, _}, 5_000
assert_receive {:ipse, ^third, {:done, :ok}}, 5_000
send(third_reader, {:read, third_channel, %{"kind" => "prompt"}})
assert_receive {:third_read, {:ok, "staged before owner loss" = pending3, witness3}}, 5_000
assert {:ok, ticket3} = Ipse.Session.stage_input(third, third_channel, pending3, witness3)
assert Map.has_key?(:sys.get_state(Ipse.Session.Input).entries, ticket3)
{:ok, %{id: third_draft, revision: third_revision}} = Ipse.Session.draft(third)

assert {:ok, %{"render_id" => third_render}} =
         Ipse.Session.render_draft(third, third_channel, third_draft, third_revision)

send(third_reader, {:read, third_channel, %{"kind" => "draft", "render_id" => third_render}})
assert_receive {:third_read, {:ok, _, third_witness}}, 5_000
assert Map.has_key?(:sys.get_state(Ipse.Session.Input).entries, third_witness)
third_monitor = Process.monitor(third)
Process.exit(third, :kill)
assert_receive {:DOWN, ^third_monitor, :process, ^third, _}, 5_000

wait_removed = fn wait_removed, attempts ->
  cond do
    not Map.has_key?(:sys.get_state(Ipse.Session.Input).entries, ticket3) and
        not Map.has_key?(:sys.get_state(Ipse.Session.Input).entries, third_witness) ->
      :ok

    attempts == 0 ->
      flunk("owner loss left a staged input")

    true ->
      Process.sleep(5)
      wait_removed.(wait_removed, attempts - 1)
  end
end

wait_removed.(wait_removed, 1000)
IO.puts("SYNTHETIC_DRAFT_OPERATOR_WITNESS_PASSED")
