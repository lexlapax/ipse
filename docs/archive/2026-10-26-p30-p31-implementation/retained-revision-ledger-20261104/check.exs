ExUnit.start(autorun: false)
Code.require_file("/home/lexlapax/projects/lexlapax/ipse/_build/verification/ipse-retained-read-final-20261104-01/read_assertions.exs")

defmodule RetainedRevisionReadOnly do
  import ExUnit.Assertions
  @root "/dev/shm/ipse-native-seed-recall-d739-20261103-01"
  @external "/dev/shm/ipse-recall-seed-populated-d739-20261103-01"
  @out __DIR__
  @helper "/home/lexlapax/projects/lexlapax/ipse/_build/verification/ipse-retained-read-final-20261104-01/read_assertions.exs"
  def hash(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  def read(path), do: path |> File.read!() |> Jason.decode!()
  def fingerprint!(ref) do
    assert String.starts_with?(ref["path"], @root <> "/")
    bytes = File.read!(ref["path"])
    assert byte_size(bytes) == ref["bytes"] and hash(bytes) == ref["sha256"]
  end
  def inventory(path) do
    st = File.lstat!(path, time: :posix)
    facts = %{type: st.type, inode: st.inode, mode: st.mode, uid: st.uid, gid: st.gid, size: st.size, mtime: st.mtime, ctime: st.ctime}
    case st.type do
      :regular -> %{path => Map.put(facts, :sha256, hash(File.read!(path)))}
      :directory ->
        File.ls!(path) |> Enum.sort() |> Enum.reduce(%{path => facts}, fn name, acc -> Map.merge(acc, inventory(Path.join(path, name))) end)
      _ -> raise "unexpected retained object type"
    end
  end
  def save(name, value), do: File.write!(Path.join(@out, name), Jason.encode!(value, pretty: true), [:exclusive])
  def main do
    assert hash(File.read!(@helper)) == "288fba318d2a3da84d8a24f2006e66519a9aa09aaaf23d9e60b2ab7c1b20df03"
    before = Map.merge(inventory(@root), inventory(@external))
    save("originals-before.json", before)
    result = try do
      manifest = read(Path.join(@root, "manifest.json"))
      for ref <- manifest["files"], do: fingerprint!(ref)
      reports = for index <- 1..length(manifest["plan"]) do
        closed = read(Path.join(@root, "checkpoints/closed-#{index}.json"))
        assert closed["index"] == index and closed["exit_code"] == 0
        fingerprint!(closed["report"])
        report = read(closed["report"]["path"])
        assert report["index"] == index and report["closed"] == true
        report
      end
      refs = reports |> Enum.flat_map(& &1["sources"]) |> Enum.filter(fn ref ->
        Path.dirname(ref["path"]) in [Path.join(@root, "home/sessions"), Path.join(@root, "home/knowledge-management")] and String.ends_with?(ref["path"], ".jsonl")
      end) |> Enum.uniq_by(& &1["path"])
      journals = Enum.map(refs, fn ref ->
        fingerprint!(ref)
        {:ok, events} = Ipse.Journal.load(Path.dirname(ref["path"]), Path.basename(ref["path"], ".jsonl"))
        events
      end)
      revisions = Ipse.Development.RetainedReadAssertions.publication_revisions!(journals)
      assert map_size(revisions) == 2000
      %{status: "pass", journal_count: length(journals), publication_revision_count: map_size(revisions), app_started: false, session_started: false, native_called: false, recall_qualified: false}
    rescue
      error -> %{status: "fail", error_class: inspect(error.__struct__), recall_qualified: false}
    end
    after_inventory = Map.merge(inventory(@root), inventory(@external))
    save("originals-after.json", after_inventory)
    unchanged = before === after_inventory
    result = Map.merge(result, %{original_object_count: map_size(before), originals_pre_post_identical: unchanged, helper_post_identical: hash(File.read!(@helper)) == "288fba318d2a3da84d8a24f2006e66519a9aa09aaaf23d9e60b2ab7c1b20df03"})
    save("result.json", result)
    IO.puts(Jason.encode!(result))
    if result.status != "pass" or not unchanged or not result.helper_post_identical, do: System.halt(1)
  end
end
RetainedRevisionReadOnly.main()
