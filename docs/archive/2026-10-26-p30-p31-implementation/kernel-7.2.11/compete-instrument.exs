root = "/tmp/ipse-sdk-compete-diagnostic-20261027/project"
source = Path.join(root, "lib/ipse/extension/managed_collection_call.ex")
text = File.read!(source)
needle = """
      {:ok, witness} ->
        Process.put(c.managed_first_proof, witness)
"""
replacement = """
      {:ok, witness} ->
        if listener = :persistent_term.get({:ipse_sdk_compete_diagnostic, :listener}, nil) do
          send(listener, {:diagnostic_after_postproof_close, self(), witness})
          receive do
            :diagnostic_resume_first -> :ok
          after
            20_000 -> raise "diagnostic timeout"
          end
        end
        Process.put(c.managed_first_proof, witness)
"""
unless String.contains?(text, needle), do: raise("postproof source changed")
File.write!(source, String.replace(text, needle, replacement, global: false))

test = Path.join(root, "test/ipse/extension/managed_collection_call_session_test.exs")
text = File.read!(test)
needle = ~S|if state["mode"] == "hold", do: (File.write!(state["trace"], "held\\n", [:append]); Process.sleep(600))|
replacement = ~S|if state["mode"] == "hold", do: (File.write!(state["trace"], "held\\n", [:append]); wait_release(state["trace"] <> ".release"))|
unless String.contains?(text, needle), do: raise("fixture hold source changed")
text = String.replace(text, needle, replacement, global: false)
needle = "      defp advance(\"list\", %{\"status\" => \"ok\", \"value\" => value}, state) do"
replacement = """
      defp wait_release(path) do
        if File.exists?(path), do: :ok, else: (Process.sleep(10); wait_release(path))
      end
      defp advance("list", %{"status" => "ok", "value" => value}, state) do
"""
unless String.contains?(text, needle), do: raise("fixture advance source changed")
text = String.replace(text, needle, replacement, global: false)
testbody = """
  defp clear_compete_traces do
    receive do
      {:trace, _, _, _} -> clear_compete_traces()
      {:trace, _, _, _, _} -> clear_compete_traces()
    after
      0 -> :ok
    end
  end

  @tag metadata_version: 3
  test "diagnostic two Sessions serialize at postproof close", c do
    :persistent_term.put({:ipse_sdk_compete_diagnostic, :listener}, self())
    :erlang.trace_pattern({ProjectIdentity, :with_domain_publication, 6}, [{:_, [], [{:return_trace}]}], [:local])
    :erlang.trace(:all, true, [:call])

    try do
      first = start(c)
      second = start(c, %{fixture_mode: "hold"})
      assert :ok = Session.prompt(second, "Synthetic café observation")
      await_marker(c.trace, "held", 1500)
      assert :ok = Session.prompt(first, "Synthetic café observation")
      assert_receive {:diagnostic_after_postproof_close, first_effect, witness}, 15_000
      assert JSON.sha256?(witness.root_sha256)

      state = c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()
      assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]["state"] == "prepared"
      clear_compete_traces()
      File.write!(c.trace <> ".release", "release")
      expected_home = c.home
      expected_cwd = c.cwd

      assert_receive {:trace, blocked, :call, {ProjectIdentity, :with_domain_publication,
        [^expected_home, ^expected_cwd, _, _, _, _]}} when blocked != first_effect, 10_000
      assert_receive {:trace, ^blocked, :return_from, {ProjectIdentity, :with_domain_publication, 6}, {:error, :project_identity_unavailable}}, 10_000
      assert_receive {:ipse, ^second, {:done, :ok}}, 15_000
      assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1

      send(first_effect, :diagnostic_resume_first)
      assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
      {:ok, events} = Journal.load(c.dir, Session.info(second).id)
      result = Enum.find(events, &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed"))
      assert result["outcome"]["status"] == "failed"
      state = c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()
      entry = state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]
      assert entry["state"] == "active" and entry["first_root_sha256"] == witness.root_sha256

      :persistent_term.erase({:ipse_sdk_compete_diagnostic, :listener})
      third = start(c)
      assert :ok = Session.prompt(third, "Synthetic café observation")
      assert_receive {:ipse, ^third, {:done, :ok}}, 15_000
      assert collection_read(c, %{"op" => "snapshot"})["generation"] == 2
      state = c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()
      assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace] == entry
    after
      :persistent_term.erase({:ipse_sdk_compete_diagnostic, :listener})
      :erlang.trace(:all, false, [:call])
      :erlang.trace_pattern({ProjectIdentity, :with_domain_publication, 6}, false, [:local])
    end
  end
"""
unless String.ends_with?(text, "end\n"), do: raise("fixture end changed")
File.write!(test, String.replace_suffix(text, "end\n", testbody <> "end\n"))
