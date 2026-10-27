//! Pure identity checks for a proposed disposable Serenity block-fault fixture.
//! No production kernel profile is changed by this code. This file does not
//! invoke commands or mutate devices. It requires an independently reviewed
//! runner that handles device selection, namespace lifetime and crash cleanup.

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Expected {
    pub(crate) loop_major: u64,
    pub(crate) loop_minor: u64,
    pub(crate) backing_major: u64,
    pub(crate) backing_minor: u64,
    pub(crate) backing_inode: u64,
    pub(crate) loop_ref: String,
    pub(crate) dm_name: String,
    pub(crate) dm_uuid: String,
    pub(crate) dm_major: u64,
    pub(crate) dm_minor: u64,
    pub(crate) sectors: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Table { Linear, Error }

fn num(value: &str) -> Option<u64> {
    if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) { return None; }
    value.parse().ok()
}
fn dev(value: &str) -> Option<(u64, u64)> {
    let (major, minor) = value.split_once(':')?;
    Some((num(major)?, num(minor)?))
}
fn fields<'a>(line: &'a str, expected: usize) -> Option<Vec<&'a str>> {
    if line.contains('\n') || line.contains('\r') || line.len() > 2048 { return None; }
    let values: Vec<_> = line.split('|').map(str::trim).collect();
    if values.len() != expected || values.iter().any(|x| x.is_empty()) { return None; }
    Some(values)
}
fn name_ok(name: &str, prefix: &str) -> bool {
    let Some(suffix) = name.strip_prefix(prefix) else { return false; };
    suffix.len() == 32 && suffix.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
}
fn expected_ok(e: &Expected) -> bool {
    name_ok(&e.dm_name, "ipse-q-") && name_ok(&e.dm_uuid, "IPSE-Q-") &&
    e.dm_name[7..] == e.dm_uuid[7..] && e.loop_ref == e.dm_name &&
    e.loop_major == 7 && e.backing_inode != 0 && e.sectors > 0 &&
    e.sectors <= 1_048_576 && e.dm_major != e.loop_major
}

/// Expected losetup fields: BACK-INO,BACK-MAJ:MIN,MAJ:MIN,OFFSET,SIZELIMIT,RO,REF.
/// Use one `losetup --list --raw --noheadings --output ...` invocation; the
/// raw output is whitespace-delimited and is normalized by the caller to '|'.
/// `REF` must be a nonempty nonce without whitespace. Never join values from
/// multiple observations and pretend they came from one atomic snapshot.
/// This asserts output meaning, not atomicity with a later ioctl.
pub(crate) fn loop_matches(e: &Expected, line: &str) -> bool {
    let Some(v) = fields(line, 7) else { return false; };
    expected_ok(e) && num(v[0]) == Some(e.backing_inode) &&
    dev(v[1]) == Some((e.backing_major, e.backing_minor)) &&
    dev(v[2]) == Some((e.loop_major, e.loop_minor)) && num(v[3]) == Some(0) &&
    num(v[4]) == Some(e.sectors * 512) && v[5] == "0" && v[6] == e.loop_ref
}

/// Expected dmsetup info fields: name,uuid,major,minor,open, separated by '|'.
pub(crate) fn mapper_matches(e: &Expected, line: &str, require_closed: bool) -> bool {
    let Some(v) = fields(line, 5) else { return false; };
    expected_ok(e) && v[0] == e.dm_name && v[1] == e.dm_uuid &&
    num(v[2]) == Some(e.dm_major) && num(v[3]) == Some(e.dm_minor) &&
    num(v[4]).is_some_and(|opens| !require_closed || opens == 0)
}

/// Enforce one whole-device target; never accept extra regions or a host device.
pub(crate) fn table_matches(e: &Expected, line: &str, wanted: Table) -> bool {
    if !expected_ok(e) || line.contains('\n') || line.contains('\r') || line.len() > 512 {
        return false;
    }
    let v: Vec<_> = line.split_ascii_whitespace().collect();
    match wanted {
        Table::Linear => v.len() == 5 && num(v[0]) == Some(0) &&
            num(v[1]) == Some(e.sectors) && v[2] == "linear" &&
            dev(v[3]) == Some((e.loop_major, e.loop_minor)) && num(v[4]) == Some(0),
        Table::Error => v.len() == 3 && num(v[0]) == Some(0) &&
            num(v[1]) == Some(e.sectors) && v[2] == "error",
    }
}

