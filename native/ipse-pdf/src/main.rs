use lopdf::{Document, LoadOptions, Object};
use std::io::{Read, Write};
use std::time::{Duration, Instant};

const INPUT: usize = 16 * 1024 * 1024;
const EXPANDED: usize = 32 * 1024 * 1024;
const TEXT: usize = 1024 * 1024;
const PAGES: usize = 256;
const OUTPUT: usize = TEXT + PAGES * 9 + 13;
const MAGIC_IN: &[u8; 8] = b"IPDF0001";
const MAGIC_OUT: &[u8; 8] = b"IPDO0001";
const COMPLETE: u8 = 0;
const PARTIAL: u8 = 1;
const IMAGE_ONLY: u8 = 2;
const ENCRYPTED: u8 = 3;
const MALFORMED: u8 = 4;
const RESOURCE: u8 = 5;
const PROTOCOL: u8 = 6;
const PAGE_LIMIT: u8 = 7;
const TEXT_LIMIT: u8 = 8;
const EMBEDDED: u8 = 9;
const RESOURCE_BACKEND: u8 = 10;

#[derive(Clone, Copy)]
struct Limits {
    pages: usize,
    expanded: usize,
    text: usize,
}
struct Request {
    limits: Limits,
    bytes: Vec<u8>,
}

fn error(code: u8) -> Vec<u8> {
    let mut bytes = MAGIC_OUT.to_vec();
    bytes.push(code);
    bytes.extend_from_slice(&0_u32.to_be_bytes());
    bytes
}

fn decode_request(header: &[u8; 24]) -> Result<(Limits, usize), u8> {
    let n = |offset| u32::from_be_bytes(header[offset..offset + 4].try_into().unwrap()) as usize;
    let limits = Limits {
        pages: n(8),
        expanded: n(12),
        text: n(16),
    };
    let size = n(20);
    if &header[..8] != MAGIC_IN
        || size == 0
        || size > INPUT
        || limits.pages == 0
        || limits.pages > PAGES
        || limits.expanded == 0
        || limits.expanded > EXPANDED
        || limits.text == 0
        || limits.text > TEXT
    {
        return Err(PROTOCOL);
    }
    Ok((limits, size))
}

