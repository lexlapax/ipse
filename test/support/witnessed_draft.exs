defmodule Ipse.Test.WitnessedDraft do
  import ExUnit.Assertions

  def run(root, entry) do
    driver = Path.join(root, "draft-lineage-pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--draft-accept-one", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand(entry), root],
        env: [{"IPSE_WITNESSED_DRAFT_CHILD", "1"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "1 passed"
  end

  def accept(session, draft_id, revision) do
    client = self()

    reader =
      spawn(fn ->
        receive do
          {:read, channel, render} ->
            send(
              client,
              {:draft_observed,
               Ipse.Session.observe_channel(
                 session,
                 channel,
                 %{"kind" => "draft", "render_id" => render},
                 30_000
               )}
            )

            receive do
              :stop -> :ok
            end
        end
      end)

    try do
      {:ok, channel} = Ipse.Session.open_input_channel(session, reader)

      {:ok, %{"render_id" => render}} =
        Ipse.Session.render_draft(session, channel, draft_id, revision)

      send(reader, {:read, channel, render})
      assert_receive {:draft_observed, {:ok, input, witness}}, 10_000
      assert :ok = Ipse.Session.accept_draft_observed(session, channel, render, input, witness)
      :ok
    after
      Process.exit(reader, :kill)
    end
  end
end
