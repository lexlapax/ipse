defmodule Ipse.Test.TransactionFixtureLoader do
  @moduledoc false
  @source Path.expand("../../lib/ipse/runner/transaction.ex", __DIR__)

  # Compile the production implementation under a distinct fixture name. Only
  # helper selection changes; production accepts no ambient helper override.
  # Dynamic fixtures need no Inspect implementation in the consolidated VM.
  def load do
    :global.trans({{__MODULE__, :transaction}, self()}, fn -> load_transaction() end, [node()])
  end

  defp load_transaction do
    unless Code.ensure_loaded?(Ipse.Test.TransactionFixture) do
      @source
      |> File.read!()
      |> String.replace("Ipse.Runner.Transaction", "Ipse.Test.TransactionFixture")
      |> String.replace("Ipse.Runner.protected_helper(cwd)", "Ipse.Runner.native_helper(cwd)")
      |> String.replace(
        ~r/    defimpl Inspect do\n      def inspect\(_, _\), do: "#Transaction.Capability<private>"\n    end\n/,
        ""
      )
      |> Code.compile_string(@source <> ":fixture")
    end

    :ok
  end

  def load_project do
    :ok = load()
    :global.trans({{__MODULE__, :project}, self()}, fn -> load_project_source() end, [node()])
  end

  defp load_project_source do
    unless Code.ensure_loaded?(Ipse.Test.ProjectIdentityFixture) do
      path = Path.expand("../../lib/ipse/extension/project_identity.ex", __DIR__)

      path
      |> File.read!()
      |> String.replace("Ipse.Extension.ProjectIdentity", "Ipse.Test.ProjectIdentityFixture")
      |> String.replace(
        "Ipse.Test.ProjectIdentityFixture.DomainAuth",
        "Ipse.Extension.ProjectIdentity.DomainAuth"
      )
      |> String.replace("Ipse.Runner.Transaction", "Ipse.Test.TransactionFixture")
      |> String.replace(
        "alias Ipse.Test.TransactionFixture\n",
        "alias Ipse.Test.TransactionFixture, as: Transaction\n"
      )
      |> String.replace(
        "Ipse.Runner.protected_helper(context.cwd)",
        "Ipse.Runner.native_helper(context.cwd)"
      )
      |> String.replace("Ipse.Runner.protected_current_uid()", "Ipse.Runner.current_uid()")
      |> String.replace("Ipse.Runner.protected_sync_directory(", "Ipse.Runner.sync_directory(")
      |> Code.compile_string(path <> ":fixture")
    end

    :ok
  end
end