fn extraction(request: &Request) -> Result<Vec<u8>, u8> {
    let mut document = Document::load_mem_with_options(
        &request.bytes,
        LoadOptions {
            strict: true,
            max_decompressed_size: Some(request.limits.expanded),
            ..Default::default()
        },
    )
    .map_err(classify)?;
    if document.was_encrypted() || document.trailer.has(b"Encrypt") {
        return Err(ENCRYPTED);
    }
    if document.objects.len() > 100_000 {
        return Err(RESOURCE);
    }
    let mut inspected = 0;
    for object in document.objects.values() {
        inspect_embedded(object, 0, &mut inspected)?;
    }
    let catalog = document
        .trailer
        .get(b"Root")
        .and_then(Object::as_reference)
        .map_err(classify)?;
    let root = document
        .get_dictionary(catalog)
        .and_then(|dictionary| dictionary.get(b"Pages"))
        .and_then(Object::as_reference)
        .map_err(classify)?;
    let ordered = validate_pages(
        &document,
        root,
        None,
        &mut std::collections::HashSet::new(),
        0,
        request.limits.pages,
    )?;
    // Retained non-image streams are decoded once against an aggregate envelope.
    // Load-time xref/object streams have the library's per-stream cap; the OS
    // address-space and CPU ceilings contain their combined parse cost.
    let mut expanded = 0_usize;
    for object in document.objects.values_mut() {
        let dictionary = match object {
            Object::Dictionary(dictionary) => Some(&*dictionary),
            Object::Stream(stream) => Some(&stream.dict),
            _ => None,
        };
        if let Some(dictionary) = dictionary {
            let kind = dictionary
                .get(b"Type")
                .and_then(Object::as_name)
                .unwrap_or_default();
            if kind == b"EmbeddedFile" || kind == b"Filespec" || dictionary.has(b"EmbeddedFiles") {
                return Err(EMBEDDED);
            }
        }
        if let Object::Stream(stream) = object {
            if stream.dict.get(b"Subtype").and_then(Object::as_name).ok() == Some(b"Image") {
                continue;
            }
            if stream.dict.has(b"Filter") {
                stream
                    .decompress_with_limit(request.limits.expanded.saturating_sub(expanded))
                    .map_err(classify)?;
            }
            expanded = expanded.checked_add(stream.content.len()).ok_or(RESOURCE)?;
            if expanded > request.limits.expanded {
                return Err(RESOURCE);
            }
        }
    }
    let pages = document.get_pages();
    if pages.is_empty() {
        return Err(MALFORMED);
    }
    if pages.len() > request.limits.pages {
        return Err(PAGE_LIMIT);
    }
    if pages.values().copied().collect::<Vec<_>>() != ordered {
        return Err(MALFORMED);
    }
    let mut rows = Vec::new();
    let mut text_bytes = 0_usize;
    let mut supported = 0_usize;
    let mut failures = 0_usize;
    let mut partial = false;
    for number in pages.keys() {
        let (status, text) =
            match document.extract_text_with_limit(&[*number], request.limits.expanded) {
                Ok(text) if !text.trim().is_empty() => {
                    text_bytes = text_bytes.checked_add(text.len()).ok_or(TEXT_LIMIT)?;
                    if text_bytes > request.limits.text {
                        return Err(TEXT_LIMIT);
                    }
                    supported += 1;
                    (0_u8, text)
                }
                Ok(_) => {
                    partial = true;
                    (1_u8, String::new())
                }
                Err(lopdf::Error::Decompress(lopdf::DecompressError::MemoryLimitExceeded {
                    ..
                })) => return Err(RESOURCE),
                Err(_) => {
                    partial = true;
                    failures += 1;
                    (2_u8, String::new())
                }
            };
        rows.extend_from_slice(&number.to_be_bytes());
        rows.push(status);
        rows.extend_from_slice(&(text.len() as u32).to_be_bytes());
        rows.extend_from_slice(text.as_bytes());
    }
    if supported == 0 {
        return Err(if failures == 0 { IMAGE_ONLY } else { MALFORMED });
    }
    let mut output = MAGIC_OUT.to_vec();
    output.push(if partial { PARTIAL } else { COMPLETE });
    output.extend_from_slice(&(pages.len() as u32).to_be_bytes());
    output.extend_from_slice(&rows);
    Ok(output)
}

fn inspect_embedded(object: &Object, depth: usize, inspected: &mut usize) -> Result<(), u8> {
    *inspected += 1;
    if depth > 64 || *inspected > 200_000 {
        return Err(RESOURCE);
    }
    let dictionary = match object {
        Object::Dictionary(dictionary) => Some(dictionary),
        Object::Stream(stream) => Some(&stream.dict),
        Object::Array(values) => {
            for value in values {
                inspect_embedded(value, depth + 1, inspected)?;
            }
            None
        }
        _ => None,
    };
    if let Some(dictionary) = dictionary {
        let kind = dictionary
            .get(b"Type")
            .and_then(Object::as_name)
            .unwrap_or_default();
        if kind == b"EmbeddedFile"
            || kind == b"Filespec"
            || dictionary.has(b"EmbeddedFiles")
            || dictionary.has(b"EF")
        {
            return Err(EMBEDDED);
        }
        for (_, value) in dictionary {
            inspect_embedded(value, depth + 1, inspected)?;
        }
    }
    Ok(())
}

