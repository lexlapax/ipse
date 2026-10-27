# Creates a new private source-derived diagnostic helper. Never edits the
# checkout or shared helper. This changes kernel allowlist and staging control
# ONLY in an isolated test source; it does not qualify a production profile.
defmodule MakeBarrier do
  @checkout "/home/lexlapax/projects/lexlapax/ipse/native"
  @target "/tmp/ipse-serenity-barrier-private"
  @socket "/work/control/native-stage.sock"
  @pending ".pending-" <> String.duplicate("b",32)
  def replace_once(source,needle,replacement) do
    case String.split(source,needle) do
      [before,after_] -> before<>replacement<>after_
      _ -> raise "expected exactly one source site"
    end
  end
  def make do
    :ok=File.mkdir(@target)
    :ok=File.chmod(@target,0o700)
    :ok=File.mkdir(Path.join(@target,"native"))
    for path<-Path.wildcard(Path.join(@checkout,"*.rs")) do
      :ok=File.cp(path,Path.join([@target,"native",Path.basename(path)]))
    end
    transaction=Path.join([@target,"native","ipse-transaction.rs"])
    source=File.read!(transaction)
    insertion="""
        // PRIVATE TEST-ONLY: fixed synthetic pending file, one controller socket.
        fn fixture_barrier(name: &str, remaining: usize, count: usize) -> Result<Option<std::os::unix::net::UnixStream>, u8> {
            if name != \"#{@pending}\" || remaining != count { return Ok(None); }
            let mut peer = std::os::unix::net::UnixStream::connect(\"#{@socket}\").map_err(|_| IO)?;
            peer.set_read_timeout(Some(Duration::from_secs(10))).map_err(|_| IO)?;
            peer.set_write_timeout(Some(Duration::from_secs(10))).map_err(|_| IO)?;
            peer.write_all(b\"R\").map_err(|_| IO)?;
            let mut gate = [0_u8; 1]; peer.read_exact(&mut gate).map_err(|_| IO)?;
            if gate != *b\"G\" { return Err(IO); }
            Ok(Some(peer))
        }
        fn fixture_report(peer: &mut Option<std::os::unix::net::UnixStream>, phase: u8, result: &io::Result<()>) -> Result<(), u8> {
            if let Some(peer) = peer.as_mut() {
                let errno = match result { Ok(()) => 0_i32, Err(error) => error.raw_os_error().unwrap_or(-1) };
                peer.write_all(&[phase]).map_err(|_| IO)?;
                peer.write_all(&errno.to_be_bytes()).map_err(|_| IO)?;
            }
            Ok(())
        }

    """
    marker="    fn stage_data(stage: &mut Stage, held: &Held, bytes: &[u8], uid: u32) -> Result<(), u8> {"
    source=replace_once(source,marker,insertion<>marker)
    original="""
                let count = bytes.len().min(size - stage.written);
                stage.file.as_mut().unwrap().write_all(&bytes[..count]).map_err(|_| IO)?;
                stage.written += count; stage.remaining -= count; bytes = &bytes[count..];
                if stage.written == *size {
                    let file = stage.file.take().unwrap(); file.sync_all().map_err(|_| IO)?;
    """
    replacement="""
                let count = bytes.len().min(size - stage.written);
                let mut fixture_peer = fixture_barrier(name, stage.remaining, count)?;
                let written = stage.file.as_mut().unwrap().write_all(&bytes[..count]);
                fixture_report(&mut fixture_peer, b'W', &written)?;
                written.map_err(|_| IO)?;
                stage.written += count; stage.remaining -= count; bytes = &bytes[count..];
                if stage.written == *size {
                    let file = stage.file.take().unwrap();
                    let synced = file.sync_all(); fixture_report(&mut fixture_peer, b'S', &synced)?;
                    synced.map_err(|_| IO)?;
    """
    source=replace_once(source,original,replacement)
    :ok=File.write(transaction,source)
    profile=Path.join([@target,"native","ipse-storage-profile.rs"])
    source=File.read!(profile)
    old="release.trim() == \"7.2.10\" || release.trim().starts_with(\"7.2.10-\")"
    new="release.trim() == \"7.2.11-arch1-1\" || "<>old
    :ok=File.write(profile,replace_once(source,old,new))
    IO.puts("Private source created at #{@target}; no helper was executed.")
  end
end
MakeBarrier.make()
