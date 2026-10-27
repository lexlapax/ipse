//! Review-only fault-switch controller. Its entry point is disabled; the real
//! backend is unreviewed and must not be enabled before all prerequisites pass.
#![allow(dead_code)]
#[path = "identity_guard.rs"] mod guard;
#[path = "real_backend.rs"] mod real_backend;
#[path = "provisioning.rs"] mod provisioning;
#[path = "loop_device.rs"] mod loop_device;
#[path = "existing_loop.rs"] mod existing_loop;
#[path = "loop_owner_filter.rs"] mod loop_owner_filter;
#[path = "loop_provenance.rs"] mod loop_provenance;
#[path = "barrier_orchestration.rs"] mod barrier_orchestration;
#[path = "barrier_framing.rs"] mod barrier_framing;
#[path = "barrier_peer.rs"] mod barrier_peer;
#[path = "recovery_ledger.rs"] mod recovery_ledger;
#[path = "diagnostic_receipt.rs"] mod diagnostic_receipt;
#[path = "diagnostic_driver.rs"] mod diagnostic_driver;
#[path = "held_loop_client.rs"] mod held_loop_client;
#[path = "owner_launcher.rs"] mod owner_launcher;
#[path = "owner_guardian.rs"] mod owner_guardian;
#[path = "guardian_launcher.rs"] mod guardian_launcher;
#[path = "diagnostic_fault.rs"] mod diagnostic_fault;
#[path = "index_receipt.rs"] mod index_receipt;
#[path = "private_loop_node.rs"] mod private_loop_node;
#[path = "private_mapper_node.rs"] mod private_mapper_node;
#[path = "diagnostic_stage_channel.rs"] mod diagnostic_stage_channel;
#[path = "recovery_guardian.rs"] mod recovery_guardian;
#[path = "cgroup_witness.rs"] mod cgroup_witness;
#[path = "btrfs_identity.rs"] mod btrfs_identity;
#[path = "bind_mount.rs"] mod bind_mount;
#[path = "private_unmount.rs"] mod private_unmount;
#[path = "peer_channel.rs"] mod peer_channel;
#[path = "peer_channel_container.rs"] mod peer_channel_container;
#[path = "gated_switch.rs"] mod gated_switch;
use guard::{Expected, Table, loop_matches, mapper_matches, table_matches};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum State { Ready, FaultPending, ErrorActive, RestorePending, LinearActive, UnmountPending,
    Unmounted, RemovePending, MapperRemoved, DetachPending, Detached, IndexRemovePending, IndexRemoved, Unknown }
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

/// Exact recovery is only attempted after an independently verified quiescence
/// boundary and a separately reserved recovery budget. Implementations must
/// establish these facts from held live resources, not a caller-provided flag.
trait RecoveryBackend: Backend {
    fn verify_owned_quiescence(&mut self,e: &Expected)->Result<(),()>;
    fn reserve_recovery_budget(&mut self)->Result<(),()>;
}
fn recover<B:RecoveryBackend>(b:&mut B,e:&Expected,recorded:State)->State {
    if !matches!(recorded,State::ErrorActive|State::LinearActive) {return State::Unknown}
    if b.verify_owned_quiescence(e).is_err() || b.reserve_recovery_budget().is_err() {return State::Unknown}
    let observed=match b.observe(){Ok(v)=>v,Err(_)=>return State::Unknown};
    let expected_table=if recorded==State::ErrorActive {Table::Error} else {Table::Linear};
    if !checked(e,&observed,expected_table,None) || b.fixture_mount(e)!=Ok(true) {return State::Unknown}
    let state=if recorded==State::ErrorActive {transition(b,e,recorded,Table::Linear)} else {recorded};
    if state!=State::LinearActive {return State::Unknown}
    cleanup(b,e,state)
}

