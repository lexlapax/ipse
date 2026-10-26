defmodule Ipse.Development.Knowledge.Interaction do
  @moduledoc "Nonpublishing P31 interaction model. Operator-channel proof is simulated, never established here."
  @week 7 * 86_400_000

  def new(project, client, now) do
    %{
      project: project,
      client: client,
      now: now,
      current: false,
      selected: false,
      consent: 0,
      active: false,
      candidates: %{},
      draft: nil,
      mode: :ordinary
    }
  end

  def enable(s),
    do:
      {%{s | selected: true, active: true, consent: s.consent + 1},
       "Saved; active in your next new session. This conversation keeps its current settings."}

  def new_session(s, client) do
    candidates = Map.new(s.candidates, fn {id, c} -> {id, %{c | render: nil}} end)
    %{s | current: s.selected and s.active, client: client, draft: nil, candidates: candidates}
  end

  def disable(s),
    do: %{s | selected: false, active: false, current: false, consent: s.consent + 1}

  def advance(s, now) when now >= s.now, do: %{s | now: now}
  def mode(s, mode) when mode in [:ordinary, :planning, :read_only], do: %{s | mode: mode}

  def propose(s, text, origin) do
    with true <- text?(text, 6_144),
         true <- origin in [:assistant, :run_input],
         true <- map_size(s.candidates) < 64 do
      id = nonce()

      c = %{
        id: id,
        project: s.project,
        text: text,
        origin: origin,
        hash: hash(text),
        version: 1,
        expires: s.now + @week,
        status: :pending,
        render: nil
      }

      candidates = Map.put(s.candidates, id, c)

      if pending_bytes(candidates) <= 262_144,
        do: {:ok, %{s | candidates: candidates}, id},
        else: {:error, :proposal_refused}
    else
      _ -> {:error, :proposal_refused}
    end
  end

  def render(s, id, :simulated_verified_terminal) do
    with %{status: :pending, expires: expiry} = c <- s.candidates[id],
         true <- c.project == s.project,
         true <- s.now < expiry do
      code = nonce()

      render = %{
        code: code,
        project: s.project,
        client: s.client,
        version: c.version,
        hash: c.hash,
        consent: s.consent
      }

      {:ok, put_in(s.candidates[id].render, render),
       %{text: c.text, origin: c.origin, command: "accept " <> code}}
    else
      _ -> {:error, :render_refused}
    end
  end

  def render(_, _, _), do: {:error, :operator_channel_required}

  def accept(s, "accept " <> code, :simulated_verified_terminal) do
    with [{id, c}] <-
           Enum.filter(s.candidates, fn {_, c} -> c.render && c.render.code == code end),
         true <- c.status == :pending and s.now < c.expires,
         true <- c.project == s.project,
         true <- s.active and s.current and s.mode == :ordinary,
         true <-
           Map.drop(c.render, [:code]) == %{
             project: s.project,
             client: s.client,
             version: c.version,
             hash: hash(c.text),
             consent: s.consent
           } do
      event = %{
        candidate: id,
        version: c.version,
        text_sha256: c.hash,
        original_origin: c.origin,
        acceptance: :simulated_operator_event,
        permissions_granted: []
      }

      {:ok, put_in(s.candidates[id], %{c | status: :accepted, render: nil}), event}
    else
      _ -> {:error, :acceptance_refused}
    end
  end

  def accept(_, _, _), do: {:error, :acceptance_refused}

  def correct(s, id, text) do
    with %{status: :pending} = c <- s.candidates[id],
         true <- c.project == s.project,
         true <- text?(text, 6_144) do
      next = %{c | text: text, hash: hash(text), version: c.version + 1, render: nil}
      candidates = Map.put(s.candidates, id, next)

      if pending_bytes(candidates) <= 262_144,
        do: {:ok, %{s | candidates: candidates}},
        else: {:error, :correction_refused}
    else
      _ -> {:error, :correction_refused}
    end
  end

  def draft(s, text) do
    with true <- is_nil(s.draft) or s.draft.status in [:cancelled, :consumed],
         true <- text?(text, 8_192) do
      d = %{id: nonce(), version: 1, text: text, status: :pending, enclosing: s.mode}
      {:ok, %{s | draft: d}}
    else
      _ -> {:error, :draft_refused}
    end
  end

  def replace(%{draft: %{status: :pending} = d} = s, text) do
    if text?(text, 8_192),
      do: {:ok, %{s | draft: %{d | version: d.version + 1, text: text}}},
      else: {:error, :draft_refused}
  end

  def replace(_, _), do: {:error, :draft_refused}

  def cancel(%{draft: %{status: :pending} = d} = s),
    do:
      {:ok, %{s | draft: %{d | status: :cancelled}},
       "Host intent status: draft abandoned; it supplies no requirements for subsequent tasks."}

  def cancel(_), do: {:error, :draft_refused}

  def accept_draft(%{draft: %{status: :pending, id: id, version: version} = d} = s, id, version),
    do: {:ok, %{s | draft: %{d | status: :accepted}}}

  def accept_draft(_, _, _), do: {:error, :draft_refused}

  def consume(%{draft: %{status: :accepted} = d} = s),
    do: {:ok, %{s | draft: %{d | status: :consumed}, mode: stricter(s.mode, d.enclosing)}, d.text}

  def consume(_), do: {:error, :draft_refused}

  defp pending_bytes(candidates),
    do:
      candidates
      |> Map.new(fn {id, c} ->
        {id, c |> Map.delete(:render) |> Map.put(:status, :accepted)}
      end)
      |> JSON.encode!()
      |> byte_size()

  defp stricter(:read_only, _), do: :read_only
  defp stricter(_, :read_only), do: :read_only
  defp stricter(:planning, _), do: :planning
  defp stricter(_, :planning), do: :planning
  defp stricter(_, _), do: :ordinary

  defp nonce, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  defp hash(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  defp text?(text, limit),
    do: is_binary(text) and String.valid?(text) and byte_size(text) in 1..limit
end
