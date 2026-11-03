# Keep only the fixture root and fixed ExUnit result lines, never PTY output.
for line <- IO.stream(:stdio, :line) do
  clean = String.trim_trailing(line)
  cond do
    Regex.match?(~r{\ASOURCE_TIMING_FIXTURE_ROOT=/dev/shm/ipse-source-phase-controls-f44-20261103-01/(single|split8)/ipse-native-recall-[a-f0-9]+\z}, clean) -> IO.puts(clean)
    Regex.match?(~r/\A\d+ tests?, \d+ failures?(, \d+ excluded)?\z/, clean) -> IO.puts(clean)
    String.starts_with?(clean, "inconclusive test result:") -> IO.puts("inconclusive test result")
    true -> :ok
  end
end
