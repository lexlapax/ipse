defmodule Ipse.Session.Permissions do
  @moduledoc "Ephemeral native-tool grants owned by one running Session."

  def new(config) do
    %{
      edits:
        Map.get(config, :approval, :ask) == :ask and config[:accept_edits] == true and
          is_nil(config[:delegation_origin]),
      commands: []
    }
  end

  def source(s, name, args) do
    cond do
      Map.get(s.config, :approval, :ask) != :ask or s.config[:delegation_origin] != nil -> nil
      name in ["write", "edit"] and s.permissions.edits -> "workspace_edits"
      name == "shell" and key(s, args) in s.permissions.commands -> "exact_command"
      true -> nil
    end
  end

  def grant(s, name, _args, :session_edits) when name in ["write", "edit"] do
    if eligible?(s),
      do: {:ok, %{s.permissions | edits: true}, "workspace_edits"},
      else: {:error, :grant_unavailable}
  end

  def grant(s, "shell", args, :session_command) do
    if eligible?(s) and is_binary(args["command"]) and
         byte_size(Jason.encode!(args)) <= 16_384 and length(s.permissions.commands) < 32 do
      commands = Enum.uniq([key(s, args) | s.permissions.commands])
      {:ok, %{s.permissions | commands: commands}, "exact_command"}
    else
      {:error, :grant_unavailable}
    end
  end

  def grant(_, _, _, _), do: {:error, :grant_unavailable}

  def snapshot(s) do
    %{
      "mode" => to_string(Map.get(s.config, :approval, :ask)),
      "workspace_edits" => s.permissions.edits,
      "workspace" => s.cwd,
      "expires" => "session close; never restored or inherited",
      "commands" =>
        Enum.map(s.permissions.commands, fn {cwd, sandbox, args} ->
          %{"cwd" => cwd, "sandbox" => to_string(sandbox), "arguments" => args}
        end)
    }
  end

  defp eligible?(s),
    do: Map.get(s.config, :approval, :ask) == :ask and is_nil(s.config[:delegation_origin])

  defp key(s, args), do: {s.cwd, Map.get(s.config, :sandbox, :off), args}
end
