use super::{SIGNAL, error, exit_code, signals};
use std::fs::{DirBuilder, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::fd::{AsFd, AsRawFd, OwnedFd};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Component, Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::Ordering;
use std::time::{Duration, Instant};

const CALLS: u64 = 64;
const TOTAL: u64 = 8 * 1024 * 1024;
const STREAM: usize = 1024 * 1024;
const FLAGS: i32 = 0x20000 | 0x800;

mod bootstrap;

unsafe extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
    fn getuid() -> u32;
}

fn at(root: &File, name: &str) -> PathBuf {
    PathBuf::from(format!("/proc/self/fd/{}/{}", root.as_raw_fd(), name))
}

fn pinned(path: &Path) -> io::Result<File> {
    let mut root = File::open(if path.is_absolute() { "/" } else { "." })?;
    for part in path.components() {
        match part {
            Component::RootDir => (),
            Component::Normal(name) => {
                root = OpenOptions::new()
                    .read(true)
                    .custom_flags(FLAGS | 0x10000)
                    .open(at(
                        &root,
                        name.to_str().ok_or_else(|| error("non UTF-8 path"))?,
                    ))?;
            }
            _ => return Err(error("noncanonical recorder path")),
        }
    }
    Ok(root)
}

fn directory(path: &Path) -> io::Result<File> {
    let root = pinned(path)?;
    let meta = root.metadata()?;
    if meta.uid() != unsafe { getuid() } || meta.mode() & 0o077 != 0 {
        return Err(error("recorder directory must be private and owned"));
    }
    Ok(root)
}

fn file(root: &File, name: &str, new: bool) -> io::Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(new)
        .mode(0o600)
        .custom_flags(FLAGS)
        .open(at(root, name))?;
    let meta = file.metadata()?;
    if !meta.is_file()
        || meta.nlink() != 1
        || meta.uid() != unsafe { getuid() }
        || meta.mode() & 0o077 != 0
    {
        return Err(error("recorder file must be private and singly linked"));
    }
    Ok(file)
}

struct Lock(File);
impl Lock {
    fn take(file: File, exclusive: bool) -> io::Result<Self> {
        if unsafe { flock(file.as_raw_fd(), (if exclusive { 2 } else { 1 }) | 4) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self(file))
    }
}
impl Drop for Lock {
    fn drop(&mut self) {
        unsafe {
            flock(self.0.as_raw_fd(), 8);
        }
    }
}

fn deadline(until: Instant) -> io::Result<()> {
    if SIGNAL.load(Ordering::Relaxed) != 0 || Instant::now() >= until {
        Err(error("recorder interrupted or deadline exceeded"))
    } else {
        Ok(())
    }
}

fn locked(root: &File, until: Instant) -> io::Result<Lock> {
    loop {
        deadline(until)?;
        match Lock::take(file(root, "budget", false)?, true) {
            Ok(lock) => return Ok(lock),
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(2))
            }
            Err(e) => return Err(e),
        }
    }
}

fn budget(file: &mut File) -> io::Result<[u64; 3]> {
    file.seek(SeekFrom::Start(0))?;
    let mut text = String::new();
    file.take(128).read_to_string(&mut text)?;
    let fields: Vec<u64> = text
        .split_whitespace()
        .map(str::parse)
        .collect::<Result<_, _>>()
        .map_err(|_| error("invalid recorder budget"))?;
    if fields.len() != 3
        || fields[0] > CALLS
        || fields[1] > TOTAL
        || fields[2] > 1
        || text != format!("{} {} {}\n", fields[0], fields[1], fields[2])
    {
        return Err(error("invalid recorder budget"));
    }
    Ok([fields[0], fields[1], fields[2]])
}

fn store(file: &mut File, values: [u64; 3]) -> io::Result<()> {
    file.seek(SeekFrom::Start(0))?;
    file.set_len(0)?;
    writeln!(file, "{} {} {}", values[0], values[1], values[2])?;
    file.sync_data()
}

