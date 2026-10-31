defmodule Ipse.Extension.CollectionManagedV3Test do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection, as: C
  alias Ipse.JSON

  # Actual native Collection publications exercise the Core change envelope.
  # Values here are trusted synthetic metadata, not DomainAuth or SDK evidence.
  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-managed-v3-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    %{root: Path.join(parent, "collections"), project: JSON.sha256("v3 Core envelope")}
  end

  defp fence(n, width),
    do: Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(width, "0")

  defp a(n), do: "host.validity.a." <> fence(n, 64)
  defp l(n), do: "host.validity.l." <> fence(n, 66)

  defp change(key, revision, value \\ %{"synthetic" => true}),
    do: %{"key" => key, "expected_revision" => revision, "value" => value}

  defp request(generation),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => true,
      "changes" => [change("note.#{generation}", 0, %{"text" => "exact original"})]
    }

  defp initial, do: [change("host.validity.format", 0), change(a(0), 0), change(l(0), 0)]
  defp normalized(request, extras), do: Map.update!(request, "changes", &(&1 ++ extras))

  defp run(c, generation, extras, id \\ Ipse.Usage.id()) do
    original = request(generation)

    C.execute_managed_v3(c.root, c.project, original, id, JSON.sha256("recipe"), fn _, _ ->
      {:ok, normalized(original, extras), %{"version" => 3}}
    end)
  end

  defp get(c, key),
    do: C.execute(c.root, c.project, %{"op" => "get", "key" => key}, Ipse.Usage.id())

  defp pointer(c), do: Path.join([c.root, c.project, "root.json"])

  test "native absence requires the exact three initial metadata keys and binds the normalized receipt",
       c do
    id = Ipse.Usage.id()
    assert {:ok, result} = run(c, 0, initial(), id)
    assert result["receipt"]["generation"] == 1
    assert result["receipt"]["request_sha256"] == JSON.digest([normalized(request(0), initial())])
    assert result["binding"]["normalization_sha256"] == JSON.digest([%{"version" => 3}])

    assert {:ok, %{"record" => %{"revision" => 1, "operation_id" => ^id}}} =
             get(c, "host.validity.format")

    assert {:ok, %{"record" => %{"value" => %{"text" => "exact original"}}}} = get(c, "note.0")

    assert {:existing, _} =
             C.execute_managed_v3(c.root, c.project, request(0), id, JSON.sha256("recipe"), fn _,
                                                                                               _ ->
               flunk("replayed callback")
             end)
  end

  test "initialization cannot omit, relocate, delete or add a sentinel or page", c do
    for extras <- [
          tl(initial()),
          [change("host.validity.format", 0), change(a(1), 0), change(l(0), 0)],
          initial() ++ [change(a(1), 0)],
          List.replace_at(initial(), 1, change(a(0), 0, nil)),
          List.replace_at(initial(), 2, change(l(0), 1))
        ] do
      assert {:error, :managed_normalization_refused} = run(c, 0, extras)
      refute File.exists?(pointer(c))
    end
  end

  test "four replacements and one exact retained-revision deletion publish atomically", c do
    assert {:ok, _} = run(c, 0, initial())

    assert {:ok, _} =
             run(c, 1, [change(a(0), 1), change(a(1), 0), change(l(0), 1), change(l(1), 0)])

    extras = [
      change(a(0), 2),
      change(a(1), 2, nil),
      change(l(0), 2),
      change(l(1), 2),
      change(l(2), 0)
    ]

    assert {:ok, result} = run(c, 2, extras)
    assert result["receipt"]["generation"] == 3
    assert {:ok, %{"record" => nil}} = get(c, a(1))
    assert {:ok, %{"record" => %{"revision" => 3}}} = get(c, a(0))
    assert {:ok, %{"record" => %{"revision" => 3}}} = get(c, l(2))
    assert {:ok, %{"record" => %{"revision" => 1}}} = get(c, "host.validity.format")
    assert {:ok, %{"record" => %{"value" => %{"text" => "exact original"}}}} = get(c, "note.2")
  end

  test "established roots reject sentinel changes, missing deletions, wrong revisions and nonpage keys",
       c do
    assert {:ok, _} = run(c, 0, initial())
    bytes = File.read!(pointer(c))

    for extras <- [
          [change(a(0), 0, nil)],
          [change(a(0), 2, nil)],
          [change(a(9), 1, nil)],
          [change("host.validity.format", 1, nil)],
          [change("host.validity.format", 1)],
          [change("host.validity.forged", 0)],
          [change("host.validity.a.UPPER", 0)],
          [change("host.validity.l.03" <> fence(0, 64), 0)],
          [change("ordinary", 0)]
        ] do
      assert {:error, :managed_normalization_refused} = run(c, 1, extras)
      assert File.read!(pointer(c)) == bytes
      assert {:ok, %{"record" => nil}} = get(c, "note.1")
    end
  end

  test "five values, six changes and two deletions exceed the automatic v3 envelope", c do
    assert {:ok, _} = run(c, 0, initial())
    bytes = File.read!(pointer(c))

    for extras <- [
          Enum.map(1..5, &change(a(&1), 0)),
          Enum.map(1..6, &change(a(&1), 0)),
          [change(a(0), 1, nil), change(l(0), 1, nil)]
        ] do
      assert {:error, :managed_normalization_refused} = run(c, 1, extras)
      assert File.read!(pointer(c)) == bytes
    end
  end

  test "present legacy roots cannot initialize v3 while the explicit legacy path remains usable",
       c do
    assert {:ok, _} =
             C.execute(
               c.root,
               c.project,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [change("legacy", 0)]
               },
               Ipse.Usage.id()
             )

    bytes = File.read!(pointer(c))
    assert {:error, :managed_normalization_refused} = run(c, 1, [change(a(0), 0)])
    assert {:error, :managed_normalization_refused} = run(c, 1, initial())
    assert File.read!(pointer(c)) == bytes
    original = request(1)

    assert {:ok, _} =
             C.execute_managed(
               c.root,
               c.project,
               original,
               Ipse.Usage.id(),
               JSON.sha256("recipe"),
               fn _, _ ->
                 {:ok, normalized(original, [change("host.validity.legacy", 0)]), %{}}
               end
             )
  end

  test "v3 requires its receipt version and preserves original values before publication", c do
    original = request(0)

    for {proposed, receipt} <- [
          {normalized(original, initial()), %{"version" => 2}},
          {normalized(original, initial()), nil},
          {put_in(normalized(original, initial()), ["changes", Access.at(0), "value"], %{
             "changed" => true
           }), %{"version" => 3}}
        ] do
      assert {:error, :managed_normalization_refused} =
               C.execute_managed_v3(
                 c.root,
                 c.project,
                 original,
                 Ipse.Usage.id(),
                 JSON.sha256("recipe"),
                 fn _, _ -> {:ok, proposed, receipt} end
               )

      refute File.exists?(pointer(c))
    end

    assert {:conflict, _} =
             C.execute_managed_v3(
               c.root,
               c.project,
               request(1),
               Ipse.Usage.id(),
               JSON.sha256("recipe"),
               fn _, _ -> flunk("stale CAS entered callback") end
             )
  end

  test "the v3 callback retains the same32-unit shared read budget and fail-closed excess latch",
       c do
    for count <- [32, 33] do
      separate = %{c | root: c.root <> "-#{count}"}
      original = request(0)

      result =
        C.execute_managed_v3(
          separate.root,
          c.project,
          original,
          Ipse.Usage.id(),
          JSON.sha256("recipe"),
          fn _, read ->
            for _ <- 1..count, do: read.("missing")
            {:ok, normalized(original, initial()), %{"version" => 3}}
          end
        )

      if count == 32,
        do: assert({:ok, _} = result),
        else: assert({:error, :managed_normalization_refused} = result)
    end
  end

  test "pending metadata summaries share the same fail-closed read budget", c do
    for count <- [4, 5] do
      separate = %{c | root: c.root <> "-pending-#{count}"}
      original = request(0)

      result =
        C.execute_managed_v3(
          separate.root,
          c.project,
          original,
          Ipse.Usage.id(),
          JSON.sha256("recipe"),
          fn _, read ->
            assert {:error, :managed_read_refused} =
                     Task.async(fn -> read.(%{"op" => "pending_summary"}) end) |> Task.await()

            results = for _ <- 1..count, do: read.(%{"op" => "pending_summary"})

            assert Enum.take(results, 4) ==
                     List.duplicate({:ok, %{"count" => 0, "bytes" => 0}}, 4)

            {:ok, normalized(original, initial()), %{"version" => 3}}
          end
        )

      if count == 4,
        do: assert({:ok, _} = result),
        else: assert({:error, :managed_normalization_refused} = result)
    end
  end

  test "pending summary and publication share the Collection lock across owners", c do
    assert {:ok, _} = run(c, 0, initial())

    for batch <- 0..7 do
      count = if batch == 7, do: 7, else: 8

      changes =
        for offset <- 1..count do
          n = batch * 8 + offset
          change("pending." <> fence(n, 64), 0, %{"synthetic" => n})
        end

      assert {:ok, _} =
               C.execute(
                 c.root,
                 c.project,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end

    parent = self()

    proposal = fn n, generation ->
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => true,
        "changes" => [change("pending." <> fence(n, 64), 0)]
      }
    end

    first = proposal.(100, 9)

    worker =
      Task.async(fn ->
        C.execute_managed_v3(
          c.root,
          c.project,
          first,
          Ipse.Usage.id(),
          JSON.sha256("recipe"),
          fn _, read ->
            assert {:ok, %{"count" => 63}} = read.(%{"op" => "pending_summary"})
            send(parent, {:locked_summary, self()})
            receive do: (:release -> :ok)
            {:ok, normalized(first, [change(a(0), 1)]), %{"version" => 3}}
          end
        )
      end)

    assert_receive {:locked_summary, owner}, 5_000
    second = proposal.(101, 9)

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    program = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    result = Ipse.Extension.Collection.execute_managed_v3(
      #{inspect(c.root)}, #{inspect(c.project)}, #{inspect(second)},
      #{inspect(Ipse.Usage.id())}, #{inspect(JSON.sha256("recipe"))},
      fn _, _ -> IO.puts("UNEXPECTED_CALLBACK"); {:error, :unexpected} end)
    case result do
      {:error, :collection_unavailable} -> IO.puts("BUSY")
      {:conflict, _} -> IO.puts("CONFLICT")
      _ -> System.halt(2)
    end
    """

    invoke_other_vm = fn ->
      System.cmd("elixir", ["--erl", "+S 2:2"] ++ paths ++ ["-e", program],
        stderr_to_stdout: true
      )
    end

    assert {"BUSY\n", 0} = invoke_other_vm.()

    rival =
      Task.async(fn ->
        send(parent, :rival_started)

        C.execute_managed_v3(
          c.root,
          c.project,
          second,
          Ipse.Usage.id(),
          JSON.sha256("recipe"),
          fn _, _ ->
            send(parent, :rival_entered)
            {:ok, normalized(second, [change(a(0), 1)]), %{"version" => 3}}
          end
        )
      end)

    assert_receive :rival_started, 5_000
    refute_receive :rival_entered, 100
    send(owner, :release)
    assert {:ok, _} = Task.await(worker, 10_000)
    assert {"CONFLICT\n", 0} = invoke_other_vm.()
    rival_result = Task.await(rival, 10_000)

    assert match?({:conflict, _}, rival_result) or
             rival_result == {:error, :collection_unavailable}

    refute_receive :rival_entered

    last = proposal.(102, 10)

    current_program = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    result = Ipse.Extension.Collection.execute_managed_v3(
      #{inspect(c.root)}, #{inspect(c.project)}, #{inspect(last)},
      #{inspect(Ipse.Usage.id())}, #{inspect(JSON.sha256("recipe"))},
      fn _, read ->
        case read.(%{"op" => "pending_summary"}) do
          {:ok, %{"count" => 64}} -> IO.puts("FULL_64"); {:error, :queue_full}
          _ -> System.halt(3)
        end
      end)
    case result do
      {:error, :managed_normalization_refused} -> IO.puts("REFUSED")
      _ -> System.halt(2)
    end
    """

    assert {"FULL_64\nREFUSED\n", 0} =
             System.cmd("elixir", ["--erl", "+S 2:2"] ++ paths ++ ["-e", current_program],
               stderr_to_stdout: true
             )

    assert {:error, :managed_normalization_refused} =
             C.execute_managed_v3(
               c.root,
               c.project,
               last,
               Ipse.Usage.id(),
               JSON.sha256("recipe"),
               fn _, read ->
                 assert {:ok, %{"count" => 64}} = read.(%{"op" => "pending_summary"})
                 {:error, :queue_full}
               end
             )
  end
end
