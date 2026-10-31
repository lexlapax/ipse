# Builds a diagnostic-only Journal source. The rendezvous does not change the
# actual file-server request; it lets the fixture suspend that server first.
source = File.read!("lib/ipse/journal.ex")
needle = ":ok <- IO.binwrite(file, encoded <> \"\\n\"),"

replacement = """
:ok <-
               (case Process.whereis(:ipse_header_interposition) do
                 nil -> :ok
                 observer ->
                   send(observer, {:header_before_write, self(), file, path})
                   receive do
                     :header_go -> :ok
                   end
               end),
             :ok <- IO.binwrite(file, encoded <> "\\n"),
"""

unless length(String.split(source, needle)) == 2, do: raise("header write site changed")

File.write!(
  System.fetch_env!("IPSE_HEADER_INSTRUMENT_SOURCE"),
  String.replace(source, needle, replacement)
)
