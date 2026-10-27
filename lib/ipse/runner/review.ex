defmodule Ipse.Runner.Review do
  @moduledoc """
  Native terminal review with an owner-bound, one-use consumption permit.

  This internal host primitive observes exact terminal input; it grants no
  effect permission, source truth or current storage authority. Its trusted
  caller must supply the complete proposed facts, release all locks before
  review, and revalidate those facts and authority under the effect's locks
  before consuming. No worker/SDK or serialized-observation constructor exists.
  """
  alias Ipse.{JSON, Runner, Session.Resources}
  @slot {__MODULE__, :permit}
  @lifetime 30_000
  @facts_bytes 16_384
  @display_bytes 65_536
  @error {:error, :native_review_refused}
  @unknown {:unknown, :native_review_unconfirmed}

  defmodule Permit do
    @moduledoc false
    @enforce_keys [:owner, :ref]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#NativeReview<private>"
    end
  end

  @doc "Observe a fresh exact command/challenge, then enter a bounded host callback without holding terminal IO locks."
  def with_review(command, facts, fun) when is_function(fun, 1) do
    with true <- is_nil(Process.get(@slot)),
         true <- valid?(command, facts) and Resources.active?(),
         upstream = Resources.file_effect_owner(),
         true <- is_pid(upstream) and Process.alive?(upstream),
         scope = Resources.current(),
         challenge = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
         input = command <> " " <> challenge,
         display = display(command, facts, challenge),
         true <- byte_size(display) <= @display_bytes,
         {:ok, observation} <- Runner.operator_input(display, 120_000, 2),
         observed_at = System.system_time(:millisecond),
         deadline = now() + @lifetime,
         true <- JSON.safe_uint?(observed_at),
         true <- observation["text"] === input,
         true <-
           Ipse.Session.Input.valid_observation?(Map.delete(observation, "text"), input, 2),
         true <- observation["display_sha256"] == JSON.sha256(display),
         true <- Resources.current() === scope and Resources.active?(),
         true <- Process.alive?(upstream),
         true <- now() < deadline do
      receipt = %{
        "version" => 1,
        "kind" => "native_review",
        "command" => command,
        "event_id" => observation["event_id"],
        "display_sha256" => observation["display_sha256"],
        "challenge" => challenge,
        "input_sha256" => observation["text_sha256"],
        "observed_at_ms" => observed_at,
        "facts_sha256" => JSON.digest([facts])
      }

      enter(command, facts, receipt, upstream, scope, deadline, fun)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def with_review(_, _, _), do: @error

  @doc "Consume once against the exact revalidated facts, before attempting the bound effect."
  def consume(%Permit{owner: owner, ref: ref}, command, facts) when owner == self() do
    case Process.get(@slot) do
      %{ref: ^ref, status: :available} = pending ->
        # A real owner's first attempt spends the permit even when its facts
        # changed. It cannot silently rebase to another target or retry a write.
        Process.put(@slot, %{pending | status: :refused})

        if command === pending.command and facts === pending.facts and live?(pending) do
          Process.put(@slot, %{pending | status: :consumed})
          {:ok, pending.receipt}
        else
          @error
        end

      _ ->
        @error
    end
  end

  def consume(_, _, _), do: @error

  defp enter(command, facts, receipt, upstream, scope, deadline, fun) do
    ref = make_ref()

    pending = %{
      ref: ref,
      status: :available,
      command: command,
      facts: facts,
      receipt: receipt,
      upstream: upstream,
      scope: scope,
      deadline: deadline
    }

    Process.put(@slot, pending)

    try do
      result = fun.(%Permit{owner: self(), ref: ref})

      case Process.get(@slot) do
        %{ref: ^ref, status: :consumed} = current ->
          if (result === :ok or match?({:ok, _}, result)) and live?(current),
            do: result,
            else: @unknown

        %{ref: ^ref, status: :available} ->
          if match?({:error, _}, result), do: result, else: @error

        _ ->
          @error
      end
    rescue
      _ -> interrupted()
    catch
      _, _ -> interrupted()
    after
      Process.delete(@slot)
    end
  end

  defp interrupted do
    case Process.get(@slot) do
      %{status: :consumed} -> @unknown
      _ -> @error
    end
  end

  defp live?(pending) do
    remaining = pending.deadline - now()

    remaining > 0 and Process.alive?(pending.upstream) and
      Resources.current() === pending.scope and Resources.active?(min(remaining, 5_000)) and
      now() < pending.deadline and Process.alive?(pending.upstream) and
      Resources.current() === pending.scope
  end

  defp valid?(command, facts),
    do:
      is_binary(command) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, command) and
        is_map(facts) and map_size(facts) > 0 and JSON.validate_object(facts) == :ok and
        byte_size(Jason.encode!(facts)) <= @facts_bytes

  defp display(command, facts, challenge) do
    Ipse.CLI.Terminal.escape(
      "Review the complete proposed facts below. This confirmation applies only to this exact review.\n" <>
        Jason.encode!(facts, pretty: true) <>
        "\nType #{command} #{challenge} to confirm, or anything else to cancel.\n> "
    )
  end

  defp now, do: System.monotonic_time(:millisecond)
end
