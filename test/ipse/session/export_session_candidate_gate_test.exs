defmodule Ipse.Session.ExportSessionCandidateGateTest do
  use ExUnit.Case, async: false

  alias Ipse.Session

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-export-gate-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "state")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    opts = [
      config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
      cwd: root,
      state_dir: dir,
      subscriber: self()
    ]

    %{dir: dir, opts: opts}
  end

  test "candidate entry and direct GenServer initializer refuse before any journal or lock", c do
    for fun <- [
          fn -> Session.start_export_candidate_link(c.opts) end,
          fn -> GenServer.start(Session, {:export_v1, c.opts}) end
        ] do
      parent = self()

      spawn(fn ->
        Process.flag(:trap_exit, true)
        send(parent, {:candidate_result, fun.()})
      end)

      assert_receive {:candidate_result, {:error, :export_candidate_unavailable}}, 5_000
      assert [] == Path.wildcard(Path.join(c.dir, "*.jsonl"))
      assert [] == Path.wildcard(Path.join(c.dir, "*.lock"))
    end
  end

  test "legacy Session still starts and closes", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)

    assert :sys.get_state(session).lock_mode ==
             if(:os.type() == {:unix, :linux}, do: :header_v1, else: :legacy)

    assert :ok = Session.close_confirmed(session)
  end
end