fn validate_pages(
    document: &Document,
    id: lopdf::ObjectId,
    parent: Option<lopdf::ObjectId>,
    seen: &mut std::collections::HashSet<lopdf::ObjectId>,
    depth: usize,
    limit: usize,
) -> Result<Vec<lopdf::ObjectId>, u8> {
    if depth > 64 || !seen.insert(id) {
        return Err(MALFORMED);
    }
    let dictionary = document.get_dictionary(id).map_err(classify)?;
    if let Some(parent) = parent {
        if dictionary
            .get(b"Parent")
            .and_then(Object::as_reference)
            .ok()
            != Some(parent)
        {
            return Err(MALFORMED);
        }
    }
    match dictionary
        .get(b"Type")
        .and_then(Object::as_name)
        .map_err(classify)?
    {
        b"Page" => Ok(vec![id]),
        b"Pages" => {
            let count = dictionary
                .get(b"Count")
                .and_then(Object::as_i64)
                .map_err(classify)?;
            if count < 0 {
                return Err(MALFORMED);
            }
            if count as u64 > limit as u64 {
                return Err(PAGE_LIMIT);
            }
            let children = dictionary
                .get(b"Kids")
                .and_then(Object::as_array)
                .map_err(classify)?;
            if children.len() > limit {
                return Err(PAGE_LIMIT);
            }
            let mut pages = Vec::new();
            for child in children {
                let child = child.as_reference().map_err(classify)?;
                pages.extend(validate_pages(
                    document,
                    child,
                    Some(id),
                    seen,
                    depth + 1,
                    limit,
                )?);
                if pages.len() > limit {
                    return Err(PAGE_LIMIT);
                }
            }
            if pages.len() != count as usize {
                return Err(MALFORMED);
            }
            Ok(pages)
        }
        _ => Err(MALFORMED),
    }
}

