defmodule Ipse.CLI.InputLifecycleTest do
  use ExUnit.Case, async: false

  test "reader exit precedes the actual Input cleanup barrier" do
    owner = self()
    reader = spawn(fn -> receive do: (:stop -> :ok) end)
    channel = Ipse.Usage.id()

    session =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:release_input_read, ^channel}} ->
            send(owner, {:reader_alive_at_release, Process.alive?(reader)})
            GenServer.reply(from, Ipse.Session.Input.release_for_output())
        end
      end)

    assert :ok = Ipse.CLI.Input.stop_confirmed(reader, session, channel)
    assert_receive {:reader_alive_at_release, false}
    refute Process.alive?(reader)
  end

  test "an unconfirmed Session cleanup cannot authorize the review handoff" do
    reader = spawn(fn -> receive do: (:stop -> :ok) end)
    channel = Ipse.Usage.id()

    session =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:release_input_read, ^channel}} ->
            GenServer.reply(from, {:error, :operator_cleanup_unconfirmed})
        end
      end)

    assert {:error, :operator_cleanup_unconfirmed} =
             Ipse.CLI.Input.stop_confirmed(reader, session, channel)

    refute Process.alive?(reader)
  end
end