fn reserve(root: &File, call: bool, bytes: usize, until: Instant) -> io::Result<u64> {
    let mut held = locked(root, until)?;
    let mut values = budget(&mut held.0)?;
    if values[2] != 0 || (call && values[0] == CALLS) || bytes as u64 > TOTAL - values[1] {
        values[2] = 1;
        store(&mut held.0, values)?;
        return Err(error("recorder cumulative limit exhausted"));
    }
    let id = values[0];
    values[0] += u64::from(call);
    values[1] += bytes as u64;
    store(&mut held.0, values)?;
    Ok(id)
}

fn nonblocking(fd: i32) -> io::Result<()> {
    let flags = unsafe { super::fcntl(fd, 3) };
    if flags < 0 || unsafe { super::fcntl(fd, 4, flags | 0x800) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn read(reader: &mut impl Read, bytes: &mut [u8]) -> io::Result<Option<usize>> {
    match reader.read(bytes) {
        Ok(n) => Ok(Some(n)),
        Err(e)
            if matches!(
                e.kind(),
                io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
            ) =>
        {
            Ok(None)
        }
        Err(e) => Err(e),
    }
}

fn write(writer: &mut impl Write, bytes: &[u8]) -> io::Result<usize> {
    match writer.write(bytes) {
        Ok(0) => Err(error("recorder output closed")),
        Ok(n) => Ok(n),
        Err(e)
            if matches!(
                e.kind(),
                io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
            ) =>
        {
            Ok(0)
        }
        Err(e) => Err(e),
    }
}

struct Owned(Child);
impl Drop for Owned {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn record(root: &File, program: &str, events: bool, until: Instant) -> io::Result<i32> {
    let mut gate = Lock::take(file(root, "gate", false)?, false)?;
    let mut state = String::new();
    (&mut gate.0).take(16).read_to_string(&mut state)?;
    if state != "open\n" {
        return Err(error("recorder is sealed"));
    }
    let id = reserve(root, true, 0, until)?;
    let mut request = file(root, &format!("{id:03}-request.json"), true)?;
    let mut response = file(root, &format!("{id:03}-response.jsonl"), true)?;
    let (mut input, bootstrap) = if events {
        let (input, bootstrap) = bootstrap::receive_stdin()?;
        (input, Some(bootstrap))
    } else {
        (File::from(io::stdin().as_fd().try_clone_to_owned()?), None)
    };
    nonblocking(input.as_raw_fd())?;
    let mut asked = Vec::new();
    let mut chunk = [0; 8192];
    loop {
        deadline(until)?;
        match read(&mut input, &mut chunk)? {
            Some(0) => break,
            Some(n) => {
                if asked.len() + n > STREAM {
                    return Err(error("recorder request limit"));
                }
                reserve(root, false, n, until)?;
                request.write_all(&chunk[..n])?;
                asked.extend_from_slice(&chunk[..n]);
            }
            None => std::thread::sleep(Duration::from_millis(2)),
        }
    }
    request.sync_all()?;
    let parent = std::process::id() as i32;
    let mut command = Command::new(program);
    command
        .args(["ask", "--json"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    let forwarded = bootstrap
        .map(|bootstrap| bootstrap.prepare(&mut command))
        .transpose()?;
    unsafe {
        command.pre_exec(move || {
            if super::prctl(1, 9, 0, 0, 0) != 0 || super::getppid() != parent {
                return Err(error("recorder child lost its parent"));
            }
            Ok(())
        });
    }
    let mut child = Owned(command.spawn()?);
    drop(command);
    let mut sent = forwarded.or_else(|| child.0.stdin.take().map(|p| File::from(OwnedFd::from(p))));
    let mut received = child
        .0
        .stdout
        .take()
        .ok_or_else(|| error("missing child stdout"))?;
    nonblocking(
        sent.as_ref()
            .ok_or_else(|| error("missing child stdin"))?
            .as_raw_fd(),
    )?;
    nonblocking(received.as_raw_fd())?;
    let mut output = io::stdout();
    nonblocking(output.as_raw_fd())?;
    let (mut request_at, mut response_bytes, mut pending_at, mut eof) = (0, 0, 0, false);
    let mut pending = Vec::new();
    let code = loop {
        deadline(until)?;
        if let Some(pipe) = sent.as_mut() {
            if request_at < asked.len() {
                request_at += write(pipe, &asked[request_at..])?;
            }
            if request_at == asked.len() {
                sent.take();
            }
        }
        if pending_at == pending.len() && !eof {
            match read(&mut received, &mut chunk)? {
                Some(0) => eof = true,
                Some(n) => {
                    if response_bytes + n > STREAM {
                        return Err(error("recorder response limit"));
                    }
                    reserve(root, false, n, until)?;
                    response.write_all(&chunk[..n])?;
                    response_bytes += n;
                    pending.clear();
                    pending.extend_from_slice(&chunk[..n]);
                    pending_at = 0;
                }
                None => (),
            }
        }
        if pending_at < pending.len() {
            pending_at += write(&mut output, &pending[pending_at..])?;
        }
        if eof && pending_at == pending.len() {
            if let Some(status) = child.0.try_wait()? {
                break exit_code(status);
            }
        }
        std::thread::sleep(Duration::from_millis(1));
    };
    if request_at != asked.len() {
        return Err(error("recorder request not fully delivered"));
    }
    response.sync_all()?;
    let mut receipt = file(root, &format!("{id:03}-receipt.json"), true)?;
    writeln!(
        receipt,
        "{{\"schema\":1,\"call\":{id},\"request_bytes\":{},\"response_bytes\":{response_bytes},\"exit_code\":{code},\"transport_complete\":true,\"complete_run\":false}}",
        asked.len()
    )?;
    receipt.sync_all()?;
    Ok(code)
}

pub fn run(args: &[String]) -> io::Result<i32> {
    signals()?;
    let until = Instant::now() + Duration::from_secs(60);
    match args {
        [mode, path] if mode == "init" => {
            let path = Path::new(path);
            let parent_path = path
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
                .ok_or_else(|| error("recorder path requires a parent"))?;
            let parent = pinned(parent_path)?;
            let name = path
                .file_name()
                .and_then(|n| n.to_str())
                .ok_or_else(|| error("missing recorder directory name"))?;
            DirBuilder::new().mode(0o700).create(at(&parent, name))?;
            let root = directory(path)?;
            file(&root, "gate", true)?.write_all(b"open\n")?;
            store(&mut file(&root, "budget", true)?, [0, 0, 0])?;
            Ok(0)
        }
        [mode, path, program, verb, json] if mode == "ask" && verb == "ask" && json == "--json" => {
            record(&directory(Path::new(path))?, program, false, until)
        }
        [mode, path, program, verb, json, events]
            if mode == "ask"
                && verb == "ask"
                && json == "--json"
                && events == "--event-bootstrap" =>
        {
            record(&directory(Path::new(path))?, program, true, until)
        }
        [mode, path] if mode == "seal" => {
            let root = directory(Path::new(path))?;
            let mut gate = Lock::take(file(&root, "gate", false)?, true)?;
            gate.0.set_len(0)?;
            gate.0.write_all(b"sealed\n")?;
            gate.0.sync_all()?;
            let values = budget(&mut locked(&root, until)?.0)?;
            let receipts = (0..values[0])
                .filter(|id| {
                    file(&root, &format!("{id:03}-receipt.json"), false)
                        .is_ok_and(|f| f.metadata().is_ok_and(|m| m.len() > 0 && m.len() <= 512))
                })
                .count();
            let complete = values[2] == 0 && receipts as u64 == values[0];
            let mut summary = file(&root, "summary.json", true)?;
            writeln!(
                summary,
                "{{\"schema\":1,\"scope\":\"evaluation-model-ipc\",\"sealed\":true,\"calls\":{},\"bytes\":{},\"limit_exhausted\":{},\"capture_complete\":{complete},\"complete_run\":false,\"helper_attribution\":null}}",
                values[0],
                values[1],
                values[2] != 0
            )?;
            summary.sync_all()?;
            Ok(if complete { 0 } else { 1 })
        }
        _ => Err(error(
            "usage: record init ROOT | ask ROOT PROGRAM ask --json [--event-bootstrap] | seal ROOT",
        )),
    }
}
