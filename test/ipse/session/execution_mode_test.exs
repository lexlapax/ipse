defmodule Ipse.Session.ExecutionModeTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.Mode

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-session-mode-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "sessions")}
  end

  defp start(c, config, id \\ nil) do
    opts = [
      cwd: c.root,
      state_dir: c.dir,
      subscriber: self(),
      config:
        Map.merge(%{provider: :demo, model: "fixture", home: Path.join(c.root, "home")}, config)
    ]

    opts = if id, do: Keyword.put(opts, :id, id), else: opts
    DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
  end

  test "first header persists headless origin and a separate yes headless channel", c do
    for config <- [
          %{approval: :deny, approval_origin: :default_headless, headless: true},
          %{approval: :allow, approval_origin: :yes, headless: true}
        ] do
      assert {:ok, session} = start(c, config)
      id = Session.info(session).id
      assert {:ok, [header | _]} = Journal.load(c.dir, id)
      mode = header["metadata"]["execution_mode"]
      assert header["metadata"]["semantic_admission"]["status"] == "off"
      assert header["metadata"]["semantic_admission"]["pin"] == nil
      assert Mode.valid?(mode) and mode["headless"]
      assert mode["approval_origin"] == Atom.to_string(config.approval_origin)
      assert :ok = Session.close_confirmed(session)
    end
  end

  test "startup-selection provenance cannot be attached to a child or nonplanning mode", c do
    for config <- [
          %{planning_cli_start: true, execution_mode: :normal},
          %{planning_cli_start: true, execution_mode: :planning, enclosing_mode: :read_only},
          %{planning_cli_start: true, execution_mode: :planning, delegation_origin: %{}},
          %{planning_cli_start: "true", execution_mode: :planning}
        ] do
      assert {:error, :invalid_planning_start_origin} = start(c, config)
    end
  end

  test "resume retains saved active/enclosing and explicit deny floors despite yes", c do
    for config <- [
          %{approval: :ask, execution_mode: :planning},
          %{approval: :ask, execution_mode: :draft, enclosing_mode: :read_only},
          %{approval: :deny}
        ] do
      assert {:ok, session} = start(c, config)
      id = Session.info(session).id
      assert :ok = Session.close_confirmed(session)

      assert {:ok, resumed} =
               start(c, %{approval: :allow, approval_origin: :yes, headless: true}, id)

      actual = :sys.get_state(resumed).config
      assert {:ok, mode} = Mode.capture(actual)
      assert :deny = Mode.ordinary(mode, true)
      assert {:error, _} = Mode.knowledge(mode, "collection.publish")
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  test "a planning ceiling selected on resume survives the next resume", c do
    assert {:ok, initial} = start(c, %{approval: :ask})
    id = Session.info(initial).id
    assert :ok = Session.close_confirmed(initial)

    assert {:ok, planning} = start(c, %{approval: :ask, execution_mode: :planning}, id)
    assert Session.info(planning).execution_mode["ceiling"] == "planning"
    assert :ok = Session.close_confirmed(planning)

    assert {:ok, resumed} = start(c, %{approval: :allow, approval_origin: :yes}, id)
    assert Session.info(resumed).execution_mode["ceiling"] == "planning"
    assert :deny = Mode.ordinary(Session.info(resumed).execution_mode, true)
    assert :ok = Session.close_confirmed(resumed)
  end

  test "an explicit denial selected on resume survives a later yes", c do
    assert {:ok, initial} = start(c, %{approval: :ask})
    id = Session.info(initial).id
    assert :ok = Session.close_confirmed(initial)
    assert {:ok, denied} = start(c, %{approval: :deny, approval_origin: :explicit}, id)
    assert :ok = Session.close_confirmed(denied)
    assert {:ok, resumed} = start(c, %{approval: :allow, approval_origin: :yes}, id)
    assert Session.info(resumed).execution_mode["approval"] == "deny"
    assert :ok = Session.close_confirmed(resumed)
  end

  test "local and inherited planning remain distinguishable across actual resumes", c do
    for {config, local, enclosing} <- [
          {%{execution_mode: :planning}, "planning", "normal"},
          {%{enclosing_mode: :planning}, "normal", "planning"}
        ] do
      assert {:ok, initial} = start(c, config)
      id = Session.info(initial).id
      assert :ok = Session.close_confirmed(initial)
      assert {:ok, resumed} = start(c, %{approval: :allow, approval_origin: :yes}, id)
      mode = Session.info(resumed).execution_mode
      assert mode["ceiling"] == local and mode["enclosing_ceiling"] == enclosing
      assert :deny = Mode.ordinary(mode, true)
      assert :ok = Session.close_confirmed(resumed)
      assert {:ok, events} = Journal.load(c.dir, id)
      assert Enum.any?(events, &(&1["type"] == "execution_mode_resumed" and &1["version"] === 2))
      assert {:ok, ^mode} = Session.Saved.execution_mode(events, id)

      assert {:ok, later} = start(c, %{approval: :ask}, id)
      later_mode = Session.info(later).execution_mode
      assert later_mode["ceiling"] == local and later_mode["enclosing_ceiling"] == enclosing
      assert :deny = Mode.ordinary(later_mode, true)
      assert :ok = Session.close_confirmed(later)
    end
  end

  test "knowledge restrictions selected when resuming a legacy session survive later resumes",
       c do
    assert {:ok, template} = start(c, %{approval: :ask})
    template_id = Session.info(template).id
    assert :ok = Session.close_confirmed(template)
    assert {:ok, [header | _]} = Journal.load(c.dir, template_id)

    legacy_metadata =
      Map.drop(header["metadata"], ~w(execution_mode native_journal_layout release_receipt_layout
        session_lock_identity source_origin source_origin_layout))

    for ceiling <- [:paused, :disabled] do
      assert {:ok, id} = Journal.create(c.dir, legacy_metadata)
      assert {:ok, restricted} = start(c, %{approval: :ask, knowledge_ceiling: ceiling}, id)
      assert Session.info(restricted).execution_mode["knowledge"] == Atom.to_string(ceiling)
      assert :ok = Session.close_confirmed(restricted)

      assert {:ok, events} = Journal.load(c.dir, id)
      assert {:ok, saved} = Session.Saved.execution_mode(events, id)
      assert saved["knowledge"] == Atom.to_string(ceiling)
      assert {:ok, resumed} = start(c, %{approval: :allow, approval_origin: :yes}, id)
      assert Session.info(resumed).execution_mode["knowledge"] == Atom.to_string(ceiling)

      assert {:error, :knowledge_disabled} =
               Mode.knowledge(Session.info(resumed).execution_mode, "collection.read")

      assert :ok = Session.close_confirmed(resumed)
    end
  end

  test "resume mode checkpoints bind prior mode and cannot widen it" do
    id = String.duplicate("a", 32)
    {:ok, initial} = Mode.capture(%{approval: :ask})
    {:ok, planning} = Mode.inherit(initial, %{approval: :ask, execution_mode: :planning})
    {:ok, retained} = Mode.inherit(planning, %{approval: :allow, approval_origin: :yes})
    header = %{"metadata" => %{"execution_mode" => initial}}

    checkpoint = fn prior, mode ->
      %{
        "type" => "execution_mode_resumed",
        "version" => 1,
        "session_id" => id,
        "previous_sha256" => Ipse.JSON.digest([prior]),
        "mode" => mode
      }
    end

    first = checkpoint.(initial, planning)
    second = checkpoint.(planning, retained)
    assert {:ok, ^retained} = Session.Saved.execution_mode([header, first, second], id)

    assert {:ok, ^planning} =
             Session.Saved.execution_mode([%{"metadata" => %{}}, checkpoint.(nil, planning)], id)

    for invalid <- [
          [header, first, first],
          [header, second],
          [header, first, checkpoint.(planning, initial)],
          [header, Map.put(first, "session_id", String.duplicate("b", 32))],
          [header, Map.put(first, "extra", true)]
        ] do
      assert {:error, :invalid_saved_execution_mode} = Session.Saved.execution_mode(invalid, id)
    end
  end

  test "saved malformed ceiling is refused while missing legacy marker remains explicit" do
    assert {:ok, mode} = Mode.capture(%{approval: :deny})
    assert {:ok, nil} = Session.Saved.execution_mode([%{"metadata" => %{}}])

    assert {:ok, ^mode} =
             Session.Saved.execution_mode([%{"metadata" => %{"execution_mode" => mode}}])

    for invalid <- [nil, %{}, Map.put(mode, "version", 1.0), Map.put(mode, "extra", true)] do
      assert {:error, :invalid_saved_execution_mode} =
               Session.Saved.execution_mode([
                 %{"metadata" => %{"execution_mode" => invalid}}
               ])
    end
  end

  test "version two resume checkpoints preserve each floor and legacy checkpoints remain valid" do
    id = String.duplicate("d", 32)
    {:ok, local} = Mode.capture(%{execution_mode: :planning})
    {:ok, resumed} = Mode.resume(local, %{approval: :allow, approval_origin: :yes})
    header = %{"metadata" => %{"execution_mode" => local}}

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => id,
      "previous_sha256" => Ipse.JSON.digest([local]),
      "mode" => resumed
    }

    assert {:ok, ^resumed} = Session.Saved.execution_mode([header, checkpoint], id)

    for invalid <- [
          put_in(checkpoint, ["mode", "ceiling"], "normal"),
          Map.put(checkpoint, "version", 2.0),
          Map.put(checkpoint, "version", 1)
        ] do
      assert {:error, :invalid_saved_execution_mode} =
               Session.Saved.execution_mode([header, invalid], id)
    end

    {:ok, legacy} = Mode.inherit(local, %{approval: :allow, approval_origin: :yes})
    old = %{checkpoint | "version" => 1, "mode" => legacy}
    assert {:ok, ^legacy} = Session.Saved.execution_mode([header, old], id)
    assert {:ok, retained} = Mode.resume(legacy, %{approval: :ask})
    assert retained["enclosing_ceiling"] == "planning"
  end

  test "preselected Journal ID is validated and its first header is exclusively created", c do
    id = String.duplicate("e", 32)
    assert {:ok, ^id} = Journal.create_with_id(c.dir, id, %{"pin_session_id" => id})
    assert {:error, _} = Journal.create_with_id(c.dir, id, %{"replaced" => true})
    assert {:ok, [header]} = Journal.load(c.dir, id)
    assert header["metadata"] == %{"pin_session_id" => id}

    for invalid <- ["../outside", "short", String.duplicate("E", 32), nil] do
      assert {:error, :invalid_id} = Journal.create_with_id(c.dir, invalid, %{})
    end
  end

  test "resuming an inactive Session never activates a later selection in equivalent direct runtime",
       c do
    assert {:ok, session} = start(c, %{approval: :deny})
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)

    selection = %{
      "notes" => %{
        "version" => 1,
        "project" => String.duplicate("a", 64),
        "policy_sha256" => String.duplicate("b", 64),
        "enabled" => true
      }
    }

    assert {:ok, resumed} = start(c, %{approval: :deny, semantic_selections: selection}, id)
    assert :sys.get_state(resumed).config.semantic_admission["pin"] == nil
    assert :sys.get_state(resumed).config.semantic_admission["status"] == "off"
    assert :ok = Session.close_confirmed(resumed)
    refute File.exists?(Path.join(c.root, "home/knowledge-control"))
  end

  test "explicit null/forged semantic admission cannot be treated as legacy absence" do
    id = String.duplicate("c", 32)
    assert {:ok, nil} = Session.Saved.semantic_admission([%{"metadata" => %{}}], id)

    for value <- [nil, %{}, %{"version" => 1.0}] do
      assert {:error, :invalid_saved_semantic_admission} =
               Session.Saved.semantic_admission(
                 [
                   %{"metadata" => %{"semantic_admission" => value}}
                 ],
                 id
               )
    end
  end

  test "context inspection preserves input validation precedence and validates explicit headers" do
    message = %{"type" => "message", "message" => %{"role" => "user", "content" => "legacy"}}

    header = %{"type" => "session", "metadata" => %{}}

    assert {:ok, [%{"role" => "user", "content" => "legacy"}]} =
             Session.restore_context([header, message])

    damaged =
      Ipse.Session.Input.received(Ipse.Usage.id(), Ipse.Usage.id(), "original", "original", nil)

    damaged = Map.put(damaged, "text", "changed")
    assert {:error, :invalid_input_origin} = Session.restore_context([damaged])

    for key <- ["execution_mode", "semantic_admission"] do
      assert {:error, _} =
               Session.restore_context([
                 %{"type" => "session", "metadata" => %{key => nil}},
                 message
               ])
    end
  end
end
