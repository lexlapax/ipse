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
