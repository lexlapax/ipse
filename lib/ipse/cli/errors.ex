defmodule Ipse.CLI.Errors do
  @moduledoc "Operator error text and recovery routes, without inspecting arbitrary terms."

  @manual "docs/operator/recovery.md"
  @messages %{
    native_review_publication_fence_unavailable:
      {"Reviewed note mutation is temporarily unavailable: a live Review permit cannot fence the final rename before its expiry. No review or mutation was started. Keep existing records and inspect older uncertain operations; --yes cannot bypass this gate.",
       "inspect-unconfirmed-protected-knowledge"},
    state_deadline_fence_unavailable:
      {"Deadline-bearing State writes are temporarily unavailable: the clock check and rename are separate operations. No write was started. Keep existing drafts and inspect earlier uncertain writes; do not remove the deadline to retry.",
       "diagnose-startup-and-service-errors"},
    collection_deadline_fence_unavailable:
      {"Protected collection publication is temporarily unavailable for this request shape. No publication was started. Use the supported native knowledge commands, keep existing records and inspect saved receipts; --yes cannot bypass this gate.",
       "inspect-unconfirmed-protected-knowledge"},
    journal_capacity_insufficient:
      {"This Session's journal cannot hold another worst-case document Collection invocation. No extension callback or host call was started. Close this Session and repeat the command with the same Job continuation in a new Session; do not edit the continuation.",
       "recover-a-corpus-query-or-document-operation"},
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
    header_unconfirmed:
      {"Fresh session header publication is unconfirmed. Preserve pending files and any published journal; inspect the original state before explicit resume after its lock is free. Do not automatically retry startup or delete its lock files.",
       "respect-active-ownership"},
    session_lock_identity_unavailable:
      {"The saved Session lock identity could not be verified. No saved work was replayed. Preserve the original journal and lock file, and request developer-assisted inspection with the matching native helper.",
       "respect-active-ownership"},
    journal_lock_owner_required:
      {"This journal requires its qualified native lock owner for changes. Preserve the original journal and lock file; do not modify it through an inactive or legacy writer.",
       "respect-active-ownership"},
    journal_unavailable:
      {"Journal storage is unavailable. An append may already have reached disk; inspect the original journal and effects before retrying.",
       "respect-active-ownership"},
    journal_origin_unavailable:
      {"Saved journal does not match its original location or file identity. No saved work was replayed; preserve it and use the original state directory or a reviewed fresh-session handoff.",
       "find-the-original-session"},
    workspace_not_found:
      {"Workspace directory does not exist or cannot be read. No task was started; pass --cwd with an existing readable directory and inspect ipse config.",
       "diagnose-startup-and-service-errors"},
    workspace_path_unavailable:
      {"Workspace path cannot be resolved. Check directory access and symbolic links, then retry with a readable --cwd.",
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
    # Producers own fixed causes and effect-state guidance. Slash commands,
    # endpoint paths and service names are ordinary prose, not term dumps.
    if String.valid?(reason) and byte_size(reason) <= 2048 and
         not Regex.match?(
           ~r/[\x00-\x1f\x7f]|%\{|#(?:PID|Port|Reference)<|\{:[a-z_]|(?:\A|\s):[a-z][a-z0-9_]*/u,
           reason
         ) do
      %{text: reason, recovery: @manual <> "#diagnose-startup-and-service-errors"}
    else
      message(:unexpected_diagnostic)
    end
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
    do: module |> Module.split() |> List.last() |> safe_code()

  defp code(reason) when is_atom(reason), do: reason |> Atom.to_string() |> safe_code()
  defp code(_), do: "unknown"

  defp safe_code(value) do
    if Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_]{0,63}\z/, value), do: value, else: "unknown"
  end
end