/// The controller may only advance after an independently obtained successful
/// observation. Every effect has a durable pending state first; an interrupted
/// effect never gets replayed automatically. Recovery is an operator action.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Phase {
    Prepared, LoopPending, LoopVerified, MapperPending, LinearVerified,
    MountPending, Mounted, WriterReady, FaultPending, ErrorVerified,
    RestorePending, Restored, ObservationComplete, UnmountPending, Unmounted,
    RemovePending, MapperRemoved, DetachPending, Detached, Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Event {
    BeginLoop, ConfirmLoop, BeginMapper, ConfirmLinear, BeginMount, ConfirmMount,
    ConfirmWriterReady, BeginFault, ConfirmError, BeginRestore, ConfirmRestored,
    ConfirmObservation, BeginUnmount, ConfirmUnmount, BeginRemove, ConfirmRemoved,
    BeginDetach, ConfirmDetached, Interrupted,
}
pub(crate) fn advance(phase: Phase, event: Event) -> Option<Phase> {
    use Event::*;
    use Phase::*;
    match (phase, event) {
        (_, Interrupted) => Some(Unknown),
        (Prepared, BeginLoop) => Some(LoopPending),
        (LoopPending, ConfirmLoop) => Some(LoopVerified),
        (LoopVerified, BeginMapper) => Some(MapperPending),
        (MapperPending, ConfirmLinear) => Some(LinearVerified),
        (LinearVerified, BeginMount) => Some(MountPending),
        (MountPending, ConfirmMount) => Some(Mounted),
        (Mounted, ConfirmWriterReady) => Some(WriterReady),
        (WriterReady, BeginFault) => Some(FaultPending),
        (FaultPending, ConfirmError) => Some(ErrorVerified),
        (ErrorVerified, BeginRestore) => Some(RestorePending),
        (RestorePending, ConfirmRestored) => Some(Restored),
        (Restored, ConfirmObservation) => Some(ObservationComplete),
        (ObservationComplete, BeginUnmount) => Some(UnmountPending),
        (UnmountPending, ConfirmUnmount) => Some(Unmounted),
        (Unmounted, BeginRemove) => Some(RemovePending),
        (RemovePending, ConfirmRemoved) => Some(MapperRemoved),
        (MapperRemoved, BeginDetach) => Some(DetachPending),
        (DetachPending, ConfirmDetached) => Some(Detached),
        _ => None,
    }
}

