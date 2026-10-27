Code.require_file(Path.expand("../../support/transaction_fixture.exs", __DIR__))
:ok = Ipse.Test.TransactionFixtureLoader.load_project()

defmodule Ipse.Extension.ProjectIdentityTest do
  use ExUnit.Case, async: false
  alias Ipse.Test.ProjectIdentityFixture, as: P

  setup_all do
    base = Path.join(System.tmp_dir!(), "ipse-identity-native-probe-" <> Ipse.Usage.id())
    File.mkdir!(base)
    File.chmod!(base, 0o700)
    source = Path.join(base, "probe.rs")
    helper = Path.join(base, "probe")
    real = Path.join(base, "runner")
    config = Path.join(base, "config")
    root = Path.expand("../../..", __DIR__)

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.join(root, "native/ipse-runner.rs"),
                 "-o",
                 real
               ],
               stderr_to_stdout: true
             )

    File.write!(
      source,
      ~S'''
      #[path=__TRANSACTION__] mod ipse_transaction;
      #[path=__STORAGE__] mod ipse_storage;
      use std::{env,fs,io::Write,process::{Command,exit},thread,time::Duration};
      use std::os::unix::process::CommandExt;
      unsafe extern "C" {fn mkfifo(path:*const std::ffi::c_char,mode:u32)->i32;fn kill(pid:i32,signal:i32)->i32;}
      fn config()->Vec<String>{fs::read_to_string(__CONFIG__).unwrap_or_default().lines().map(|s|s.to_owned()).collect()}
      fn frame(kind:u8,bytes:&[u8])->std::io::Result<()>{
        let c=config();let marker=c.get(1).map(String::as_str).unwrap_or("");
        if kind==b'A'{fs::write(format!("{}.lockpid",marker),std::process::id().to_string())?;}
        if kind==b'S'&&c.get(2).is_some_and(|s|s=="kill_after_write"){unsafe{kill(std::process::id() as i32,9);}}
        let mut out=std::io::stdout().lock();out.write_all(&[kind])?;out.write_all(&(bytes.len() as u32).to_be_bytes())?;out.write_all(bytes)?;out.flush()
      }
      fn main(){
        let args:Vec<_>=env::args().skip(1).collect();
        let c=config();
        let real=c[0].clone(); let marker=c[1].clone(); let mode=c[2].clone();
        if mode=="poison"{fs::write(marker,"ambient helper invoked").unwrap();exit(70);}
        if args.first().is_some_and(|a|a=="--transaction-lock"){
          let full:Vec<_>=env::args().collect();if ipse_transaction::run(&full).is_err(){exit(1);}return;
        }
        let before=mode=="kill_before_copy"&&args.first().is_some_and(|a|a=="--copy-regular");
        let after=mode=="kill_after_write"&&args.first().is_some_and(|a|a=="--sync-directory")&&std::path::Path::new(&args[1]).join("index.json").exists();
        if (before||after)&&!std::path::Path::new(&marker).exists(){
          let pid:i32=fs::read_to_string(format!("{}.lockpid",marker)).unwrap().parse().unwrap();
          assert_eq!(unsafe{kill(pid,9)},0);fs::write(&marker,"lock lost").unwrap();thread::sleep(Duration::from_millis(100));
        }
        if args.first().is_some_and(|a|a=="--copy-regular"){
          if mode=="delay"&&!std::path::Path::new(&marker).exists(){
            fs::write(&marker,"started").unwrap();thread::sleep(Duration::from_millis(4100));
          }
          if mode=="fifo"&&!std::path::Path::new(&marker).exists(){
            fs::rename(&args[1],format!("{}.old",&args[1])).unwrap();
            let name=std::ffi::CString::new(args[1].as_bytes()).unwrap();
            assert_eq!(unsafe{mkfifo(name.as_ptr(),0o600)},0);
            fs::write(&marker,"fifo").unwrap();
          }
          let result=Command::new(&real).args(&args).output().unwrap();
          if mode=="replace"&&args[1].ends_with("/gitdir")&&!std::path::Path::new(&marker).exists(){
            let git=c[3].clone();
            let bytes=fs::read(&git).unwrap();fs::rename(&git,format!("{}.old",git)).unwrap();
            fs::write(git,bytes).unwrap();fs::write(&marker,"replaced").unwrap();
          }
          let _=std::io::stdout().write_all(&result.stdout);
          if mode=="delay"{fs::write(format!("{}.finished",marker),"finished").unwrap();}
          exit(result.status.code().unwrap_or(70));
        }
        let _=Command::new(real).args(args).exec();exit(70);
      }
      '''
      |> String.replace("__TRANSACTION__", inspect(Path.join(root, "native/ipse-transaction.rs")))
      |> String.replace("__STORAGE__", inspect(Path.join(root, "native/ipse-storage.rs")))
      |> String.replace("__CONFIG__", inspect(config))
    )

    assert {output, 0} =
             System.cmd(
               System.find_executable("rustc"),
               ["--edition=2021", "-A", "dead_code", source, "-o", helper],
               stderr_to_stdout: true
             )

    refute output =~ "warning:"
    on_exit(fn -> File.rm_rf!(base) end)
    %{probe_helper: helper, native_helper: real, probe_config: config}
  end

  setup c do
    base = Path.join(System.tmp_dir!(), "ipse-project-identity-" <> Ipse.Usage.id())
    File.mkdir!(base)
    File.chmod!(base, 0o700)
    home = Path.join(base, "home")
    primary = Path.join(base, "primary")
    linked = Path.join(base, "linked")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    File.mkdir_p!(Path.join(primary, ".git/worktrees/linked"))
    File.mkdir!(linked)
    admin = Path.join(primary, ".git/worktrees/linked")
    File.write!(Path.join(linked, ".git"), "gitdir: #{admin}\n")
    File.write!(Path.join(admin, "commondir"), "../..\n")
    File.write!(Path.join(admin, "gitdir"), Path.join(linked, ".git") <> "\n")
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", c.native_helper)

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end)

    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base, home: home, primary: primary, linked: linked, admin: admin}
  end

  test "preview creates no binding and explicit folder scope never joins repository candidates",
       c do
    assert {:ok, %{"kind" => "primary_repository", "admitted" => false}} =
             P.preview(c.home, c.primary)

    refute File.exists?(index(c))
    assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.primary)
    assert {:ok, %{"kind" => "linked_candidate"}} = P.preview(c.home, c.linked)
    assert {:error, :primary_root_setup_required} = P.admit(c.home, c.linked, :repository)
    assert {:ok, primary} = P.admit(c.home, c.primary, :folder)
    assert primary["common_directory"] == nil
    assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
    assert {:ok, linked} = P.admit(c.home, c.linked, :folder)
    refute primary["project_id"] == linked["project_id"]
    assert {:error, :project_identity_conflict} = P.admit(c.home, c.primary, :repository)
    assert P.admit(c.home, c.primary, :folder) == {:ok, primary}
  end

  test "reciprocal registration shares opaque project identity and binds each worktree separately",
       c do
    assert {:ok, primary} = P.admit(c.home, c.primary, :repository)
    assert {:ok, linked} = P.resolve(c.home, c.linked)
    assert primary["project_id"] == linked["project_id"]
    refute primary["worktree_id"] == linked["worktree_id"]
    assert P.resolve(c.home, c.linked) == {:ok, linked}
    assert {:ok, linked} == P.with_binding(c.home, c.linked, linked, &{:ok, &1})
    caller = self()

    for forged <- [
          Map.put(linked, "project_id", Ipse.JSON.sha256("forgery")),
          Map.put(linked, "extra", true)
        ] do
      assert {:error, :stale_project_identity} =
               P.with_binding(c.home, c.linked, forged, fn _ -> send(caller, :forged_callback) end)
    end

    refute_received :forged_callback

    assert {:ok, :project_identity_lock_order} =
             P.with_binding(c.home, c.linked, linked, fn _ ->
               assert {:error, :project_identity_lock_order} = P.resolve(c.home, c.linked)
               {:ok, :project_identity_lock_order}
             end)

    assert {:unknown, :project_identity_callback_unconfirmed} =
             P.with_binding(c.home, c.linked, linked, fn _ -> raise "effect may have happened" end)

    assert File.stat!(index(c)).mode |> Bitwise.band(0o777) == 0o600
  end

  test "outward pointers, nonreciprocal backlinks and malformed records grant no inherited identity",
       c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    forged = Path.join(c.base, "archive")
    File.mkdir!(forged)
    File.write!(Path.join(forged, ".git"), File.read!(Path.join(c.linked, ".git")))
    assert {:error, :project_identity_not_admitted} = P.resolve(c.home, forged)

    for {file, bad} <- [
          {"commondir", "../../other\n"},
          {"commondir", "../..\nextra\n"},
          {"gitdir", Path.join(forged, ".git") <> "\n"}
        ] do
      path = Path.join(c.admin, file)
      original = File.read!(path)
      File.write!(path, bad)
      assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
      File.write!(path, original)
    end

    for suffix <- ["\nextra\n", "\n\n", "\r\n", String.duplicate("x", 4097)] do
      File.write!(Path.join(c.linked, ".git"), "gitdir: #{c.admin}" <> suffix)
      assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
    end

    assert state(c)["bindings"] |> map_size() == 1
  end

  test "symlinks, hardlinks and writable metadata are refused before sharing", c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)

    for path <- [
          Path.join(c.linked, ".git"),
          Path.join(c.admin, "commondir"),
          Path.join(c.admin, "gitdir")
        ] do
      original = File.read!(path)
      saved = path <> ".saved"
      File.rename!(path, saved)
      File.ln_s!(saved, path)
      assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
      File.rm!(path)
      File.rename!(saved, path)
      File.ln!(path, saved)
      assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
      File.rm!(saved)
      File.chmod!(path, 0o666)
      assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
      File.chmod!(path, 0o644)
      assert File.read!(path) == original
    end

    saved = c.admin <> "-saved"
    File.rename!(c.admin, saved)
    File.ln_s!(saved, c.admin)
    assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
  end

  test "replaced common directories, registration directories and metadata do not inherit", c do
    assert {:ok, primary} = P.admit(c.home, c.primary, :repository)
    assert {:ok, linked} = P.resolve(c.home, c.linked)
    path = Path.join(c.admin, "gitdir")
    original = File.read!(path)
    File.rename!(path, path <> ".old")
    File.write!(path, original)
    assert {:error, :stale_project_identity} = P.resolve(c.home, c.linked)
    refute P.with_binding(c.home, c.linked, linked, fn _ -> :unexpected end) == :unexpected
    File.rm!(path)
    File.rename!(path <> ".old", path)
    worktrees = Path.dirname(c.admin)
    File.rename!(worktrees, worktrees <> ".old")
    File.mkdir!(worktrees)
    File.rename!(Path.join(worktrees <> ".old", "linked"), c.admin)
    assert {:error, :stale_project_identity} = P.resolve(c.home, c.linked)
    common = Path.join(c.primary, ".git")
    File.rename!(common, common <> ".old")
    File.mkdir!(common)
    assert {:error, :stale_project_identity} = P.resolve(c.home, c.primary)
    assert {:error, :stale_project_identity} = P.admit(c.home, c.primary, :repository)
    refute P.with_binding(c.home, c.primary, primary, fn _ -> :unexpected end) == :unexpected
  end

  test "moves and independent clones never inherit prior binding IDs", c do
    assert {:ok, primary} = P.admit(c.home, c.primary, :repository)
    assert {:ok, linked} = P.resolve(c.home, c.linked)
    moved = c.linked <> "-moved"
    File.rename!(c.linked, moved)
    File.write!(Path.join(c.admin, "gitdir"), Path.join(moved, ".git") <> "\n")
    assert {:error, :project_identity_move_requires_join} = P.resolve(c.home, moved)
    assert {:error, _} = P.resolve(c.home, c.linked)
    clone = Path.join(c.base, "clone")
    File.mkdir_p!(Path.join(clone, ".git"))
    assert {:error, :project_identity_not_admitted} = P.resolve(c.home, clone)
    assert {:ok, separate} = P.admit(c.home, clone, :repository)
    refute separate["project_id"] in [primary["project_id"], linked["project_id"]]
    moved_primary = c.primary <> "-moved"
    File.rename!(c.primary, moved_primary)
    assert {:error, _} = P.resolve(c.home, moved_primary)
    assert {:ok, new} = P.admit(c.home, moved_primary, :repository)
    refute new["project_id"] == primary["project_id"]
  end

  test "protected state, closed schemas and same-process lock ordering fail closed", c do
    for owner <- [Ipse.Extension.Consent, Ipse.Extension.Collection] do
      Process.put({owner, :lock_held}, true)

      try do
        assert {:error, :project_identity_lock_order} = P.admit(c.home, c.primary, :repository)
      after
        Process.delete({owner, :lock_held})
      end
    end

    refute File.exists?(Path.join(c.home, "project-identities"))
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    bytes = File.read!(index(c))

    for malformed <- [
          "{\"version\":1,\"version\":1}",
          Jason.encode!(Map.put(state(c), "unknown", true)),
          String.duplicate("x", 1_048_577)
        ] do
      File.write!(index(c), malformed)
      assert {:error, :project_identity_unavailable} = P.resolve(c.home, c.primary)
    end

    File.write!(index(c), bytes)
    File.chmod!(index(c), 0o644)
    assert {:error, :project_identity_unavailable} = P.resolve(c.home, c.primary)
    File.chmod!(index(c), 0o600)
    File.ln!(index(c), index(c) <> ".hardlink")
    assert {:error, :project_identity_unavailable} = P.resolve(c.home, c.primary)
    File.rm!(index(c) <> ".hardlink")
    File.chmod!(c.home, 0o755)
    assert {:error, :project_identity_unavailable} = P.resolve(c.home, c.primary)
    File.chmod!(c.home, 0o700)
    assert {:ok, _} = P.resolve(c.home, c.primary)
  end

  test "two independent VMs race admission to one durable ID and retain the lock inode", c do
    body = ~S'''
    [home,cwd]=System.argv()
    retry=fn retry,left ->
      case Ipse.Extension.ProjectIdentity.admit(home,cwd,:repository) do
        {:ok,binding} -> IO.puts(Jason.encode!(binding))
        _ when left>0 -> Process.sleep(20); retry.(retry,left-1)
        other -> raise inspect(other)
      end
    end
    retry.(retry,50)
    '''

    tasks = for _ <- 1..2, do: Task.async(fn -> vm(body, [c.home, c.primary]) end)
    results = Enum.map(tasks, &Task.await(&1, 15_000))

    values =
      Enum.map(results, fn {output, status} ->
        assert status == 0, output
        Jason.decode!(String.trim(output))
      end)

    assert hd(values) == List.last(values)
    assert map_size(state(c)["projects"]) == 1
    assert map_size(state(c)["bindings"]) == 1
    assert state(c)["revision"] == 1
    lock = Path.join(c.home, "project-identities/.lock")
    inode = File.stat!(lock).inode

    halt = ~S'''
    [home,cwd]=System.argv()
    {:ok,b}=Ipse.Extension.ProjectIdentity.resolve(home,cwd)
    Ipse.Extension.ProjectIdentity.with_binding(home,cwd,b,fn _ -> System.halt(17) end)
    '''

    assert {_, 17} = vm(halt, [c.home, c.primary])
    assert {:ok, _} = eventually(fn -> P.resolve(c.home, c.primary) end)
    assert File.stat!(lock).inode == inode
  end

  test "a callback holds the actual OS lock against a different VM", c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    ready = Path.join(c.base, "ready")
    release = Path.join(c.base, "release")

    body = ~S'''
    [home,cwd,ready,release]=System.argv()
    {:ok,b}=Ipse.Extension.ProjectIdentity.resolve(home,cwd)
    Ipse.Extension.ProjectIdentity.with_binding(home,cwd,b,fn _ ->
      File.write!(ready,"ready")
      wait=fn wait,left ->
        cond do File.exists?(release)->:ok; left==0->raise "bounded release missing"; true->Process.sleep(10);wait.(wait,left-1) end
      end
      wait.(wait,500)
      IO.puts("released")
    end)
    '''

    task = Task.async(fn -> vm(body, [c.home, c.primary, ready, release]) end)

    assert {:ok, _} =
             eventually(fn ->
               if File.exists?(ready), do: {:ok, true}, else: {:error, :waiting}
             end)

    assert {:error, :project_identity_unavailable} = P.resolve(c.home, c.primary)
    File.write!(release, "release")
    assert {"released\n", 0} = Task.await(task, 10_000)
    assert {:ok, _} = P.resolve(c.home, c.primary)
  end

  test "native nonblocking copy refuses a FIFO substituted after the source precheck", c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)

    with_probe(c, "fifo", fn ->
      started = System.monotonic_time(:millisecond)
      assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
      assert System.monotonic_time(:millisecond) - started < 2000
      assert File.exists?(Path.join(c.base, "probe-marker"))
      refute File.exists?(Path.join(c.home, "project-identities/.metadata-active"))
      assert map_size(state(c)["bindings"]) == 1
    end)
  end

  test "metadata changed after one snapshot is fenced before durable worktree admission", c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    git = Path.join(c.linked, ".git")
    old = File.stat!(git).inode

    with_probe(c, "replace", fn ->
      assert {:error, :stale_project_identity} = P.resolve(c.home, c.linked)
      refute File.stat!(git).inode == old
      assert File.read!(git) == File.read!(git <> ".old")
      assert map_size(state(c)["bindings"]) == 1
    end)

    assert {:ok, _} = P.resolve(c.home, c.linked)
  end

  test "owner loss during an unconfirmed copy retains its finite staging quarantine", c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)

    with_probe(c, "delay", fn ->
      parent = self()
      caller = spawn(fn -> send(parent, {:late_result, P.resolve(c.home, c.linked)}) end)
      marker = Path.join(c.base, "probe-marker")

      assert {:ok, _} =
               eventually(fn ->
                 if File.exists?(marker), do: {:ok, true}, else: {:error, :waiting}
               end)

      Process.exit(caller, :kill)
      # The actual transaction owner now stops independently of a blocked copy.
      # After its lock releases, the retained copy quarantine still refuses IO.
      assert {:ok, true} =
               eventually(fn ->
                 case P.preview(c.home, c.primary) do
                   {:error, :project_metadata_unconfirmed} -> {:ok, true}
                   {:error, :project_identity_unavailable} -> {:error, :waiting}
                 end
               end)

      Process.sleep(3100)
      assert File.dir?(Path.join(c.home, "project-identities/.metadata-active"))
      assert {:error, :project_metadata_unconfirmed} = P.resolve(c.home, c.primary)

      assert {:ok, _} =
               eventually(fn ->
                 if File.exists?(marker <> ".finished"), do: {:ok, true}, else: {:error, :waiting}
               end)

      assert File.dir?(Path.join(c.home, "project-identities/.metadata-active"))
      assert map_size(state(c)["bindings"]) == 1
      refute_received {:late_result, _}
    end)
  end

  test "pointer dot segments cannot hide a symlink and stale previews cannot claim admission",
       c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    link = Path.join(c.base, "redirect")
    File.ln_s!(c.primary, link)
    File.write!(Path.join(c.linked, ".git"), "gitdir: #{link}/../primary/.git/worktrees/linked\n")
    assert {:error, :project_identity_not_admitted} = P.resolve(c.home, c.linked)
    File.write!(Path.join(c.linked, ".git"), "gitdir: #{c.admin}\n")
    assert {:ok, _} = P.resolve(c.home, c.linked)
    File.rename!(Path.join(c.primary, ".git"), Path.join(c.primary, ".git-old"))
    File.mkdir!(Path.join(c.primary, ".git"))
    assert {:error, :stale_project_identity} = P.preview(c.home, c.primary)
    assert {:error, _} = P.admit(c.home, "", :folder)
    assert {:error, _} = P.admit("relative-home", c.primary, :folder)
  end

  test "project count capacity refuses a new identity without evicting any existing binding", c do
    assert {:ok, first} = P.admit(c.home, c.primary, :repository)
    initial = state(c)

    full =
      Enum.reduce(1..255, initial, fn i, current ->
        path = Path.join(c.base, "folder-#{i}")
        File.mkdir!(path)
        stat = File.stat!(path)

        directory = %{
          "path" => path,
          "device" => Integer.to_string(stat.major_device),
          "inode" => Integer.to_string(stat.inode),
          "uid" => stat.uid,
          "mode" => stat.mode
        }

        id = Ipse.JSON.sha256("project#{i}")
        project = %{"id" => id, "scope" => "folder", "primary" => directory, "common" => nil}

        binding = %{
          "project_id" => id,
          "worktree_id" => Ipse.JSON.sha256("worktree#{i}"),
          "role" => "folder",
          "root" => directory,
          "registration" => nil,
          "admin" => nil,
          "metadata" => []
        }

        current
        |> put_in(["projects", id], project)
        |> put_in(["bindings", Ipse.JSON.sha256(path)], binding)
      end)

    File.write!(index(c), Jason.encode!(full))
    bytes = File.read!(index(c))
    assert {:error, :project_identity_capacity} = P.admit(c.home, c.linked, :folder)
    assert File.read!(index(c)) == bytes
    assert {:ok, ^first} = P.resolve(c.home, c.primary)
    remove = Ipse.JSON.sha256("project255")

    full =
      full
      |> update_in(["projects"], &Map.delete(&1, remove))
      |> update_in(
        ["bindings"],
        &Map.delete(&1, Ipse.JSON.sha256(Path.join(c.base, "folder-255")))
      )

    File.write!(index(c), Jason.encode!(full))
    assert {:ok, _} = P.admit(c.home, c.linked, :folder)
    assert map_size(state(c)["projects"]) == 256
  end

  test "a primary directory with an outward commondir override is unsupported and cannot reuse consent",
       c do
    path = Path.join(c.primary, ".git/commondir")
    File.write!(path, "../somewhere-else\n")
    assert {:error, :primary_root_setup_required} = P.admit(c.home, c.primary, :repository)
    File.rm!(path)
    assert {:ok, binding} = P.admit(c.home, c.primary, :repository)
    File.write!(path, "../somewhere-else\n")
    assert {:error, :stale_project_identity} = P.resolve(c.home, c.primary)

    assert {:error, :stale_project_identity} =
             P.with_binding(c.home, c.primary, binding, fn _ -> :unexpected end)
  end

  test "observed helper loss discards a callback result instead of returning recall", c do
    assert {:ok, binding} = P.admit(c.home, c.primary, :repository)

    assert {:unknown, :project_identity_lock_lost} =
             P.with_binding(c.home, c.primary, binding, fn _ ->
               controller = Process.get({Ipse.Test.TransactionFixture, :controller})
               Process.exit(controller, :kill)
               {:ok, "recall must not escape through returned value"}
             end)

    assert {:ok, ^binding} = eventually(fn -> P.resolve(c.home, c.primary) end)
  end

  test "native helper death before index write refuses admission and preserves the old index",
       c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    before = File.read!(index(c))

    with_probe(c, "kill_before_copy", fn ->
      assert {:unknown, :project_identity_lock_lost} = P.resolve(c.home, c.linked)
      assert File.read!(index(c)) == before
    end)
  end

  test "native helper death after the index switch reports unknown rather than confirmed admission",
       c do
    with_probe(c, "kill_after_write", fn ->
      assert {:unknown, :project_identity_lock_lost} = P.admit(c.home, c.primary, :folder)
      assert map_size(state(c)["bindings"]) == 1
      assert {:ok, _} = P.resolve(c.home, c.primary)
    end)
  end

  test "production identity bootstrap ignores ambient helper selection before touching controls",
       c do
    with_probe(c, "poison", fn ->
      result = Ipse.Extension.ProjectIdentity.admit(c.home, c.primary, :folder)
      assert elem(result, 0) in [:ok, :error, :unknown]
      refute File.exists?(Path.join(c.base, "probe-marker"))
    end)
  end

  test "the complete shared identity root counts against its four MiB staging budget", c do
    assert {:ok, _} = P.admit(c.home, c.primary, :repository)
    root = Path.join(c.home, "project-identities")
    alias Ipse.Test.TransactionFixture, as: T
    assert {:ok, cap} = T.acquire(Path.join(root, ".lock"), cwd: c.primary)
    assert {:ok, %{allocated: before}} = T.allocation(cap, :flat)
    filler = 4 * 1024 * 1024 - before - 4096
    assert filler > 0
    name = ".pending-" <> String.duplicate("f", 32)
    assert :ok = T.stage(cap, ".", [{name, :crypto.strong_rand_bytes(filler)}])
    assert :ok = T.install(cap, ".", name, String.duplicate("f", 64) <> ".json")
    assert :ok = T.release(cap)
    original = File.read!(index(c))
    assert {:error, :project_identity_capacity} = P.admit(c.home, c.linked, :folder)
    assert File.read!(index(c)) == original
    refute Enum.any?(File.ls!(root), &String.starts_with?(&1, ".pending-"))
  end

  test "private index and retained lock require exact 0600 without repairing existing modes", c do
    assert {:ok, binding} = P.admit(c.home, c.primary, :repository)

    for path <- [index(c), Path.join(c.home, "project-identities/.lock")],
        mode <- [0o400, 0o700] do
      File.chmod!(path, mode)
      assert {:error, :project_identity_unavailable} = P.resolve(c.home, c.primary)
      assert Bitwise.band(File.stat!(path).mode, 0o7777) == mode
      File.chmod!(path, 0o600)
    end

    assert {:ok, ^binding} = P.resolve(c.home, c.primary)
  end

  defp index(c), do: Path.join(c.home, "project-identities/index.json")
  defp state(c), do: c |> index() |> File.read!() |> Jason.decode!()

  defp with_probe(c, mode, fun) do
    {:ok, real} = Ipse.Runner.native_helper(c.primary)

    values = %{
      "IPSE_RUNNER_PATH" => c.probe_helper,
      "IPSE_IDENTITY_REAL_HELPER" => real,
      "IPSE_IDENTITY_PROBE_MARKER" => Path.join(c.base, "probe-marker"),
      "IPSE_IDENTITY_PROBE_MODE" => mode,
      "IPSE_IDENTITY_PROBE_GIT" => Path.join(c.linked, ".git")
    }

    previous = Map.new(values, fn {name, _} -> {name, System.get_env(name)} end)

    File.write!(
      c.probe_config,
      Enum.join(
        [real, Path.join(c.base, "probe-marker"), mode, Path.join(c.linked, ".git")],
        "\n"
      )
    )

    try do
      System.put_env(values)
      fun.()
    after
      Enum.each(previous, fn {name, value} ->
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end)
    end
  end

  defp vm(body, arguments) do
    libraries =
      Ipse.Runner
      |> :code.which()
      |> List.to_string()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.join("*/ebin")

    System.cmd(
      System.find_executable("elixir"),
      [
        "-pa",
        libraries,
        "-e",
        "Code.require_file(" <>
          inspect(Path.expand("../../support/transaction_fixture.exs", __DIR__)) <>
          "); Ipse.Test.TransactionFixtureLoader.load_project(); " <>
          String.replace(
            body,
            "Ipse.Extension.ProjectIdentity",
            "Ipse.Test.ProjectIdentityFixture"
          ),
        "--" | arguments
      ],
      stderr_to_stdout: true
    )
  end

  defp eventually(fun, left \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, left) do
    case fun.() do
      {:ok, _} = result ->
        result

      _ ->
        Process.sleep(20)
        eventually(fun, left - 1)
    end
  end
end
