proof = "/dev/shm/ipse-json-recall33-20261103-01"
raw = File.read!(proof <> "/fixture-private.log")
line_numbers = Regex.scan(~r/(native_note_recall_many\.exs|native_note_recall_test\.exs):([0-9]{1,5})/, raw) |> Enum.map(fn [_, file, line] -> %{file: file, line: String.to_integer(line)} end) |> Enum.uniq()
exception_classes = Regex.scan(~r/\*\* \(([A-Za-z0-9_.]+)\)/, raw) |> Enum.map(&List.last/1) |> Enum.uniq()
fixed_codes = Regex.scan(~r/:(inference_[a-z_]+|managed_[a-z_]+|collection_[a-z_]+|worker_[a-z_]+|timeout|closed|unknown|error)/, raw) |> Enum.map(&List.last/1) |> Enum.uniq()
IO.puts(inspect(%{fixture_lines: line_numbers, exception_classes: exception_classes, fixed_codes_seen: fixed_codes, listener_closed_marker: String.contains?(raw, "provider_closed=true"), private_log_sha256: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)}, charlists: :as_lists, limit: :infinity))
root = proof <> "/fixture-tmp/ipse-native-recall-d3cb1f500d36011a3c2021bb37f5cfc5"
Code.require_file(proof <> "/inspect-failure.exs")
