path = "test/ipse/extension/managed_collection_call_session_test.exs"
source = File.read!(path)
replace = fn text, from, to ->
  1 = length(:binary.matches(text, from))
  String.replace(text, from, to, global: false)
end
source = replace.(source, "defmodule Ipse.Extension.ManagedCollectionCallSessionTest do", "defmodule Ipse.Extension.CurrentLiteralPublicationProbeTest do")
source = String.replace(source, "__DIR__", inspect(Path.expand("test/ipse/extension")))
source = replace.(source, "state[\"mode\"] == \"capture_ab_literal\" ->", "state[\"mode\"] in [\"capture_ab_literal\", \"capture_ab_literal_publication\"] ->")
source = replace.(source, "if state[\"mode\"] != \"capture_ab_publication\" do", "if state[\"mode\"] not in [\"capture_ab_publication\", \"capture_ab_literal_publication\"] do")
source = replace.(source, "state[\"mode\"] in [\"capture_ab_literal\", \"capture_ab_publication\"] ->", "state[\"mode\"] in [\"capture_ab_literal\", \"capture_ab_publication\", \"capture_ab_literal_publication\"] ->")
test = ~S'''
  @tag current_literal_publication: true,
       worker_inherited_union: true,
       literal_v4_ab: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_mode: "capture_ab_literal_publication"
  test "a current genuine literal A allows a new B candidate with the full inherited union", c do
    seed = c.literal_seed
    IO.puts("CURRENT_LITERAL_PUBLICATION_ROOT=" <> c.root)
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, status}}, 15_000
    assert {:ok, events} = Journal.load(c.dir, id)

    literals =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: dependency

    assert [literal] = literals
    assert literal["subject"]["key"] == seed["key"]
    [quote] = Enum.filter(events, &(get_in(&1, ["request", "op"]) == "source.quote" and &1["type"] == "extension_action_result"))
    assert quote["outcome"]["status"] == "ok"
    assert quote["outcome"]["value"]["origin"] == "unattended_input"
    assert {:ok, _} = Session.Saved.restore(events, id)

    publications = Enum.filter(events, &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == "collection.managed"))
    assert status == :ok, "current literal publication did not complete: #{inspect(Enum.map(publications, & &1["outcome"]["status"]))}"
    assert [publication] = publications
    assert publication["outcome"]["status"] == "ok"
    [change] = publication["request"]["request"]["changes"]
    [proof] = change["value"]["evidence"]["sources"]
    assert proof["session_id"] == id
    assert proof["session_id"] != seed["session_id"]
    assert :ok = Session.close_confirmed(pid)
    assert [_, _] = Task.await(c.provider_server, 5000)
  end

'''
source = replace.(source, "  defp drain_literal_ab_notifications(pid, acc) do", test <> "  defp drain_literal_ab_notifications(pid, acc) do")
target = "/tmp/ipse-current-literal-publication-20261102_test.exs"
{:ok, file} = File.open(target, [:write, :exclusive])
:ok = IO.binwrite(file, source)
:ok = File.close(file)
IO.puts(target)
