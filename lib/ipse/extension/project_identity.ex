defmodule Ipse.Extension.ProjectIdentity do
  @moduledoc """
  Internal explicit project admission and reciprocal Git worktree identity.

  A preview grants no recall. Only a trusted host may call `admit/3`; a model,
  workspace file or supplied project ID cannot authorize it. Repository setup
  starts at a canonical primary root with a `.git` directory. A linked worktree
  can resolve only after that primary has been admitted, otherwise setup must
  explicitly select the primary root. There is no silent folder fallback.
  Preview can create protected control/lock files and transient bounded metadata
  snapshots; it never publishes a project or worktree binding.

  Call `with_binding/4` before supplying recall or using a binding after a change.
  Its callback must be short and perform no inference. Lock order is identity
  index, project Consent, then Collection. Entry guards detect same-process
  reverse acquisition and reentry, not arbitrary cross-process deadlocks.
  Callbacks return data for the host to release after a successful checked return;
  they must not emit recall themselves. Native lease checks discard read results
  after observed loss; they do not fence arbitrary callback IO. The actual native
  lock owner stages and publishes the protected index, so it cannot publish after
  dying and releasing its lock. All locks are released in reverse order.
  Repository metadata is trusted only after reciprocal admission; this does not
  defend against arbitrary code able to alter operator state or admitted Git
  metadata. No repository command, hook, configuration or network is executed.
  """
  alias Ipse.JSON
  alias Ipse.Runner.Transaction
  import Bitwise, only: [band: 2]
  @bytes 1_048_576
  @metadata_bytes 4096
  @projects 256
  @bindings 1024
  @held {__MODULE__, :lock_held}
  @error {:error, :project_identity_unavailable}

  @doc "Reject same-process reentry or identity acquisition below a project lock."
  def assert_order do
    if Process.get(@held, false) != false or
         Process.get({Ipse.Extension.Consent, :lock_held}, false) != false or
         Process.get({Ipse.Extension.Collection, :lock_held}, false) != false,
       do: {:error, :project_identity_lock_order},
       else: :ok
  end

  @doc "Inspect canonical candidate facts without creating a project or worktree binding."
  def preview(home, cwd) do
    transaction(home, cwd, fn context, state ->
      with {:ok, root} <- directory(cwd, context.uid),
           :ok <- preview_binding(context, state, root),
           {:ok, facts} <- candidate(context, state, root) do
        {:read, facts}
      end
    end)
  end

  @doc "Explicitly admit a fresh primary repository or this folder only."
  def admit(home, cwd, scope) when scope in [:repository, :folder] do
    transaction(home, cwd, fn context, state ->
      with {:ok, root} <- directory(cwd, context.uid) do
        case state["bindings"][key(root["path"])] do
          nil ->
            create(context, state, root, scope)

          existing ->
            project = state["projects"][existing["project_id"]]

            if project["scope"] == Atom.to_string(scope) do
              with :ok <- revalidate(context, project, existing),
                   do: {:read, view(project, existing)}
            else
              {:error, :project_identity_conflict}
            end
        end
      end
    end)
  end

  def admit(_, _, _), do: {:error, :invalid_project_identity_scope}

  @doc "Resolve and revalidate an admitted root, or admit a reciprocal linked worktree."
  def resolve(home, cwd) do
    transaction(home, cwd, fn context, state -> resolve_locked(context, state, cwd) end)
  end

  @doc "Revalidate the exact returned binding under the index lock before a short host callback."
  def with_binding(home, cwd, binding, fun) when is_function(fun, 1) do
    transaction(home, cwd, fn context, state ->
      with {:read, actual} <- resolve_locked(context, state, cwd),
           true <- actual === binding do
        {:callback, fn -> fun.(actual) end}
      else
        _ -> {:error, :stale_project_identity}
      end
    end)
  end

  def with_binding(_, _, _, _), do: {:error, :invalid_project_identity_callback}

  defp transaction(home, cwd, fun) do
    with :ok <- assert_order(),
         true <-
           path?(home) and Path.type(home) == :absolute and path?(cwd) and
             Path.type(cwd) == :absolute do
      Ipse.Session.Resources.file_effect(fn -> locked(home, cwd, fun) end)
    else
      {:error, _} = error -> error
      _ -> @error
    end
  end

  defp locked(home, cwd, fun) do
    with {:ok, uid} <- Ipse.Runner.protected_current_uid(),
         {:ok, home} <- private_home(home, uid),
         false <- overlap?(home, Path.expand(cwd)),
         root = Path.join(home, "project-identities"),
         :ok <- create_private(root, uid),
         :ok <- safe_lock(Path.join(root, ".lock"), uid),
         {:ok, lock} <- Transaction.acquire(Path.join(root, ".lock"), cwd: cwd) do
      Process.put(@held, true)

      released(lock, fn ->
        context = %{root: root, uid: uid, cwd: cwd}

        with :ok <- safe_lock(Path.join(root, ".lock"), uid),
             {:error, :enoent} <- File.lstat(Path.join(root, ".metadata-active")),
             :ok <- reclaim_pending(root, lock),
             :ok <- Transaction.quota(lock, :flat, 4 * 1024 * 1024),
             {:ok, state} <- read(root, uid) do
          case fun.(context, state) do
            {:read, value} ->
              with :ok <- lease(lock, :before), do: {:ok, value}

            {:write, next, value, project, binding} ->
              with :ok <- lease(lock, :before),
                   :ok <- revalidate(context, project, binding),
                   :ok <- write(root, next, lock) do
                with :ok <- lease(lock, :after),
                     :ok <- revalidate(context, project, binding),
                     :ok <- lease(lock, :after),
                     do: {:ok, value},
                     else: (_ -> {:unknown, :project_identity_admission_unconfirmed})
              end

            {:callback, callback} ->
              with :ok <- lease(lock, :before) do
                result =
                  try do
                    callback.()
                  catch
                    _, _ -> {:unknown, :project_identity_callback_unconfirmed}
                  end

                with :ok <- lease(lock, :after), do: result
              end

            other ->
              other
          end
        else
          {:ok, _} ->
            {:error, :project_metadata_unconfirmed}

          {:error, :transaction_capacity} ->
            {:error, :project_identity_capacity}

          {:error, :transaction_filesystem_unsupported} ->
            {:error, :project_identity_filesystem_unsupported}

          _ ->
            @error
        end
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp released(lock, fun) do
    result =
      try do
        fun.()
      rescue
        _ -> @error
      catch
        _, _ -> {:unknown, :project_identity_callback_unconfirmed}
      after
        Process.delete(@held)
      end

    case Transaction.release(lock) do
      :ok -> result
      _ -> {:unknown, :project_identity_lock_lost}
    end
  end

  defp reclaim_pending(root, lock) do
    with {:ok, names} <- File.ls(root),
         true <- length(names) <= 70 do
      pending = Enum.filter(names, &Regex.match?(~r/\A\.pending-[0-9a-f]{32}\z/, &1))

      cond do
        pending == [] -> :ok
        length(pending) <= 64 -> Transaction.reclaim(lock, ".", pending)
        true -> @error
      end
    else
      _ -> @error
    end
  end

  defp create(context, state, root, scope) do
    common =
      case scope do
        :folder -> {:ok, nil}
        :repository -> directory(Path.join(root["path"], ".git"), context.uid)
      end

    with {:ok, common} <- common,
         :ok <- primary_layout(common),
         true <-
           map_size(state["projects"]) < @projects and map_size(state["bindings"]) < @bindings do
      project = %{
        "id" => id(),
        "scope" => Atom.to_string(scope),
        "primary" => root,
        "common" => common
      }

      binding = %{
        "project_id" => project["id"],
        "worktree_id" => id(),
        "role" => Atom.to_string(if(scope == :folder, do: :folder, else: :primary)),
        "root" => root,
        "registration" => nil,
        "admin" => nil,
        "metadata" => []
      }

      next =
        state
        |> put_in(["projects", project["id"]], project)
        |> put_in(["bindings", key(root["path"])], binding)

      {:write, advance(next), view(project, binding), project, binding}
    else
      false -> {:error, :project_identity_capacity}
      _ -> {:error, :primary_root_setup_required}
    end
  end

  defp resolve_locked(context, state, cwd) do
    with {:ok, root} <- directory(cwd, context.uid) do
      case state["bindings"][key(root["path"])] do
        nil ->
          join(context, state, root)

        binding ->
          project = state["projects"][binding["project_id"]]
          with :ok <- revalidate(context, project, binding), do: {:read, view(project, binding)}
      end
    end
  end

  defp candidate(context, state, root) do
    path = Path.join(root["path"], ".git")

    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        with {:ok, common} <- directory(path, context.uid),
             do:
               {:ok,
                %{
                  "kind" => "primary_repository",
                  "root" => root["path"],
                  "common_directory" => common["path"],
                  "admitted" => Map.has_key?(state["bindings"], key(root["path"]))
                }}

      {:ok, %{type: :regular}} ->
        with {:ok, text, _} <- metadata(context, path),
             {:ok, admin} <- git_pointer(text, root["path"], "gitdir: ") do
          {:ok,
           %{
             "kind" => "linked_candidate",
             "root" => root["path"],
             "admin_candidate" => admin,
             "admitted" => Map.has_key?(state["bindings"], key(root["path"]))
           }}
        end

      {:error, :enoent} ->
        {:ok,
         %{
           "kind" => "folder",
           "root" => root["path"],
           "admitted" => Map.has_key?(state["bindings"], key(root["path"]))
         }}

      _ ->
        {:error, :unsafe_project_metadata}
    end
  end

  defp preview_binding(context, state, root) do
    case state["bindings"][key(root["path"])] do
      nil -> :ok
      binding -> revalidate(context, state["projects"][binding["project_id"]], binding)
    end
  end

  defp join(context, state, root) do
    with false <- Enum.any?(state["bindings"], fn {_, b} -> same_directory?(b["root"], root) end),
         {:ok, text, git} <- metadata(context, Path.join(root["path"], ".git")),
         {:ok, admin_path} <- git_pointer(text, root["path"], "gitdir: "),
         {_, project} when is_map(project) <-
           Enum.find(state["projects"], fn {_, p} ->
             p["scope"] == "repository" and
               Path.dirname(Path.dirname(admin_path)) == p["common"]["path"] and
               Path.basename(Path.dirname(admin_path)) == "worktrees"
           end),
         {:ok, binding} <- linked(context, project, root, admin_path, git),
         false <-
           Enum.any?(state["bindings"], fn {_, b} ->
             b["role"] == "linked" and same_directory?(b["admin"], binding["admin"])
           end),
         true <- map_size(state["bindings"]) < @bindings do
      next = put_in(state["bindings"][key(root["path"])], binding) |> advance()
      {:write, next, view(project, binding), project, binding}
    else
      true -> {:error, :project_identity_move_requires_join}
      false -> {:error, :project_identity_capacity}
      _ -> {:error, :project_identity_not_admitted}
    end
  end

  defp linked(context, project, root, admin_path, git) do
    with :ok <- primary(context, project),
         false <- overlap?(root["path"], project["common"]["path"]),
         {:ok, worktrees} <-
           directory(Path.join(project["common"]["path"], "worktrees"), context.uid),
         true <- Path.dirname(admin_path) == worktrees["path"],
         {:ok, admin} <- directory(admin_path, context.uid),
         {:ok, common_text, common} <- metadata(context, Path.join(admin_path, "commondir")),
         {:ok, common_path} <- git_pointer(common_text, admin_path, ""),
         true <- common_path == project["common"]["path"],
         {:ok, back_text, backlink} <- metadata(context, Path.join(admin_path, "gitdir")),
         {:ok, back_path} <- git_pointer(back_text, admin_path, ""),
         true <- back_path == Path.join(root["path"], ".git") do
      {:ok,
       %{
         "project_id" => project["id"],
         "worktree_id" => id(),
         "role" => "linked",
         "root" => root,
         "registration" => worktrees,
         "admin" => admin,
         "metadata" => [git, common, backlink]
       }}
    else
      _ -> {:error, :unsafe_project_metadata}
    end
  end

  defp revalidate(context, project, binding) do
    with :ok <- primary(context, project),
         {:ok, root} <- directory(binding["root"]["path"], context.uid),
         true <- root === binding["root"] do
      if binding["role"] == "linked" do
        with [git, _, _] <- binding["metadata"],
             {:ok, text, actual} <- metadata(context, git["path"]),
             {:ok, admin} <- git_pointer(text, root["path"], "gitdir: "),
             {:ok, fresh} <- linked(context, project, root, admin, actual),
             true <- Map.drop(fresh, ["worktree_id"]) === Map.drop(binding, ["worktree_id"]),
             do: :ok,
             else: (_ -> {:error, :stale_project_identity})
      else
        :ok
      end
    else
      _ -> {:error, :stale_project_identity}
    end
  end

  defp primary(context, project) do
    with {:ok, root} <- directory(project["primary"]["path"], context.uid),
         true <- root === project["primary"] do
      if project["scope"] == "repository" do
        with {:ok, common} <- directory(Path.join(root["path"], ".git"), context.uid),
             true <- common === project["common"],
             :ok <- primary_layout(common),
             do: :ok,
             else: (_ -> {:error, :stale_project_identity})
      else
        :ok
      end
    else
      _ -> {:error, :stale_project_identity}
    end
  end

  defp view(project, binding),
    do: %{
      "version" => 1,
      "project_id" => project["id"],
      "worktree_id" => binding["worktree_id"],
      "scope" => project["scope"],
      "root" => binding["root"]["path"],
      "primary_root" => project["primary"]["path"],
      "common_directory" => if(project["common"], do: project["common"]["path"], else: nil),
      "binding_sha256" => JSON.digest([project, binding])
    }

  defp primary_layout(nil), do: :ok

  defp primary_layout(common) do
    # An outward common-directory override is a different layout, even when
    # `.git` itself happens to be a directory. It cannot inherit this subset.
    case File.lstat(Path.join(common["path"], "commondir")) do
      {:error, :enoent} -> :ok
      _ -> {:error, :primary_root_setup_required}
    end
  end

  defp git_pointer(text, base, prefix) do
    text =
      case String.split(text, "\n") do
        [line] -> line
        [line, ""] -> line
        _ -> ""
      end

    with true <- String.valid?(text) and String.starts_with?(text, prefix),
         value = String.replace_prefix(text, prefix, ""),
         true <- path?(value),
         {:ok, path} <- pointer_path(value, base),
         {:ok, ^path} <- Ipse.Workspace.canonical_path(path),
         do: {:ok, path},
         else: (_ -> {:error, :unsafe_project_metadata})
  end

  defp pointer_path(value, base) do
    raw = if Path.type(value) == :absolute, do: value, else: Path.join(base, value)
    parts = Path.split(raw)

    if length(parts) > 128 do
      {:error, :unsafe_project_metadata}
    else
      parts
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, ""}, fn {part, index}, {:ok, current} ->
        cond do
          part == "/" ->
            {:cont, {:ok, "/"}}

          part == "." ->
            {:cont, {:ok, current}}

          part == ".." ->
            {:cont, {:ok, Path.dirname(current)}}

          true ->
            next = Path.join(current, part)

            case File.lstat(next) do
              {:ok, %{type: type}} when type in [:directory, :regular] ->
                if index == length(parts) - 1 or type == :directory,
                  do: {:cont, {:ok, next}},
                  else: {:halt, {:error, :unsafe_project_metadata}}

              _ ->
                {:halt, {:error, :unsafe_project_metadata}}
            end
        end
      end)
    end
  end

  defp directory(path, uid) do
    with true <- path?(path) and Path.type(path) == :absolute and Path.expand(path) == path,
         {:ok, ^path} <- Ipse.Workspace.canonical_path(path),
         :ok <- ancestors(path, uid),
         {:ok, %{type: :directory, uid: ^uid} = stat} <- File.lstat(path),
         true <- band(stat.mode, 0o022) == 0 do
      {:ok,
       %{
         "path" => path,
         "device" => Integer.to_string(stat.major_device),
         "inode" => Integer.to_string(stat.inode),
         "uid" => uid,
         "mode" => stat.mode
       }}
    else
      _ -> {:error, :unsafe_project_path}
    end
  end

  defp private_home(path, uid) do
    with {:ok, directory} <- directory(path, uid),
         true <- band(directory["mode"], 0o077) == 0,
         do: {:ok, directory["path"]},
         else: (_ -> @error)
  end

  defp create_private(path, uid) do
    case File.mkdir(path) do
      :ok ->
        with :ok <- File.chmod(path, 0o700),
             do: Ipse.Runner.protected_sync_directory(Path.dirname(path))

      {:error, :eexist} ->
        :ok

      _ ->
        @error
    end
    |> case do
      :ok ->
        case private_home(path, uid) do
          {:ok, _} -> :ok
          _ -> @error
        end

      _ ->
        @error
    end
  end

  defp ancestors(path, uid) do
    root_uid = File.lstat!("/").uid

    Enum.reduce_while(Path.split(path), "", fn part, parent ->
      current = if parent == "", do: part, else: Path.join(parent, part)

      case File.lstat(current) do
        {:ok, %{type: :directory, uid: owner, mode: mode}} when owner in [0, root_uid, uid] ->
          if band(mode, 0o022) == 0 or (owner in [0, root_uid] and band(mode, 0o1000) != 0),
            do: {:cont, current},
            else: {:halt, :unsafe}

        _ ->
          {:halt, :unsafe}
      end
    end)
    |> case do
      ^path -> :ok
      _ -> @error
    end
  end

  defp safe_lock(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, stat} -> if safe_file?(stat, uid) and stat.size == 0, do: :ok, else: @error
      _ -> @error
    end
  end

  defp safe_file?(stat, uid),
    do:
      stat.type == :regular and stat.uid == uid and stat.links == 1 and
        band(stat.mode, 0o7777) == 0o600

  defp read(root, uid) do
    path = Path.join(root, "index.json")

    case File.lstat(path) do
      {:error, :enoent} ->
        {:ok, %{"version" => 1, "revision" => 0, "projects" => %{}, "bindings" => %{}}}

      {:ok, stat} ->
        with true <- safe_file?(stat, uid) and stat.size <= @bytes,
             {:ok, bytes} <- File.open(path, [:read, :binary], &IO.binread(&1, @bytes + 1)),
             {:ok, state} <- JSON.decode_bounded(bytes, @bytes),
             true <- valid_state?(state),
             do: {:ok, state},
             else: (_ -> @error)

      _ ->
        @error
    end
  end

  defp write(_root, state, lock) do
    with true <- valid_state?(state),
         {:ok, bytes} <- Jason.encode(state),
         true <- byte_size(bytes) <= @bytes,
         {:ok, ^state} <- JSON.decode_bounded(bytes, @bytes) do
      pending = ".pending-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      with :ok <- lease(lock, :before),
           :ok <- Transaction.preflight(lock, [byte_size(bytes)]),
           :ok <- Transaction.stage(lock, ".", [{pending, bytes}]),
           :ok <- Transaction.switch(lock, pending, "index.json"),
           :ok <- lease(lock, :after) do
        :ok
      else
        {:error, :transaction_capacity} ->
          {:error, :project_identity_capacity}

        {:error, :transaction_filesystem_unsupported} ->
          {:error, :project_identity_filesystem_unsupported}

        {:error, :project_identity_lock_lost} = result ->
          result

        {:unknown, :project_identity_lock_lost} = result ->
          result

        _ ->
          {:unknown, :project_identity_write_unconfirmed}
      end
    else
      _ -> {:error, :project_identity_capacity}
    end
  end

  defp lease(cap, phase) do
    if Transaction.check(cap) == :ok,
      do: :ok,
      else:
        if(phase == :after,
          do: {:unknown, :project_identity_lock_lost},
          else: {:error, :project_identity_lock_lost}
        )
  end

  defp advance(state), do: %{state | "revision" => state["revision"] + 1}

  defp metadata(context, path),
    do: Ipse.Extension.ProjectIdentity.Metadata.read(context, path, @metadata_bytes)

  defp valid_state?(state) do
    keys?(state, ~w(version revision projects bindings)) and state["version"] === 1 and
      JSON.safe_uint?(state["revision"]) and
      is_map(state["projects"]) and map_size(state["projects"]) <= @projects and
      is_map(state["bindings"]) and map_size(state["bindings"]) <= @bindings and
      Enum.all?(state["projects"], fn {id, p} ->
        JSON.sha256?(id) and project?(p) and p["id"] == id
      end) and
      Enum.all?(state["bindings"], fn {id, b} ->
        binding?(b) and id == key(b["root"]["path"]) and
          Map.has_key?(state["projects"], b["project_id"]) and
          binding_project?(b, state["projects"][b["project_id"]])
      end) and
      length(Enum.uniq_by(Map.values(state["bindings"]), & &1["worktree_id"])) ==
        map_size(state["bindings"]) and
      Enum.all?(state["projects"], fn {id, p} ->
        case state["bindings"][key(p["primary"]["path"])] do
          %{"project_id" => ^id, "role" => role} when role in ~w(primary folder) -> true
          _ -> false
        end
      end)
  rescue
    _ -> false
  end

  defp project?(p),
    do:
      keys?(p, ~w(id scope primary common)) and JSON.sha256?(p["id"]) and
        p["scope"] in ~w(folder repository) and directory?(p["primary"]) and
        if(p["scope"] == "folder",
          do: p["common"] == nil,
          else:
            directory?(p["common"]) and
              p["common"]["path"] == Path.join(p["primary"]["path"], ".git")
        )

  defp binding?(b),
    do:
      keys?(b, ~w(project_id worktree_id role root registration admin metadata)) and
        JSON.sha256?(b["project_id"]) and
        JSON.sha256?(b["worktree_id"]) and b["role"] in ~w(folder primary linked) and
        directory?(b["root"]) and is_list(b["metadata"]) and
        if(b["role"] == "linked",
          do:
            directory?(b["registration"]) and directory?(b["admin"]) and
              length(b["metadata"]) == 3 and
              Enum.all?(b["metadata"], &Ipse.Extension.ProjectIdentity.Metadata.valid?/1),
          else: b["registration"] == nil and b["admin"] == nil and b["metadata"] == []
        )

  defp binding_project?(b, p),
    do:
      if(b["role"] == "linked",
        do:
          p["scope"] == "repository" and
            b["registration"]["path"] == Path.join(p["common"]["path"], "worktrees") and
            Path.dirname(b["admin"]["path"]) == b["registration"]["path"] and
            not overlap?(b["root"]["path"], p["common"]["path"]) and
            Enum.map(b["metadata"], & &1["path"]) == [
              Path.join(b["root"]["path"], ".git"),
              Path.join(b["admin"]["path"], "commondir"),
              Path.join(b["admin"]["path"], "gitdir")
            ],
        else:
          b["root"] === p["primary"] and
            b["role"] == if(p["scope"] == "folder", do: "folder", else: "primary")
      )

  defp directory?(d),
    do:
      keys?(d, ~w(path device inode uid mode)) and path?(d["path"]) and
        Path.expand(d["path"]) == d["path"] and
        digits?(d["device"]) and digits?(d["inode"]) and JSON.safe_uint?(d["uid"]) and
        JSON.safe_uint?(d["mode"])

  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp digits?(v), do: is_binary(v) and byte_size(v) in 1..20 and Regex.match?(~r/\A[0-9]+\z/, v)

  defp path?(p),
    do:
      is_binary(p) and String.valid?(p) and byte_size(p) in 1..4096 and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, p)

  defp overlap?(a, b),
    do:
      a == b or String.starts_with?(a, String.trim_trailing(b, "/") <> "/") or
        String.starts_with?(b, String.trim_trailing(a, "/") <> "/")

  defp key(path), do: JSON.sha256(path)
  defp same_directory?(a, b), do: a["inode"] == b["inode"] and a["device"] == b["device"]
  defp id, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
