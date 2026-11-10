Code.require_file("../../../extensions/knowledge/src/store/collection/projection.ex", __DIR__)

defmodule Ipse.KnowledgeProjectionCapacityTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Store.Collection.Projection

  # The reference geometry in dev/knowledge/collection_profile_operations.exs.
  defp live_keys(n), do: 8 * n + 1 + div(n + 15, 16) + 2 * div(n + 7, 8) + 2

  test "per-source projections stop at the last source count that fits 8,192 live keys" do
    assert live_keys(1000) == 8_316
    assert live_keys(984) <= 8_192 and live_keys(985) > 8_192
    assert Projection.per_source_capacity?(0)
    assert Projection.per_source_capacity?(984)
    refute Projection.per_source_capacity?(985)
    refute Projection.per_source_capacity?(nil)
    refute Projection.per_source_capacity?(-1)
  end
end