fn classify(error: lopdf::Error) -> u8 {
    match error {
        lopdf::Error::Decryption(_)
        | lopdf::Error::InvalidPassword
        | lopdf::Error::UnsupportedSecurityHandler(_) => ENCRYPTED,
        lopdf::Error::Decompress(lopdf::DecompressError::MemoryLimitExceeded { .. }) => RESOURCE,
        _ => MALFORMED,
    }
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
mod platform {
    use super::*;
    use std::ffi::c_int;
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
    #[repr(C)]
    struct Rlimit {
        current: u64,
        maximum: u64,
    }
    #[repr(C)]
    struct Poll {
        fd: c_int,
        events: i16,
        revents: i16,
    }
    unsafe extern "C" {
        fn setrlimit(resource: c_int, value: *const Rlimit) -> c_int;
        fn poll(fds: *mut Poll, count: usize, timeout: c_int) -> c_int;
        fn getppid() -> c_int;
        fn geteuid() -> u32;
        fn flock(fd: c_int, operation: c_int) -> c_int;
        fn fork() -> c_int;
        fn pipe(fds: *mut c_int) -> c_int;
        fn close(fd: c_int) -> c_int;
        fn fcntl(fd: c_int, command: c_int, ...) -> c_int;
        fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
        fn kill(pid: c_int, signal: c_int) -> c_int;
        fn _exit(status: c_int) -> !;
    }
    #[cfg(target_os = "linux")]
    const ADDRESS_SPACE: c_int = 9;
    #[cfg(target_os = "macos")]
    const ADDRESS_SPACE: c_int = 5;

    pub fn lease(path: &str, create: bool) -> Option<std::fs::File> {
        #[cfg(target_os = "linux")]
        const NOFOLLOW: c_int = 0x20000;
        #[cfg(target_os = "macos")]
        const NOFOLLOW: c_int = 0x100;
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(create)
            .mode(0o600)
            .custom_flags(NOFOLLOW)
            .open(path)
            .ok()?;
        let metadata = file.metadata().ok()?;
        if !metadata.is_file()
            || metadata.nlink() != 1
            || metadata.uid() != unsafe { geteuid() }
            || metadata.mode() & 0o777 != 0o600
            || metadata.len() != 0
            || unsafe { flock(file.as_raw_fd(), 2 | 4) } != 0
        {
            return None;
        }
        Some(file)
    }

    pub fn restrict() -> std::io::Result<()> {
        for (resource, maximum) in [(0, 4), (ADDRESS_SPACE, 384 * 1024 * 1024), (4, 0)] {
            let value = Rlimit {
                current: maximum,
                maximum,
            };
            if unsafe { setrlimit(resource, &value) } != 0 {
                return Err(std::io::Error::last_os_error());
            }
        }
        // A returned setting alone is not evidence that the address-space
        // backend constrains allocations on this platform. Fail closed if an
        // allocation larger than the complete ceiling can still be reserved.
        let mut probe = Vec::<u8>::new();
        if probe.try_reserve_exact(384 * 1024 * 1024 + 1).is_ok() {
            return Err(std::io::Error::other("address-space limit not enforced"));
        }
        Ok(())
    }
    fn read_exact(input: &mut impl Read, bytes: &mut [u8], deadline: Instant) -> Result<(), u8> {
        let mut offset = 0;
        while offset < bytes.len() {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(RESOURCE);
            }
            let mut descriptor = Poll {
                fd: 0,
                events: 1,
                revents: 0,
            };
            let result =
                unsafe { poll(&mut descriptor, 1, remaining.as_millis().min(100) as c_int) };
            if result < 0 {
                return Err(PROTOCOL);
            }
            if result == 0 {
                continue;
            }
            let count = input.read(&mut bytes[offset..]).map_err(|_| PROTOCOL)?;
            if count == 0 {
                return Err(PROTOCOL);
            }
            offset += count;
        }
        Ok(())
    }
    fn request(deadline: Instant) -> Result<Request, u8> {
        // StdinLock may read ahead: polling fd 0 again would then wait while
        // the requested body already sits in its private buffer. Keep raw fd 0
        // open for the supervisor's subsequent owner-liveness polling.
        let mut input = std::mem::ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(0) });
        let mut header = [0_u8; 24];
        read_exact(&mut *input, &mut header, deadline)?;
        let (limits, size) = decode_request(&header)?;
        let mut bytes = vec![0; size];
        read_exact(&mut *input, &mut bytes, deadline)?;
        Ok(Request { limits, bytes })
    }
    fn worker(parent: u32, request: &Request) -> Vec<u8> {
        if restrict().is_err() {
            return error(RESOURCE_BACKEND);
        }
        if unsafe { getppid() } as u32 != parent {
            return error(RESOURCE);
        }
        std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                if unsafe { getppid() } as u32 != parent || Instant::now() >= deadline {
                    std::process::exit(70);
                }
                std::thread::sleep(Duration::from_millis(10));
            }
        });
        match extraction(request) {
            Ok(output) => output,
            Err(code) => error(code),
        }
    }
    pub fn supervisor() -> Vec<u8> {
        let deadline = Instant::now() + Duration::from_secs(5);
        let request = match request(deadline) {
            Ok(request) => request,
            Err(code) => return error(code),
        };
        let mut descriptors = [-1; 2];
        if unsafe { pipe(descriptors.as_mut_ptr()) } != 0 {
            return error(RESOURCE);
        }
        let parent = std::process::id();
        // This standalone supervisor is single-threaded at fork. The child
        // inherits the already admitted image and request bytes; no executable
        // pathname is reopened and no external loader is involved after fork.
        let child = unsafe { fork() };
        if child == 0 {
            unsafe {
                close(descriptors[0]);
            }
            for (name, _) in std::env::vars_os() {
                unsafe {
                    std::env::remove_var(name);
                }
            }
            let output = worker(parent, &request);
            let mut pipe = unsafe { std::fs::File::from_raw_fd(descriptors[1]) };
            let _ = pipe.write_all(&output);
            unsafe {
                _exit(0);
            }
        }
        unsafe {
            close(descriptors[1]);
        }
        let mut pipe = unsafe { std::fs::File::from_raw_fd(descriptors[0]) };
        if child < 0 {
            return error(RESOURCE);
        }
        if !nonblocking(descriptors[0]) {
            unsafe {
                kill(child, 9);
                waitpid(child, std::ptr::null_mut(), 0);
            }
            return error(RESOURCE);
        }
        let mut output = Vec::new();
        let mut good = false;
        let mut reaped = false;
        let mut failure = RESOURCE;
        loop {
            let mut descriptors = [
                Poll {
                    fd: 0,
                    events: 1,
                    revents: 0,
                },
                Poll {
                    fd: descriptors[0],
                    events: 1,
                    revents: 0,
                },
            ];
            let polled = unsafe { poll(descriptors.as_mut_ptr(), 2, 10) };
            // EOF/HUP means the owning Port disappeared. Extra bytes are a
            // protocol failure, never another request or an execution command.
            if Instant::now() >= deadline || polled < 0 || descriptors[0].revents != 0 {
                if descriptors[0].revents & 1 != 0 {
                    let mut unexpected = [0_u8; 1];
                    if std::io::stdin().read(&mut unexpected).ok() == Some(1) {
                        failure = PROTOCOL;
                    }
                }
                break;
            }
            let mut buffer = [0_u8; 8192];
            loop {
                match pipe.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(count) => output.extend_from_slice(&buffer[..count]),
                    Err(problem) if problem.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(_) => break,
                }
                if output.len() > OUTPUT {
                    break;
                }
            }
            if output.len() > OUTPUT {
                break;
            }
            let mut status = 0;
            if unsafe { waitpid(child, &mut status, 1) } == child {
                reaped = true;
                // The child can write its final bytes between our last read
                // and waitpid. Once reaped, drain the closed pipe to EOF before
                // accepting its frame, still respecting the output ceiling.
                good = status == 0
                    && (&mut pipe)
                        .take((OUTPUT + 1 - output.len()) as u64)
                        .read_to_end(&mut output)
                        .is_ok();
                break;
            }
        }
        if !reaped {
            unsafe {
                kill(child, 9);
                waitpid(child, std::ptr::null_mut(), 0);
            }
        }
        if good && output.len() <= OUTPUT {
            output
        } else {
            error(failure)
        }
    }

    fn nonblocking(fd: c_int) -> bool {
        #[cfg(target_os = "linux")]
        const NONBLOCK: c_int = 0x800;
        #[cfg(target_os = "macos")]
        const NONBLOCK: c_int = 4;
        let flags = unsafe { fcntl(fd, 3) };
        flags >= 0 && unsafe { fcntl(fd, 4, flags | NONBLOCK) } == 0
    }

    pub fn write_result(bytes: &[u8], deadline: Instant) {
        if !nonblocking(1) {
            return;
        }
        let mut output = std::mem::ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(1) });
        let mut offset = 0;
        while offset < bytes.len() && Instant::now() < deadline {
            let mut descriptors = [
                Poll {
                    fd: 0,
                    events: 1,
                    revents: 0,
                },
                Poll {
                    fd: 1,
                    events: 4,
                    revents: 0,
                },
            ];
            if unsafe { poll(descriptors.as_mut_ptr(), 2, 10) } < 0 || descriptors[0].revents != 0 {
                return;
            }
            match output.write(&bytes[offset..]) {
                Ok(0) => return,
                Ok(count) => offset += count,
                Err(problem) if problem.kind() == std::io::ErrorKind::WouldBlock => {}
                Err(_) => return,
            }
        }
    }
}

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    let deadline = Instant::now() + Duration::from_secs(6);
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let arguments: Vec<_> = std::env::args().collect();
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let _lease = if arguments.len() == 3 && arguments[1] == "--lease-check" {
        match platform::lease(&arguments[2], false) {
            Some(_lease) => {
                let _ = std::io::stdout().write_all(b"QUIESCENT\n");
                std::process::exit(0);
            }
            None => std::process::exit(1),
        }
    } else if arguments.len() == 3 && arguments[1] == "--lease" {
        match platform::lease(&arguments[2], true) {
            Some(lease) => {
                // No work input is accepted and no child is forked before this
                // barrier. The Port guardian can cancel a pre-ready launch
                // without mistaking an earlier lease probe for quiescence.
                let _ = std::io::stdout().write_all(b"IPLEASE1");
                let _ = std::io::stdout().flush();
                Some(lease)
            }
            None => std::process::exit(1),
        }
    } else {
        None
    };
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let output = if arguments.len() == 1 || (arguments.len() == 3 && arguments[1] == "--lease") {
        platform::supervisor()
    } else {
        error(PROTOCOL)
    };
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let output = error(RESOURCE);
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    platform::write_result(&output, deadline);
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        let _ = deadline;
        let _ = std::io::stdout().lock().write_all(&output);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lopdf::{Stream, dictionary};
    fn pdf(text: Option<&str>) -> Vec<u8> {
        let mut document = Document::with_version("1.5");
        let pages = document.new_object_id();
        let font = document.add_object(
            dictionary! {"Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Helvetica"},
        );
        let content = text
            .map(|text| format!("BT /F1 12 Tf 20 50 Td ({text}) Tj ET"))
            .unwrap_or_default();
        let content = document.add_object(Stream::new(dictionary! {}, content.into_bytes()));
        let page = document.add_object(dictionary! {"Type"=>"Page", "Parent"=>pages, "Contents"=>content,
            "Resources"=>dictionary! {"Font"=>dictionary! {"F1"=>font}}, "MediaBox"=>vec![0.into(),0.into(),200.into(),100.into()]});
        document.objects.insert(
            pages,
            Object::Dictionary(
                dictionary! {"Type"=>"Pages", "Kids"=>vec![page.into()], "Count"=>1},
            ),
        );
        let catalog = document.add_object(dictionary! {"Type"=>"Catalog", "Pages"=>pages});
        document.trailer.set("Root", catalog);
        let mut bytes = Vec::new();
        document.save_to(&mut bytes).unwrap();
        bytes
    }
    fn request(bytes: Vec<u8>) -> Request {
        Request {
            limits: Limits {
                pages: PAGES,
                expanded: EXPANDED,
                text: TEXT,
            },
            bytes,
        }
    }
    #[test]
    fn actual_pdf_text_and_page_frame() {
        let output = extraction(&request(pdf(Some("independent fixture")))).unwrap();
        assert_eq!(&output[..8], MAGIC_OUT);
        assert_eq!(output[8], COMPLETE);
        assert_eq!(u32::from_be_bytes(output[9..13].try_into().unwrap()), 1);
        assert_eq!(u32::from_be_bytes(output[13..17].try_into().unwrap()), 1);
        assert!(
            std::str::from_utf8(&output[22..])
                .unwrap()
                .contains("independent fixture")
        );
    }
    #[test]
    fn image_only_malformed_and_text_limits_are_explicit() {
        assert_eq!(extraction(&request(pdf(None))).unwrap_err(), IMAGE_ONLY);
        assert_eq!(
            extraction(&request(b"not a PDF".to_vec())).unwrap_err(),
            MALFORMED
        );
        let mut value = request(pdf(Some("too much text")));
        value.limits.text = 1;
        assert_eq!(extraction(&value).unwrap_err(), TEXT_LIMIT);
    }
    #[test]
    fn input_protocol_cannot_raise_limits() {
        let mut header = [0; 24];
        header[..8].copy_from_slice(MAGIC_IN);
        for (offset, value) in [(8, PAGES), (12, EXPANDED), (16, TEXT), (20, 1)] {
            header[offset..offset + 4].copy_from_slice(&(value as u32).to_be_bytes());
        }
        assert!(decode_request(&header).is_ok());
        header[8..12].copy_from_slice(&((PAGES + 1) as u32).to_be_bytes());
        assert!(matches!(decode_request(&header), Err(PROTOCOL)));
    }
}