/// Pure mock of fault-switch planning only: never invokes dmsetup. A real
/// controller must persist each pending transition and obtain fresh checks at
/// each effect boundary; these observations are deliberately not sufficient
/// to authorize a real ioctl.
#[cfg(test)]
fn mock_fault_commands(e: &Expected, loop_row: &str, mapper_row: &str,
                       table_row: &str, phase: Phase) -> Option<Vec<Vec<String>>> {
    if phase != Phase::WriterReady || !loop_matches(e, loop_row) ||
        !mapper_matches(e, mapper_row, false) || !table_matches(e, table_row, Table::Linear) {
        return None;
    }
    let error_table = format!("0 {} error", e.sectors);
    Some(vec![
        vec!["suspend".into(), "--noflush".into(), "--nolockfs".into(), e.dm_name.clone()],
        vec!["reload".into(), e.dm_name.clone(), "--table".into(), error_table],
        vec!["resume".into(), e.dm_name.clone()],
    ])
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample() -> Expected {
        let nonce = "0123456789abcdef0123456789abcdef";
        Expected { loop_major: 7, loop_minor: 42, backing_major: 0, backing_minor: 37,
            backing_inode: 221, loop_ref: format!("ipse-q-{nonce}"),
            dm_name: format!("ipse-q-{nonce}"), dm_uuid: format!("IPSE-Q-{nonce}"),
            dm_major: 253, dm_minor: 11, sectors: 1_048_576 }
    }
    fn loop_line() -> String {
        format!("221|0:37|7:42|0|536870912|0|ipse-q-0123456789abcdef0123456789abcdef")
    }
    fn dm_line(open: u32) -> String {
        format!("ipse-q-0123456789abcdef0123456789abcdef|IPSE-Q-0123456789abcdef0123456789abcdef|253|11|{open}")
    }
    #[test] fn correct_loop_and_mapper_accepted() {
        let e = sample();
        assert!(loop_matches(&e, &loop_line()));
        assert!(mapper_matches(&e, &dm_line(1), false));
        assert!(!mapper_matches(&e, &dm_line(1), true));
        assert!(mapper_matches(&e, &dm_line(0), true));
    }
    #[test] fn changed_backing_device_inode_range_reference_or_loop_refuses() {
        let e = sample(); let row = loop_line();
        for (a,b) in [("221|", "222|"), ("0:37", "0:38"), ("7:42", "7:43"),
                       ("|0|536", "|1|536"), ("536870912", "536870911"),
                       ("|0|ipse", "|1|ipse"), ("abcdef", "abcdee")] {
            assert!(!loop_matches(&e, &row.replacen(a,b,1)), "{a}");
        }
        assert!(!loop_matches(&e, &(row.clone() + "\n" + &row)));
        assert!(!loop_matches(&e, &(row + "|extra")));
    }
    #[test] fn mapper_rejects_wrong_uuid_device_names_opens_and_multiline() {
        let e = sample(); let row = dm_line(0);
        for (a,b) in [("IPSE-Q-", "IPSE-X-"), ("ipse-q-", "ipse-x-"),
                       ("|253|11|", "|253|12|"), ("|0", "|x")] {
            assert!(!mapper_matches(&e, &row.replacen(a,b,1), true), "{a}");
        }
        assert!(!mapper_matches(&e, &(row.clone() + "\n" + &row), true));
    }
    #[test] fn exact_linear_and_error_tables_only() {
        let e = sample();
        assert!(table_matches(&e, "0 1048576 linear 7:42 0", Table::Linear));
        assert!(table_matches(&e, "0 1048576 error", Table::Error));
        for row in ["0 1048575 linear 7:42 0", "0 1048576 linear 259:3 0",
                    "0 1048576 linear 7:42 1", "1 1048576 linear 7:42 0",
                    "0 1048576 linear 7:42 0\n0 1 error", "0 1048576 error extra"] {
            assert!(!table_matches(&e, row, Table::Linear));
            assert!(!table_matches(&e, row, Table::Error));
        }
    }
    #[test] fn forged_or_mismatched_nonces_and_oversized_device_refuse() {
        let mut e = sample(); e.dm_uuid.replace_range(7..8, "f");
        assert!(!loop_matches(&e, &loop_line()));
        let mut e = sample(); e.sectors += 1;
        assert!(!loop_matches(&e, &loop_line()));
        let mut e = sample(); e.dm_name.replace_range(7..8, "F");
        assert!(!expected_ok(&e));
    }
    #[test] fn mock_fault_sequence_requires_confirmed_boundaries() {
        use Event::*; use Phase::*;
        let mut state = Prepared;
        for event in [BeginLoop, ConfirmLoop, BeginMapper, ConfirmLinear,
            BeginMount, ConfirmMount, ConfirmWriterReady, BeginFault,
            ConfirmError, BeginRestore, ConfirmRestored, ConfirmObservation,
            BeginUnmount, ConfirmUnmount, BeginRemove, ConfirmRemoved,
            BeginDetach, ConfirmDetached] {
            state = advance(state, event).expect("valid transition");
        }
        assert_eq!(state, Detached);
        assert_eq!(advance(FaultPending, BeginFault), None);
        assert_eq!(advance(FaultPending, BeginRestore), None);
        assert_eq!(advance(Mounted, BeginFault), None);
        assert_eq!(advance(UnmountPending, BeginRemove), None);
        assert_eq!(advance(FaultPending, Interrupted), Some(Unknown));
        assert_eq!(advance(Unknown, BeginRestore), None);
        assert_eq!(advance(Unknown, BeginRemove), None);
    }
    #[test] fn mock_switch_emits_only_exact_name_and_bounded_error_table() {
        let e = sample(); let linear = "0 1048576 linear 7:42 0";
        let actions = mock_fault_commands(&e, &loop_line(), &dm_line(1), linear,
                                          Phase::WriterReady).unwrap();
        assert_eq!(actions[0], ["suspend", "--noflush", "--nolockfs", &e.dm_name]);
        assert_eq!(actions[1], ["reload", &e.dm_name, "--table", "0 1048576 error"]);
        assert_eq!(actions[2], ["resume", &e.dm_name]);
        assert!(mock_fault_commands(&e, &loop_line(), &dm_line(1), linear,
                                    Phase::FaultPending).is_none());
        assert!(mock_fault_commands(&e, &loop_line(), &dm_line(1),
                                    "0 1048576 linear 259:3 0", Phase::WriterReady).is_none());
        assert!(mock_fault_commands(&e, &loop_line(), &dm_line(0).replace("|253|11|", "|253|12|"),
                                    linear, Phase::WriterReady).is_none());
    }
}
