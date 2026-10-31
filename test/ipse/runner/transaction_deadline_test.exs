defmodule Ipse.Runner.TransactionDeadlineTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner.Transaction
  alias Ipse.Session.Resources

  @tag :retention_deadline_fence
  test "trusted root deadline switches preserve pre-rename refusal and ordinary switching" do
    root = Path.join(System.tmp_dir!(), "ipse-native-switch-deadline-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    # Retain this small synthetic directory for uncertain-publication diagnosis.

    assert :ok =
             Resources.file_effect(fn ->
               assert {:ok, cap} = Transaction.acquire(Path.join(root, ".lock"))
               stage = ".pending-" <> Ipse.Usage.id()
               assert :ok = Transaction.stage(cap, ".", [{stage, "original"}])
               assert :ok = Transaction.switch(cap, stage, "root.json")
               stage = ".pending-" <> Ipse.Usage.id()
               assert :ok = Transaction.stage(cap, ".", [{stage, "reviewed"}])

               for deadline <- [0, -1, 9_007_199_254_740_992, "future", nil] do
                 assert {:error, :invalid_transaction_request} =
                          Transaction.switch_before(cap, stage, "root.json", deadline)
               end

               assert {:error, :invalid_transaction_request} =
                        Transaction.switch_before(
                          cap,
                          stage,
                          "control.json",
                          System.system_time(:millisecond) + 60_000
                        )

               assert {:error, :transaction_write_deadline_elapsed} =
                        Transaction.switch_before(
                          cap,
                          stage,
                          "root.json",
                          System.system_time(:millisecond)
                        )

               assert {:ok, "original"} = Transaction.read(cap, ".", "root.json", 1024)
               assert File.read!(Path.join(root, stage)) == "reviewed"
               assert :ok = Transaction.check(cap)

               assert :ok =
                        Transaction.switch_before(
                          cap,
                          stage,
                          "root.json",
                          System.system_time(:millisecond) + 60_000
                        )

               assert {:ok, "reviewed"} = Transaction.read(cap, ".", "root.json", 1024)
               assert :ok = Transaction.release(cap)
               :ok
             end)
  end
end
