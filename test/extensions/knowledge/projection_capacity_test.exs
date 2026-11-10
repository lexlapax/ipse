defmodule Ipse.KnowledgeProjectionCapacityTest do
  use ExUnit.Case, async: false

  # Other suites require the Collection modules to be absent from this VM, so
  # the module is compiled for this case only and removed afterwards.
  setup_all do
    module = Module.concat(["IpseKnowledge", "Store", "Collection", "Projection"])
    loaded = :code.is_loaded(module) != false

    unless loaded,
      do:
        Code.compile_file(Path.expand("extensions/knowledge/src/store/collection/projection.ex"))

    on_exit(fn ->
      unless loaded do
        :code.delete(module)
        :code.purge(module)
      end
    end)

    %{projection: module}
  end

  # The reference geometry in dev/knowledge/collection_profile_operations.exs.
  defp live_keys(n), do: 8 * n + 1 + div(n + 15, 16) + 2 * div(n + 7, 8) + 2

  test "per-source projections stop at the last source count that fits 8,192 live keys", c do
    capacity? = &apply(c.projection, :per_source_capacity?, [&1])
    assert live_keys(1000) == 8_316
    assert live_keys(984) <= 8_192 and live_keys(985) > 8_192
    assert capacity?.(0)
    assert capacity?.(984)
    refute capacity?.(985)
    refute capacity?.(nil)
    refute capacity?.(-1)
  end
end
