root = Path.expand(".")
for module <- [Ipse.Extension.Collection.DocumentStage, Ipse.Extension.Collection.WorkspaceDocumentGuard, Ipse.Tools] do
  {:module, ^module} = Code.ensure_loaded(module)
  expected = Path.join([root, "_build/test/lib/ipse/ebin", Atom.to_string(module) <> ".beam"])
  true = Path.expand(List.to_string(:code.which(module))) == expected
end
{:ok, _} = Application.ensure_all_started(:ipse)

source = File.read!("lib/ipse/extension/collection/workspace_document_guard.ex")
name = "defmodule Ipse.Extension.Collection.WorkspaceDocumentGuard do"
visibility = "  defp check_documents(context, intent, documents) do"
true = length(String.split(source, name)) == 2
true = length(String.split(source, visibility)) == 2
source = source
  |> String.replace(name, "defmodule Ipse.Test.LegacyGuardSeam do", global: false)
  |> String.replace(visibility, "  def check_documents(context, intent, documents) do", global: false)
Code.compile_string(source)

defmodule Ipse.Test.LegacyOwner do
  use GenServer
  def init(arg), do: {:ok, arg}
  def handle_call({:extension_workspace_document_authorize, _, _, _}, _, state),
    do: {:reply, {:ok, :legacy_workspace}, state}
  def handle_call({:extension_workspace_snapshot_bind, _, _, _, _}, _, state),
    do: {:reply, :ok, state}
end

ExUnit.start(autorun: false, seed: 0)
defmodule Ipse.Test.LegacyGuardSeamTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.{DocumentStage, Profile}

  test "synthetic legacy classification rechecks the original before the common commit" do
    dir = Path.join(System.tmp_dir!(), "ipse-legacy-seam-" <> Usage.id())
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "source.docx")
    original = "synthetic original document bytes"
    replacement = "changed synthetic document bytes"
    File.write!(path, original)
    sha = JSON.sha256(original)
    {:ok, _, %{"byte_count" => count, "sha256" => ^sha}} =
      Ipse.Tools.workspace_binary_snapshot("source.docx", sha, %{cwd: dir})

    File.write!(path, replacement)
    {:ok, owner} = GenServer.start_link(Ipse.Test.LegacyOwner, :fixture)
    token = make_ref()
    reader = spawn(fn ->
      receive do
        {:workspace_snapshot_read, ^token, peer} ->
          result = Ipse.Tools.workspace_binary_snapshot("source.docx", sha, %{cwd: dir})
          send(peer, {:workspace_snapshot_result, token, result})
      end
    end)
    on_exit(fn -> if Process.alive?(reader), do: Process.exit(reader, :kill) end)
    context = %{owner: owner, job_ref: make_ref(), snapshot_intent: %{},
      workspace_snapshot_reader: %{pid: reader, token: token, path: "source.docx", sha: sha}}
    document = %{"path" => "source.docx", "original_sha256" => sha, "original_bytes" => count}
    namespace = JSON.sha256("legacy-seam")
    store = Path.join(dir, "collections")
    binding = %{"project_id" => JSON.sha256("project"), "identity_sha256" => JSON.sha256("identity"),
      "session_id" => Usage.id(), "invocation_id" => Usage.id()}
    {:ok, snapshot} = DocumentStage.execute(store, namespace, %{"op" => "snapshot"}, Usage.id(), binding)
    body = Jason.encode!(%{"kind" => "synthetic"})
    key = "source.fixture.legacy"
    request = %{"op" => "value.put_inline", "key" => key, "generation" => snapshot["generation"],
      "expected_revision" => 0, "data" => body, "byte_count" => byte_size(body), "sha256" => JSON.sha256(body)}
    guard = fn _, _ -> Ipse.Test.LegacyGuardSeam.check_documents(context, %{}, [document]) end
    assert {:error, :document_store_refused} =
      DocumentStage.execute(store, namespace, request, Usage.id(), binding, publication_guard: guard)
    assert {:ok, %{"record" => nil}} =
      Collection.execute_profile(store, namespace, %{"op" => "get", "key" => key}, Usage.id(), Profile.documents())
    assert File.read!(path) == replacement
  end
end
result = ExUnit.run()
if result.total != 1 or result.failures != 0, do: System.halt(1)
