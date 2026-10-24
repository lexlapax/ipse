defmodule Ipse.CLI.Errors do
  @moduledoc "Operator error text and recovery routes, without inspecting arbitrary terms."

  @manual "docs/operator/recovery.md"
  @messages %{
    invalid_handoff:
      {"Invalid handoff: expected one closed version-1 UTF-8 artifact of at most 16 KiB with consistent unknown-effect provenance. No session was started; review the artifact before importing it.",
       "continue-in-a-fresh-session"},
    invalid_handoff_record:
      {"Invalid committed handoff record; refusing recovery. Preserve the original journal for inspection.",
       "continue-in-a-fresh-session"},
    resume_configuration_mismatch:
      {"Saved session configuration differs. Restore its provider, model, endpoint (--base-url), profiles, extensions and MCP configuration. Legacy MCP fingerprints also require a compatible OTP runtime. Otherwise export a handoff or start a fresh session. No saved work was replayed.",
       "resume-compatible-work"},
    journal_limit_reached:
      {"Journal resource limit reached. History was preserved; inspect it and use an explicit fresh-session handoff. Oversized legacy files require bounded source-page inspection.",
       "continue-in-a-fresh-session"},
    invalid_session:
      {"Saved session is malformed or incomplete. No saved work was replayed; preserve the journal and run ipse diagnose --resume SESSION_ID with its original --state-dir.",
       "find-the-original-session"},
    session_not_found:
      {"Saved session was not found. No saved work was replayed; run ipse sessions --json with the original --state-dir and choose a listed ID.",
       "find-the-original-session"},
    invalid_id:
      {"Invalid session ID. No saved work was replayed; choose an ID from ipse sessions --json with the original --state-dir.",
       "find-the-original-session"},
    invalid_journal:
      {"Saved journal is malformed or unreadable. No saved work was replayed; preserve it and run ipse diagnose --resume SESSION_ID with its original --state-dir.",
       "find-the-original-session"},
    incomplete_journal:
      {"Saved journal is incomplete. No saved work was replayed; preserve it and inspect with ipse diagnose --resume SESSION_ID before resuming.",
       "find-the-original-session"},
    session_locked:
      {"Saved session already has an owner. No work was started by this attempt; close the existing owner normally, then retry. Never delete its lock file.",
       "respect-active-ownership"},
    journal_unavailable:
      {"Journal storage is unavailable. An append may already have reached disk; inspect the original journal and effects before retrying.",
       "respect-active-ownership"},
    workspace_not_found:
      {"Workspace directory does not exist or cannot be read. No task was started; pass --cwd with an existing readable directory and inspect ipse config.",
       "diagnose-startup-and-service-errors"},
    invalid_provider_endpoint:
      {"Provider endpoint was refused before dispatch. Inspect ipse config and choose an HTTPS endpoint or explicit HTTP loopback; subscription credentials require the official endpoint.",
       "diagnose-startup-and-service-errors"},
    question_confirmation:
      {"Answer was not submitted. Review the pending question and explicitly confirm the selected answer; no action permission was granted.",
       "resume-compatible-work"},
    invalid_answer:
      {"Answer does not match the pending question. Review the displayed choices and submit a valid answer; no action permission was granted.",
       "resume-compatible-work"}
  }

  def message({:error, reason}), do: message(reason)
  def message({:shutdown, reason}), do: message(reason)
  def message({:failed_to_start_child, _child, reason}), do: message(reason)
  def message({:already_registered, _pid}), do: message(:session_locked)
  def message({:corrupt_journal, _detail}), do: message(:invalid_journal)

  def message("cannot acquire session lock" <> _), do: message(:session_locked)

  def message(reason) when is_binary(reason) do
    %{text: reason, recovery: @manual <> "#diagnose-startup-and-service-errors"}
  end

  def message(reason) do
    case Map.fetch(@messages, reason) do
      {:ok, {text, anchor}} ->
        %{text: text, recovery: @manual <> "#" <> anchor}

      :error ->
        %{
          text:
            "Unexpected error (#{code(reason)}). An effect may have happened; inspect saved receipts before retrying and report the command with secrets removed.",
          recovery: @manual <> "#report-a-reproducible-problem"
        }
    end
  end

  def format(reason) do
    %{text: text, recovery: recovery} = message(reason)
    text <> " See " <> recovery <> "."
  end

  defp code(%{__exception__: true, __struct__: module}) when is_atom(module),
    do: module |> Module.split() |> List.last()

  defp code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp code(_), do: "unknown"
end
