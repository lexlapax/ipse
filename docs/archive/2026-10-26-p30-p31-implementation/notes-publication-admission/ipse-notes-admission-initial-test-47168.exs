Code.require_file("collection_normalizer_v3_integration_test.exs", __DIR__)

defmodule Ipse.Extension.NotesPublicationAdmissionTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture
  alias Ipse.Session.Resources
  @moduletag :notes_admission
  @deadline_key {Collection, :switch_deadline}
  @admission_key {Collection, :notes_publication_admission}

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-notes-admission-" <> Usage.id())

    for path <- [base, base <> "/home", base <> "/work"] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    {:ok, binding} = ProjectIdentity.admit(base <> "/home", base <> "/work", :folder)

    c = %{
      base: base,
      home: base <> "/home",
      cwd: base <> "/work",
      binding: binding,
      root: base <> "/collections",
      namespace: Ipse.Test.NormalizerV3Fixture.namespace()
    }

    # Retain actual native stores, including any prepared/unknown effect, for inspection.
    c
  end

  test "invalid/elapsed scopes run no callback and generic strict timed notes entry stays closed",
       c do
    parent = self()

    for deadline <- [nil, 0, -1, 1.0, "future"] do
      assert {:error, :invalid_collection_request} =
               Collection.with_notes_publication_deadline(deadline, fn -> send(parent, :ran) end)
    end

    assert {:error, :collection_use_expired} =
             Collection.with_notes_publication_deadline(System.system_time(:millisecond), fn ->
               send(parent, :ran)
             end)

    refute_receive :ran, 20

    assert {:error, :collection_deadline_fence_unavailable} =
             Collection.with_publication_deadline(System.system_time(:millisecond) + 60_000, fn ->
               flunk("legacy callback")
             end)

    assert {:error, :collection_deadline_fence_unavailable} =
             Collection.execute_profile_before(
               c.root,
               c.namespace,
               %{},
               Usage.id(),
               Collection.Profile.notes(),
               System.system_time(:millisecond) + 60_000
             )

    refute File.exists?(c.root)
  end

  test "same file-effect scope keeps minima and restores inherited state on exception" do
    assert :ok =
             Resources.file_effect(fn ->
               inherited = System.system_time(:millisecond) + 30_000
               Process.put(@deadline_key, inherited)
               before = Process.get(@admission_key)

               try do
                 assert :ok =
                          Collection.with_notes_publication_deadline(inherited + 20_000, fn ->
                            assert Process.get(@deadline_key) == inherited
                            {owner, token} = Process.get(@admission_key)
                            assert owner == self() and is_reference(token)

                            assert :ok =
                                     Collection.with_notes_publication_deadline(
                                       inherited - 1000,
                                       fn ->
                                         assert Process.get(@deadline_key) == inherited - 1000
                                         :ok
                                       end
                                     )

                            assert Process.get(@deadline_key) == inherited
                            :ok
                          end)

                 assert_raise RuntimeError, "scope fixture", fn ->
                   Collection.with_notes_publication_deadline(inherited, fn ->
                     raise "scope fixture"
                   end)
                 end

                 assert Process.get(@deadline_key) == inherited
                 assert Process.get(@admission_key) == before
                 :ok
               after
                 Process.delete(@deadline_key)
               end
             end)
  end

  test "actual v3 signed capture uses live final admission and retains original clocks", c do
    now = System.system_time(:millisecond)
    opts = %{Fixture.options(1, 0) | now_ms: now}
    scope = scope(c)

    assert {:ok, result} =
             Collection.with_notes_publication_deadline(now + 60_000, fn ->
               Fixture.publish(c, opts, scope, first: true)
             end)

    assert result.core["normalization"]["first_admitted_ms"] == now
    assert result.core["normalization"]["valid_until_ms"] > now + 60_000
    assert result.core["receipt"]["generation"] == 1

    assert {:ok, %{"operation" => operation}} =
             Collection.execute(
               c.root,
               c.namespace,
               %{"op" => "inspect", "operation_id" => scope.operation_id},
               Usage.id()
             )

    assert operation["generation"] == 1
  end

  for shorter <- [:policy, :normalization] do
    test "#{shorter} deadline is the actual native minimum after synced staging", c do
      shorter = unquote(shorter)
      now = System.system_time(:millisecond)
      deadline = now + 2000
      opts = %{Fixture.options(1, 0) | now_ms: now}

      opts =
        if shorter == :normalization do
          update_in(opts.recipe["rules"], fn rules ->
            Enum.map(rules, fn rule ->
              if rule["category"] == "ordinary", do: Map.put(rule, "max_age_ms", 2000), else: rule
            end)
          end)
        else
          opts
        end

      policy = if shorter == :policy, do: deadline, else: now + 60_000
      observer = self()
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:ipse, :extension, :collection, :staged],
          fn _, _, _, _ ->
            if Process.get(@admission_key) != nil do
              assert Process.get(@deadline_key) == deadline
              Process.sleep(max(deadline - System.system_time(:millisecond) + 2, 0))
              assert System.system_time(:millisecond) >= deadline
              send(observer, {:expired_after_stage, shorter})
            end
          end,
          nil
        )

      try do
        assert {:unknown, _} =
                 Collection.with_notes_publication_deadline(policy, fn ->
                   Fixture.publish(c, opts, scope(c), first: true)
                 end)

        assert_receive {:expired_after_stage, ^shorter}, 1000
        refute File.exists?(Path.join([c.root, c.namespace, "root.json"]))

        assert {:ok, %{"generation" => 0}} =
                 Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())
      after
        :telemetry.detach(handler)
      end
    end
  end

  defp scope(c),
    do: %{
      namespace: c.namespace,
      format: "managed-metadata-v3",
      operation_id: Usage.id(),
      initialize: true
    }
end
