//! Bounded fault phase only. Unknown states are preserved, not replayed or
//! cleaned. Exact Transaction scope and cgroup ownership remain prerequisites.
use super::{Backend,Expected,State,Table,transition};use super::diagnostic_receipt::{Effect,Record};
pub(super) trait RecordedBackend:Backend {fn diagnostic_record(&mut self,r:Record)->Result<(),()>;fn fault_budget(&self,minimum_ms:u64)->Result<(),()>;}
pub(super) trait Peer {fn ready(&mut self)->Result<(),()>;fn authorize(&mut self,pid:u32)->Result<(),()>;fn release(&mut self)->Result<String,()>;fn finish(&mut self)->Result<(),()>;}
pub(super) trait Stage {fn prepare(&mut self)->Result<u32,()>;fn begin(&mut self)->Result<(),()>;fn finish(&mut self,report:&str)->Result<(),()>;}
impl Stage for super::diagnostic_stage_channel::Stage {fn prepare(&mut self)->Result<u32,()>{self.prepare().map_err(|_|())}fn begin(&mut self)->Result<(),()>{self.begin().map_err(|_|())}fn finish(&mut self,report:&str)->Result<(),()>{self.finish(report).map_err(|_|())}}
impl Peer for super::peer_channel_container::Channel {fn ready(&mut self)->Result<(),()>{self.ready().map(|_|()).map_err(|_|())}fn authorize(&mut self,pid:u32)->Result<(),()>{self.authorize(pid).map_err(|_|())}fn release(&mut self)->Result<String,()>{self.release().map_err(|_|())}fn finish(&mut self)->Result<(),()>{self.finish().map_err(|_|())}}
/// Reports only the instrumented helper W/S frame; a completed scope and full
/// kernel qualification require separate evidence. No cleanup is attempted.
pub(super) fn run<B:RecordedBackend,P:Peer,S:Stage>(b:&mut B,e:&Expected,p:&mut P,stage:&mut S)->Result<String,()> {
 // The caller has already synced PrepareStage intent before spawning BEAM.
 b.fault_budget(45_000)?;let pid=stage.prepare()?;b.diagnostic_record(Record::Confirmed(Effect::PrepareStage))?;b.fault_budget(30_000)?;stage.begin()?;
 if pid==0||p.ready().is_err()||p.authorize(pid).is_err()||b.fixture_mount(e)!=Ok(true){return Err(())}
 b.diagnostic_record(Record::Pending(Effect::SwitchError))?;
 if transition(b,e,State::Ready,Table::Error)!=State::ErrorActive{return Err(())}
 b.diagnostic_record(Record::Confirmed(Effect::SwitchError))?;
 b.diagnostic_record(Record::Pending(Effect::ReleaseStage))?;
 let report=p.release()?;p.finish()?;stage.finish(&report)?;
 b.diagnostic_record(Record::Confirmed(Effect::ReleaseStage))?;
 b.diagnostic_record(Record::Pending(Effect::RestoreLinear))?;
 if transition(b,e,State::ErrorActive,Table::Linear)!=State::LinearActive{return Err(())}
 b.diagnostic_record(Record::Confirmed(Effect::RestoreLinear))?;Ok(report)
}
