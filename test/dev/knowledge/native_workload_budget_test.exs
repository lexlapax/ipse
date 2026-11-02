Code.require_file("../../../dev/knowledge/storage_workload.ex", __DIR__)

defmodule Ipse.Development.NativeWorkloadBudgetTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.StorageWorkload

  test "complete lifecycle cycles cannot borrow the primitive churn's identity count" do
    mixed = StorageWorkload.native_operation_floor(365, 10_000, :mixed_operations)
    complete = StorageWorkload.native_operation_floor(365, 10_000, :complete_cycles)
    assert mixed["minimum_operations"] == 22_980
    assert complete["minimum_operations"] == 42_980
    assert mixed["minimum_operations_by_effect"]["additional_churn"] == 10_000
    assert complete["minimum_operations_by_effect"]["additional_churn"] == 30_000
    assert mixed["disposition"] == "not_ruled_out_by_operation_floor"
    assert complete["disposition"] == "exceeds_current_operation_limit"
    assert complete["current_operation_limit"] == Ipse.Extension.Collection.limits()["operations"]
    assert complete["minimum_excess"] == 10_212

    for report <- [mixed, complete] do
      assert report["actual_native_operations"] == 0
      assert report["actual_turns"] == 0
      assert report["qualification_passed"] == false
      assert "expiry" in report["unaccounted_operations"]
      assert "imports" in report["unaccounted_operations"]
      assert "compaction" in report["unaccounted_operations"]
    end
  end

  test "initial floor and the declared day-90 burst survive a zero-churn request" do
    early = StorageWorkload.native_operation_floor(30, 0, :complete_cycles)
    before_burst = StorageWorkload.native_operation_floor(89, 0, :complete_cycles)
    after_burst = StorageWorkload.native_operation_floor(90, 0, :complete_cycles)
    assert early["minimum_operations"] == 2900
    assert early["minimum_operations_by_effect"]["initial_records"] == 2000
    assert early["minimum_operations_by_effect"]["ordinary_additions"] == 600
    assert after_burst["minimum_operations"] - before_burst["minimum_operations"] == 60
    assert after_burst["minimum_operations_by_effect"]["temporal_supersessions"] == 364
  end

  test "missing interpretation and out-of-contract workloads cannot silently choose weaker semantics" do
    for arguments <- [
          [365, 10_000, nil],
          [365, 10_000, :primitive],
          [0, 10_000, :complete_cycles],
          [366, 10_000, :complete_cycles],
          [365, 10_001, :mixed_operations],
          [365, -1, :mixed_operations]
        ] do
      assert_raise FunctionClauseError, fn ->
        apply(StorageWorkload, :native_operation_floor, arguments)
      end
    end
  end
end
