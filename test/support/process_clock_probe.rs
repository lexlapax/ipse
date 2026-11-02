//! Direct libc, Rust standard-library and raw-kernel observations for the
//! isolated process-clock fixture. This executable never starts Ipse.

use std::ffi::{c_int, c_long, c_void};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[repr(C)]
#[derive(Default)]
struct ClockValue {
    seconds: i64,
    fraction: i64,
}

extern "C" {
    fn clock_gettime(clock: c_int, value: *mut ClockValue) -> c_int;
    fn gettimeofday(value: *mut ClockValue, zone: *mut c_void) -> c_int;
    fn time(value: *mut i64) -> i64;
    fn syscall(number: c_long, ...) -> c_long;
    fn __errno_location() -> *mut c_int;
}

fn raw_ms(clock: c_int) -> i64 {
    let mut value = ClockValue::default();
    assert_eq!(
        unsafe { syscall(228, clock, &mut value as *mut ClockValue) },
        0
    );
    value.seconds * 1000 + value.fraction / 1_000_000
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--invalid") {
        let mut value = ClockValue::default();
        assert_eq!(unsafe { clock_gettime(0, &mut value) }, -1);
        assert_eq!(unsafe { *__errno_location() }, 22);
        assert_eq!(
            unsafe { gettimeofday(&mut value, std::ptr::null_mut()) },
            -1
        );
        assert_eq!(unsafe { *__errno_location() }, 22);
        assert_eq!(unsafe { time(std::ptr::null_mut()) }, -1);
        assert_eq!(unsafe { *__errno_location() }, 22);
        assert_eq!(unsafe { clock_gettime(1, &mut value) }, 0);
        println!("invalid_offset_refused=1");
        return;
    }

    let offset: i64 = std::env::var("IPSE_TEST_CLOCK_OFFSET_MS")
        .unwrap()
        .parse()
        .unwrap();
    let before = raw_ms(0);
    let mut wall = ClockValue::default();
    assert_eq!(unsafe { clock_gettime(0, &mut wall) }, 0);
    let wall_ms = wall.seconds * 1000 + wall.fraction / 1_000_000;
    let rust_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64;
    let mut coarse = ClockValue::default();
    assert_eq!(unsafe { clock_gettime(5, &mut coarse) }, 0);
    let coarse_ms = coarse.seconds * 1000 + coarse.fraction / 1_000_000;
    let mut timeval = ClockValue::default();
    assert_eq!(
        unsafe { gettimeofday(&mut timeval, std::ptr::null_mut()) },
        0
    );
    let timeval_ms = timeval.seconds * 1000 + timeval.fraction / 1000;
    let mut seconds = 0_i64;
    assert_eq!(unsafe { time(&mut seconds) }, seconds);
    let after = raw_ms(0);
    for value in [wall_ms, rust_ms, timeval_ms] {
        assert!((before + offset..=after + offset).contains(&value));
    }
    assert!((before + offset - 100..=after + offset).contains(&coarse_ms));
    assert!(((before + offset) / 1000..=(after + offset) / 1000).contains(&seconds));

    let mono_before = raw_ms(1);
    let mut mono = ClockValue::default();
    assert_eq!(unsafe { clock_gettime(1, &mut mono) }, 0);
    let mono_ms = mono.seconds * 1000 + mono.fraction / 1_000_000;
    let mono_after = raw_ms(1);
    assert!((mono_before..=mono_after).contains(&mono_ms));
    let instant = Instant::now();
    let raw_start = raw_ms(1);
    std::thread::sleep(Duration::from_millis(80));
    let instant_ms = instant.elapsed().as_millis() as i64;
    let raw_elapsed = raw_ms(1) - raw_start;
    assert!(instant_ms >= 60 && (instant_ms - raw_elapsed).abs() <= 20);
    println!("raw_wall_before_ms={before}\nraw_wall_after_ms={after}\nwall_ms={wall_ms}\nrust_ms={rust_ms}\nmonotonic_sleep_ms={instant_ms}");
}
