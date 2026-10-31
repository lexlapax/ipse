alias Ipse.Session.ReleaseReceipt, as: R
session = String.duplicate("a", 32)
epoch = String.duplicate("b", 32)
origin = %{"version" => 1, "session_id" => session, "directory" => "/tmp/ipse-receipt-fixture", "major_device" => 5, "minor_device" => 0, "inode" => 42, "uid" => 1000}
{:ok, owner} = R.owner_started(session)
header = %{"type" => "session", "metadata" => %{"source_origin_layout" => "journal_origin_v1", "source_origin" => origin}}
started = %{"type" => "lifecycle_epoch_started", "version" => 1, "session_id" => session, "epoch_id" => epoch, "mode" => "fresh", "previous_epoch_id" => nil, "previous_state" => "none"}
closure = %{"type" => "lifecycle_epoch_closed", "version" => 1, "session_id" => session, "epoch_id" => epoch, "closure" => "close", "cleanup_confirmed" => false}
{:ok, intent, private} = R.prepare(session, owner["owner_id"], epoch, closure, origin, %{device: 5, inode: 7}, String.duplicate("c", 64))
{:ok, bytes} = R.seal(intent, private)
history = [header, owner, started, closure, intent]
:signed_release_claim = R.classify_current(history, session, bytes)
next_epoch = %{started | "epoch_id" => String.duplicate("d", 32), "mode" => "resume", "previous_epoch_id" => epoch, "previous_state" => "closed"}
{:ok, nil} = R.current_intent(history ++ [next_epoch], session)
:unknown = R.classify_current(history ++ [next_epoch], session, bytes)
{:ok, [^intent]} = R.intents(history ++ [next_epoch], session)
IO.puts("RELEASE_RECEIPT_V6_NEW_EPOCH_INVALIDATION_OK")
{:ok, next_owner} = R.owner_started(session)
{:ok, nil_intent, nil_private} = R.prepare(session, next_owner["owner_id"], nil, nil, origin, %{device: 5, inode: 7}, String.duplicate("c", 64))
{:ok, nil_bytes} = R.seal(nil_intent, nil_private)
active_prior_owner = [header, owner, started, next_owner, nil_intent]
{:ok, %{epoch: ^epoch, closed: false}} = Ipse.Session.RuntimeLifecycle.restore(active_prior_owner, session)
{:ok, ^nil_intent} = R.current_intent(active_prior_owner, session)
:signed_release_claim = R.classify_current(active_prior_owner, session, nil_bytes)
IO.puts("RELEASE_RECEIPT_V6_NEW_OWNER_NIL_EPOCH_SCOPE_OBSERVED")
