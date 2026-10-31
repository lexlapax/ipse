defmodule Ipse.MCP.ManagedHTTPUnknownTest do
  use ExUnit.Case, async: false

  for mode <- ~w(observation_failure transport_unknown) do
    @tag unknown_transport: mode == "transport_unknown"
    test "#{mode} preserves cleanup uncertainty in an isolated runtime" do
      paths = :code.get_path() |> Enum.reverse() |> Enum.flat_map(&["-pa", to_string(&1)])
      fixture = Path.expand("../../support/managed_http_unknown.exs", __DIR__)

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 2:2"] ++ paths ++ [fixture, unquote(mode)],
          stderr_to_stdout: true
        )

      assert status == 0, output
    end
  end
end