end

defmodule Ipse.Extension.ProjectIdentity.Metadata do
  @moduledoc false
  alias Ipse.JSON
  import Bitwise, only: [band: 2]
  @error {:error, :unsafe_project_metadata}
  @source_keys ~w(device inode bytes mode nlink mtime_seconds mtime_nanoseconds ctime_seconds ctime_nanoseconds)

  # OTP's public file.open interface has no NOFOLLOW/NONBLOCK flags. The existing
  # native bounded regular-file copy retains its source FD and checks identity
  # through EOF. Never open an untrusted workspace pathname with OTP instead.
  def read(context, path, limit) do
    with true <- is_binary(path) and Path.expand(path) == path,
         {:ok, ^path} <- Ipse.Workspace.canonical_path(path),
         {:ok, before} <- File.lstat(path, time: :posix),
         true <- safe_source?(before, context.uid, limit),
         {:ok, helper} <- Ipse.Runner.protected_helper(context.cwd),
         :ok <- protected_helper(helper, context.uid),
         active = Path.join(context.root, ".metadata-active"),
         :ok <- File.mkdir(active),
         :ok <- File.chmod(active, 0o700) do
      identity = File.lstat!(active)
      target = Path.join(active, "value")

      try do
        port =
          Port.open(
            {:spawn_executable, String.to_charlist(helper)},
            [
              :binary,
              :exit_status,
              :use_stdio,
              :hide,
              args: ["--copy-regular", path, target, Integer.to_string(before.size)]
            ]
          )

        {result, confirmed?} = await(port, "", System.monotonic_time(:millisecond) + 3000)
        if Port.info(port), do: Port.close(port)

        decoded =
          case result do
            {:ok, output} -> decode(output, path, target, before, context.uid, limit)
            error -> error
          end

        if confirmed?, do: cleanup(active, target, identity, context.uid, limit)
        decoded
      rescue
        _ -> {:error, :project_metadata_unconfirmed}
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp await(port, output, deadline) do
    receive do
      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= 2048 ->
        await(port, output <> data, deadline)

      {^port, {:exit_status, status}} ->
        {if(status == 0, do: {:ok, output}, else: @error), true}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {{:error, :project_metadata_unconfirmed}, false}
    end
  end

  defp decode(output, path, target, before, uid, limit) do
    with {:ok, receipt} <- JSON.decode_bounded(output, 2048),
         true <- keys?(receipt, ~w(version bytes source destination)) and receipt["version"] === 1,
         source = receipt["source"],
         destination = receipt["destination"],
         true <- source?(source) and source?(destination) and matches?(source, before),
         true <- receipt["bytes"] === before.size,
         {:ok, after_stat} <- File.lstat(path, time: :posix),
         true <- safe_source?(after_stat, uid, limit) and matches?(source, after_stat),
         {:ok, target_stat} <- File.lstat(target, time: :posix),
         true <-
           safe_source?(target_stat, uid, limit) and band(target_stat.mode, 0o777) == 0o600 and
             matches?(destination, target_stat),
         {:ok, bytes} <- File.open(target, [:read, :binary], &IO.binread(&1, limit + 1)),
         true <- is_binary(bytes) and byte_size(bytes) == before.size do
      witness = %{
        "path" => path,
        "uid" => uid,
        "source" => source,
        "sha256" => JSON.sha256(bytes)
      }

      {:ok, bytes, witness}
    else
      _ -> @error
    end
  end

  def valid?(w),
    do:
      keys?(w, ~w(path uid source sha256)) and is_binary(w["path"]) and
        String.valid?(w["path"]) and byte_size(w["path"]) in 1..4096 and
        Path.expand(w["path"]) == w["path"] and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, w["path"]) and JSON.safe_uint?(w["uid"]) and
        JSON.sha256?(w["sha256"]) and source?(w["source"])

  defp source?(s),
    do:
      keys?(s, @source_keys) and digits?(s["device"]) and digits?(s["inode"]) and
        s["nlink"] == "1" and is_integer(s["bytes"]) and s["bytes"] in 1..4096 and
        JSON.safe_uint?(s["mode"]) and
        signed?(s["mtime_seconds"]) and signed?(s["ctime_seconds"]) and
        is_integer(s["mtime_nanoseconds"]) and s["mtime_nanoseconds"] in 0..999_999_999 and
        is_integer(s["ctime_nanoseconds"]) and s["ctime_nanoseconds"] in 0..999_999_999

  defp matches?(s, stat),
    do:
      s["device"] == Integer.to_string(stat.major_device) and
        s["inode"] == Integer.to_string(stat.inode) and
        s["bytes"] == stat.size and s["mode"] == stat.mode and
        s["nlink"] == Integer.to_string(stat.links) and
        s["mtime_seconds"] == Integer.to_string(stat.mtime) and
        s["ctime_seconds"] == Integer.to_string(stat.ctime)

  defp safe_source?(stat, uid, limit),
    do:
      stat.type == :regular and stat.uid == uid and stat.links == 1 and
        stat.size in 1..limit and band(stat.mode, 0o022) == 0

  defp protected_helper(path, uid) do
    root_uid = File.lstat!("/").uid

    directories =
      Enum.reduce_while(Path.split(Path.dirname(path)), "", fn part, parent ->
        current = if parent == "", do: part, else: Path.join(parent, part)

        case File.lstat(current) do
          {:ok, %{type: :directory, uid: owner, mode: mode}} when owner in [0, root_uid, uid] ->
            if band(mode, 0o022) == 0 or (owner in [0, root_uid] and band(mode, 0o1000) != 0),
              do: {:cont, current},
              else: {:halt, :unsafe}

          _ ->
            {:halt, :unsafe}
        end
      end)

    if directories == Path.dirname(path), do: :ok, else: @error
  end

  defp cleanup(active, target, identity, uid, limit) do
    with {:ok, current} <- File.lstat(active), true <- same?(identity, current) do
      case File.lstat(target) do
        {:ok, %{type: :regular, uid: ^uid, links: 1, size: size}} when size <= limit ->
          File.rm(target)

        {:error, :enoent} ->
          :ok

        _ ->
          :unsafe
      end

      File.rmdir(active)
    end
  end

  defp same?(a, b),
    do:
      a.type == :directory and b.type == :directory and a.uid == b.uid and a.inode == b.inode and
        a.major_device == b.major_device

  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp digits?(s), do: is_binary(s) and byte_size(s) in 1..20 and Regex.match?(~r/\A[0-9]+\z/, s)

  defp signed?(s),
    do: is_binary(s) and byte_size(s) in 1..21 and Regex.match?(~r/\A-?[0-9]+\z/, s)
end
