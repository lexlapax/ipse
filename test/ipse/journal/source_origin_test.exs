defmodule Ipse.Journal.SourceOriginTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.{SourceOrigin, Writer}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-origin-" <> Ipse.Usage.id())

    for name <- ["original", "copy", "home", "work"] do
      path = Path.join(root, name)
      File.mkdir_p!(path)
      File.chmod!(path, 0o700)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, directory: Path.join(root, "original"), copy: Path.join(root, "copy")}
  end

  defp create(c) do
    assert {:ok, id} =
             Journal.create(c.directory, %{"source_origin_layout" => SourceOrigin.layout()})

    assert {:ok, [%{"metadata" => metadata}]} = Journal.load(c.directory, id)
    {id, metadata, Path.join(c.directory, id <> ".jsonl")}
  end

  test "new header binds actual descriptor identity and remains writable on the original", c do
    {id, metadata, path} = create(c)
    stat = File.stat!(path)
    assert {:ok, origin} = SourceOrigin.recorded(metadata, id)
    assert origin["directory"] == c.directory
    assert origin["inode"] == stat.inode
    assert origin["major_device"] == stat.major_device
    assert :ok = SourceOrigin.check_path(c.directory, id, metadata)
    assert {:ok, writer} = Writer.start(c.directory, id, self())
    assert :ok = Writer.append(writer, %{"type" => "synthetic"})
    assert :ok = Writer.close(writer)
    assert {:ok, writer} = Writer.start(c.directory, id, self())
    assert :ok = Writer.close(writer)
  end

  test "an intact copy remains inspectable and cannot reopen for appends", c do
    {id, metadata, original} = create(c)
    copied = Path.join(c.copy, id <> ".jsonl")
    File.cp!(original, copied)
    File.chmod!(copied, 0o600)
    before = File.read!(copied)
    assert {:ok, [%{"metadata" => ^metadata}]} = Journal.load(c.copy, id)
    assert {:error, :journal_origin_unavailable} = SourceOrigin.check_path(c.copy, id, metadata)
    assert {:error, :journal_unavailable} = Writer.start(c.copy, id, self())
    assert File.read!(copied) == before
    assert :ok = SourceOrigin.check_path(c.directory, id, metadata)
  end

  test "replacement at the same pathname cannot acquire the original file identity", c do
    {id, metadata, path} = create(c)
    File.rename!(path, path <> ".retained")
    File.cp!(path <> ".retained", path)
    File.chmod!(path, 0o600)
    before = File.read!(path)

    assert {:error, :journal_origin_unavailable} =
             SourceOrigin.check_path(c.directory, id, metadata)

    assert {:error, :journal_unavailable} = Writer.start(c.directory, id, self())
    assert File.read!(path) == before
  end

  test "legacy headers remain legacy and malformed origin declarations refuse", c do
    assert {:ok, id} = Journal.create(c.directory, %{})
    assert {:ok, nil} = SourceOrigin.recorded(%{}, id)
    assert {:ok, writer} = Writer.start(c.directory, id, self())
    assert :ok = Writer.append(writer, %{"type" => "legacy"})
    assert :ok = Writer.close(writer)
    assert {:ok, [header, _]} = Journal.load(c.directory, id)
    refute Map.has_key?(header["metadata"], "source_origin")

    for metadata <- [
          %{"source_origin_layout" => SourceOrigin.layout()},
          %{"source_origin_layout" => "future"},
          %{"source_origin" => %{}},
          %{"source_origin_layout" => SourceOrigin.layout(), "source_origin" => %{}}
        ] do
      assert {:error, :journal_origin_unavailable} = SourceOrigin.recorded(metadata, id)
    end
  end

  test "an active source window cannot return cached facts after journal replacement", c do
    {id, _metadata, path} = create(c)
    assert {:ok, events} = Journal.load(c.directory, id)
    assert {:ok, window} = Ipse.Session.SourceWindow.restore(events, id)
    assert {:ok, writer} = Writer.start(c.directory, id, self())
    assert :ok = Writer.install_source_window(writer, window)
    assert {:ok, _} = Writer.source_query(writer, :snapshot)
    monitor = Process.monitor(writer)
    File.rename!(path, path <> ".retained")
    File.cp!(path <> ".retained", path)
    File.chmod!(path, 0o600)
    before = File.read!(path)
    assert {:error, :source_index_refused} = Writer.source_query(writer, :snapshot)
    assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}
    assert File.read!(path) == before
  end

  test "the writer refuses a source window reconstructed under another origin", c do
    {id, _metadata, _path} = create(c)
    assert {:ok, events} = Journal.load(c.directory, id)
    assert {:ok, window} = Ipse.Session.SourceWindow.restore(events, id)
    assert {:ok, writer} = Writer.start(c.directory, id, self())
    legacy = %{window | index: %{window.index | origin_sha256: nil}}
    foreign = %{window | index: %{window.index | origin_sha256: Ipse.JSON.sha256("different")}}
    assert {:error, :source_index_refused} = Writer.install_source_window(writer, legacy)
    assert {:error, :source_index_refused} = Writer.install_source_window(writer, foreign)
    assert :ok = Writer.install_source_window(writer, window)
    assert {:ok, _} = Writer.source_query(writer, :snapshot)
    assert :ok = Writer.close(writer)
  end

  for mutation <- [:public_parent, :relocated_parent],
      operation <- [:query, :append, :reserved] do
    @tag origin_boundary: true
    test "active origin #{operation} refuses #{mutation}", c do
      {id, metadata, path} = create(c)
      assert {:ok, events} = Journal.load(c.directory, id)
      assert {:ok, window} = Ipse.Session.SourceWindow.restore(events, id)
      assert {:ok, writer} = Writer.start(c.directory, id, self())
      assert :ok = Writer.install_source_window(writer, window)
      assert {:ok, token} = Writer.reserve(writer, %{bytes: 4096, events: 1})
      before = File.read!(path)
      monitor = Process.monitor(writer)

      case unquote(mutation) do
        :public_parent ->
          File.chmod!(c.directory, 0o755)

        :relocated_parent ->
          relocated = c.directory <> ".moved"
          File.rename!(c.directory, relocated)
          File.ln_s!(relocated, c.directory)
      end

      assert {:error, :journal_origin_unavailable} =
               SourceOrigin.check_path(c.directory, id, metadata)

      case unquote(operation) do
        :query ->
          assert {:error, :source_index_refused} = Writer.source_query(writer, :origin)

        :append ->
          assert {:error, :journal_write_unconfirmed} =
                   Writer.append(writer, %{"type" => "synthetic"})

        :reserved ->
          assert {:error, :journal_write_unconfirmed} =
                   Writer.append_reserved(writer, token, %{"type" => "synthetic"})
      end

      assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}
      assert File.read!(path) == before
    end
  end

  @tag origin_boundary: true
  test "a directory alias to the original canonical location preserves the origin", c do
    {id, _metadata, _path} = create(c)
    alias_path = Path.join(c.root, "alias")
    File.ln_s!(c.directory, alias_path)
    assert {:ok, events} = Journal.load(alias_path, id)
    assert {:ok, window} = Ipse.Session.SourceWindow.restore(events, id)
    assert {:ok, writer} = Writer.start(alias_path, id, self())
    assert :ok = Writer.install_source_window(writer, window)
    assert :ok = Writer.append(writer, %{"type" => "synthetic"})
    assert {:ok, origin} = Writer.source_query(writer, :origin)
    assert origin["directory"] == c.directory
    assert :ok = Writer.close(writer)
  end

  test "fresh Session binds its source and copied resume refuses before torn-tail repair", c do
    config = %{provider: :demo, model: "demo", home: Path.join(c.root, "home"), approval: :ask}

    opts = [
      config: config,
      cwd: Path.join(c.root, "work"),
      state_dir: c.directory,
      subscriber: self()
    ]

    assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(session).id
    assert :ok = Ipse.Session.close_confirmed(session)
    path = Path.join(c.directory, id <> ".jsonl")
    assert {:ok, [header | _]} = Journal.load(c.directory, id)
    assert {:ok, origin} = SourceOrigin.recorded(header["metadata"], id)
    assert origin["directory"] == c.directory

    copied = Path.join(c.copy, id <> ".jsonl")
    File.cp!(path, copied)
    File.chmod!(copied, 0o600)
    File.write!(copied, "{\"torn\":", [:append])
    before = File.read!(copied)
    copied_opts = Keyword.merge(opts, state_dir: c.copy, id: id)

    # Resume first requires an existing lock inode. Exercise both the missing
    # lock refusal and the separate copied-journal identity check.
    assert {:error, "source lock unavailable"} =
             DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, copied_opts})

    assert File.read!(copied) == before
    copied_lock = Path.join(c.copy, id <> ".lock")
    File.write!(copied_lock, "")
    File.chmod!(copied_lock, 0o600)

    assert {:error, :journal_origin_unavailable} =
             DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, copied_opts})

    assert File.read!(copied) == before

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert :ok = Ipse.Session.close_confirmed(resumed)
  end
end
