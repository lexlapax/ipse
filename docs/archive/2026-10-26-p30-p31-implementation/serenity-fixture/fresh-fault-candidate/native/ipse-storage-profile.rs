//! Explicit allocation profiles for newly created, dense, write-only files.
//! Unknown kernels/filesystems refuse; observed allocation is never an estimate.
use std::fs::File;
#[cfg(all(target_os = "linux", target_pointer_width = "64"))]
use std::io::Read;
#[cfg(all(target_os = "linux", target_pointer_width = "64"))]
use std::path::Path;

#[derive(Debug, PartialEq)]
pub(crate) enum TransactionAllowanceError { Unsupported, Capacity, Unsafe }

#[cfg(all(target_os = "linux", target_pointer_width = "64"))]
fn bounded(path: &Path, maximum: usize) -> Result<String, TransactionAllowanceError> {
    let mut bytes = Vec::new();
    File::open(path).map_err(|_| TransactionAllowanceError::Unsupported)?
        .take(maximum as u64 + 1).read_to_end(&mut bytes)
        .map_err(|_| TransactionAllowanceError::Unsupported)?;
    if bytes.len() > maximum { return Err(TransactionAllowanceError::Unsupported); }
    String::from_utf8(bytes).map_err(|_| TransactionAllowanceError::Unsupported)
}

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn supported_kernel(release: &str) -> bool {
    // This finite profile is tied to the inspected upstream 7.2.10 implementation.
    // A broader kernel or platform contract needs independent review/qualification.
    release.trim() == "7.2.11-arch1-1" || release.trim() == "7.2.10" || release.trim().starts_with("7.2.10-")
}

fn allowance(unit: u64, lengths: &[u64]) -> Result<u64, TransactionAllowanceError> {
    if !unit.is_power_of_two() || !(4096..=65_536).contains(&unit) || lengths.len() > 256 {
        return Err(TransactionAllowanceError::Unsupported);
    }
    let mut sum = 0u64;
    let mut reserve = 0u64;
    for length in lengths {
        if !(1..=8 * 1024 * 1024).contains(length) { return Err(TransactionAllowanceError::Unsafe); }
        sum = sum.checked_add(*length).ok_or(TransactionAllowanceError::Unsafe)?;
        let rounded = length.checked_add(unit - 1).ok_or(TransactionAllowanceError::Unsafe)? / unit * unit;
        reserve = reserve.checked_add(rounded.checked_mul(2).ok_or(TransactionAllowanceError::Unsafe)?)
            .ok_or(TransactionAllowanceError::Unsafe)?;
    }
    if sum > 64 * 1024 * 1024 { return Err(TransactionAllowanceError::Unsafe); }
    Ok(reserve)
}

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn selected_policy(global: &str) -> Result<(), TransactionAllowanceError> {
    let selected: Vec<_> = global.split_whitespace().filter_map(|v| v.strip_prefix('[')?.strip_suffix(']')).collect();
    if selected.len() == 1 && matches!(selected[0], "never" | "deny" | "advise" | "within_size" | "always") {
        Ok(())
    } else { Err(TransactionAllowanceError::Unsupported) }
}

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn mount_policy(fdinfo: &str, mounts: &str) -> Result<(), TransactionAllowanceError> {
    let ids: Vec<_> = fdinfo.lines().filter_map(|line| {
        let (key, value) = line.split_once(':')?;
        if key == "mnt_id" { value.trim().parse::<u64>().ok() } else { None }
    }).collect();
    if ids.len() != 1 || ids[0] == 0 { return Err(TransactionAllowanceError::Unsupported); }
    let mut matched = 0;
    for line in mounts.lines() {
        let Some((left, right)) = line.split_once(" - ") else { return Err(TransactionAllowanceError::Unsupported) };
        let fields: Vec<_> = left.split_whitespace().collect();
        if fields.first().and_then(|v| v.parse::<u64>().ok()) != Some(ids[0]) { continue; }
        let rest: Vec<_> = right.split_whitespace().collect();
        if fields.len() < 6 || rest.len() != 3 || rest[0] != "tmpfs" { return Err(TransactionAllowanceError::Unsupported); }
        let policies: Vec<_> = fields[5].split(',').chain(rest[2].split(','))
            .filter_map(|v| v.strip_prefix("huge=")).collect();
        if policies.len() != 1 || !matches!(policies[0], "never" | "advise") {
            return Err(TransactionAllowanceError::Unsupported);
        }
        matched += 1;
    }
    if matched == 1 { Ok(()) } else { Err(TransactionAllowanceError::Unsupported) }
}

