//! Review-only composition of the instrumented stage barrier and fixture.
//! No real host backend or main. Every ambiguous effect terminates unknown.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Phase { Unstarted, SetupPending, Mounted, StagePending, Staging, Paused, FaultPending, Faulted, ReleasePending, Released, Finished, RestorePending, Restored, CleanupPending, Clean, Unknown }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Outcome { ExactWriteError(i32), ExactSyncError(i32), NoError, Unknown }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Event { Ready, Write(i32), Sync(i32), StageUnknown, StageSuccess, Closed, Timeout, Malformed }
pub(super) trait Fixture {
    // All capabilities encapsulate identity and bounded deadlines; unknown is Err.
    // Implementations must not return success on merely attempted side effects.
    fn setup(&mut self) -> Result<(), ()>;
    fn start_scoped_stage(&mut self) -> Result<(), ()>;
    fn next_event(&mut self) -> Result<Event, ()>;
    fn verify_pause(&mut self) -> Result<(), ()>; // exact owner, nonempty partial inode, live barrier
    fn apply_error(&mut self) -> Result<(), ()>; // observed error table after checked transition
    fn release(&mut self) -> Result<(), ()>; // exact one-byte G to authenticated peer
    fn await_receipt(&mut self) -> Result<(), ()>; // scope/controller/helper cleanup proof
    fn restore_linear(&mut self) -> Result<(), ()>; // exact transition with independent teardown budget
    fn cleanup(&mut self) -> Result<(), ()>; // only verified owned device lifecycle
    fn record(&mut self, phase: Phase) -> Result<(), ()>; // durable journal
}
#[derive(Debug, PartialEq, Eq)]
pub(super) struct Result_ { pub(super) phase: Phase, pub(super) outcome: Outcome }
pub(super) fn run<B: Fixture>(b: &mut B) -> Result_ {
    let phase = Phase::Unstarted;
    macro_rules! step { ($pending:expr, $call:expr, $next:expr) => {
        if b.record($pending).is_err() || $call.is_err() || b.record($next).is_err() { return Result_ { phase: Phase::Unknown, outcome: Outcome::Unknown }; }
    } }
    if b.record(phase).is_err() { return Result_ {phase: Phase::Unknown, outcome: Outcome::Unknown}; }
    step!(Phase::SetupPending, b.setup(), Phase::Mounted);
    step!(Phase::StagePending, b.start_scoped_stage(), Phase::Staging);
    if b.next_event() != Ok(Event::Ready) { return Result_ {phase: Phase::Unknown, outcome: Outcome::Unknown}; }
    step!(Phase::Staging, b.verify_pause(), Phase::Paused);
    step!(Phase::FaultPending, b.apply_error(), Phase::Faulted);
    step!(Phase::ReleasePending, b.release(), Phase::Released);
    // Every result requires exact protocol ordering; one native error prevents
    // later frames by construction. No response alone constitutes EIO.
    let (outcome, ending) = match b.next_event() {
        Ok(Event::Write(n)) if n > 0 => (Outcome::ExactWriteError(n), b.next_event()),
        Ok(Event::Write(0)) => match b.next_event() {
            Ok(Event::Sync(n)) if n > 0 => (Outcome::ExactSyncError(n), b.next_event()),
            Ok(Event::Sync(0)) => (Outcome::NoError, b.next_event()),
            _ => return Result_ {phase: Phase::Unknown, outcome: Outcome::Unknown},
        },
        _ => return Result_ {phase: Phase::Unknown, outcome: Outcome::Unknown},
    };
    let consistent = matches!((outcome, ending),
        (Outcome::ExactWriteError(_), Ok(Event::StageUnknown)) |
        (Outcome::ExactSyncError(_), Ok(Event::StageUnknown)) |
        (Outcome::NoError, Ok(Event::StageSuccess)));
    if !consistent { return Result_ {phase: Phase::Unknown, outcome: Outcome::Unknown}; }
    step!(Phase::Released, b.await_receipt(), Phase::Finished);
    step!(Phase::RestorePending, b.restore_linear(), Phase::Restored);
    step!(Phase::CleanupPending, b.cleanup(), Phase::Clean);
    Result_ {phase: Phase::Clean, outcome}
}
#[cfg(test)] mod tests {
    use super::*; use std::collections::VecDeque;
    struct Mock { events: VecDeque<Event>, calls: Vec<&'static str>, fail: Option<&'static str>, records: Vec<Phase>, fail_record: Option<Phase> }
    impl Mock { fn new(events: &[Event]) -> Self {Self {events: events.iter().copied().collect(), calls: vec![], fail: None, records: vec![], fail_record: None}}
      fn call(&mut self, name: &'static str) -> Result<(), ()> {self.calls.push(name); if self.fail == Some(name) {Err(())} else {Ok(())}} }
    impl Fixture for Mock {
      fn setup(&mut self)->Result<(),()>{self.call("setup")}
      fn start_scoped_stage(&mut self)->Result<(),()>{self.call("stage")}
      fn next_event(&mut self)->Result<Event,()>{self.calls.push("event"); self.events.pop_front().ok_or(())}
      fn verify_pause(&mut self)->Result<(),()>{self.call("verify")}
      fn apply_error(&mut self)->Result<(),()>{self.call("fault")}
      fn release(&mut self)->Result<(),()>{self.call("release")}
      fn await_receipt(&mut self)->Result<(),()>{self.call("receipt")}
      fn restore_linear(&mut self)->Result<(),()>{self.call("restore")}
      fn cleanup(&mut self)->Result<(),()>{self.call("cleanup")}
      fn record(&mut self,p:Phase)->Result<(),()>{self.records.push(p);self.call("record")?;if self.fail_record == Some(p) {Err(())} else {Ok(())}}
    }
    #[test] fn exact_write_and_sync_errors_and_success_have_distinct_results() {
      for (events, expected) in [
        (vec![Event::Ready, Event::Write(5), Event::StageUnknown],Outcome::ExactWriteError(5)),
        (vec![Event::Ready, Event::Write(0), Event::Sync(5), Event::StageUnknown],Outcome::ExactSyncError(5)),
        (vec![Event::Ready, Event::Write(0), Event::Sync(0), Event::StageSuccess],Outcome::NoError),
      ] { let mut m=Mock::new(&events); assert_eq!(run(&mut m), Result_ {phase:Phase::Clean,outcome:expected});
          assert_eq!(m.calls.iter().filter(|s| **s=="fault").count(),1); }
    }
    #[test] fn no_fault_if_boundary_is_unproved() {
      for event in [Event::Closed,Event::Timeout,Event::Malformed] { let mut m=Mock::new(&[event]);
        assert_eq!(run(&mut m).phase,Phase::Unknown);assert!(!m.calls.contains(&"fault")); }
      let mut m=Mock::new(&[Event::Ready]);m.fail=Some("verify");
      assert_eq!(run(&mut m).phase,Phase::Unknown);assert!(!m.calls.contains(&"fault"));
    }
    #[test] fn malformed_or_inconsistent_reports_never_restore_or_cleanup() {
      for events in [vec![Event::Ready,Event::Write(5),Event::StageSuccess],
          vec![Event::Ready,Event::Write(-1),Event::StageUnknown], vec![Event::Ready,Event::Write(0),Event::Sync(-1),Event::StageUnknown], vec![Event::Ready,Event::Write(0),Event::Closed], vec![Event::Ready,Event::Sync(5)]] {
        let mut m=Mock::new(&events);assert_eq!(run(&mut m).phase,Phase::Unknown);
        assert!(!m.calls.contains(&"restore")); assert!(!m.calls.contains(&"cleanup")); }
    }
    #[test] fn failed_effect_never_advances_to_later_effects() {
      for fail in ["setup","stage","verify","fault","release","receipt","restore","cleanup"] {
        let mut m=Mock::new(&[Event::Ready,Event::Write(5),Event::StageUnknown]);m.fail=Some(fail);
        assert_eq!(run(&mut m).phase,Phase::Unknown);
        assert_eq!(m.calls.last(),Some(&fail));
      }
    }
    #[test] fn missing_pre_effect_intent_never_executes_the_effect() {
      for (pending,effect) in [(Phase::SetupPending,"setup"),(Phase::StagePending,"stage"),
         (Phase::FaultPending,"fault"),(Phase::ReleasePending,"release"),
         (Phase::RestorePending,"restore"),(Phase::CleanupPending,"cleanup")] {
        let mut m=Mock::new(&[Event::Ready,Event::Write(5),Event::StageUnknown]);m.fail_record=Some(pending);
        assert_eq!(run(&mut m).phase,Phase::Unknown); assert!(!m.calls.contains(&effect));
        assert_eq!(m.records.last(),Some(&pending));
      }
    }
}