/// A created loop index is not proven gone merely because its backing is detached.
/// This final step may run only with exact durable creation provenance and an
/// independently observed unbound index. LOOP_CTL_REMOVE itself is the atomic
/// kernel no-openers check; no EBUSY or interrupted result can be treated as
/// absence. No real implementation currently supplies these prerequisites.
trait IndexRemovalBackend: Backend {
    fn created_index_identity(&mut self,e: &Expected)->Result<bool,()>;
    fn remove_created_index(&mut self,e: &Expected)->Result<(),()>;
    fn index_absent(&mut self,e: &Expected)->Result<bool,()>;
}
fn finish_index<B:IndexRemovalBackend>(b: &mut B,e: &Expected,state:State)->State {
 if state!=State::Detached || b.created_index_identity(e)!=Ok(true) || b.loop_absent(e)!=Ok(true) {return State::Unknown}
 if b.journal(State::IndexRemovePending,None).is_err() || b.remove_created_index(e).is_err() {return State::Unknown}
 if b.index_absent(e)!=Ok(true) || b.journal(State::IndexRemoved,None).is_err() {return State::Unknown}
 State::IndexRemoved
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
    if !cfg!(ipse_live_reviewed) {eprintln!("diagnostic entry disabled");std::process::exit(2)}
    if let Err(e)=diagnostic_entry() {eprintln!("DIAGNOSTIC_UNKNOWN: {e}");std::process::exit(3)}
}
fn diagnostic_entry()->Result<(),String> {
    use std::os::fd::FromRawFd;
    use std::os::unix::fs::{OpenOptionsExt,PermissionsExt};
    use std::process::{Command,Stdio};
    unsafe extern "C" {fn fcntl(fd:i32,cmd:i32,...)->i32;}
    let a:Vec<_>=std::env::args().collect();if a.len()!=9{return Err("arguments".into())}
    let nonce=&a[1];let loop_minor:u64=a[2].parse().map_err(|_|"loop minor")?;
    let dm_major:u64=a[3].parse().map_err(|_|"mapper major")?;let dm_minor:u64=a[4].parse().map_err(|_|"mapper minor")?;
    let host_ns:u64=a[5].parse().map_err(|_|"host namespace")?;let container_id=&a[6];
    let boundary=owner_launcher::LaunchBoundary::validate(container_id,host_ns).map_err(|_|"boundary")?;
    boundary.validate_runtime().map_err(|_|"runtime mounts")?;
    let ledger=std::fs::OpenOptions::new().read(true).custom_flags(0x30000).open("/work/fixture-ledger").map_err(|_|"ledger")?;
    let host_dev:u64=a[7].parse().map_err(|_|"host dev")?;let host_ino:u64=a[8].parse().map_err(|_|"host dev inode")?;
    let boot=std::fs::read_to_string("/proc/sys/kernel/random/boot_id").map_err(|_|"boot id")?;
    let index=index_receipt::read(&ledger,nonce,boot.trim_end_matches('\n'),u32::try_from(loop_minor).map_err(|_|"loop minor")?).map_err(|_|"index receipt")?;
    private_loop_node::create(&index,&ledger,nonce,host_ns,(host_dev,host_ino)).map_err(|_|"private node pending")?;
    let dup=||->Result<std::fs::File,String>{let n=unsafe{fcntl(2,1030,3)};if n<0{return Err("stderr pipe".into())}Ok(unsafe{std::fs::File::from_raw_fd(n)})};
    let mut backend=real_backend::RealBackend::new(nonce,loop_minor,dm_major,dm_minor,host_ns,(host_dev,host_ino),120).map_err(|_|"backend preflight")?;
    backend.set_arm_inputs(boundary,ledger,dup()?,dup()?).map_err(|_|"owner inputs")?;
    let mut expected=Expected {loop_major:7,loop_minor,backing_major:0,backing_minor:0,backing_inode:0,loop_ref:format!("ipse-q-{nonce}"),dm_name:format!("ipse-q-{nonce}"),dm_uuid:format!("IPSE-Q-{nonce}"),dm_major,dm_minor,sectors:1_048_576};
    if provisioning::provision(&mut backend,&mut expected,provisioning::Status::Empty)!=provisioning::Status::Mounted{return Err("provision pending; inspect receipt".into())}
    backend.record_diagnostic(diagnostic_receipt::Record::Pending(diagnostic_receipt::Effect::PrepareStage)).map_err(|_|"stage intent")?;
    std::fs::create_dir("/work/mount/transaction").map_err(|_|"stage directory")?;
    std::fs::set_permissions("/work/mount/transaction",std::fs::Permissions::from_mode(0o700)).map_err(|_|"stage permissions")?;
    let mut peer=peer_channel_container::Channel::start("/work/mount/transaction").map_err(|_|"listener")?;
    let child=Command::new("/usr/lib/elixir/bin/elixir").env_clear().env("PATH","/usr/lib/erlang/bin:/usr/lib/elixir/bin:/usr/bin").env("ERL_FLAGS","+S 2:2 +A 1").args(["-pa","/work/runtime/lib/*/ebin","-e","Application.ensure_all_started(:ipse); Code.eval_file(\"/work/tools/share/diagnostic-stage.exs\")"]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().map_err(|_|"stage launch")?;
    let mut stage=diagnostic_stage_channel::Stage::from_child(child).map_err(|_|"stage pipes")?;
    let beam=std::fs::File::open("/usr/lib/erlang/erts-17.1/bin/beam.smp").map_err(|_|"beam executable")?;
    stage.attest_and_activate(&beam).map_err(|_|"stage attestation")?;
    let report=diagnostic_fault::run(&mut backend,&expected,&mut peer,&mut stage).map_err(|_|"fault pending; inspect receipt")?;
    println!("DIAGNOSTIC_FRAME {report}");println!("DEVICE_TEARDOWN_UNCONFIRMED: retain and inspect exact recorded resources");Ok(())
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
                  loop_exists: bool, budget_ms:u64 }
    impl Mock {
        fn new() -> Self { let n = "0123456789abcdef0123456789abcdef"; Self {
            obs: Observation { loop_row: format!("221|0:37|7:42|0|536870912|0|ipse-q-{n}"),
                mapper_row: format!("ipse-q-{n}|IPSE-Q-{n}|253|11|1"),
                active: "0 1048576 linear 7:42 0".into(), inactive: None },
            effects: vec![], journal: vec![], fail_effect: None, tamper_at: None, observes: 0,
            fail_journal_at: None, mounted: true, mapper_exists: true, loop_exists: true, budget_ms:120_000 } }
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
      fn recheck_pause_deadline(&mut self)->Result<(),()>{Ok(())}
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
        if self.state==State::IndexRemoved {Ok(())} else {Err(())}
      }
      fn record(&mut self,_:barrier_orchestration::Phase)->Result<(),()>{Ok(())}
    }
    #[test] fn composed_barrier_refuses_clean_without_loop_index_removal() {
      use barrier_orchestration::{Event,Outcome,Phase};
      let mut c=Composed { devices:Mock::new(), e:expected(), state:State::Ready,
          events:[Event::Ready,Event::Write(5),Event::StageUnknown].into() };
      let result=barrier_orchestration::run(&mut c);
      assert_eq!(result.phase,Phase::Unknown); assert_eq!(result.outcome,Outcome::Unknown);
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
    struct RecoveryMock {device:Mock, quiet:bool, budget:bool}
    impl Backend for RecoveryMock {
      fn journal(&mut self,s:State,a:Option<Action>)->Result<(),()>{self.device.journal(s,a)}
      fn observe(&mut self)->Result<Observation,()>{self.device.observe()}
      fn observe_loop(&mut self)->Result<String,()>{self.device.observe_loop()}
      fn effect(&mut self,a:Action,e:&Expected)->Result<(),()>{self.device.effect(a,e)}
      fn fixture_mount(&mut self,e:&Expected)->Result<bool,()>{self.device.fixture_mount(e)}
      fn mapper_absent(&mut self,e:&Expected)->Result<bool,()>{self.device.mapper_absent(e)}
      fn loop_absent(&mut self,e:&Expected)->Result<bool,()>{self.device.loop_absent(e)}
      fn loop_has_no_holders(&mut self,e:&Expected)->Result<bool,()>{self.device.loop_has_no_holders(e)}
    }
    impl RecoveryBackend for RecoveryMock {
      fn verify_owned_quiescence(&mut self,_:&Expected)->Result<(),()>{if self.quiet {Ok(())}else{Err(())}}
      fn reserve_recovery_budget(&mut self)->Result<(),()>{if self.budget {Ok(())}else{Err(())}}
    }
    #[test]fn recovery_restores_only_exact_known_error_state_then_tears_down(){
      let e=expected();let mut m=RecoveryMock{device:Mock::new(),quiet:true,budget:true};
      m.device.obs.active="0 1048576 error".into();
      assert_eq!(recover(&mut m,&e,State::ErrorActive),State::Detached);
      assert_eq!(m.device.effects,vec![Action::Suspend,Action::LoadLinear,Action::Resume,Action::Unmount,Action::RemoveMapper,Action::DetachLoop]);
    }
    #[test]fn recovery_refuses_unknown_identity_or_unconfirmed_quiescence(){
      let e=expected();for (state,quiet,budget) in [(State::Unknown,true,true),(State::ErrorActive,false,true),(State::ErrorActive,true,false)] {
       let mut m=RecoveryMock{device:Mock::new(),quiet,budget};m.device.obs.active="0 1048576 error".into();
       assert_eq!(recover(&mut m,&e,state),State::Unknown);assert!(m.device.effects.is_empty());
      }
      let mut m=RecoveryMock{device:Mock::new(),quiet:true,budget:true};m.device.obs.active="0 1048576 error".into();m.device.tamper_at=Some(1);
      assert_eq!(recover(&mut m,&e,State::ErrorActive),State::Unknown);assert!(m.device.effects.is_empty());
    }
    struct IndexMock {device:Mock, owned:bool, present:bool, busy:bool, removes:u32}
    impl Backend for IndexMock {
      fn journal(&mut self,s:State,a:Option<Action>)->Result<(),()>{self.device.journal(s,a)}
      fn observe(&mut self)->Result<Observation,()>{self.device.observe()}
      fn observe_loop(&mut self)->Result<String,()>{self.device.observe_loop()}
      fn effect(&mut self,a:Action,e:&Expected)->Result<(),()>{self.device.effect(a,e)}
      fn fixture_mount(&mut self,e:&Expected)->Result<bool,()>{self.device.fixture_mount(e)}
      fn mapper_absent(&mut self,e:&Expected)->Result<bool,()>{self.device.mapper_absent(e)}
      fn loop_absent(&mut self,e:&Expected)->Result<bool,()>{self.device.loop_absent(e)}
      fn loop_has_no_holders(&mut self,e:&Expected)->Result<bool,()>{self.device.loop_has_no_holders(e)}
    }
    impl IndexRemovalBackend for IndexMock {
      fn created_index_identity(&mut self,_:&Expected)->Result<bool,()>{Ok(self.owned)}
      fn remove_created_index(&mut self,_:&Expected)->Result<(),()>{self.removes+=1;if self.busy {Err(())}else{self.present=false;Ok(())}}
      fn index_absent(&mut self,_:&Expected)->Result<bool,()>{Ok(!self.present)}
    }
    #[test]fn created_index_removal_requires_provenance_unbound_and_kernel_success(){
      let e=expected();for (owned,busy,loop_exists) in [(false,false,false),(true,true,false),(true,false,true)] {
        let mut m=IndexMock{device:Mock::new(),owned,present:true,busy,removes:0};m.device.loop_exists=loop_exists;
        assert_eq!(finish_index(&mut m,&e,State::Detached),State::Unknown);
        assert_eq!(m.removes,if owned && busy && !loop_exists {1}else{0});
      }
      let mut m=IndexMock{device:Mock::new(),owned:true,present:true,busy:false,removes:0};m.device.loop_exists=false;
      assert_eq!(finish_index(&mut m,&e,State::Detached),State::IndexRemoved);assert_eq!(m.removes,1);
      assert!(m.device.journal.contains(&(State::IndexRemovePending,None)));
    }
    struct GateMock{ready:bool,auth:bool,released:bool}
    impl gated_switch::Peer for GateMock {
      fn ready(&mut self)->Result<(),()>{if self.ready {Ok(())}else{Err(())}}
      fn authorize(&mut self,_:u32)->Result<(),()>{if self.auth {Ok(())}else{Err(())}}
      fn release(&mut self)->Result<String,()>{self.released=true;Ok("REPORT W=5".into())}
    }
    #[test]fn gated_switch_wires_exact_mapper_transition_to_verified_peer_release(){
      let e=expected();let mut b=Mock::new();let mut p=GateMock{ready:true,auth:true,released:false};
      assert_eq!(gated_switch::switch(&mut b,&e,&mut p,10).unwrap(),"REPORT W=5");
      assert!(p.released);assert_eq!(b.effects,vec![Action::Suspend,Action::LoadError,Action::Resume]);
    }
    #[test]fn gated_switch_never_releases_after_bad_identity_or_failed_transition(){
      let e=expected();for (ready,auth,tamper) in [(false,true,false),(true,false,false),(true,true,true)]{
       let mut b=Mock::new();if tamper{b.tamper_at=Some(1)}let mut p=GateMock{ready,auth,released:false};
       assert!(gated_switch::switch(&mut b,&e,&mut p,10).is_err());assert!(!p.released);assert!(b.effects.is_empty());
      }
    }

    impl super::diagnostic_fault::RecordedBackend for Mock {fn diagnostic_record(&mut self,_:super::diagnostic_receipt::Record)->Result<(),()>{Ok(())}fn fault_budget(&self,n:u64)->Result<(),()>{if self.budget_ms>=n{Ok(())}else{Err(())}}}
    struct FaultPeer{fail:bool,released:bool}
    impl super::diagnostic_fault::Peer for FaultPeer {fn ready(&mut self)->Result<(),()>{Ok(())}fn authorize(&mut self,_:u32)->Result<(),()>{Ok(())}fn release(&mut self)->Result<String,()>{self.released=true;if self.fail{Err(())}else{Ok("REPORT W=5".into())}}fn finish(&mut self)->Result<(),()>{Ok(())}}
    struct FaultStage;impl super::diagnostic_fault::Stage for FaultStage {fn prepare(&mut self)->Result<u32,()>{Ok(10)}fn begin(&mut self)->Result<(),()>{Ok(())}fn finish(&mut self,_:&str)->Result<(),()>{Ok(())}}
    struct CountingStage{prepared:bool,begun:bool}impl super::diagnostic_fault::Stage for CountingStage {fn prepare(&mut self)->Result<u32,()>{self.prepared=true;Ok(10)}fn begin(&mut self)->Result<(),()>{self.begun=true;Ok(())}fn finish(&mut self,_:&str)->Result<(),()>{Ok(())}}
    #[test]fn insufficient_fault_budget_stops_before_stage_gate(){let e=expected();let mut b=Mock::new();b.budget_ms=44_999;let mut p=FaultPeer{fail:false,released:false};let mut s=CountingStage{prepared:false,begun:false};assert!(super::diagnostic_fault::run(&mut b,&e,&mut p,&mut s).is_err());assert!(!s.prepared&&!s.begun&&!p.released&&b.effects.is_empty());}
    #[test]fn diagnostic_fault_restores_only_after_complete_peer_report(){let e=expected();let mut b=Mock::new();let mut p=FaultPeer{fail:false,released:false};assert_eq!(super::diagnostic_fault::run(&mut b,&e,&mut p,&mut FaultStage),Ok("REPORT W=5".into()));assert!(p.released);assert_eq!(b.effects,vec![Action::Suspend,Action::LoadError,Action::Resume,Action::Suspend,Action::LoadLinear,Action::Resume]);let mut b=Mock::new();let mut p=FaultPeer{fail:true,released:false};assert!(super::diagnostic_fault::run(&mut b,&e,&mut p,&mut FaultStage).is_err());assert!(p.released);assert!(!b.effects.contains(&Action::LoadLinear));}
}
