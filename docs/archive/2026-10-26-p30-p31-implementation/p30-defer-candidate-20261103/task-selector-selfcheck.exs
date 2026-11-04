Process.register(self(), :p30_selector_observer)
ExUnit.start(
  autorun: false,
  seed: 0,
  exclude: [:test],
  include: [test: :"test actual bundled shadow Session is deferred candidate"]
)
defmodule P30SelectorControl do
  use ExUnit.Case, async: false
  for name <- [
        "approved",
        "deferred candidate",
        "mixed literal and pending sources",
        "low confidence",
        "unknown decision remains charged and is not replayed",
        "source withdrawn before decision",
        "source withdrawn before output release",
        "denied",
        "revoked grant",
        "expired while preflight is blocked",
        "expired while result admission is blocked"
      ] do
    test "actual bundled shadow Session is #{name}" do
      send(:p30_selector_observer, unquote(name))
    end
  end
end
%{total: 11, excluded: 10, skipped: 0, failures: 0} = ExUnit.run()
receive do
  "deferred candidate" -> :ok
  other -> raise "unexpected selected test: #{inspect(other)}"
after
  100 -> raise "no selected test"
end
receive do
  other -> raise "extra test ran: #{inspect(other)}"
after
  0 -> IO.puts("SELECTOR_EXACT_NAME_ONLY")
end
