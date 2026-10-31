defmodule Ipse.Session.ShareCandidateOldHelperTest do
  use ExUnit.Case, async: false
  @moduletag skip: System.get_env("IPSE_SESSION_SHARE_OLD_HELPER_TEST") != "1"

  test "older pinned helper refuses candidate before creating a journal" do
    root = Path.join(System.tmp_dir!(), "ipse-share-old-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "sessions")
    on_exit(fn -> File.rm_rf!(root) end)

    opts = [
      config: %{
        provider: :demo,
        model: "fixture",
        home: root,
        approval: :deny,
        observability: Map.put(Ipse.Observability.defaults(), "mode", "local")
      },
      cwd: root,
      state_dir: dir,
      subscriber: self()
    ]

    parent = self()

    spawn(fn ->
      Process.flag(:trap_exit, true)
      send(parent, {:old_helper_start, Ipse.Session.start_share_candidate_link(opts)})
    end)

    assert_receive {:old_helper_start, {:error, _}}, 10_000
    assert Path.wildcard(Path.join(dir, "*.jsonl")) == []
  end
end
