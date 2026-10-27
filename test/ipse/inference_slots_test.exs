defmodule Ipse.InferenceSlotsTest do
  use ExUnit.Case, async: false
  alias Ipse.{InferenceSlots, InferenceSlots.Store, Runner.Transaction}

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-service-slots-" <> Ipse.Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)

    config = %{
      provider: :ollama,
      model: "fixture-main",
      base_url: "http://127.0.0.1:11434",
      home: home,
      extensions: [%{identity: %{"capabilities" => ~w(host.model host.embedding)}}],
      model_profiles: %{
        "answer" => %{
          "provider" => "ollama",
          "model" => "fixture-answer",
          "base_url" => "http://localhost:11434"
        }
      },
      embedding_profiles: %{
        "search" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture-embedding",
          "base_url" => "http://127.0.0.1:11434",
          "dimensions" => 1024,
          "dimension_mode" => "native"
        }
      },
      inference_services: %{
        "local" => %{
          "version" => 1,
          "origins" => ["http://127.0.0.1:11434", "http://localhost:11434"]
        }
      }
    }

    opts = [cwd: cwd, wait_ms: 5_000, dispatch_timeout_ms: 5_000, notify: self()]

    supported =
      case InferenceSlots.status(config, cwd: cwd) do
        {:ok, _} -> true
        {:error, :service_filesystem_unsupported} -> false
        other -> flunk("service slot bootstrap failed: #{inspect(other)}")
      end

    %{base: base, home: home, cwd: cwd, config: config, opts: opts, supported: supported}
  end

  defp selector(op \\ "main", profile \\ nil),
    do: %{
      "operation" => op,
      "profile" => profile,
      "processing_region" => nil,
      "storage_region" => nil,
      "cache_retention" => nil,
      "account_controls" => nil
    }

  defp meta(priority \\ "foreground"),
    do: %{
      "session_id" => Ipse.Usage.id(),
      "project_id" => Ipse.JSON.sha256("fixture-project"),
      "request_sha256" => Ipse.JSON.sha256("fixture-request"),
      "priority" => priority
    }

  defp checked(c, fun) do
    if c.supported do
      fun.()
    else
      parent = self()

      assert {:error, :service_filesystem_unsupported} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 send(parent, :unexpected_dispatch)
                 {:settled, nil}
               end)

      refute_received :unexpected_dispatch

      IO.puts(
        "#{c.test}: unsupported filesystem refusal verified; supported runtime journey NOT RUN"
      )
    end
  end

  defp blocked(parent, tag),
    do: fn reservation ->
      send(parent, {:entered, tag, self(), reservation, Process.get({Transaction, :controller})})

      receive do
        :finish_fixture -> {:settled, tag}
      end
    end

  defp eventually(fun, remaining \\ 100) do
    if fun.(),
      do: :ok,
      else:
        if(remaining > 0,
          do:
            (
              Process.sleep(20)
              eventually(fun, remaining - 1)
            ),
          else: flunk("condition did not converge")
        )
  end

  test "settled main generation releases the service before a nested embedding or named-model tool",
       c do
    checked(c, fn ->
      assert {:ok, :main} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 assert {:error, :service_slot_lock_order} =
                          InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                            flunk("recursive dispatch")
                          end)

                 {:settled, :main}
               end)

      for {op, profile} <- [{"embedding.create", "search"}, {"model.complete", "answer"}] do
        assert {:ok, ^op} =
                 InferenceSlots.run(c.config, selector(op, profile), meta(), c.opts, fn %{
                                                                                          "route" =>
                                                                                            route
                                                                                        } ->
                   assert route["service_id"] == "local"
                   {:settled, op}
                 end)
      end

      assert {:ok, state} = InferenceSlots.status(c.config, cwd: c.cwd)
      assert map_size(state["services"]) == 1 and length(state["recent"]) == 3
      assert state["services"]["local"]["active"] == nil
    end)
  end

  test "unknown completion blocks every alias and model until exact protected reconciliation",
       c do
    checked(c, fn ->
      assert {:unknown, %{"reservation_id" => id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 {:error, :synthetic_timeout}
               end)

      parent = self()

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(
                 c.config,
                 selector("model.complete", "answer"),
                 meta(),
                 c.opts,
                 fn _ ->
                   send(parent, :unexpected_dispatch)
                   {:settled, nil}
                 end
               )

      refute_received :unexpected_dispatch
      assert {:ok, state} = InferenceSlots.status(c.config, cwd: c.cwd)

      receipt = %{
        "version" => 1,
        "reason" => "shared_service_reconciled",
        "service_id" => "local",
        "reservation_id" => id,
        "expected_revision" => state["revision"],
        "operator_receipt_sha256" => Ipse.JSON.sha256("synthetic-reviewed-reconciliation")
      }

      assert {:error, _} =
               InferenceSlots.reconcile(
                 c.config,
                 "local",
                 Ipse.Usage.id(),
                 state["revision"],
                 receipt,
                 cwd: c.cwd
               )

      assert {:error, _} =
               InferenceSlots.reconcile(c.config, "local", id, state["revision"] - 1, receipt,
                 cwd: c.cwd
               )

      assert {:ok, _} =
               InferenceSlots.reconcile(c.config, "local", id, state["revision"], receipt,
                 cwd: c.cwd
               )

      assert {:ok, :next} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 {:settled, :next}
               end)

      assert {:ok, state} = InferenceSlots.status(c.config, cwd: c.cwd)
      assert Enum.any?(state["recent"], &(&1["id"] == id and &1["status"] == "reconciled"))
    end)
  end

  test "foreground waiters outrank background work across models and projects", c do
    checked(c, fn ->
      parent = self()

      assert {:ok, active} =
               InferenceSlots.start(
                 c.config,
                 selector(),
                 meta(),
                 c.opts,
                 blocked(parent, :active)
               )

      assert_receive {:entered, :active, running, _, _}, 5_000

      assert {:ok, background} =
               InferenceSlots.start(
                 %{c.config | model: "another-model"},
                 selector(),
                 meta("background"),
                 c.opts,
                 blocked(parent, :background)
               )

      background_ref = background.ref
      assert_receive {:inference_slot, ^background_ref, %{"state" => "waiting"}}, 5_000
      foreground_meta = Map.put(meta(), "project_id", Ipse.JSON.sha256("different-project"))

      assert {:ok, foreground} =
               InferenceSlots.start(
                 c.config,
                 selector("embedding.create", "search"),
                 foreground_meta,
                 c.opts,
                 blocked(parent, :foreground)
               )

      foreground_ref = foreground.ref
      assert_receive {:inference_slot, ^foreground_ref, %{"state" => "waiting"}}, 5_000
      send(running, :finish_fixture)
      assert {:ok, :active} = InferenceSlots.await(active)
      assert_receive {:entered, :foreground, fg, _, _}, 5_000
      refute_receive {:entered, :background, _, _, _}, 100
      send(fg, :finish_fixture)
      assert {:ok, :foreground} = InferenceSlots.await(foreground)
      assert_receive {:entered, :background, bg, _, _}, 5_000
      send(bg, :finish_fixture)
      assert {:ok, :background} = InferenceSlots.await(background)
    end)
  end

  test "cancelled known-unstarted waiters never invoke callbacks and handles cannot replay or transfer",
       c do
    checked(c, fn ->
      parent = self()

      assert {:ok, active} =
               InferenceSlots.start(
                 c.config,
                 selector(),
                 meta(),
                 c.opts,
                 blocked(parent, :active)
               )

      assert_receive {:entered, :active, running, _, _}, 5_000

      assert {:ok, waiting} =
               InferenceSlots.start(c.config, selector(), meta(), c.opts, fn _ ->
                 send(parent, :unexpected_dispatch)
                 {:settled, nil}
               end)

      ref = waiting.ref
      assert_receive {:inference_slot, ^ref, %{"state" => "waiting"}}, 5_000
      task = Task.async(fn -> {InferenceSlots.cancel(waiting), InferenceSlots.await(waiting)} end)

      assert {{:error, :invalid_service_slot_request}, {:error, :invalid_service_slot_request}} =
               Task.await(task)

      assert {:error, :invalid_service_slot_request} =
               InferenceSlots.cancel(%{waiting | id: Ipse.Usage.id()})

      assert :ok = InferenceSlots.cancel(waiting)
      assert {:error, :service_cancelled} = InferenceSlots.await(waiting)
      assert {:error, :invalid_service_slot_request} = InferenceSlots.await(waiting)
      refute_received :unexpected_dispatch
      send(running, :finish_fixture)
      assert {:ok, :active} = InferenceSlots.await(active)
    end)
  end

  test "a never-awaited handle still enforces the callback deadline and retains unresolved work",
       c do
    checked(c, fn ->
      parent = self()
      opts = Keyword.put(c.opts, :dispatch_timeout_ms, 150)

      assert {:ok, handle} =
               InferenceSlots.start(c.config, selector(), meta(), opts, blocked(parent, :timed))

      assert_receive {:entered, :timed, worker, %{"reservation_id" => id}, controller}, 5_000
      eventually(fn -> not Process.alive?(worker) and not Process.alive?(controller) end)
      assert {:unknown, _} = InferenceSlots.await(handle)

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("replayed unresolved work")
               end)
    end)
  end

  test "cancelling an admitted handle stops its worker before await and retains its marker", c do
    checked(c, fn ->
      parent = self()

      assert {:ok, handle} =
               InferenceSlots.start(
                 c.config,
                 selector(),
                 meta(),
                 c.opts,
                 blocked(parent, :cancel_active)
               )

      assert_receive {:entered, :cancel_active, worker, %{"reservation_id" => id}, controller},
                     5_000

      assert :ok = InferenceSlots.cancel(handle)
      eventually(fn -> not Process.alive?(worker) and not Process.alive?(controller) end)
      assert {:unknown, _} = InferenceSlots.await(handle)

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("cancelled remote work replay")
               end)
    end)
  end

  test "distinct service identities can run concurrently under the one shared bounded tree", c do
    checked(c, fn ->
      parent = self()

      assert {:ok, first} =
               InferenceSlots.start(
                 c.config,
                 selector(),
                 meta(),
                 c.opts,
                 blocked(parent, :first_service)
               )

      assert_receive {:entered, :first_service, worker, _, _}, 5_000

      config = %{
        c.config
        | base_url: "http://127.0.0.1:11435",
          inference_services:
            Map.put(c.config.inference_services, "second", %{
              "version" => 1,
              "origins" => ["http://127.0.0.1:11435"]
            })
      }

      assert {:ok, "second"} =
               InferenceSlots.run(config, selector(), meta(), c.opts, fn %{"route" => route} ->
                 {:settled, route["service_id"]}
               end)

      assert Process.alive?(worker)
      send(worker, :finish_fixture)
      assert {:ok, :first_service} = InferenceSlots.await(first)
      assert {:ok, state} = InferenceSlots.status(c.config, cwd: c.cwd)
      assert map_size(state["services"]) == 2
    end)
  end

  test "owner death and actual native controller loss cannot clear admitted work", c do
    checked(c, fn ->
      parent = self()

      owner =
        spawn(fn ->
          InferenceSlots.run(c.config, selector(), meta(), c.opts, blocked(parent, :owner))
        end)

      assert_receive {:entered, :owner, worker, %{"reservation_id" => id}, controller}, 5_000
      Process.exit(owner, :kill)
      eventually(fn -> not Process.alive?(worker) and not Process.alive?(controller) end)

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("owner-death replay")
               end)

      assert {:ok, state} = InferenceSlots.status(c.config, cwd: c.cwd)

      receipt = %{
        "version" => 1,
        "reason" => "owned_service_quiescent",
        "service_id" => "local",
        "reservation_id" => id,
        "expected_revision" => state["revision"],
        "operator_receipt_sha256" => Ipse.JSON.sha256("fixture")
      }

      assert {:ok, _} =
               InferenceSlots.reconcile(c.config, "local", id, state["revision"], receipt,
                 cwd: c.cwd
               )

      assert {:ok, handle} =
               InferenceSlots.start(
                 c.config,
                 selector(),
                 meta(),
                 c.opts,
                 blocked(parent, :native)
               )

      assert_receive {:entered, :native, _, %{"reservation_id" => second}, controller}, 5_000
      Process.exit(controller, :kill)
      assert {:unknown, _} = InferenceSlots.await(handle)

      assert {:unknown, %{"reservation_id" => ^second}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("native-loss replay")
               end)
    end)
  end

  test "persisted aliases cannot be escaped by a config rename or binding replacement", c do
    checked(c, fn ->
      assert {:unknown, _} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ -> :unknown end)

      service = c.config.inference_services["local"]
      renamed = %{c.config | inference_services: %{"renamed" => service}}

      assert {:error, :service_identity_conflict} =
               InferenceSlots.run(renamed, selector(), meta(), c.opts, fn _ ->
                 flunk("renamed unresolved route")
               end)

      changed =
        put_in(c.config, [:inference_services, "local", "origins"], ["http://127.0.0.1:11434"])

      assert {:error, :service_identity_conflict} =
               InferenceSlots.run(changed, selector(), meta(), c.opts, fn _ ->
                 flunk("changed unresolved binding")
               end)
    end)
  end

  test "a suspended resource scope cannot retain a native lease after the original caller dies",
       c do
    checked(c, fn ->
      parent = self()

      owner =
        spawn(fn ->
          {:ok, handle} =
            InferenceSlots.start(
              c.config,
              selector(),
              meta(),
              c.opts,
              blocked(parent, :suspended_scope)
            )

          send(parent, {:original_owner, self(), handle.scope})

          receive do
            :never -> :ok
          end
        end)

      assert_receive {:original_owner, ^owner, scope}, 5_000

      assert_receive {:entered, :suspended_scope, worker, %{"reservation_id" => id}, controller},
                     5_000

      assert :sys.get_state(controller).upstream == owner
      :ok = :sys.suspend(scope)
      on_exit(fn -> if Process.alive?(scope), do: :sys.resume(scope) end)
      Process.exit(owner, :kill)
      eventually(fn -> not Process.alive?(worker) and not Process.alive?(controller) end)
      assert Process.alive?(scope)

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("suspended-scope owner escaped")
               end)

      :ok = :sys.resume(scope)
      eventually(fn -> not Process.alive?(scope) end)
    end)
  end

  test "cancellation bypasses a suspended scope and blocks late settlement", c do
    checked(c, fn ->
      parent = self()

      assert {:ok, handle} =
               InferenceSlots.start(
                 c.config,
                 selector(),
                 meta(),
                 c.opts,
                 blocked(parent, :suspended_cancel)
               )

      assert_receive {:entered, :suspended_cancel, worker, %{"reservation_id" => id}, controller},
                     5_000

      :ok = :sys.suspend(handle.scope)
      on_exit(fn -> if Process.alive?(handle.scope), do: :sys.resume(handle.scope) end)
      assert :ok = InferenceSlots.cancel(handle)
      eventually(fn -> not Process.alive?(worker) and not Process.alive?(controller) end)

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("suspended-scope cancellation escaped")
               end)

      :ok = :sys.resume(handle.scope)
      assert {:unknown, _} = InferenceSlots.await(handle)
    end)
  end

  test "a late known-terminal callback cannot settle after its actual native owner dies", c do
    checked(c, fn ->
      assert {:unknown, %{"reservation_id" => id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 Process.exit(Process.get({Transaction, :controller}), :kill)
                 {:settled, :late_callback}
               end)

      assert {:unknown, %{"reservation_id" => ^id}} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("late terminal result cleared the fence")
               end)

      assert {:ok, state} = InferenceSlots.status(c.config, cwd: c.cwd)
      assert state["services"]["local"]["active"]["id"] == id
      refute Enum.any?(state["recent"], &(&1["id"] == id))
    end)
  end

  test "unsafe paths and changed protected files refuse without repair or disclosure", c do
    checked(c, fn ->
      root = Path.join(c.home, "inference-services")
      control = Path.join(root, "control.json")
      File.write!(control, "untrusted")
      File.chmod!(control, 0o644)
      assert {:error, _} = InferenceSlots.status(c.config, cwd: c.cwd)
      assert Bitwise.band(File.stat!(control).mode, 0o7777) == 0o644
      File.rm!(control)
      File.ln_s!(Path.join(c.base, "outside"), control)
      assert {:error, _} = InferenceSlots.status(c.config, cwd: c.cwd)
      refute File.exists?(Path.join(c.base, "outside"))
      File.rm!(control)

      assert {:ok, _} =
               InferenceSlots.run(c.config, selector(), meta(), c.opts, fn _ ->
                 {:settled, :safe}
               end)

      File.ln!(control, Path.join(c.base, "alias"))
      assert {:error, _} = InferenceSlots.status(c.config, cwd: c.cwd)
    end)
  end

  test "the full fixed tree and staged ledger count toward one MiB", c do
    checked(c, fn ->
      assert {:ok, context} = Store.context(c.home, c.cwd)
      assert {:ok, cap} = Transaction.acquire(Path.join(context.root, ".lock"), cwd: c.cwd)
      assert :ok = Transaction.quota(cap, :collection, 1_048_576)
      assert {:ok, %{allocated: allocated}} = Transaction.allocation(cap, :collection)
      assert allocated <= 1_048_576
      pending = ".pending-" <> Ipse.Usage.id()

      assert :ok = Transaction.stage(cap, ".", [{pending, :crypto.strong_rand_bytes(65_536)}])
      assert {:ok, %{allocated: peak}} = Transaction.allocation(cap, :collection)
      assert peak > allocated and peak <= 1_048_576
      assert {:error, :transaction_capacity} = Transaction.preflight(cap, [1_048_576])
      assert :ok = Transaction.release(cap)
      assert {:ok, _} = InferenceSlots.status(c.config, cwd: c.cwd)
      refute File.exists?(Path.join(context.root, pending))
    end)
  end

  test "configured deadlines, selectors and reverse lock order refuse before any worker", c do
    for opts <- [
          Keyword.put(c.opts, :dispatch_timeout_ms, 100_001),
          Keyword.put(c.opts, :wait_ms, 60_001),
          Keyword.put(c.opts, :dispatch_timeout_ms, 1.0)
        ] do
      assert {:error, :invalid_service_slot_request} =
               InferenceSlots.start(c.config, selector(), meta(), opts, fn _ ->
                 flunk("invalid dispatch")
               end)
    end

    assert {:error, _} =
             InferenceSlots.start(
               c.config,
               Map.put(selector(), "endpoint", "http://127.0.0.1:9999"),
               meta(),
               c.opts,
               fn _ -> flunk("forged route") end
             )

    for module <- [
          Ipse.Extension.ProjectIdentity,
          Ipse.Extension.Consent,
          Ipse.Extension.Collection
        ] do
      Process.put({module, :lock_held}, true)

      assert {:error, :service_slot_lock_order} =
               InferenceSlots.start(c.config, selector(), meta(), c.opts, fn _ ->
                 flunk("reverse-lock dispatch")
               end)

      Process.delete({module, :lock_held})
    end
  end

  test "independent VMs serialize aliases and project routes through the same protected slot",
       c do
    checked(c, fn ->
      code = """
      {:ok,_}=Application.ensure_all_started(:ipse)
      result=Ipse.InferenceSlots.run(#{inspect(c.config)}, #{inspect(selector())}, #{inspect(meta())}, #{inspect(Keyword.delete(c.opts, :notify))}, fn _ ->
        IO.puts("SLOT_ADMITTED")
        case IO.gets("") do
          "complete\\n" -> {:settled, :completed}
          _ -> :unknown
        end
      end)
      IO.puts("SLOT_RESULT:" <> inspect(result))
      """

      paths =
        :code.get_path()
        |> Enum.reverse()
        |> Enum.flat_map(fn path -> ["-pa", List.to_string(path)] end)

      port =
        Port.open({:spawn_executable, String.to_charlist(System.find_executable("elixir"))}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: paths ++ ["-e", code]
        ])

      on_exit(fn -> if Port.info(port), do: Port.close(port) end)
      assert :ok = vm_wait(port, "SLOT_ADMITTED", <<>>)
      parent = self()

      assert {:error, :service_wait_timeout} =
               InferenceSlots.run(
                 c.config,
                 selector("embedding.create", "search"),
                 meta(),
                 Keyword.put(c.opts, :wait_ms, 200),
                 fn _ ->
                   send(parent, :unexpected_dispatch)
                   {:settled, :bad}
                 end
               )

      refute_received :unexpected_dispatch
      assert Port.command(port, "complete\n")
      assert :ok = vm_wait(port, "SLOT_RESULT:{:ok, :completed}", <<>>)

      assert {:ok, :after_vm} =
               InferenceSlots.run(
                 c.config,
                 selector("model.complete", "answer"),
                 meta(),
                 c.opts,
                 fn _ -> {:settled, :after_vm} end
               )
    end)
  end

  defp vm_wait(port, expected, bytes) when byte_size(bytes) <= 8192 do
    if String.contains?(bytes, expected) do
      :ok
    else
      receive do
        {^port, {:data, data}} -> vm_wait(port, expected, bytes <> data)
        {^port, {:exit_status, status}} -> flunk("fixture VM exited #{status}: #{bytes}")
      after
        10_000 -> flunk("fixture VM did not reach #{expected}: #{bytes}")
      end
    end
  end
end
