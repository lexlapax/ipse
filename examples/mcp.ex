defmodule IpseMCPExample.Read do
  @behaviour Ipse.Extension
  @capabilities ~w(invoke.command host.actions host.mcp host.results host.actions.mixed host.state.read host.question)

  def describe do
    %{
      "sdk" => 1,
      "capabilities" => @capabilities,
      "exports" => %{
        "version" => 1,
        "tools" => [],
        "services" => [],
        "commands" => [
          %{
            "id" => "read",
            "description" => "Call an operator-bound MCP tool and read its bounded result",
            "arguments_schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => ["request"],
              "properties" => %{
                "request" => %{"type" => "object"},
                "read" => %{"type" => "boolean"},
                "question" => %{"type" => "boolean"},
                "before_reads" => %{"type" => "integer", "minimum" => 0, "maximum" => 512},
                "repeat" => %{"type" => "integer", "minimum" => 1, "maximum" => 17},
                "read_override" => %{"type" => "object"}
              }
            },
            "result_schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => ~w(status statuses reads bytes sha256 last),
              "properties" => %{
                "status" => %{"type" => "string"},
                "statuses" => %{"type" => "array", "items" => %{"type" => "string"}},
                "reads" => %{"type" => "integer"},
                "bytes" => %{"type" => "integer"},
                "sha256" => %{"type" => "string"},
                "last" => %{"type" => "object"}
              }
            }
          }
        ]
      }
    }
  end

  def init(options), do: {:ok, options}

  def handle("invoke.command", payload, _options) do
    next(initial(payload["arguments"]))
  end

  def handle(
        "host.actions",
        %{"checkpoint" => %{"descriptor" => descriptor} = checkpoint} = payload,
        _state
      ) do
    state = %{
      initial(checkpoint["arguments"])
      | before_reads: 0,
        remaining: checkpoint["remaining"],
        statuses: ["ok", payload["outcome"]["status"]],
        last: payload["outcome"]
    }

    if payload["outcome"]["status"] == "answered",
      do: read(state, descriptor, 0),
      else: finish(state)
  end

  def handle("host.actions", payload, state) do
    outcome = payload["outcome"]
    state = %{state | last: outcome, statuses: state.statuses ++ [outcome["status"]]}

    case state.phase do
      :before ->
        next(%{state | before_reads: state.before_reads - 1})

      :call ->
        if outcome["status"] == "ok" and state.args["read"] == true do
          descriptor = outcome["value"]

          if state.args["question"] == true,
            do: question(state, descriptor),
            else: read(state, descriptor, 0)
        else
          next(%{state | remaining: state.remaining - 1})
        end

      {:read, descriptor} ->
        if outcome["status"] == "ok" do
          value = outcome["value"]
          state = %{state | reads: state.reads + 1, text: state.text <> value["text"]}

          if value["complete"],
            do: next(%{state | remaining: state.remaining - 1}),
            else: read(state, descriptor, value["next"])
        else
          finish(state)
        end
    end
  end

  defp initial(args) do
    %{
      args: args,
      before_reads: args["before_reads"] || 0,
      remaining: args["repeat"] || 1,
      statuses: [],
      reads: 0,
      text: "",
      last: %{},
      phase: :before
    }
  end

  defp question(state, descriptor) do
    request = %{
      "op" => "operator.question",
      "checkpoint" => %{
        "descriptor" => descriptor,
        "arguments" => state.args,
        "remaining" => state.remaining
      },
      "arguments" => %{
        "questions" => [
          %{"id" => "continue", "kind" => "text", "prompt" => "Read the saved synthetic result?"}
        ]
      }
    }

    call(request, %{state | phase: :question})
  end

  defp next(%{before_reads: count} = state) when count > 0 do
    request = %{"op" => "state.get", "scope" => "session", "key" => "missing"}
    call(request, %{state | phase: :before})
  end

  defp next(%{remaining: count} = state) when count > 0,
    do: call(state.args["request"], %{state | phase: :call})

  defp next(state), do: finish(state)

  defp read(state, descriptor, offset) do
    request = %{
      "op" => "effect.result.read",
      "version" => 1,
      "operation_id" => descriptor["operation_id"],
      "source_sha256" => descriptor["source_sha256"],
      "offset" => offset,
      "limit" => 4096
    }

    request = Map.merge(request, state.args["read_override"] || %{})
    call(request, %{state | phase: {:read, descriptor}})
  end

  defp call(request, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}

  defp finish(state) do
    value = %{
      "status" => state.last["status"] || "empty",
      "statuses" => state.statuses,
      "reads" => state.reads,
      "bytes" => byte_size(state.text),
      "sha256" => Base.encode16(:crypto.hash(:sha256, state.text), case: :lower),
      "last" => state.last
    }

    {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
  end
end
