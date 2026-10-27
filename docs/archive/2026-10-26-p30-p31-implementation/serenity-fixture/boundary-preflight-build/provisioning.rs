//! Provisioning transition logic for a disabled, review-only disposable fixture.
//! This module has no host backend and cannot by itself create any resource.
use super::guard::{Expected, Table, loop_matches, mapper_matches, table_matches};
use super::Observation;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Step { Backing, Loop, Mapper, Format, Mount }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Status { Empty, BackingReady, LoopReady, MapperReady, Formatted, Mounted, Unknown }
pub(super) trait Backend {
    /// Must be exclusive and durable; effect is never entered if this fails.
    fn pending(&mut self, step: Step) -> Result<(), ()>;
    fn effect(&mut self, step: Step, expected: &Expected) -> Result<(), ()>;
    /// Observe the just-created open file and return its native filesystem
    /// device/inode. The real backend must tie this to the original create FD.
    fn created_backing_identity(&mut self) -> Result<(u64,u64,u64), ()>;
    fn backing_matches(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn loop_unassigned(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn mapper_unassigned(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn loop_row(&mut self) -> Result<String, ()>;
    fn observation(&mut self) -> Result<Observation, ()>;
    fn no_holders(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn loop_held_only_by_mapper(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn mounted(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn confirmed(&mut self, status: Status) -> Result<(), ()>;
}
fn effect<B: Backend>(b: &mut B, e: &Expected, step: Step) -> bool {
    b.pending(step).is_ok() && b.effect(step,e).is_ok()
}
pub(super) fn provision<B: Backend>(b: &mut B, e: &mut Expected, state: Status) -> Status {
    // No resume or recovery path is encoded: after any failure inspect manually.
    if state != Status::Empty { return Status::Unknown; }
    if b.loop_unassigned(e) != Ok(true) || b.mapper_unassigned(e) != Ok(true) ||
       !effect(b,e,Step::Backing) {
        return Status::Unknown;
    }
    let (major,minor,inode) = match b.created_backing_identity() {
        Ok((major,minor,inode)) if inode != 0 => (major,minor,inode), _ => return Status::Unknown,
    };
    e.backing_major=major; e.backing_minor=minor; e.backing_inode=inode;
    if b.backing_matches(e) != Ok(true) || b.confirmed(Status::BackingReady).is_err() { return Status::Unknown; }
    if b.loop_unassigned(e) != Ok(true) || b.backing_matches(e) != Ok(true) ||
       !effect(b,e,Step::Loop) { return Status::Unknown; }
    let loop_row = match b.loop_row() { Ok(row) => row, Err(_) => return Status::Unknown };
    if !loop_matches(e,&loop_row) || b.backing_matches(e) != Ok(true) || b.confirmed(Status::LoopReady).is_err() ||
       b.mapper_unassigned(e) != Ok(true) || !effect(b,e,Step::Mapper) {
        return Status::Unknown;
    }
    let o = match b.observation() { Ok(o) => o, Err(_) => return Status::Unknown };
    if !loop_matches(e,&o.loop_row) || !mapper_matches(e,&o.mapper_row,true) ||
       !table_matches(e,&o.active,Table::Linear) || o.inactive.is_some() ||
       b.backing_matches(e) != Ok(true) || b.no_holders(e) != Ok(true) || b.loop_held_only_by_mapper(e) != Ok(true) ||
       b.mounted(e) != Ok(false) || b.confirmed(Status::MapperReady).is_err() || !effect(b,e,Step::Format) {
        return Status::Unknown;
    }
    if b.confirmed(Status::Formatted).is_err() { return Status::Unknown; }
    let o = match b.observation() { Ok(o) => o, Err(_) => return Status::Unknown };
    if !loop_matches(e,&o.loop_row) || !mapper_matches(e,&o.mapper_row,true) ||
       !table_matches(e,&o.active,Table::Linear) || o.inactive.is_some() ||
       b.backing_matches(e) != Ok(true) || b.loop_held_only_by_mapper(e) != Ok(true) || b.mounted(e) != Ok(false) ||
       !effect(b,e,Step::Mount) || b.mounted(e) != Ok(true) || b.confirmed(Status::Mounted).is_err() {
        return Status::Unknown;
    }
    Status::Mounted
}

#[cfg(test)] mod tests {
    use super::*;
    fn expected() -> Expected { let n="0123456789abcdef0123456789abcdef"; Expected {
      loop_major:7,loop_minor:42,backing_major:0,backing_minor:37,backing_inode:221,
      loop_ref:format!("ipse-q-{n}"),dm_name:format!("ipse-q-{n}"),dm_uuid:format!("IPSE-Q-{n}"),
      dm_major:253,dm_minor:11,sectors:1_048_576 } }
    struct Mock { steps: Vec<Step>, pending: Vec<Step>, fail: Option<Step>, loop_busy: bool,
        dm_busy: bool, backing: bool, mounted: bool, holder: bool, wrong_table: bool }
    impl Mock { fn new() -> Self { Self {steps:vec![],pending:vec![],fail:None,loop_busy:false,
        dm_busy:false,backing:false,mounted:false,holder:false,wrong_table:false} } }
    impl Backend for Mock {
        fn pending(&mut self,s:Step)->Result<(),()>{self.pending.push(s);Ok(())}
        fn effect(&mut self,s:Step,_:&Expected)->Result<(),()>{
          self.steps.push(s);if self.fail==Some(s){return Err(())}
          match s {Step::Backing=>self.backing=true,Step::Loop=>self.loop_busy=true,
             Step::Mapper=>self.dm_busy=true,Step::Mount=>self.mounted=true,Step::Format=>()};Ok(()) }
        fn created_backing_identity(&mut self)->Result<(u64,u64,u64),()>{if self.backing {Ok((0,37,221))} else {Err(())}}
        fn backing_matches(&mut self,_:&Expected)->Result<bool,()>{Ok(self.backing)}
        fn loop_unassigned(&mut self,_:&Expected)->Result<bool,()>{Ok(!self.loop_busy)}
        fn mapper_unassigned(&mut self,_:&Expected)->Result<bool,()>{Ok(!self.dm_busy)}
        fn loop_row(&mut self)->Result<String,()>{let n="0123456789abcdef0123456789abcdef";
           Ok(format!("221|0:37|7:42|0|536870912|0|ipse-q-{n}"))}
        fn observation(&mut self)->Result<Observation,()>{ let n="0123456789abcdef0123456789abcdef";
            Ok(Observation{loop_row:self.loop_row()?,mapper_row:format!("ipse-q-{n}|IPSE-Q-{n}|253|11|0"),
              active:if self.wrong_table {"0 1048576 linear 259:2 0"} else {"0 1048576 linear 7:42 0"}.into(),inactive:None}) }
        fn no_holders(&mut self,_:&Expected)->Result<bool,()>{Ok(!self.holder)}
        fn loop_held_only_by_mapper(&mut self,_:&Expected)->Result<bool,()>{Ok(!self.holder)}
        fn mounted(&mut self,_:&Expected)->Result<bool,()>{Ok(self.mounted)}
        fn confirmed(&mut self,_:Status)->Result<(),()>{Ok(())}
    }
    #[test] fn every_real_effect_is_preceded_by_an_exact_pending_step() {
        let mut b=Mock::new(); assert_eq!(provision(&mut b,&mut expected(),Status::Empty),Status::Mounted);
        assert_eq!(b.steps,vec![Step::Backing,Step::Loop,Step::Mapper,Step::Format,Step::Mount]);
        assert_eq!(b.steps,b.pending);
    }
    #[test] fn any_failed_effect_stops_without_retry_or_cleanup() {
        for (i,s) in [Step::Backing,Step::Loop,Step::Mapper,Step::Format,Step::Mount].iter().enumerate(){
          let mut b=Mock::new();b.fail=Some(*s);
          assert_eq!(provision(&mut b,&mut expected(),Status::Empty),Status::Unknown);
          assert_eq!(b.steps.len(),i+1);
          assert_eq!(provision(&mut b,&mut expected(),Status::Unknown),Status::Unknown);
          assert_eq!(b.steps.len(),i+1);
        }
    }
    #[test] fn preexisting_devices_or_wrong_backing_mapping_cannot_format() {
        let mut b=Mock::new();b.loop_busy=true;
        assert_eq!(provision(&mut b,&mut expected(),Status::Empty),Status::Unknown); assert!(b.steps.is_empty());
        let mut b=Mock::new();b.dm_busy=true;
        assert_eq!(provision(&mut b,&mut expected(),Status::Empty),Status::Unknown); assert!(b.steps.is_empty());
        let mut b=Mock::new();b.wrong_table=true;
        assert_eq!(provision(&mut b,&mut expected(),Status::Empty),Status::Unknown); assert!(!b.steps.contains(&Step::Format));
        let mut b=Mock::new();b.holder=true;
        assert_eq!(provision(&mut b,&mut expected(),Status::Empty),Status::Unknown); assert!(!b.steps.contains(&Step::Format));
    }
}
