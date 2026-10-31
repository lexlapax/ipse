defmodule Ipse.Session.ReleaseReceipt do
  @moduledoc """
  Closed, signed facts for a Session lock release. This module does not observe
  a helper, write a sidecar, or authorize execution; trusted host code must only
  sign after observing the exact release and other cleanup receipts.

  The signature separates an observed release from an unsigned or replayed
  sidecar. Journal and protected storage remain a cooperative same-user trust
  boundary; this is not containment of hostile BEAM or process-memory access.
  """

  alias Ipse.JSON
  @domain "ipse.session.release-receipt.v1\0"
  @intent_keys ~w(type version session_id owner_id operation_id epoch_id closure_sha256 origin_sha256 lock_device lock_inode helper_sha256 public_key)
  @owner_keys ~w(type version session_id owner_id)
  @body_keys ~w(type version session_id operation_id intent_sha256 native_outcome)
  @receipt_keys ~w(body signature)
  @error {:error, :invalid_release_receipt}
  @max_bytes 2_048

  @doc false
  def layout, do: "session_release_receipt_v1"

  defmodule SigningKey do
    @moduledoc false
    @enforce_keys [:owner, :bytes]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#Session.ReleaseReceipt.SigningKey<private>"
    end
  end

  @doc false
  def owner_started(session) do
    if id?(session),
      do:
        {:ok,
         %{
           "type" => "session_release_owner_started",
           "version" => 1,
           "session_id" => session,
           "owner_id" => Ipse.Usage.id()
         }},
      else: @error
  end

  @doc false
  def valid_owner_marker?(marker, session) do
    id?(session) and keys?(marker, @owner_keys) and
      marker["type"] == "session_release_owner_started" and marker["version"] === 1 and
      marker["session_id"] == session and id?(marker["owner_id"])
  end

  @doc false
  def prepare(session, owner, epoch, closure, origin, lock, helper_sha) do
    with true <- id?(session),
         true <- id?(owner),
         true <- valid_closure?(closure, session, epoch),
         {:ok, ^origin} <-
           Ipse.Journal.SourceOrigin.recorded(
             %{
               "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
               "source_origin" => origin
             },
             session
           ),
         true <- is_map(lock),
         true <- JSON.safe_uint?(lock[:device]) and JSON.safe_uint?(lock[:inode]),
         true <- lock[:inode] > 0 and sha256?(helper_sha) do
      {public, private} = :crypto.generate_key(:eddsa, :ed25519)

      intent = %{
        "type" => "session_release_intent",
        "version" => 1,
        "session_id" => session,
        "owner_id" => owner,
        "operation_id" => Ipse.Usage.id(),
        "epoch_id" => epoch,
        "closure_sha256" => if(closure, do: JSON.digest([closure])),
        "origin_sha256" => JSON.digest([origin]),
        "lock_device" => lock.device,
        "lock_inode" => lock.inode,
        "helper_sha256" => helper_sha,
        "public_key" => encode(public)
      }

      if valid_intent?(intent),
        do: {:ok, intent, %SigningKey{owner: self(), bytes: private}},
        else: @error
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def seal(intent, %SigningKey{owner: owner, bytes: private})
      when owner == self() and is_binary(private) and byte_size(private) == 32 do
    with true <- valid_intent?(intent),
         {:ok, public} <- decode(intent["public_key"], 32) do
      body = body(intent)
      signature = :crypto.sign(:eddsa, :none, message(intent, body), [private, :ed25519])

      if :crypto.verify(:eddsa, :none, message(intent, body), signature, [public, :ed25519]) do
        {:ok, Jason.encode!(%{"body" => body, "signature" => encode(signature)})}
      else
        @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def seal(_, _), do: @error

  @doc false
  def verify(intent, bytes) when is_binary(bytes) and byte_size(bytes) <= @max_bytes do
    with true <- valid_intent?(intent),
         {:ok, receipt} <- JSON.decode_bounded(bytes, @max_bytes),
         true <- keys?(receipt, @receipt_keys),
         body when is_map(body) <- receipt["body"],
         true <- keys?(body, @body_keys) and body === body(intent),
         {:ok, public} <- decode(intent["public_key"], 32),
         {:ok, signature} <- decode(receipt["signature"], 64),
         true <-
           :crypto.verify(:eddsa, :none, message(intent, body), signature, [public, :ed25519]) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def verify(_, _), do: @error

  @doc false
  def classify(_intent, nil), do: :unknown

  # A signature is a claim from trusted host code, not an observation of the
  # native outcome or proof of sidecar publication and cleanup by itself.
  def classify(intent, bytes),
    do: if(verify(intent, bytes) == :ok, do: :signed_release_claim, else: :unknown)

  @doc false
  def intents(events, session) when is_list(events) do
    with {:ok, state} <- scan(events, session), do: {:ok, Enum.reverse(state.intents)}
  end

  def intents(_, _), do: @error

  # Historical signatures do not authorize adoption after another owner starts.
  # Recording exhaustion makes current cleanup unknowable, even when an earlier
  # signed claim is still useful as historical evidence.
  @doc false
  def current_intent(events, session) when is_list(events) do
    with {:ok, state} <- scan(events, session) do
      {:ok, if(state.stopped, do: nil, else: state.current_intent)}
    end
  end

  def current_intent(_, _), do: @error

  @doc false
  def classify_current(events, session, bytes) do
    case current_intent(events, session) do
      {:ok, intent} when is_map(intent) -> classify(intent, bytes)
      _ -> :unknown
    end
  end

  @doc false
  def inspect_current(directory, session) when is_binary(directory) do
    path = Path.join(directory, session <> ".lock")

    with true <- id?(session) and Path.type(directory) == :absolute,
         {:ok, before} <- File.lstat(path),
         true <- before.type == :regular and before.links == 1,
         {:ok, port} <- Ipse.Runner.protected_header_lock(path) do
      claim =
        try do
          inspect_locked(directory, session, port, before)
        rescue
          _ -> :unknown
        end

      if Ipse.Runner.unlock_export_candidate(port) == :ok, do: claim, else: :unknown
    else
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  def inspect_current(_, _), do: :unknown

  defp inspect_locked(directory, session, port, before) do
    deadline = System.monotonic_time(:millisecond) + 2_000

    with {:ok, lock} <- Ipse.Runner.session_header_lock_identity(port, deadline),
         true <- {lock.device, lock.inode} == {before.major_device, before.inode},
         {:ok, events} <- Ipse.Journal.load(directory, session),
         metadata when is_map(metadata) <- hd(events)["metadata"],
         true <- metadata["release_receipt_layout"] == layout(),
         {:ok, origin} when is_map(origin) <-
           Ipse.Journal.SourceOrigin.recorded(metadata, session),
         true <- origin["directory"] == directory,
         :ok <- Ipse.Journal.SourceOrigin.check_path(directory, session, metadata),
         {:ok, intent} when is_map(intent) <- current_intent(events, session),
         true <- {intent["lock_device"], intent["lock_inode"]} == {lock.device, lock.inode},
         {:ok, helper} <- Ipse.Runner.protected_helper_digest(),
         true <- helper == intent["helper_sha256"],
         {:ok, bytes} <-
           read_private_receipt(directory, session, intent["operation_id"], origin["uid"]),
         :signed_release_claim <- classify(intent, bytes),
         :ok <- Ipse.Journal.SourceOrigin.check_path(directory, session, metadata),
         {:ok, ^lock} <- Ipse.Runner.session_header_lock_identity(port, deadline) do
      :signed_release_claim
    else
      _ -> :unknown
    end
  end

  defp read_private_receipt(directory, session, operation, uid) do
    path = Path.join(directory, ".release-" <> session <> "-" <> operation)

    with {:ok, before} <- File.lstat(path),
         true <- private_receipt?(before, uid),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      try do
        with {:ok, info} <- :file.read_file_info(file),
             opened = File.Stat.from_record(info),
             true <-
               private_receipt?(opened, uid) and
                 receipt_identity(opened) == receipt_identity(before),
             {:ok, bytes} <- :file.read(file, @max_bytes + 1),
             true <- byte_size(bytes) == before.size,
             {:ok, after_info} <- :file.read_file_info(file),
             {:ok, named_after} <- File.lstat(path),
             after_stat = File.Stat.from_record(after_info),
             true <- private_receipt?(after_stat, uid) and private_receipt?(named_after, uid),
             true <-
               receipt_identity(after_stat) == receipt_identity(before) and
                 receipt_identity(named_after) == receipt_identity(before) do
          {:ok, bytes}
        else
          _ -> @error
        end
      after
        :file.close(file)
      end
    else
      _ -> @error
    end
  end

  defp private_receipt?(stat, uid),
    do:
      stat.type == :regular and stat.links == 1 and stat.uid == uid and
        Bitwise.band(stat.mode, 0o077) == 0 and stat.size in 1..@max_bytes

  defp receipt_identity(stat), do: {stat.major_device, stat.minor_device, stat.inode, stat.size}

  defp scan(events, session) do
    header = List.first(events) || %{}

    with true <- id?(session),
         {:ok, _} <- Ipse.Session.RuntimeLifecycle.restore(events, session),
         {:ok, origin} <- Ipse.Journal.SourceOrigin.recorded(header["metadata"], session) do
      scan_intents(events, session, origin)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp scan_intents(events, session, origin) do
    Enum.reduce_while(
      events,
      {:ok,
       %{
         closures: %{},
         epochs: MapSet.new(),
         ids: MapSet.new(),
         owners: MapSet.new(),
         used_owners: MapSet.new(),
         intents: [],
         current_owner: nil,
         current_epoch: nil,
         last_closed: nil,
         current_intent: nil,
         stopped: false
       }},
      fn
        %{"type" => "session_release_owner_started"} = marker, {:ok, acc} ->
          owner = marker["owner_id"]

          if valid_owner_marker?(marker, session) and
               not MapSet.member?(acc.owners, owner) do
            {:cont,
             {:ok,
              %{
                acc
                | owners: MapSet.put(acc.owners, owner),
                  current_owner: owner,
                  current_epoch: nil,
                  last_closed: nil,
                  current_intent: nil
              }}}
          else
            {:halt, @error}
          end

        %{"type" => "lifecycle_epoch_started", "epoch_id" => epoch}, {:ok, acc} ->
          {:cont, {:ok, %{acc | current_epoch: epoch, last_closed: nil, current_intent: nil}}}

        %{"type" => "lifecycle_recording_stopped"}, {:ok, acc} ->
          {:cont, {:ok, %{acc | stopped: true, current_intent: nil}}}

        %{"type" => "lifecycle_epoch_closed", "epoch_id" => epoch} = closure, {:ok, acc} ->
          if epoch == acc.current_epoch and not Map.has_key?(acc.closures, epoch) do
            {:cont,
             {:ok, %{acc | closures: Map.put(acc.closures, epoch, closure), last_closed: epoch}}}
          else
            {:halt, @error}
          end

        %{"type" => "session_release_intent"} = intent, {:ok, acc} ->
          epoch = intent["epoch_id"]
          closure = if epoch, do: acc.closures[epoch]

          if not acc.stopped and valid_intent?(intent) and intent["session_id"] == session and
               is_map(origin) and
               intent["origin_sha256"] == JSON.digest([origin]) and
               intent["owner_id"] == acc.current_owner and
               not MapSet.member?(acc.used_owners, intent["owner_id"]) and
               not MapSet.member?(acc.ids, intent["operation_id"]) and
               ((is_nil(epoch) and is_nil(acc.current_epoch)) or
                  (not is_nil(epoch) and acc.last_closed == epoch and
                     not MapSet.member?(acc.epochs, epoch))) and
               valid_closure?(closure, session, epoch) and
               intent["closure_sha256"] == if(closure, do: JSON.digest([closure])) do
            next = %{
              acc
              | ids: MapSet.put(acc.ids, intent["operation_id"]),
                used_owners: MapSet.put(acc.used_owners, intent["owner_id"]),
                epochs: if(epoch, do: MapSet.put(acc.epochs, epoch), else: acc.epochs),
                intents: [intent | acc.intents],
                current_intent: intent
            }

            {:cont, {:ok, next}}
          else
            {:halt, @error}
          end

        event, acc when is_map(event) ->
          {:cont, acc}

        _, _ ->
          {:halt, @error}
      end
    )
  end

  @doc false
  def valid_intent?(intent) do
    keys?(intent, @intent_keys) and intent["type"] == "session_release_intent" and
      intent["version"] === 1 and id?(intent["session_id"]) and id?(intent["owner_id"]) and
      id?(intent["operation_id"]) and
      ((is_nil(intent["epoch_id"]) and is_nil(intent["closure_sha256"])) or
         (id?(intent["epoch_id"]) and sha256?(intent["closure_sha256"]))) and
      sha256?(intent["origin_sha256"]) and sha256?(intent["helper_sha256"]) and
      JSON.safe_uint?(intent["lock_device"]) and JSON.safe_uint?(intent["lock_inode"]) and
      intent["lock_inode"] > 0 and match?({:ok, _}, decode(intent["public_key"], 32))
  end

  defp valid_closure?(nil, _, nil), do: true

  defp valid_closure?(closure, session, epoch) when is_map(closure) do
    Ipse.Session.RuntimeLifecycle.valid_record?(closure) and
      closure["type"] == "lifecycle_epoch_closed" and closure["session_id"] == session and
      closure["epoch_id"] == epoch and closure["closure"] == "close" and
      closure["cleanup_confirmed"] === false
  end

  defp valid_closure?(_, _, _), do: false

  defp body(intent),
    do: %{
      "type" => "session_release_receipt",
      "version" => 1,
      "session_id" => intent["session_id"],
      "operation_id" => intent["operation_id"],
      "intent_sha256" => JSON.digest([intent]),
      "native_outcome" => "unlocked_exit_0"
    }

  defp message(intent, body), do: @domain <> JSON.digest([intent, body])
  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)

  defp decode(value, size)
       when is_binary(value) and byte_size(value) == div(size * 8 + 5, 6) do
    with {:ok, bytes} <- Base.url_decode64(value, padding: false),
         true <- byte_size(bytes) == size and encode(bytes) == value,
         do: {:ok, bytes}
  end

  defp decode(_, _), do: @error

  defp id?(value),
    do: is_binary(value) and byte_size(value) == 32 and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)

  defp sha256?(value), do: is_binary(value) and byte_size(value) == 64 and JSON.sha256?(value)

  defp keys?(map, keys),
    do:
      is_map(map) and map_size(map) == length(keys) and
        Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
