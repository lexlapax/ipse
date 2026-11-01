# Reuse actual publication before the distinct interrupted-compaction control.
Process.put({:managed_supersession_fixture, :followup}, :compaction_diagnostic)
Code.require_file("managed_supersession_session.exs", __DIR__)
