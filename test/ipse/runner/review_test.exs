defmodule Ipse.Test.ReviewRunner do
  @moduledoc false
  def operator_input(display, 120_000, 2) do
    Process.put({__MODULE__, :calls}, Process.get({__MODULE__, :calls}, 0) + 1)
    Process.put({__MODULE__, :display}, display)
    [_, input] = Regex.run(~r/\nType ([a-z][a-z0-9_-]{0,31} [0-9a-f]{16}) to confirm,/, display)

    observation = %{
      "version" => 2,
      "event_id" => String.duplicate("a", 32),
      "text" => input,
      "text_sha256" => Ipse.JSON.sha256(input),
      "display_sha256" => Ipse.JSON.sha256(display),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    if hook = Process.get({__MODULE__, :before_return}), do: hook.()

    case Process.get({__MODULE__, :mode}) do
      nil ->
        {:ok, observation}

      :eof ->
        {:error, :operator_input_eof}

      :bare_yes ->
        {:ok, %{observation | "text" => "yes", "text_sha256" => Ipse.JSON.sha256("yes")}}

      :trailing_space ->
        text = input <> " "
        {:ok, %{observation | "text" => text, "text_sha256" => Ipse.JSON.sha256(text)}}

      :wrong_display ->
        {:ok, %{observation | "display_sha256" => String.duplicate("0", 64)}}

      :wrong_text_hash ->
        {:ok, %{observation | "text_sha256" => String.duplicate("0", 64)}}

      :extra ->
        {:ok, Map.put(observation, "authority", true)}

      :legacy ->
        {:ok, %{observation | "version" => 1}}
    end
  end

  def now do
    case Process.get({__MODULE__, :clock}) do
      nil -> Process.get({__MODULE__, :now}, 1_000)
      clock -> :atomics.get(clock, 1)
    end
  end
end

# This renamed fixture replaces only native IO and monotonic time. It tests the
# host permit state machine, not terminal provenance; real PTY controls are separate.
source = File.read!(Path.expand("../../../lib/ipse/runner/review.ex", __DIR__))

source =
  String.replace(
    source,
    "defmodule Ipse.Runner.Review do",
    "defmodule Ipse.Test.ReviewFixture do"
  )

source =
  String.replace(
    source,
    ~S'''
        defimpl Inspect do
          def inspect(_, _), do: "#NativeReview<private>"
        end
    ''',
    ""
  )

source =
  String.replace(
    source,
    "alias Ipse.{JSON, Runner, Session.Resources}",
    "alias Ipse.{JSON, Session.Resources}\n  alias Ipse.Test.ReviewRunner, as: Runner"
  )

source =
  String.replace(source, "System.monotonic_time(:millisecond)", "Ipse.Test.ReviewRunner.now()")

Code.compile_string(source, "review-permit-state-fixture.ex")

defmodule Ipse.Runner.ReviewTest do
  use ExUnit.Case, async: false
  alias Ipse.Test.{ReviewFixture, ReviewRunner}
  alias Ipse.Session.Resources

  setup do
    facts = %{"target" => "synthetic", "value" => "café 日本語\e[31m", "choice" => "pin"}
    %{facts: facts}
  end

  test "invalid production arguments and ordinary JSON cannot construct or consume a permit", c do
    for command <- [nil, "", "Pin", "pin\n", "pin yes", String.duplicate("a", 33)] do
      assert {:error, :native_review_refused} =
               Ipse.Runner.Review.with_review(command, c.facts, fn _ -> flunk("entered") end)
    end

    for facts <- [%{}, nil, %{"x" => self()}, %{"x" => String.duplicate("x", 16_384)}] do
      assert {:error, :native_review_refused} =
               Ipse.Runner.Review.with_review("pin", facts, fn _ -> flunk("entered") end)
    end

    assert {:error, :native_review_refused} = Ipse.Runner.Review.consume(%{}, "pin", c.facts)
    forged = %Ipse.Runner.Review.Permit{owner: self(), ref: make_ref()}
    assert inspect(forged) == "#NativeReview<private>"
    assert {:error, :native_review_refused} = Ipse.Runner.Review.consume(forged, "pin", c.facts)
  end

  test "a matching simulated observation binds full escaped facts and can be consumed only once",
       c do
    assert {:ok, receipt} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:ok, receipt} = ReviewFixture.consume(permit, "pin", c.facts)

               assert {:error, :native_review_refused} =
                        ReviewFixture.consume(permit, "pin", c.facts)

               assert receipt["kind"] == "native_review"
               assert receipt["facts_sha256"] == Ipse.JSON.digest([c.facts])
               assert receipt["input_sha256"] == Ipse.JSON.sha256("pin " <> receipt["challenge"])

               assert receipt["display_sha256"] ==
                        Ipse.JSON.sha256(Process.get({ReviewRunner, :display}))

               assert Ipse.JSON.safe_uint?(receipt["observed_at_ms"])
               {:ok, receipt}
             end)

    assert receipt["command"] == "pin"
    display = Process.get({ReviewRunner, :display})
    refute display =~ <<27>>
    assert display =~ "日本語"
    assert String.downcase(display) =~ "\\u001b"
    assert Process.get({ReviewRunner, :calls}) == 1
    assert Process.get({ReviewFixture, :permit}) == nil
  end

  test "changed command or exact facts spends the permit without a silent rebase", c do
    for {command, facts} <- [{"forget", c.facts}, {"pin", Map.put(c.facts, "new", true)}] do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, command, facts)

                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, "pin", c.facts)

                 :ignored
               end)
    end
  end

  test "foreign process and forged ref do not spend the actual owner's permit", c do
    assert :ok =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:error, :native_review_refused} =
                        Task.async(fn -> ReviewFixture.consume(permit, "pin", c.facts) end)
                        |> Task.await()

               forged = %{permit | ref: make_ref()}

               assert {:error, :native_review_refused} =
                        ReviewFixture.consume(forged, "pin", c.facts)

               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               :ok
             end)
  end

  test "scope exit, callback exceptions and missing consumption cannot create success", c do
    for callback <- [fn _ -> :ok end, fn _ -> raise "synthetic before consumption" end] do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, callback)

      assert Process.get({ReviewFixture, :permit}) == nil
    end

    assert {:error, :stale_target} =
             ReviewFixture.with_review("pin", c.facts, fn _ -> {:error, :stale_target} end)

    assert {:unknown, :native_review_unconfirmed} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               raise "synthetic effect may have happened"
             end)

    for returned <- [{:error, :synthetic_after_effect}, {:conflict, %{}}, :unexpected] do
      assert {:unknown, :native_review_unconfirmed} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
                 returned
               end)
    end

    parent = self()

    assert :ok =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               send(parent, {:spent_permit, permit})
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               :ok
             end)

    assert_receive {:spent_permit, permit}
    assert {:error, :native_review_refused} = ReviewFixture.consume(permit, "pin", c.facts)
    assert Process.get({ReviewFixture, :permit}) == nil
  end

  test "bare yes, whitespace, mismatched hashes and failed native restoration never enter callback",
       c do
    for mode <- [
          :bare_yes,
          :trailing_space,
          :wrong_display,
          :wrong_text_hash,
          :extra,
          :legacy,
          :eof
        ] do
      Process.put({ReviewRunner, :mode}, mode)

      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn _ -> flunk("entered") end)
    end
  end

  test "the exact deadline refuses consumption and post-consumption expiry withholds success",
       c do
    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               Process.put({ReviewRunner, :now}, 31_000)

               assert {:error, :native_review_refused} =
                        ReviewFixture.consume(permit, "pin", c.facts)

               :ignored
             end)

    Process.put({ReviewRunner, :now}, 1_000)

    assert {:unknown, :native_review_unconfirmed} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               Process.put({ReviewRunner, :now}, 31_000)
               :ok
             end)
  end

  test "closed and unrelated resource scopes cannot consume or finish a review", c do
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      assert Resources.active?()

      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert :ok = Resources.finish(scope)
                 refute Resources.active?()

                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, "pin", c.facts)

                 :ignored
               end)

      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn _ -> flunk("entered") end)
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "resource activity admits only actual owner, tracked task and effect, then refuses after finish" do
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      assert Resources.active?()
      assert Resources.active?(1_000)
      for timeout <- [0, -1, 5_001, 1.0, nil], do: refute(Resources.active?(timeout))

      refute Task.async(fn ->
               Resources.bind(scope)
               Resources.active?()
             end)
             |> Task.await()

      assert Resources.async(fn -> Resources.active?() end) |> Task.await()
      assert Resources.file_effect(fn -> Resources.active?() end)
      assert :ok = Resources.finish(scope)
      refute Resources.active?()
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "a complete maximum-size facts object is shown and the next byte refuses before native IO" do
    facts = %{"x" => String.duplicate("x", 8_192), "y" => String.duplicate("y", 8_177)}
    assert byte_size(Jason.encode!(facts)) == 16_384

    assert :ok =
             ReviewFixture.with_review("pin", facts, fn permit ->
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", facts)
               :ok
             end)

    assert Process.get({ReviewRunner, :calls}) == 1

    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("pin", %{facts | "y" => facts["y"] <> "y"}, fn _ ->
               flunk("entered")
             end)

    assert Process.get({ReviewRunner, :calls}) == 1
  end

  test "nested review cannot replace a pending permit", c do
    assert :ok =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:error, :native_review_refused} =
                        ReviewFixture.with_review("forget", c.facts, fn _ -> flunk("nested") end)

               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               :ok
             end)

    assert Process.get({ReviewRunner, :calls}) == 1
  end

  test "upstream death refuses consumption and finished scope withholds a consumed result", c do
    upstream =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    monitor = Process.monitor(upstream)
    owner_key = {Resources, :effect_owner}
    previous = Process.get(owner_key)
    :ok = Resources.bind_effect_owner(upstream)

    try do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 send(upstream, :stop)
                 assert_receive {:DOWN, ^monitor, :process, ^upstream, :normal}

                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, "pin", c.facts)

                 :ignored
               end)
    after
      if is_nil(previous), do: Process.delete(owner_key), else: Process.put(owner_key, previous)
      if Process.alive?(upstream), do: Process.exit(upstream, :kill)
      Process.demonitor(monitor, [:flush])
    end

    {:ok, scope} = Resources.start(self())
    previous_scope = Resources.bind(scope)

    try do
      assert {:unknown, :native_review_unconfirmed} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
                 :ok = Resources.finish(scope)
                 :ok
               end)
    after
      Resources.bind(previous_scope)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "the observation lifetime cannot restart after the post-input resource query", c do
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)
    clock = :atomics.new(1, [])
    :atomics.put(clock, 1, 1_000)
    Process.put({ReviewRunner, :clock}, clock)
    caller = self()

    Process.put({ReviewRunner, :before_return}, fn ->
      :ok = :sys.suspend(scope)

      watcher =
        Task.async(fn ->
          try do
            wait_for_active(scope, caller, System.monotonic_time(:millisecond) + 3_000)
            :atomics.put(clock, 1, 31_000)
          after
            :sys.resume(scope)
          end
        end)

      Process.put({ReviewRunner, :entry_watcher}, watcher)
    end)

    try do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn _ ->
                 flunk("expired observation entered callback")
               end)

      Task.await(Process.get({ReviewRunner, :entry_watcher}))
    after
      Process.delete({ReviewRunner, :before_return})
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "deadline and upstream are rechecked after a real blocking scope query", c do
    for phase <- [:consume, :finish], loss <- [:deadline, :upstream] do
      {:ok, scope} = Resources.start(self())
      previous_scope = Resources.bind(scope)

      upstream =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      owner_key = {Resources, :effect_owner}
      previous_owner = Process.get(owner_key)
      :ok = Resources.bind_effect_owner(upstream)
      clock = :atomics.new(1, [])
      :atomics.put(clock, 1, 1_000)
      Process.put({ReviewRunner, :clock}, clock)

      try do
        result =
          ReviewFixture.with_review("pin", c.facts, fn permit ->
            if phase == :finish,
              do: assert({:ok, _} = ReviewFixture.consume(permit, "pin", c.facts))

            caller = self()
            :ok = :sys.suspend(scope)

            watcher =
              Task.async(fn ->
                try do
                  wait_for_active(scope, caller, System.monotonic_time(:millisecond) + 3_000)

                  if loss == :deadline do
                    :atomics.put(clock, 1, 31_000)
                  else
                    monitor = Process.monitor(upstream)
                    send(upstream, :stop)

                    receive do
                      {:DOWN, ^monitor, :process, ^upstream, :normal} -> :ok
                    after
                      1_000 -> flunk("upstream did not stop")
                    end
                  end
                after
                  :sys.resume(scope)
                end
              end)

            Process.put(:native_review_watcher, watcher)

            if phase == :consume do
              assert {:error, :native_review_refused} =
                       ReviewFixture.consume(permit, "pin", c.facts)

              :ignored
            else
              :ok
            end
          end)

        expected =
          if phase == :consume,
            do: {:error, :native_review_refused},
            else: {:unknown, :native_review_unconfirmed}

        assert result == expected
        assert :ok = Task.await(Process.delete(:native_review_watcher), 5_000)
      after
        Process.delete({ReviewRunner, :clock})
        Resources.bind(previous_scope)

        if is_nil(previous_owner),
          do: Process.delete(owner_key),
          else: Process.put(owner_key, previous_owner)

        if Process.alive?(upstream), do: Process.exit(upstream, :kill)
        if Process.alive?(scope), do: Resources.close(scope)
      end
    end
  end

  defp wait_for_active(scope, caller, deadline) do
    {:messages, messages} = Process.info(scope, :messages)

    if Enum.any?(messages, &match?({:"$gen_call", {^caller, _}, :active}, &1)) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "resource query was not queued"
      Process.sleep(1)
      wait_for_active(scope, caller, deadline)
    end
  end
end
