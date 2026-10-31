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
#[derive(Clone, Copy, Debug, PartialEq)]
enum KernelProfile { Linux7210, Linux7211ArchTmpfs }

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn kernel_profile(release: &str) -> Option<KernelProfile> {
    let release = release.trim();
    if release == "7.2.10" || release.starts_with("7.2.10-") {
        Some(KernelProfile::Linux7210)
    } else if release == "7.2.11-arch1-1" && cfg!(target_arch = "x86_64") {
        // Qualified only for the exact tmpfs features checked below. In
        // particular, this does not admit Btrfs on this newer kernel.
        Some(KernelProfile::Linux7211ArchTmpfs)
    } else { None }
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
fn selected_policy(global: &str) -> Result<&str, TransactionAllowanceError> {
    let selected: Vec<_> = global.split_whitespace().filter_map(|v| v.strip_prefix('[')?.strip_suffix(']')).collect();
    if selected.len() == 1 && matches!(selected[0], "never" | "deny" | "advise" | "within_size" | "always") {
        Ok(selected[0])
    } else { Err(TransactionAllowanceError::Unsupported) }
}

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn mount_policy<'a>(fdinfo: &str, mounts: &'a str) -> Result<&'a str, TransactionAllowanceError> {
    let ids: Vec<_> = fdinfo.lines().filter_map(|line| {
        let (key, value) = line.split_once(':')?;
        if key == "mnt_id" { value.trim().parse::<u64>().ok() } else { None }
    }).collect();
    if ids.len() != 1 || ids[0] == 0 { return Err(TransactionAllowanceError::Unsupported); }
    let mut matched = 0;
    let mut policy = None;
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
        policy = Some(policies[0]);
    }
    if matched == 1 { Ok(policy.unwrap()) } else { Err(TransactionAllowanceError::Unsupported) }
}

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn filesystem_supported(profile: KernelProfile, kind: u64) -> bool {
    match kind {
        0x9123_683e => profile == KernelProfile::Linux7210,
        0x0102_1994 => true,
        _ => false,
    }
}

#[cfg(any(all(target_os = "linux", target_pointer_width = "64"), test))]
fn tmpfs_policy(profile: KernelProfile, unit: u64, page: i64, global: &str, fdinfo: &str, mounts: &str)
    -> Result<(), TransactionAllowanceError> {
    if page <= 0 || page as u64 != unit { return Err(TransactionAllowanceError::Unsupported); }
    let selected = selected_policy(global)?;
    let mounted = mount_policy(fdinfo, mounts)?;
    if profile == KernelProfile::Linux7211ArchTmpfs &&
        (unit != 4096 || selected != "advise" || mounted != "advise") {
        return Err(TransactionAllowanceError::Unsupported);
    }
    Ok(())
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
    let profile = kernel_profile(&bounded(Path::new("/proc/sys/kernel/osrelease"), 256)?)
        .ok_or(TransactionAllowanceError::Unsupported)?;
    if !filesystem_supported(profile, stat.kind as u64) { return Err(TransactionAllowanceError::Unsupported); }
    match stat.kind as u64 {
        0x9123_683e => (), // Btrfs sectorsize; directory blocks are checked separately.
        0x0102_1994 => {
            tmpfs_policy(profile, unit, unsafe { sysconf(30) } as i64,
                &bounded(Path::new("/sys/kernel/mm/transparent_hugepage/shmem_enabled"), 4096)?,
                &bounded(Path::new(&format!("/proc/self/fdinfo/{}", directory.as_raw_fd())), 4096)?,
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
        assert_eq!(mount_policy(fd, mount), Ok("advise"));
        assert!(mount_policy(fd, &mount.replace("advise", "always")).is_err());
        assert!(mount_policy(fd, &mount.replace("advise", "within_size")).is_err());
        assert!(mount_policy("mnt_id: 7", mount).is_err());
        assert!(mount_policy("mnt_id: 42\nmnt_id: 42", mount).is_err());
        assert!(mount_policy(fd, &mount.replace(",huge=advise", "")).is_err());
        assert!(selected_policy("always [force] never").is_err());
        assert!(selected_policy("[advise] [never]").is_err());
        assert_eq!(selected_policy("always [advise] never force"), Ok("advise"));
        assert_eq!(kernel_profile("7.2.10-arch1-1\n"), Some(KernelProfile::Linux7210));
        assert_eq!(kernel_profile("7.2.100"), None);
        assert_eq!(kernel_profile("7.3.0"), None);
    }
    #[test]
    fn exact_new_kernel_admits_only_qualified_tmpfs_features() {
        let p = KernelProfile::Linux7211ArchTmpfs;
        let fd = "pos:\t0\nmnt_id:\t42\n";
        let mount = "42 1 0:2 / /tmp rw - tmpfs tmpfs rw,huge=advise";
        if cfg!(target_arch = "x86_64") {
            assert_eq!(kernel_profile("7.2.11-arch1-1\n"), Some(p));
        }
        for release in ["7.2.11", "7.2.11-arch1-2", "7.2.11-arch2-1", "7.2.11-arch1-1-extra", "7.2.110-arch1-1"] {
            assert_eq!(kernel_profile(release), None);
        }
        assert!(filesystem_supported(p, 0x0102_1994));
        assert!(!filesystem_supported(p, 0x9123_683e));
        assert!(!filesystem_supported(p, 0xef53));
        assert_eq!(tmpfs_policy(p, 4096, 4096, "always [advise] never force", fd, mount), Ok(()));
        for (unit, page) in [(8192,8192),(4096,8192),(8192,4096),(4096,-1)] {
            assert!(tmpfs_policy(p, unit, page, "[advise]", fd, mount).is_err());
        }
        for selected in ["[always]", "[never]", "[within_size]", "[deny]", "[force]", "[advise] [never]", "advise"] {
            assert!(tmpfs_policy(p, 4096, 4096, selected, fd, mount).is_err());
        }
        for mounted in ["never", "always", "within_size", "deny", "force"] {
            assert!(tmpfs_policy(p, 4096, 4096, "[advise]", fd, &mount.replace("advise", mounted)).is_err());
        }
        assert!(tmpfs_policy(p,4096,4096,"[advise]","mnt_id: 41",mount).is_err());
        assert!(tmpfs_policy(p,4096,4096,"[advise]",fd,&mount.replace("tmpfs tmpfs", "ext4 /dev/sda1")).is_err());
        // Preserve the older profile's broader reviewed policy choices.
        assert!(filesystem_supported(KernelProfile::Linux7210,0x9123_683e));
        assert_eq!(tmpfs_policy(KernelProfile::Linux7210,8192,8192,"[always]",fd,&mount.replace("advise","never")),Ok(()));
    }
}
