//! Linux/glibc x86-64 test-process wall clock. Never linked into Ipse.
//!
//! Compile as a cdylib and preload only into an isolated synthetic cohort.
//! IPSE_TEST_CLOCK_OFFSET_MS is fixed before exec; changing it during a process
//! is unsupported. Monotonic clocks and the kernel's clock remain unchanged.

#[cfg(not(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu")))]
compile_error!("the process-clock fixture supports only Linux/glibc x86-64");

use std::ffi::{c_char, c_int, c_long, c_void};
use std::sync::OnceLock;

const MAX_OFFSET_MS: i64 = 500 * 86_400_000;
const SYS_CLOCK_GETTIME: c_long = 228;
const SYS_GETTIMEOFDAY: c_long = 96;

#[repr(C)]
pub struct ClockValue {
    seconds: i64,
    fraction: i64,
}

extern "C" {
    fn syscall(number: c_long, ...) -> c_long;
    fn getenv(name: *const c_char) -> *const c_char;
    fn __errno_location() -> *mut c_int;
}

static OFFSET: OnceLock<Option<i64>> = OnceLock::new();

fn offset_ms() -> Option<i64> {
    *OFFSET.get_or_init(|| {
        // This fixture owns a fixed startup environment, not a runtime clock API.
        let value = unsafe { getenv(c"IPSE_TEST_CLOCK_OFFSET_MS".as_ptr()) };
        if value.is_null() {
            return None;
        }
        let mut result = 0_i64;
        for index in 0..=11 {
            let byte = unsafe { *value.add(index) } as u8;
            if byte == 0 {
                return (index > 0 && result <= MAX_OFFSET_MS).then_some(result);
            }
            if !byte.is_ascii_digit() || index == 11 {
                return None;
            }
            result = result
                .checked_mul(10)?
                .checked_add(i64::from(byte - b'0'))?;
        }
        None
    })
}

fn invalid() -> c_int {
    unsafe { *__errno_location() = 22 };
    -1
}

unsafe fn advance(value: *mut ClockValue, offset: i64, units: i64) -> c_int {
    let value = &mut *value;
    let fraction = value.fraction + offset % 1000 * (units / 1000);
    let Some(seconds) = value
        .seconds
        .checked_add(offset / 1000)
        .and_then(|seconds| seconds.checked_add(fraction / units))
    else {
        return invalid();
    };
    value.seconds = seconds;
    value.fraction = fraction % units;
    0
}

/// # Safety
/// The caller supplies the ordinary libc clock_gettime ABI and writable output.
#[no_mangle]
pub unsafe extern "C" fn clock_gettime(clock: c_int, value: *mut ClockValue) -> c_int {
    // Raw syscalls avoid recursive dynamic symbol resolution. Clock IDs other
    // than realtime and realtime-coarse retain the kernel's exact behavior.
    if clock != 0 && clock != 5 {
        return syscall(SYS_CLOCK_GETTIME, clock, value) as c_int;
    }
    let Some(offset) = offset_ms() else {
        return invalid();
    };
    let result = syscall(SYS_CLOCK_GETTIME, clock, value) as c_int;
    if result != 0 {
        return result;
    }
    advance(value, offset, 1_000_000_000)
}

/// # Safety
/// The caller supplies the ordinary libc gettimeofday ABI and writable outputs.
#[no_mangle]
pub unsafe extern "C" fn gettimeofday(value: *mut ClockValue, zone: *mut c_void) -> c_int {
    let Some(offset) = offset_ms() else {
        return invalid();
    };
    let result = syscall(SYS_GETTIMEOFDAY, value, zone) as c_int;
    if result != 0 || value.is_null() {
        return result;
    }
    advance(value, offset, 1_000_000)
}

/// # Safety
/// A nonnull pointer must be writable as required by libc time(3).
#[no_mangle]
pub unsafe extern "C" fn time(destination: *mut i64) -> i64 {
    let mut value = ClockValue {
        seconds: 0,
        fraction: 0,
    };
    if clock_gettime(0, &mut value) != 0 {
        return -1;
    }
    if !destination.is_null() {
        *destination = value.seconds;
    }
    value.seconds
}
