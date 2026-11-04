IO.stream(:stdio, :line)
|> Enum.each(fn line ->
  cond do
    Regex.match?(~r<\ANATIVE_RECALL_FIXTURE_ROOT=/dev/shm/ipse-json-recall33-cache-qualification-state-20261103-01/fixture-tmp/ipse-native-recall-[0-9a-f]{32}\s*\z>, line) -> IO.write(line)
    Regex.match?(~r<\AResult: [0-9]+(?:/[0-9]+)? passed, [0-9]+ excluded\s*\z>, line) -> IO.write(line)
    Regex.match?(~r<\A\s*[0-9]+\) test >, line) -> IO.puts("SYNTHETIC_FIXTURE_FAILURE=1")
    true -> :ok
  end
end)
