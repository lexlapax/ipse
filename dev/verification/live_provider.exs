defmodule Ipse.Development.Verification.LiveProvider do
  @moduledoc "Explicit three-request live text/tool verification without transcript output."
  alias Ipse.Provider.Registry

  def main(argv) do
    {opts, rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          provider: :string,
          profile: :string,
          config: :string,
          cwd: :string,
          model: :string
        ]
      )

    with true <-
           rest == [] and invalid == [] and
             length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))),
         provider when provider in ~w(openrouter gemini) <- opts[:provider],
         true <- System.get_env("IPSE_LIVE_PROVIDER_CONFIRM") == provider,
         cwd = Path.expand(opts[:cwd] || File.cwd!()),
         home = System.get_env("IPSE_HOME") || Path.join(System.user_home!(), ".ipse"),
         {:ok, effective} <-
           Ipse.Config.resolve(
             cwd,
             home,
             Keyword.take(opts, [:provider, :profile, :config, :model]) ++ [project_config: false]
           ),
         {:ok, config} <-
           Ipse.Config.runtime(effective, %{
             workspace: cwd,
             home: home,
             operator_home: home,
             auth_dir: Path.join(home, "auth"),
             mcp_config: nil,
             base_url: nil,
             operator_questions: false,
             approval: :deny
           }),
         :ok <- preflight(config, provider),
         {:ok, destination} <- Ipse.Provider.destination(config) do
      selected = %{
        "event" => "live_provider_plan",
        "provider" => provider,
        "model" => config.model,
        "upstream" => config[:upstream],
        "billing_mode" => Registry.fetch!(provider).billing_mode,
        "destination" => destination,
        "max_requests" => 3,
        "max_output_tokens_per_request" => cap(config)
      }

      IO.puts(Jason.encode!(selected))
      report = run(config, &Ipse.Provider.request_complete/4)
      IO.puts(Jason.encode!(report))
      if report["status"] != "passed", do: System.halt(1)
    else
      {:error, message} when is_binary(message) ->
        refuse(message)

      _ ->
        refuse(
          "Choose openrouter or gemini, an explicit model/profile, and set IPSE_LIVE_PROVIDER_CONFIRM to the same provider. No request was sent."
        )
    end
  rescue
    _ -> refuse("Live provider verification failed; no automatic retry was attempted.")
  end

  defp refuse(message) do
    IO.puts(:json.encode(%{"status" => "refused", "reason" => message}))
    System.halt(1)
  end

  def preflight(config, provider) do
    cond do
      provider not in ~w(openrouter gemini) ->
        {:error, "Live provider verification supports only openrouter and gemini."}

      to_string(config[:provider]) != provider ->
        {:error,
         "The resolved provider differs from the confirmed provider; no request was sent."}

      config[:budget] != nil ->
        {:error,
         "This bounded live verifier cannot enforce a session budget. Use a dedicated verification config without a budget, or run a normal budgeted session. No request was sent."}

      true ->
        with :ok <- Registry.validate_request(config),
             do:
               Ipse.Provider.validate_output_limit(
                 Map.put(config, :max_output_tokens, cap(config))
               )
    end
  end

  defp cap(config), do: min(config[:max_output_tokens] || 1024, 1024)

  def run(config, request) do
    provider = to_string(config[:provider])

    with :ok <- preflight(config, provider) do
      config =
        Map.merge(config, %{
          max_output_tokens: cap(config),
          timeout_ms: min(config[:timeout_ms] || 60_000, 60_000),
          max_response_bytes: min(config[:max_response_bytes] || 65_536, 65_536)
        })

      tools = [
        %{
          "type" => "function",
          "function" => %{
            "name" => "ipse_live_echo",
            "description" => "Echo the fixed verification value; no external action.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{"value" => %{"type" => "string", "enum" => ["p29"]}},
              "required" => ["value"],
              "additionalProperties" => false
            }
          }
        }
      ]

      text = [%{"role" => "user", "content" => "Reply exactly IPSE_LIVE_TEXT_OK."}]

      tool_messages = [
        %{
          "role" => "user",
          "content" =>
            "Call ipse_live_echo exactly once with value p29. After receiving its result reply exactly IPSE_LIVE_TOOL_OK."
        }
      ]

      {result, records} = perform(config, text, [], request, [])

      case result do
        {:ok, assistant, _} ->
          if exact_text?(assistant, "IPSE_LIVE_TEXT_OK"),
            do: tool_turn(config, tool_messages, tools, request, records),
            else: report(config, records, "failed", "text_answer_mismatch")

        {:error, _} ->
          report(config, records, "failed", "text_request_refused")
      end
    else
      {:error, _} ->
        %{
          "version" => 1,
          "status" => "refused",
          "requests" => [],
          "reason" => "live_preflight_refused"
        }
    end
  end

  defp tool_turn(config, tool_messages, tools, request, records) do
    {result, records} = perform(config, tool_messages, tools, request, records)

    with {:ok, assistant, _} <- result,
         {:ok, call} <- echo_call(assistant) do
      response = %{
        "role" => "tool",
        "tool_call_id" => call["id"],
        "content" => Jason.encode!(%{"value" => "p29"})
      }

      {result, records} =
        perform(config, tool_messages ++ [assistant, response], tools, request, records)

      case result do
        {:ok, final, _} ->
          report(
            config,
            records,
            if(exact_text?(final, "IPSE_LIVE_TOOL_OK"), do: "passed", else: "failed"),
            "final_tool_answer"
          )

        {:error, _} ->
          report(config, records, "failed", "tool_continuation_refused")
      end
    else
      {:error, _} -> report(config, records, "failed", "request_or_tool_contract_refused")
    end
  end

  defp perform(config, messages, tools, request, records) do
    started = System.monotonic_time(:millisecond)
    observation = make_ref()

    result =
      try do
        request.(config, messages, tools, fn
          {:provider_usage, usage} -> Process.put(observation, usage)
          _ -> :ok
        end)
      rescue
        _ -> {:error, "Provider verification raised an error; no retry was attempted."}
      catch
        _, _ -> {:error, "Provider verification terminated; no retry was attempted."}
      end

    elapsed = max(System.monotonic_time(:millisecond) - started, 0)

    raw =
      case result do
        {:ok, _, raw} -> raw
        _ -> Process.get(observation)
      end

    Process.delete(observation)

    record = %{
      "index" => length(records) + 1,
      "elapsed_ms" => elapsed,
      "outcome" => if(match?({:ok, _, _}, result), do: "completed", else: "failed"),
      "usage" => Ipse.Usage.normalize(config.provider, raw)
    }

    record =
      case result do
        {:ok, %{"provider_data" => %{"provider" => "gemini", "content" => %{"parts" => parts}}},
         _} ->
          Map.put(record, "native_continuation", %{
            "parts" => length(parts),
            "signed_parts" =>
              Enum.count(
                parts,
                &(is_binary(&1["thoughtSignature"]) and &1["thoughtSignature"] != "")
              )
          })

        _ ->
          record
      end

    record =
      case result do
        {:error, message} when is_binary(message) ->
          spec = Registry.fetch!(config.provider)

          key =
            case spec.credential do
              {:env, name} -> System.get_env(name)
              _ -> nil
            end

          {:error, safe} =
            Ipse.Provider.error(message, Map.put(config, :api_key, config[:api_key] || key))

          Map.put(record, "error", safe)

        _ ->
          record
      end

    {result, records ++ [record]}
  end

  defp exact_text?(message, expected),
    do:
      message["tool_calls"] in [nil, []] and is_binary(message["content"]) and
        String.trim(message["content"]) == expected

  defp echo_call(%{
         "tool_calls" => [
           %{"id" => id, "function" => %{"name" => "ipse_live_echo", "arguments" => arguments}} =
             call
         ]
       })
       when is_binary(id) do
    case Ipse.JSON.decode_unique(arguments) do
      {:ok, %{"value" => "p29"} = value} when map_size(value) == 1 -> {:ok, call}
      _ -> {:error, :invalid_echo_arguments}
    end
  end

  defp echo_call(_), do: {:error, :missing_echo_call}

  defp report(config, records, status, stage),
    do: %{
      "version" => 1,
      "status" => status,
      "stage" => stage,
      "provider" => to_string(config.provider),
      "model" => config.model,
      "upstream" => config[:upstream],
      "billing_mode" => Registry.fetch!(config.provider).billing_mode,
      "requests" => records,
      "text_verified" => length(records) > 1,
      "native_tool_continuation_verified" => status == "passed"
    }
end
