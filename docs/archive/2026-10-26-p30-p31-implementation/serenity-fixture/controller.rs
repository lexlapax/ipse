//! Review-only fault-switch controller. Its entry point is disabled; the real
//! backend is unreviewed and must not be enabled before all prerequisites pass.
#![allow(dead_code)]
#[path = "identity_guard.rs"] mod guard;
#[path = "real_backend.rs"] mod real_backend;
#[path = "provisioning.rs"] mod provisioning;
#[path = "barrier_orchestration.rs"] mod barrier_orchestration;
#[path = "barrier_framing.rs"] mod barrier_framing;
#[path = "barrier_peer.rs"] mod barrier_peer;
#[path = "recovery_ledger.rs"] mod recovery_ledger;
use guard::{Expected, Table, loop_matches, mapper_matches, table_matches};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum State { Ready, FaultPending, ErrorActive, RestorePending, LinearActive, UnmountPending,
    Unmounted, RemovePending, MapperRemoved, DetachPending, Detached, Unknown }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Action { Suspend, LoadError, Resume, LoadLinear, Unmount, RemoveMapper, DetachLoop }
#[derive(Clone, Debug)]
struct Observation { loop_row: String, mapper_row: String, active: String, inactive: Option<String> }

trait Backend {
    /// Must be a durably fsynced, exclusive fixture-owned journal entry.
    fn journal(&mut self, state: State, action: Option<Action>) -> Result<(), ()>;
    /// Every call must observe the real loop and exact mapper identity/table anew.
    fn observe(&mut self) -> Result<Observation, ()>;
    fn observe_loop(&mut self) -> Result<String, ()>;
    /// Must be bounded and return unknown after a possibly attempted command.
    fn effect(&mut self, action: Action, expected: &Expected) -> Result<(), ()>;
    /// These must be exact, validated observations; errors are never absence.
    fn fixture_mount(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn mapper_absent(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn loop_absent(&mut self, expected: &Expected) -> Result<bool, ()>;
    fn loop_has_no_holders(&mut self, expected: &Expected) -> Result<bool, ()>;
}

fn cleanup<B: Backend>(b: &mut B, e: &Expected, state: State) -> State {
    if state != State::LinearActive { return State::Unknown; }
    let o = match b.observe() { Ok(o) => o, Err(_) => return State::Unknown };
    if !checked(e, &o, Table::Linear, None) || b.fixture_mount(e) != Ok(true) ||
        b.journal(State::UnmountPending, Some(Action::Unmount)).is_err() ||
        b.effect(Action::Unmount, e).is_err() { return State::Unknown; }
    if b.fixture_mount(e) != Ok(false) || b.journal(State::Unmounted, None).is_err() {
        return State::Unknown;
    }
    let o = match b.observe() { Ok(o) => o, Err(_) => return State::Unknown };
    if !checked(e, &o, Table::Linear, None) || !mapper_matches(e, &o.mapper_row, true) ||
        b.journal(State::RemovePending, Some(Action::RemoveMapper)).is_err() ||
        b.effect(Action::RemoveMapper, e).is_err() { return State::Unknown; }
    if b.mapper_absent(e) != Ok(true) || b.journal(State::MapperRemoved, None).is_err() {
        return State::Unknown;
    }
    // The backend must reobserve the loop alone after mapper deletion; an
    // unrelated mapper with a reused name cannot authorize loop detachment.
    let loop_row = match b.observe_loop() { Ok(row) => row, Err(_) => return State::Unknown };
    if !loop_matches(e, &loop_row) || b.mapper_absent(e) != Ok(true) ||
        b.loop_has_no_holders(e) != Ok(true) ||
        b.journal(State::DetachPending, Some(Action::DetachLoop)).is_err() ||
        b.effect(Action::DetachLoop, e).is_err() { return State::Unknown; }
    if b.loop_absent(e) != Ok(true) || b.journal(State::Detached, None).is_err() {
        return State::Unknown;
    }
    State::Detached
}

fn checked(e: &Expected, o: &Observation, active: Table, inactive: Option<Table>) -> bool {
    loop_matches(e, &o.loop_row) && mapper_matches(e, &o.mapper_row, false) &&
        table_matches(e, &o.active, active) && match (inactive, &o.inactive) {
            (None, None) => true,
            (Some(t), Some(row)) => table_matches(e, row, t),
            _ => false,
        }
}

/// An error after a recorded pending action is unknown, never auto-restored or
/// replayed. On journal failure even the unknown marker is best-effort only.
fn transition<B: Backend>(b: &mut B, e: &Expected, state: State, desired: Table) -> State {
    let (initial, pending, finished, load) = match (state, desired) {
        (State::Ready, Table::Error) => (Table::Linear, State::FaultPending, State::ErrorActive, Action::LoadError),
        (State::ErrorActive, Table::Linear) => (Table::Error, State::RestorePending, State::LinearActive, Action::LoadLinear),
        _ => return State::Unknown,
    };
    let initial_observation = match b.observe() { Ok(o) => o, Err(_) => return State::Unknown };
    if !checked(e, &initial_observation, initial, None) || b.journal(pending, None).is_err() {
        return State::Unknown;
    }
    let actions = [Action::Suspend, load, Action::Resume];
    for (index, action) in actions.into_iter().enumerate() {
        let observation = match b.observe() { Ok(o) => o, Err(_) => return State::Unknown };
        // Reload creates an inactive table; until resume, active stays initial.
        let inactive = if index == 2 { Some(desired) } else { None };
        if !checked(e, &observation, initial, inactive) ||
            b.journal(pending, Some(action)).is_err() || b.effect(action, e).is_err() {
            let _ = b.journal(State::Unknown, None);
            return State::Unknown;
        }
    }
    let final_observation = match b.observe() { Ok(o) => o, Err(_) => return State::Unknown };
    if !checked(e, &final_observation, desired, None) || b.journal(finished, None).is_err() {
        let _ = b.journal(State::Unknown, None);
        return State::Unknown;
    }
    finished
}

fn main() {
    eprintln!("Live Serenity fault control is disabled: the unreviewed backend is not connected to an entry point.");
    std::process::exit(2);
}

#[cfg(test)] mod tests {
    use super::*;
    fn expected() -> Expected {
        let n = "0123456789abcdef0123456789abcdef";
        Expected { loop_major: 7, loop_minor: 42, backing_major: 0, backing_minor: 37,
            backing_inode: 221, loop_ref: format!("ipse-q-{n}"), dm_name: format!("ipse-q-{n}"),
            dm_uuid: format!("IPSE-Q-{n}"), dm_major: 253, dm_minor: 11, sectors: 1_048_576 }
    }
    struct Mock { obs: Observation, effects: Vec<Action>, journal: Vec<(State, Option<Action>)>,
                  fail_effect: Option<usize>, tamper_at: Option<usize>, observes: usize,
                  fail_journal_at: Option<usize>, mounted: bool, mapper_exists: bool,
                  loop_exists: bool }
    impl Mock {
        fn new() -> Self { let n = "0123456789abcdef0123456789abcdef"; Self {
            obs: Observation { loop_row: format!("221|0:37|7:42|0|536870912|0|ipse-q-{n}"),
                mapper_row: format!("ipse-q-{n}|IPSE-Q-{n}|253|11|1"),
                active: "0 1048576 linear 7:42 0".into(), inactive: None },
            effects: vec![], journal: vec![], fail_effect: None, tamper_at: None, observes: 0,
            fail_journal_at: None, mounted: true, mapper_exists: true, loop_exists: true } }
    }
    impl Backend for Mock {
        fn journal(&mut self, s: State, a: Option<Action>) -> Result<(), ()> {
            self.journal.push((s,a)); if self.fail_journal_at == Some(self.journal.len()) {Err(())} else {Ok(())}
        }
        fn observe(&mut self) -> Result<Observation, ()> {
            self.observes += 1; let mut result = self.obs.clone();
            if self.tamper_at == Some(self.observes) { result.loop_row = result.loop_row.replace("221|", "222|"); }
            Ok(result)
        }
        fn observe_loop(&mut self) -> Result<String, ()> { Ok(self.obs.loop_row.clone()) }
        fn effect(&mut self, action: Action, _: &Expected) -> Result<(), ()> {
            self.effects.push(action); if self.fail_effect == Some(self.effects.len()) {return Err(());}
            match action {
                Action::Suspend => (),
                Action::LoadError => self.obs.inactive = Some("0 1048576 error".into()),
                Action::LoadLinear => self.obs.inactive = Some("0 1048576 linear 7:42 0".into()),
                Action::Resume => { self.obs.active = self.obs.inactive.take().ok_or(())?; }
                Action::Unmount => { self.mounted = false; self.obs.mapper_row = self.obs.mapper_row.replace("|11|1", "|11|0"); }
                Action::RemoveMapper => self.mapper_exists = false,
                Action::DetachLoop => self.loop_exists = false,
            }; Ok(())
        }
        fn fixture_mount(&mut self, _: &Expected) -> Result<bool, ()> { Ok(self.mounted) }
        fn mapper_absent(&mut self, _: &Expected) -> Result<bool, ()> { Ok(!self.mapper_exists) }
        fn loop_absent(&mut self, _: &Expected) -> Result<bool, ()> { Ok(!self.loop_exists) }
        fn loop_has_no_holders(&mut self, _: &Expected) -> Result<bool, ()> { Ok(!self.mapper_exists) }
    }
    #[test] fn fault_and_restore_require_each_exact_table_and_record_pending() {
        let e=expected(); let mut m=Mock::new();
        assert_eq!(transition(&mut m, &e, State::Ready, Table::Error), State::ErrorActive);
        assert_eq!(m.effects, vec![Action::Suspend,Action::LoadError,Action::Resume]);
        assert_eq!(transition(&mut m, &e, State::ErrorActive, Table::Linear), State::LinearActive);
        assert_eq!(m.effects.len(),6);
        assert!(m.journal.contains(&(State::FaultPending,Some(Action::Suspend))));
        assert!(m.journal.contains(&(State::RestorePending,Some(Action::Resume))));
    }
    #[test] fn uncertain_effects_stop_without_replay_or_compensating_action() {
        for failure in 1..=3 { let e=expected(); let mut m=Mock::new(); m.fail_effect=Some(failure);
            assert_eq!(transition(&mut m, &e, State::Ready, Table::Error), State::Unknown);
            assert_eq!(m.effects.len(),failure); assert!(m.journal.contains(&(State::Unknown,None)));
            assert_eq!(transition(&mut m, &e, State::Unknown, Table::Linear), State::Unknown);
            assert_eq!(m.effects.len(),failure);
        }
    }
    #[test] fn changed_identity_and_missing_pending_record_stop_before_effect() {
        let e=expected(); let mut m=Mock::new(); m.tamper_at=Some(2);
        assert_eq!(transition(&mut m, &e, State::Ready, Table::Error), State::Unknown);
        assert!(m.effects.is_empty());
        let mut m=Mock::new(); m.fail_journal_at=Some(2);
        assert_eq!(transition(&mut m, &e, State::Ready, Table::Error), State::Unknown);
        assert!(m.effects.is_empty());
    }
    #[test] fn wrong_existing_or_extra_inactive_table_refuses() {
        let e=expected(); let mut m=Mock::new(); m.obs.inactive=Some("0 1 error".into());
        assert_eq!(transition(&mut m, &e, State::Ready, Table::Error), State::Unknown);
        assert!(m.effects.is_empty());
    }
    #[test] fn cleanup_requires_exact_order_and_never_runs_after_uncertainty() {
        let e=expected(); let mut m=Mock::new();
        assert_eq!(cleanup(&mut m, &e, State::LinearActive), State::Detached);
        assert_eq!(m.effects, vec![Action::Unmount, Action::RemoveMapper, Action::DetachLoop]);
        for failure in 1..=3 { let mut m=Mock::new(); m.fail_effect=Some(failure);
            assert_eq!(cleanup(&mut m, &e, State::LinearActive), State::Unknown);
            assert_eq!(m.effects.len(), failure);
            assert_eq!(cleanup(&mut m, &e, State::Unknown), State::Unknown);
            assert_eq!(m.effects.len(), failure);
        }
    }
    #[test] fn cleanup_refuses_changed_device_and_nonzero_open_count() {
        let e=expected(); let mut m=Mock::new(); m.tamper_at=Some(1);
        assert_eq!(cleanup(&mut m, &e, State::LinearActive), State::Unknown);
        assert!(m.effects.is_empty());
        let mut m=Mock::new(); m.obs.mapper_row = m.obs.mapper_row.replace("|11|1", "|11|2");
        assert_eq!(cleanup(&mut m, &e, State::LinearActive), State::Unknown);
        assert_eq!(m.effects, vec![Action::Unmount]);
    }
    struct Composed { devices: Mock, e: Expected, events: std::collections::VecDeque<barrier_orchestration::Event>, state: State }
    impl barrier_orchestration::Fixture for Composed {
      fn setup(&mut self)->Result<(),()>{Ok(())}
      fn start_scoped_stage(&mut self)->Result<(),()>{Ok(())}
      fn next_event(&mut self)->Result<barrier_orchestration::Event,()>{self.events.pop_front().ok_or(())}
      fn verify_pause(&mut self)->Result<(),()>{Ok(())}
      fn apply_error(&mut self)->Result<(),()>{
        self.state=transition(&mut self.devices,&self.e,self.state,Table::Error);
        if self.state==State::ErrorActive {Ok(())} else {Err(())}
      }
      fn release(&mut self)->Result<(),()>{Ok(())}
      fn await_receipt(&mut self)->Result<(),()>{Ok(())}
      fn restore_linear(&mut self)->Result<(),()>{
        self.state=transition(&mut self.devices,&self.e,self.state,Table::Linear);
        if self.state==State::LinearActive {Ok(())} else {Err(())}
      }
      fn cleanup(&mut self)->Result<(),()>{
        self.state=cleanup(&mut self.devices,&self.e,self.state);
        if self.state==State::Detached {Ok(())} else {Err(())}
      }
      fn record(&mut self,_:barrier_orchestration::Phase)->Result<(),()>{Ok(())}
    }
    #[test] fn composed_barrier_drives_verified_fault_restore_and_teardown() {
      use barrier_orchestration::{Event,Outcome,Phase};
      let mut c=Composed { devices:Mock::new(), e:expected(), state:State::Ready,
          events:[Event::Ready,Event::Write(5),Event::StageUnknown].into() };
      let result=barrier_orchestration::run(&mut c);
      assert_eq!(result.phase,Phase::Clean); assert_eq!(result.outcome,Outcome::ExactWriteError(5));
      assert_eq!(c.state,State::Detached);
      assert_eq!(c.devices.effects, vec![Action::Suspend,Action::LoadError,Action::Resume,
          Action::Suspend,Action::LoadLinear,Action::Resume,Action::Unmount,Action::RemoveMapper,Action::DetachLoop]);
    }
    #[test] fn composed_device_identity_mismatch_stops_before_barrier_release() {
      use barrier_orchestration::{Event,Outcome,Phase};
      let mut c=Composed { devices:Mock::new(), e:expected(), state:State::Ready,
          events:[Event::Ready,Event::Write(5),Event::StageUnknown].into() };
      c.devices.tamper_at=Some(1);
      let result=barrier_orchestration::run(&mut c);
      assert_eq!(result.phase,Phase::Unknown); assert_eq!(result.outcome,Outcome::Unknown);
      assert!(c.devices.effects.is_empty()); assert_eq!(c.events.len(),2);
    }
}
