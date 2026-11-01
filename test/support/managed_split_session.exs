# Synthetic page geometry; selected statements and replacement proof are genuine Session receipts.
Code.require_file("../ipse/extension/collection_managed_pages_test.exs", __DIR__)

defmodule Ipse.Test.ManagedSplitSession do
  import ExUnit.Assertions
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, ProjectIdentity, SemanticAdmission, ManagedRecipe}
  alias Ipse.Extension.Collection.ManagedPages
  alias Ipse.Test.ManagedPagesFixture, as: F

  def install(root) do
    source = File.read!("lib/ipse/session.ex")

    anchor = """
              with {:ok, s} <- prepare_supersession_intake(s, pending, event, source) do
                invoke_assertion_capture(s, name, args)
    """

    assert length(:binary.matches(source, anchor)) == 1

    replacement = """
              with {:ok, s} <- prepare_supersession_intake(s, pending, event, source) do
                case Process.whereis(:ipse_split_seed_control) do
                  watcher when is_pid(watcher) and is_map(s.managed_supersession) ->
                    send(watcher, {:split_source_ready, self(), s.managed_supersession.proof})
                    receive do
                      :split_seed_complete -> :ok
                    after
                      10_000 -> throw(:split_seed_not_released)
                    end
                  _ -> :ok
                end
                invoke_assertion_capture(s, name, args)
    """

    instrumented = String.replace(source, anchor, replacement, global: false)
    IO.puts("SPLIT_CONTROL_SOURCE_SHA256=" <> JSON.sha256(instrumented))
    [{module, beam}] = Code.compile_string(instrumented, "session-split-source-control.ex")
    path = Path.join(root, "Elixir.Ipse.Session.beam")
    File.write!(path, beam)
    assert {:module, ^module} = :code.load_binary(module, String.to_charlist(path), beam)
  end

  def prepare(config, cwd, home, ordinary, current, proof) do
    admission = config.semantic_admission
    pin = admission["pin"]
    root = SemanticAdmission.collection_root(home)
    assert {:ok, next} = ManagedRecipe.source_identity(proof)
    current_id = current["value"]["lineage"]
    ordinary_id = ordinary["value"]["lineage"]
    assert length(Enum.uniq([current_id, ordinary_id, next])) == 3
    points = Enum.sort([current_id, ordinary_id, next]) |> Enum.map(&String.to_integer(&1, 16))
    [a, b, c] = points
    assert b - a > 2_000 and c - b > 2_000 and a > 1_000
    fences = [0, div(a + b, 2), div(b + c, 2)]
    groups = Enum.zip(fences, points)

    scope = %{
      namespace: pin["namespace"],
      format: "managed-metadata-v3",
      operation_id: Usage.id(),
      initialize: false
    }

    assert {:ok, seeded} =
             ProjectIdentity.with_domain_publication(
               home,
               cwd,
               admission["binding"],
               scope,
               fn _ -> :ok end,
               fn cap, _catalog ->
                 assert {:ok, checked} =
                          Collection.with_managed_read(root, pin["namespace"], fn witness,
                                                                                  read,
                                                                                  alive ->
                            assert :ok = alive.()

                            leaves =
                              for kind <- [:anchor, :live], into: %{} do
                                key = ManagedPages.page_key(kind, ManagedPages.zero(kind))
                                assert {:ok, record} = read.(key)

                                needle =
                                  if kind == :live, do: "00" <> current_id, else: current_id

                                assert {:ok, neighbors} =
                                         read.(%{
                                           "op" => "neighbors",
                                           "request" => %{
                                             "version" => 1,
                                             "prefix" => ManagedPages.prefix(kind),
                                             "fence_bytes" => ManagedPages.width(kind),
                                             "needle" => needle
                                           }
                                         })

                                assert neighbors["neighbors"]["selected"]["key"] == key

                                assert neighbors["neighbors"]["predecessor"] == nil and
                                         neighbors["neighbors"]["successor"] == nil

                                assert {:ok, page} = ManagedPages.open(cap, record, neighbors)
                                assert map_size(page.entries) == 2
                                {kind, {record, page.entries}}
                              end

                            assert {:ok, target} = read.(current["key"])
                            assert target["value"] === current["value"]
                            {:ok, %{witness: witness, leaves: leaves, target: target}}
                          end)

                 request = %{
                   "op" => "commit",
                   "expected_generation" => checked.witness["root"]["generation"],
                   "advance_floor" => true,
                   "changes" => [
                     %{
                       "key" => current["key"],
                       "expected_revision" => checked.target["revision"],
                       "value" => current["value"]
                     }
                   ]
                 }

                 recipe =
                   admission["policy"]["settings"]["recipes"]
                   |> Map.values()
                   |> Enum.find(&(&1["kind"] == "literal_source"))

                 Collection.execute_managed(
                   root,
                   pin["namespace"],
                   request,
                   scope.operation_id,
                   JSON.digest([recipe]),
                   fn witness, _read ->
                     assert witness["root_sha256"] == checked.witness["root_sha256"]

                     extras =
                       for kind <- [:anchor, :live], {lower, point} <- groups do
                         lineage = F.id(point)
                         {original, existing} = checked.leaves[kind]
                         actual_id = if kind == :live, do: "00" <> lineage, else: lineage
                         actual = existing[actual_id]

                         count =
                           if kind == :anchor,
                             do: if(actual, do: 95, else: 96),
                             else: if(actual, do: 24, else: 25)

                         first =
                           case actual do
                             row when is_list(row) -> row |> Enum.at(4) |> String.to_integer(36)
                             _ -> System.system_time(:millisecond)
                           end

                         rows =
                           for i <- 1..count, into: %{} do
                             id = lower + i
                             assert id < point

                             if kind == :anchor do
                               {F.id(id), F.row()}
                             else
                               {key, row} = F.live(id, first)

                               deadline =
                                 cond do
                                   is_nil(actual) -> first + 1
                                   lineage == current_id and i == 1 -> Bitwise.bsl(1, 41)
                                   lineage == ordinary_id and i == 1 -> first + 1
                                   true -> Bitwise.bsl(1, 50)
                                 end

                               {key, List.replace_at(row, 5, F.base36(deadline))}
                             end
                           end

                         rows = if actual, do: Map.put(rows, actual_id, actual), else: rows

                         if kind == :live and actual,
                           do:
                             assert(
                               ManagedPages.weight(kind, rows) ==
                                 ManagedPages.profile(kind).capacity
                             )

                         fence = if kind == :anchor, do: F.id(lower), else: "00" <> F.id(lower)
                         key = ManagedPages.page_key(kind, fence)
                         assert {:ok, body} = ManagedPages.pack(kind, fence, rows)
                         assert {:ok, value} = ManagedPages.seal(cap, witness, key, body)

                         %{
                           "key" => key,
                           "expected_revision" =>
                             if(key == original["key"], do: original["revision"], else: 0),
                           "value" => value
                         }
                       end

                     assert length(extras) == 6
                     {:ok, Map.update!(request, "changes", &(&1 ++ extras)), %{"version" => 2}}
                   end
                 )
               end
             )

    assert seeded["normalization"] == %{"version" => 2}
    {:ok, seeded["receipt"]["generation"]}
  end

  def capture_units(_, _, _, owner) do
    {_, units, :closed} = Process.get({Collection, :managed_read})
    send(owner, {:native_split_units, units})
  end
end