#[cfg(all(target_os = "linux", target_pointer_width = "64"))]
fn unit(directory: &File) -> Result<u64, TransactionAllowanceError> {
    use std::ffi::{c_int, c_long};
    use std::os::fd::AsRawFd;
    #[repr(C)]
    struct StatFs {
        kind: c_long, block: c_long, blocks: u64, free: u64, available: u64,
        files: u64, files_free: u64, fsid: [i32; 2], names: c_long,
        fragment: c_long, flags: c_long, spare: [c_long; 4],
    }
    extern "C" { fn fstatfs(fd: c_int, stat: *mut usize) -> c_int; fn sysconf(name: c_int) -> c_long; }
    let mut stat = std::mem::MaybeUninit::<StatFs>::uninit();
    if unsafe { fstatfs(directory.as_raw_fd(), stat.as_mut_ptr().cast()) } != 0 {
        return Err(TransactionAllowanceError::Unsupported);
    }
    let stat = unsafe { stat.assume_init() };
    if stat.block <= 0 || stat.fragment != stat.block { return Err(TransactionAllowanceError::Unsupported); }
    let unit = stat.block as u64;
    allowance(unit, &[])?;
    if !supported_kernel(&bounded(Path::new("/proc/sys/kernel/osrelease"), 256)?) {
        return Err(TransactionAllowanceError::Unsupported);
    }
    match stat.kind as u64 {
        0x9123_683e => (), // Btrfs sectorsize; directory blocks are checked separately.
        0x0102_1994 => {
            if unsafe { sysconf(30) } != stat.block { return Err(TransactionAllowanceError::Unsupported); }
            selected_policy(&bounded(Path::new("/sys/kernel/mm/transparent_hugepage/shmem_enabled"), 4096)?)?;
            mount_policy(&bounded(Path::new(&format!("/proc/self/fdinfo/{}", directory.as_raw_fd())), 4096)?,
                &bounded(Path::new("/proc/self/mountinfo"), 1_048_576)?)?;
        }
        _ => return Err(TransactionAllowanceError::Unsupported),
    }
    Ok(unit)
}

#[cfg(not(all(target_os = "linux", target_pointer_width = "64")))]
fn unit(_: &File) -> Result<u64, TransactionAllowanceError> { Err(TransactionAllowanceError::Unsupported) }

pub(crate) fn reserve(directory: &File, lengths: &[u64]) -> Result<u64, TransactionAllowanceError> {
    allowance(unit(directory)?, lengths)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lengths_are_rounded_with_runtime_unit_and_checked_before_allocation() {
        assert_eq!(allowance(4096, &[1, 6144, 8192]), Ok(40_960));
        assert_eq!(allowance(65_536, &[1, 6144]), Ok(262_144));
        assert_eq!(allowance(4096, &[]), Ok(0));
        assert_eq!(allowance(4096, &[0]), Err(TransactionAllowanceError::Unsafe));
        assert_eq!(allowance(4096, &[8 * 1024 * 1024 + 1]), Err(TransactionAllowanceError::Unsafe));
        assert!(allowance(4096, &[1; 257]).is_err());
        assert!(allowance(3000, &[1]).is_err());
    }
    #[test]
    fn forced_huge_unknown_mounts_and_unreviewed_kernels_refuse() {
        let fd = "pos:\t0\nmnt_id:\t42\n";
        let mount = "42 1 0:2 / /tmp rw - tmpfs tmpfs rw,huge=advise";
        assert_eq!(mount_policy(fd, mount), Ok(()));
        assert!(mount_policy(fd, &mount.replace("advise", "always")).is_err());
        assert!(mount_policy(fd, &mount.replace("advise", "within_size")).is_err());
        assert!(mount_policy("mnt_id: 7", mount).is_err());
        assert!(mount_policy("mnt_id: 42\nmnt_id: 42", mount).is_err());
        assert!(mount_policy(fd, &mount.replace(",huge=advise", "")).is_err());
        assert!(selected_policy("always [force] never").is_err());
        assert!(selected_policy("[advise] [never]").is_err());
        assert_eq!(selected_policy("always [advise] never force"), Ok(()));
        assert!(supported_kernel("7.2.10-arch1-1\n"));
        assert!(!supported_kernel("7.2.100"));
        assert!(!supported_kernel("7.3.0"));
    }
}
