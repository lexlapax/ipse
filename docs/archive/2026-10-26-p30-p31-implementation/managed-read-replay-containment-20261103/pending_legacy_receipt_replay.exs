ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{JSON, Journal, Session}

[directory, expectation] = System.argv()
source_id = "0d5df9e52ed1f6b2b124b8b96ba5de73"
consumer_id = "7ef6001d50230563e7b8bd060fc37299"

assert JSON.sha256(File.read!(Path.join(directory, source_id <> ".jsonl"))) ==
         "191c7c0a80145b991c62354499dc972c0e98b7445a12bea3d22dcdb621aa01c8"

assert JSON.sha256(File.read!(Path.join(directory, consumer_id <> ".jsonl"))) ==
         "960df32a20699a760229323d56aa30b0997c6bae79a16e713fe5acdb230fb7e4"

assert {:ok, source} = Journal.load(directory, source_id)
assert {:ok, consumer} = Journal.load(directory, consumer_id)
assert {:ok, _} = Session.Saved.restore(source, source_id)

assert [result] =
         Enum.filter(consumer, fn event ->
           event["type"] == "extension_action_result" and
             get_in(event, ["request", "request", "op"]) == "get" and
             match?("pending." <> _, get_in(event, ["outcome", "value", "record", "key"]))
         end)

assert [proof] = get_in(result, ["outcome", "value", "record", "value", "evidence", "sources"])
assert proof["session_id"] == source_id

assert [receipt] =
         Enum.filter(consumer, fn event ->
           event["type"] == "managed_read_observed" and
             event["operation_id"] == result["operation_id"]
         end)

assert [%{"version" => 3}] = receipt["dependencies"]
assert receipt["result_sha256"] == JSON.digest([result["outcome"]["value"]])

outcome = Session.Saved.restore(consumer, consumer_id)

case expectation do
  "baseline" -> assert {:ok, _} = outcome
  "refused" -> assert {:error, _} = outcome
end

IO.puts(
  "SYNTHETIC_LEGACY_RECEIPT #{expectation} #{if match?({:ok, _}, outcome), do: "accepted", else: "refused"}"
)
