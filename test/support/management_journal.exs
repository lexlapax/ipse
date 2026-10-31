import ExUnit.Assertions
alias Ipse.{JSON, Journal, Runner}
alias Ipse.CLI.Knowledge.Management
alias Ipse.Extension.{Bundles, Consent, ProjectIdentity, SemanticAdmission, SemanticConsent}

[root] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
assert {:ok, :native} = Runner.operator_channel()
old_helper = System.get_env("IPSE_MANAGEMENT_OLD_HELPER_TEST") == "1"

for scenario <-
      if(old_helper,
        do: ["missing_target"],
        else: ~w(missing_target public_directory symlink_directory)
      ) do
  directory = Path.join(root, scenario)
  File.mkdir!(directory)
  File.chmod!(directory, 0o700)
  home = Path.join(directory, "home")
  cwd = Path.join(directory, "project")
  File.mkdir!(home)
  File.chmod!(home, 0o700)
  File.mkdir!(cwd)
  {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
  {:ok, _} = Consent.revoke(SemanticAdmission.control_root(home), binding["project_id"], 0)
  {:ok, _} = Bundles.install("knowledge", home)
  journal_dir = Path.join(home, "knowledge-management")
  outside = Path.join(directory, "outside")

  case scenario do
    "public_directory" ->
      File.mkdir!(journal_dir)
      File.chmod!(journal_dir, 0o755)

    "symlink_directory" ->
      File.mkdir!(outside)
      File.chmod!(outside, 0o700)
      File.ln_s!(outside, journal_dir)

    _ ->
      :ok
  end

  config = %{home: home, headless: false, approval: :ask, approval_origin: :interactive}
  key = "note." <> JSON.sha256("synthetic absent target")
  assert {:error, :knowledge_management_refused} = Management.expire(config, cwd, key)

  case scenario do
    "missing_target" when old_helper ->
      assert Path.wildcard(Path.join(journal_dir, "*.jsonl")) == []

    "missing_target" ->
      [path] = Path.wildcard(Path.join(journal_dir, "*.jsonl"))
      id = Path.basename(path, ".jsonl")
      before = File.read!(path)
      {:ok, [header]} = Journal.load(journal_dir, id)
      metadata = header["metadata"]
      assert metadata["native_journal_layout"] == Journal.native_owner_layout()
      refute Map.has_key?(metadata, "release_receipt_layout")
      assert metadata["kind"] == "knowledge_management"
      {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
      assert metadata["project_id"] == binding["project_id"]
      assert metadata["namespace"] == namespace
      assert :ok = Journal.SourceOrigin.check_path(journal_dir, id, metadata)
      {:ok, operation} = Management.operation(config, cwd, id)
      assert operation["journal_status"] == "unconfirmed"
      assert operation["operation_id"] == nil and operation["replayed"] == false
      assert File.read!(path) == before

      assert {:ok, contender} =
               Runner.protected_resume_lock(Path.join(journal_dir, id <> ".lock"))

      assert :ok = Runner.unlock_export_candidate(contender)

    "public_directory" ->
      assert Bitwise.band(File.stat!(journal_dir).mode, 0o777) == 0o755
      assert File.ls!(journal_dir) == []

    "symlink_directory" ->
      assert File.lstat!(journal_dir).type == :symlink
      assert File.ls!(outside) == []
  end
end

IO.puts(
  if(old_helper,
    do: "MANAGEMENT_JOURNAL_OLD_HELPER_REFUSED",
    else: "MANAGEMENT_JOURNAL_NATIVE_CALLER_PASSED"
  )
)
