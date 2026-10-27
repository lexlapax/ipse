//! Private composition of actual mapper transitions and an authenticated
//! diagnostic peer. Not enabled by main; prerequisites are not yet proven.
use super::{Backend,Expected,State,Table,transition};
pub(super) trait Peer {fn ready(&mut self)->Result<(),()>;fn authorize(&mut self,pid:u32)->Result<(),()>;fn release(&mut self)->Result<String,()>;}
impl Peer for super::peer_channel_container::Channel {
 fn ready(&mut self)->Result<(),()>{self.ready().map(|_|()).map_err(|_|())}
 fn authorize(&mut self,pid:u32)->Result<(),()>{self.authorize(pid).map_err(|_|())}
 fn release(&mut self)->Result<String,()>{self.release().map_err(|_|())}
}
/// Returns a report only when the channel and all exact table transitions
/// succeeded. Any error can leave effects uncertain and needs reviewed recovery.
/// The caller must independently bind PID to the live scoped Controller/Port,
/// prove container/tool lifetime and use a supervisor with recovery authority.
pub(super) fn switch<B:Backend,P:Peer>(backend:&mut B,expected:&Expected,peer:&mut P,pid:u32)->Result<String,()> {
 if pid==0 || peer.ready().is_err() || peer.authorize(pid).is_err() || backend.fixture_mount(expected)!=Ok(true) {return Err(())}
 if transition(backend,expected,State::Ready,Table::Error)!=State::ErrorActive {return Err(())}
 peer.release()
}
