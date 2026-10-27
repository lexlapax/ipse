defmodule Ipse.Extension.ManagedCollectionAccountingTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.ManagedCollectionCall
  alias Ipse.JSON

  # A source-derived fixture exposes unreachable arithmetic/capture fault paths;
  # real protected publication is exercised separately by the Session tests.
  setup_all do
    source =
      File.read!(Path.expand("../../../lib/ipse/extension/managed_collection_call.ex", __DIR__))

    source =
      String.replace(
        source,
        "defmodule Ipse.Extension.ManagedCollectionCall do",
        "defmodule Ipse.Test.ManagedAccountingFixture do",
        global: false
      )

    source =
      Enum.reduce(
        ~w(accounting_scope capture_accounting measured_accounting captured_accounting within_reservation?),
        source,
        fn name, text -> String.replace(text, "defp " <> name <> "(", "def " <> name <> "(") end
      )

    Code.compile_string(source, "source-derived-managed-accounting-fixture.ex")
    :ok
  end

  defp fixture, do: Module.concat(["Ipse", "Test", "ManagedAccountingFixture"])
  defp request, do: %{"request" => %{"changes" => []}, "op" => "fixture"}
  defp normalized, do: %{"changes" => [%{"value" => %{"text" => "café"}}]}
  defp receipt, do: %{"version" => 2}
  defp operation, do: {String.duplicate("a", 32), String.duplicate("a", 32)}
  defp result, do: {:ok, normalized(), receipt()}

  test "actual input uses encoded outer, normalized delta and receipt with every other dimension retained" do
    r = request()
    reserved = ManagedCollectionCall.reservation(r)
    assert {:ok, actual} = fixture().measured_accounting(r, normalized(), receipt(), reserved)

    assert actual["input_bytes"] ==
             byte_size(Jason.encode!(r)) +
               byte_size(Jason.encode!(normalized())) - byte_size(Jason.encode!(r["request"])) +
               byte_size(Jason.encode!(receipt()))

    assert Map.delete(actual, "input_bytes") == Map.delete(reserved, "input_bytes")
    assert actual["input_bytes"] < reserved["input_bytes"]
  end

  test "negative delta, oversized receipt and every invalid reservation dimension refuse" do
    r = request()
    reserved = ManagedCollectionCall.reservation(r)

    for {normalized, receipt, limit} <- [
          {%{}, receipt(), reserved},
          {normalized(), %{"text" => String.duplicate("x", 2048)}, reserved},
          {normalized(), receipt(), Map.put(reserved, "input_bytes", 1)},
          {normalized(), receipt(), Map.put(reserved, "operations", 0)},
          {normalized(), receipt(), Map.put(reserved, "output_bytes", 0)},
          {normalized(), receipt(), Map.put(reserved, "input_bytes", 9_007_199_254_740_992)},
          {normalized(), receipt(), Map.put(reserved, "input_bytes", 1.0)},
          {normalized(), receipt(), Map.delete(reserved, "operations")}
        ] do
      assert {:error, :collection_accounting_invalid} =
               fixture().measured_accounting(r, normalized, receipt, limit)
    end
  end

  test "only a single same-process capture can match the exact successful result" do
    fixture().accounting_scope(fn key, owner ->
      assert Process.get(key) == nil
      reserved = ManagedCollectionCall.reservation(request())

      assert result() ==
               fixture().capture_accounting(
                 key,
                 owner,
                 operation(),
                 request(),
                 reserved,
                 &result/0
               )

      value = %{
        "receipt" => %{"request_sha256" => JSON.digest([normalized()])},
        "normalization" => receipt(),
        "binding" => %{"normalization_sha256" => JSON.digest([receipt()])}
      }

      assert {:error, _} =
               fixture().captured_accounting(
                 key,
                 owner,
                 String.duplicate("b", 32),
                 value,
                 reserved
               )

      assert {:ok, _} =
               fixture().captured_accounting(key, owner, elem(operation(), 0), value, reserved)

      for changed <- [
            put_in(value, ["receipt", "request_sha256"], JSON.sha256("wrong")),
            Map.put(value, "normalization", %{}),
            put_in(value, ["binding", "normalization_sha256"], JSON.sha256("wrong"))
          ] do
        assert {:error, _} =
                 fixture().captured_accounting(
                   key,
                   owner,
                   elem(operation(), 0),
                   changed,
                   reserved
                 )
      end

      assert {:error, _} =
               fixture().capture_accounting(key, owner, operation(), request(), reserved, fn ->
                 flunk("repeat ran")
               end)

      assert {:error, _} =
               fixture().captured_accounting(key, owner, elem(operation(), 0), value, reserved)
    end)
  end

  test "foreign process cannot capture and failed or raised callbacks leave no private slot" do
    before = Process.get()

    assert_raise RuntimeError, "synthetic callback", fn ->
      fixture().accounting_scope(fn key, owner ->
        r = request()
        reserved = ManagedCollectionCall.reservation(r)

        task =
          Task.async(fn ->
            fixture().capture_accounting(key, owner, operation(), r, reserved, fn ->
              flunk("foreign ran")
            end)
          end)

        assert {:error, _} = Task.await(task)
        assert Process.get(key) == nil

        fixture().capture_accounting(key, owner, operation(), r, reserved, fn ->
          raise "synthetic callback"
        end)
      end)
    end

    assert Process.get() |> Enum.sort() == Enum.sort(before)

    assert {:error, :synthetic_refusal} =
             fixture().accounting_scope(fn key, owner ->
               fixture().capture_accounting(
                 key,
                 owner,
                 operation(),
                 request(),
                 ManagedCollectionCall.reservation(request()),
                 fn -> {:error, :synthetic_refusal} end
               )
             end)

    assert Process.get() |> Enum.sort() == Enum.sort(before)
  end

  test "a mismatched operation witness refuses before normalization and cannot be replaced" do
    fixture().accounting_scope(fn key, owner ->
      reserved = ManagedCollectionCall.reservation(request())
      wrong = {elem(operation(), 0), String.duplicate("b", 32)}

      assert {:error, :collection_accounting_invalid} =
               fixture().capture_accounting(key, owner, wrong, request(), reserved, fn ->
                 flunk("wrong operation normalized")
               end)

      assert Process.get(key) == :invalid

      assert {:error, :collection_accounting_invalid} =
               fixture().capture_accounting(key, owner, operation(), request(), reserved, fn ->
                 flunk("replacement normalized")
               end)
    end)
  end
end
