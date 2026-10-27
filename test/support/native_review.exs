[root, mode] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.{JSON, Runner.Review, Session.Resources}

facts = %{
  "version" => 1,
  "target" => "synthetic native review; no Collection or publication",
  "text" => "café 日本語\e[31m\nComplete retained original text",
  "policy" => %{"kind" => "pin"},
  "reason" => "Synthetic control"
}

refused = {:error, :native_review_refused}

case mode do
  "valid" ->
    for command <- ~w(pin ordinary forget duration accept) do
      {:ok, receipt} =
        Review.with_review(command, facts, fn permit ->
          "#NativeReview<private>" = inspect(permit)
          ^refused = Task.async(fn -> Review.consume(permit, command, facts) end) |> Task.await()
          ^refused = Review.consume(%{permit | ref: make_ref()}, command, facts)
          {:ok, receipt} = Review.consume(permit, command, facts)
          ^refused = Review.consume(permit, command, facts)
          "native_review" = receipt["kind"]
          ^command = receipt["command"]
          true = receipt["facts_sha256"] == JSON.digest([facts])
          true = receipt["input_sha256"] == JSON.sha256(command <> " " <> receipt["challenge"])

          File.write!(Path.join(root, "receipt-" <> command <> ".json"), Jason.encode!(receipt), [
            :exclusive
          ])

          {:ok, receipt}
        end)

      true = JSON.safe_uint?(receipt["observed_at_ms"])
    end

  value when value in ~w(cancel stale pipe) ->
    ^refused =
      Review.with_review("pin", facts, fn _ -> raise "refused review entered callback" end)

  "changed" ->
    ^refused =
      Review.with_review("pin", facts, fn permit ->
        ^refused = Review.consume(permit, "pin", Map.put(facts, "changed", true))
        ^refused = Review.consume(permit, "pin", facts)
        :ignored
      end)

  "callback_error" ->
    {:unknown, :native_review_unconfirmed} =
      Review.with_review("pin", facts, fn permit ->
        {:ok, _} = Review.consume(permit, "pin", facts)
        raise "synthetic consumed callback failure"
      end)

  "closed_scope" ->
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      {:unknown, :native_review_unconfirmed} =
        Review.with_review("pin", facts, fn permit ->
          {:ok, _} = Review.consume(permit, "pin", facts)
          :ok = Resources.finish(scope)
          false = Resources.active?()
          :ok
        end)
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
end

IO.puts("NATIVE_REVIEW_" <> String.upcase(mode) <> "_PASSED")
