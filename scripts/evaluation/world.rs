//! PID-namespace supervision and bounded run output.

#[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
compile_error!("evaluation worlds currently require Linux x86_64");

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::net::UnixStream;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::time::{Duration, Instant};

mod admission;
mod deadline;
mod ipc_record;

static SIGNAL: AtomicI32 = AtomicI32::new(0);
const KILL: i32 = 9;
const LIMIT: usize = 1024 * 1024;

unsafe extern "C" {
    fn signal(number: i32, handler: extern "C" fn(i32)) -> usize;
    fn kill(pid: i32, signal: i32) -> i32;
    fn waitpid(pid: i32, status: *mut i32, flags: i32) -> i32;
    fn prctl(option: i32, ...) -> i32;
    fn getppid() -> i32;
    fn fcntl(fd: i32, command: i32, ...) -> i32;
    fn syscall(number: i64, ...) -> i64;
}

extern "C" fn interrupted(signal: i32) {
    SIGNAL.store(signal, Ordering::Relaxed);
}

fn signals() -> io::Result<()> {
    for number in [2, 15] {
        if unsafe { signal(number, interrupted) } == usize::MAX {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

fn error(text: &str) -> io::Error {
    io::Error::other(text)
}

fn new_file(path: &str) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
}

fn exit_code(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}

fn parse_stat(text: &str) -> io::Result<(char, String)> {
    let end = text
        .rfind(')')
        .ok_or_else(|| error("invalid process stat"))?;
    let rest = text
        .get(end + 2..)
        .ok_or_else(|| error("invalid process fields"))?;
    let mut words = rest.split_whitespace();
    let state = words
        .next()
        .and_then(|s| s.chars().next())
        .ok_or_else(|| error("missing process state"))?;
    let start = words
        .nth(18)
        .ok_or_else(|| error("missing process start time"))?
        .to_owned();
    start
        .parse::<u64>()
        .map_err(|_| error("invalid process start time"))?;
    Ok((state, start))
}

fn process(pid: u32) -> io::Result<Option<(char, String)>> {
    match fs::read_to_string(format!("/proc/{pid}/stat")) {
        Ok(text) => parse_stat(&text).map(Some),
        Err(e) if e.kind() == io::ErrorKind::NotFound || e.raw_os_error() == Some(3) => Ok(None),
        Err(e) => Err(e),
    }
}

fn remaining() -> io::Result<Vec<u32>> {
    let mut live = Vec::new();
    for entry in fs::read_dir("/proc")? {
        let entry = entry?;
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|s| s.parse::<u32>().ok())
        else {
            continue;
        };
        if pid > 1 && process(pid)?.is_some_and(|(state, _)| state != 'Z' && state != 'X') {
            live.push(pid);
        }
    }
    Ok(live)
}

fn reap() {
    let mut status = 0;
    while unsafe { waitpid(-1, &mut status, 1) } > 0 {}
}

#[derive(Clone)]
struct Namespace {
    pid: u32,
    start: String,
    fd: Arc<OwnedFd>,
}

impl Namespace {
    fn pin(pid: u32) -> io::Result<Option<Self>> {
        if pid <= 1 {
            return Err(error("namespace PID must not be host init"));
        }
        let Some((_, start)) = process(pid)? else {
            return Ok(None);
        };
        let raw = unsafe { syscall(434, pid, 0u32) };
        if raw < 0 {
            let why = io::Error::last_os_error();
            return if why.raw_os_error() == Some(3) {
                Ok(None)
            } else {
                Err(why)
            };
        }
        let fd = unsafe { OwnedFd::from_raw_fd(raw as i32) };
        if !process(pid)?.is_some_and(|(_, actual)| actual == start) {
            return Err(error("namespace identity changed while pinning"));
        }
        Ok(Some(Self {
            pid,
            start,
            fd: Arc::new(fd),
        }))
    }

    fn stop(&self) -> io::Result<()> {
        self.send(KILL)
    }

    fn send(&self, number: i32) -> io::Result<()> {
        let result = unsafe {
            syscall(
                424,
                self.fd.as_raw_fd(),
                number,
                std::ptr::null::<()>(),
                0u32,
            )
        };
        if result < 0 {
            let why = io::Error::last_os_error();
            if why.raw_os_error() != Some(3) {
                return Err(why);
            }
        }
        Ok(())
    }

    fn gone(&self) -> io::Result<bool> {
        Ok(process(self.pid)?
            .is_none_or(|(state, actual)| actual != self.start || state == 'Z' || state == 'X'))
    }
}

type Identity = Arc<Mutex<Option<Namespace>>>;

struct WorldChild {
    child: Child,
    identity: Identity,
    armed: bool,
}

impl std::ops::Deref for WorldChild {
    type Target = Child;
    fn deref(&self) -> &Child {
        &self.child
    }
}

impl std::ops::DerefMut for WorldChild {
    fn deref_mut(&mut self) -> &mut Child {
        &mut self.child
    }
}

impl Drop for WorldChild {
    fn drop(&mut self) {
        if self.armed {
            let _ = stop_world(&mut self.child, &self.identity);
        }
    }
}

fn child_pid(bytes: &[u8]) -> Option<u32> {
    let text = std::str::from_utf8(bytes).ok()?;
    let value = text
        .split_once("\"child-pid\"")?
        .1
        .trim_start()
        .strip_prefix(':')?
        .trim_start();
    let digits = value.bytes().take_while(u8::is_ascii_digit).count();
    if !matches!(
        value.as_bytes().get(digits),
        Some(b',' | b'}' | b'\n' | b'\r')
    ) {
        return None;
    }
    let pid = value.get(..digits)?.parse::<u32>().ok()?;
    (pid > 1 && pid <= i32::MAX as u32).then_some(pid)
}

fn capture(
    mut input: impl Read + Send + 'static,
    path: &str,
    cap: usize,
    exceeded: Arc<AtomicBool>,
    identity: Option<Identity>,
) -> io::Result<mpsc::Receiver<io::Result<()>>> {
    let mut output = new_file(path)?;
    let (send, recv) = mpsc::channel();
    std::thread::spawn(move || {
        let result = (|| {
            let mut kept = 0usize;
            let mut buffer = [0; 8192];
            let mut info = Vec::new();
            loop {
                let size = input.read(&mut buffer)?;
                if size == 0 {
                    break;
                }
                let retain = size.min(cap.saturating_sub(kept));
                kept += retain;
                if retain != size {
                    exceeded.store(true, Ordering::Relaxed);
                }
                if let Some(identity) = &identity {
                    info.extend_from_slice(&buffer[..retain]);
                    let mut held = identity.lock().map_err(|_| error("identity lock"))?;
                    if held.is_none() {
                        if let Some(pid) = child_pid(&info) {
                            *held = Namespace::pin(pid)?;
                        }
                    }
                }
                output.write_all(&buffer[..retain])?;
            }
            output.flush()
        })();
        if result.is_err() {
            exceeded.store(true, Ordering::Relaxed);
        }
        let _ = send.send(result);
    });
    Ok(recv)
}

fn collected(readers: Vec<mpsc::Receiver<io::Result<()>>>) -> bool {
    readers
        .into_iter()
        .all(|reader| matches!(reader.recv_timeout(Duration::from_secs(2)), Ok(Ok(()))))
}

fn stop_child(child: &mut Child) -> io::Result<Option<ExitStatus>> {
    if let Some(status) = child.try_wait()? {
        return Ok(Some(status));
    }
    if let Err(why) = child.kill() {
        if why.raw_os_error() != Some(3) {
            return Err(why);
        }
    }
    let until = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(Some(status));
        }
        if Instant::now() >= until {
            return Ok(None);
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn stop_world(child: &mut Child, identity: &Identity) -> io::Result<Option<ExitStatus>> {
    let until = Instant::now() + Duration::from_secs(2);
    loop {
        if let Some(namespace) = identity.lock().map_err(|_| error("identity lock"))?.clone() {
            let grace = Instant::now() + Duration::from_secs(2);
            loop {
                namespace.send(15)?;
                if namespace.gone()? {
                    break;
                }
                if Instant::now() >= grace {
                    namespace.stop()?;
                    break;
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            break;
        }
        if Instant::now() >= until {
            break;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    stop_child(child)
}

fn outer(args: &[String]) -> io::Result<i32> {
    if args.len() < 4 {
        return Err(error(
            "outer RECEIPT TIMEOUT_MS LAUNCHER_PID COMMAND [ARGS]",
        ));
    }
    let receipt = &args[0];
    let millis: u64 = args[1].parse().map_err(|_| error("invalid deadline"))?;
    if !(1..=60000).contains(&millis) {
        return Err(error("deadline outside 1..60000ms"));
    }
    let parent: i32 = args[2].parse().map_err(|_| error("invalid launcher pid"))?;
    if parent <= 1 || unsafe { getppid() } != parent {
        return Err(error("world launcher exited before supervision"));
    }
    signals()?;
    if unsafe { prctl(1, 15usize, 0usize, 0usize, 0usize) } != 0 {
        return Err(io::Error::last_os_error());
    }
    if unsafe { getppid() } != parent {
        return Err(error("world launcher exited before supervision"));
    }
    let started = Instant::now();
    let (gate_read, mut gate_write) = UnixStream::pair()?;
    let gate_fd = gate_read.as_raw_fd();
    if gate_fd <= 2 {
        return Err(error("startup gate overlaps standard streams"));
    }
    let mut command = Command::new(&args[3]);
    command
        .args(["--block-fd", &gate_fd.to_string()])
        .args(&args[4..])
        .env_clear()
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    unsafe {
        command.pre_exec(move || {
            if fcntl(gate_fd, 2, 0) == -1 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let identity = Arc::new(Mutex::new(None));
    let mut child = WorldChild {
        child: command.spawn()?,
        identity: identity.clone(),
        armed: true,
    };
    drop(gate_read);
    let exceeded = Arc::new(AtomicBool::new(false));
    let readers = vec![
        capture(
            child.stdout.take().ok_or_else(|| error("control pipe"))?,
            &format!("{receipt}/bwrap-info.json"),
            8192,
            exceeded.clone(),
            Some(identity.clone()),
        )?,
        capture(
            child.stderr.take().ok_or_else(|| error("backend stderr"))?,
            &format!("{receipt}/backend.stderr"),
            LIMIT,
            exceeded.clone(),
            None,
        )?,
    ];
    let mut timed_out = false;
    let mut released = false;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break Some(status);
        }
        timed_out = started.elapsed() >= Duration::from_millis(millis);
        if timed_out || SIGNAL.load(Ordering::Relaxed) != 0 || exceeded.load(Ordering::Relaxed) {
            break stop_world(&mut child, &identity)?;
        }
        if !released
            && identity
                .lock()
                .map_err(|_| error("identity lock"))?
                .is_some()
        {
            gate_write.write_all(&[1])?;
            released = true;
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let streams_ok = collected(readers);
    let identity = identity.lock().map_err(|_| error("identity lock"))?.clone();
    let until = Instant::now() + Duration::from_secs(2);
    let namespace_gone = loop {
        let gone = match &identity {
            Some(namespace) => namespace.gone()?,
            None => false,
        };
        if gone || Instant::now() >= until {
            break gone;
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let code = status.map(exit_code);
    let elapsed = started.elapsed().as_millis();
    timed_out |= elapsed > u128::from(millis);
    let interrupted = SIGNAL.load(Ordering::Relaxed);
    let cleanup = status.is_some() && namespace_gone && streams_ok;
    child.armed = !cleanup;
    let failed = code != Some(0)
        || timed_out
        || interrupted != 0
        || !cleanup
        || exceeded.load(Ordering::Relaxed);
    writeln!(
        new_file(&format!("{receipt}/outer.json"))?,
        "{{\"schema\":1,\"elapsed_ms\":{elapsed},\"exit_code\":{},\"timed_out\":{timed_out},\"interrupted\":{interrupted},\"cleanup_confirmed\":{cleanup},\"output_limit_exceeded\":{},\"namespace_pid\":{}}}",
        code.map_or("null".into(), |n| n.to_string()),
        exceeded.load(Ordering::Relaxed),
        identity.map_or("null".into(), |namespace| namespace.pid.to_string())
    )?;
    Ok(if interrupted != 0 {
        128 + interrupted
    } else if timed_out {
        124
    } else {
        i32::from(failed)
    })
}

fn inner(args: &[String]) -> io::Result<i32> {
    if std::process::id() != 1 || args.is_empty() {
        return Err(error(
            "inside requires the owned PID namespace and a command",
        ));
    }
    if unsafe { prctl(4, 0usize, 0usize, 0usize, 0usize) } != 0 {
        return Err(io::Error::last_os_error());
    }
    signals()?;
    for directory in [
        "home", "config", "data", "state", "runtime", "cache", "evidence",
    ] {
        let path = format!("/world/{directory}");
        fs::create_dir(&path)?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    }
    let admission_directory = "/world/runtime/melchior/.evaluation-admission";
    let mut admission = admission::Broker::configured(
        std::path::Path::new("/input/client-attempt-limit.txt"),
        std::path::Path::new(admission_directory),
        std::path::Path::new("/receipt/client-attempts.jsonl"),
    )?;
    let staged = Command::new("/runner/bin/eval-input")
        .args(["tree", "/", "input", "/world/work", "16777216", "256"])
        .stdout(Stdio::from(new_file("/receipt/staged.json")?))
        .status()?;
    if !staged.success() {
        return Err(error("fixture staging failed"));
    }
    let closure = fs::read_to_string("/runner/closure")?;
    let tool_path = fs::read_to_string("/runner/tool-path")?;
    let mut command = Command::new("/runner/bin/bwrap");
    command.args([
        "--unshare-user",
        "--uid",
        "0",
        "--gid",
        "0",
        "--cap-add",
        "ALL",
        "--die-with-parent",
        "--new-session",
        "--ro-bind",
        "/runner",
        "/runner",
        "--ro-bind",
        "/input",
        "/input",
        "--bind",
        "/world",
        "/world",
        "--bind",
        "/tmp",
        "/tmp",
        "--dir",
        "/var",
        "--bind",
        "/var/tmp",
        "/var/tmp",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--clearenv",
        "--setenv",
        "PATH",
        tool_path.trim_end(),
        "--setenv",
        "HOME",
        "/world/home",
        "--setenv",
        "XDG_CONFIG_HOME",
        "/world/config",
        "--setenv",
        "XDG_DATA_HOME",
        "/world/data",
        "--setenv",
        "XDG_STATE_HOME",
        "/world/state",
        "--setenv",
        "XDG_RUNTIME_DIR",
        "/world/runtime",
        "--setenv",
        "XDG_CACHE_HOME",
        "/world/cache",
        "--setenv",
        "TMPDIR",
        "/tmp",
        "--setenv",
        "LC_ALL",
        "C",
        "--setenv",
        "EVAL_EVIDENCE",
        "/world/evidence",
        "--chdir",
        "/world/work",
    ]);
    for path in closure.lines() {
        command.args(["--ro-bind", path, path]);
    }
    match fs::metadata("/family") {
        Ok(metadata) if metadata.is_dir() => {
            command.args([
                "--ro-bind",
                "/family",
                "/family",
                "--ro-bind",
                "/opt/evaluation",
                "/opt/evaluation",
            ]);
        }
        Ok(_) => return Err(error("family artifact is not a directory")),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    match fs::metadata("/opt/evaluation/grammars/bin/rust") {
        Ok(metadata) if metadata.is_file() => {
            command.args(["--setenv", "CASPER_GRAMMARS", "/opt/evaluation/grammars"]);
        }
        Ok(_) => return Err(error("selected Rust grammar is not a file")),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    if admission.is_some() {
        command.args(["--ro-bind", admission_directory, admission_directory]);
    }
    command
        .args(["--remount-ro", "/", "--"])
        .args(args)
        .env_clear()
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if SIGNAL.load(Ordering::Relaxed) != 0 {
        return Err(error("world cancelled before worker launch"));
    }
    let mut child = command.spawn()?;
    let exceeded = Arc::new(AtomicBool::new(false));
    let readers = vec![
        capture(
            child.stdout.take().ok_or_else(|| error("worker stdout"))?,
            "/receipt/worker.stdout",
            LIMIT,
            exceeded.clone(),
            None,
        )?,
        capture(
            child.stderr.take().ok_or_else(|| error("worker stderr"))?,
            "/receipt/worker.stderr",
            LIMIT,
            exceeded.clone(),
            None,
        )?,
    ];
    let mut aborted = false;
    let status = loop {
        if let Some(broker) = &mut admission {
            broker.poll();
        }
        if let Some(status) = child.try_wait()? {
            break Some(status);
        }
        if SIGNAL.load(Ordering::Relaxed) != 0
            || exceeded.load(Ordering::Relaxed)
            || admission.as_ref().is_some_and(admission::Broker::failed)
        {
            aborted = true;
            break stop_child(&mut child)?;
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let admission_failed = admission.is_some_and(|broker| !broker.finish().unwrap_or(false));
    reap();
    let leaks = (!aborted)
        .then(remaining)
        .transpose()?
        .map(|pids| pids.len());
    unsafe {
        kill(-1, KILL);
    }
    let until = Instant::now() + Duration::from_secs(2);
    let left = loop {
        reap();
        let live = remaining()?.len();
        if live == 0 || Instant::now() >= until {
            break live;
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let streams_ok = collected(readers);
    let mut exported = true;
    for (name, count) in [("work", "256"), ("evidence", "32")] {
        let copied = Command::new("/runner/bin/eval-input")
            .args([
                "tree",
                "/world",
                name,
                &format!("/receipt/{name}"),
                "16777216",
                count,
            ])
            .stdout(Stdio::from(new_file(&format!(
                "/receipt/{name}-counts.json"
            ))?))
            .status()?;
        exported &= copied.success();
    }
    let code = status.map(exit_code);
    let failed = admission_failed
        || code != Some(0)
        || leaks != Some(0)
        || left != 0
        || !streams_ok
        || !exported
        || exceeded.load(Ordering::Relaxed)
        || SIGNAL.load(Ordering::Relaxed) != 0;
    writeln!(
        new_file("/receipt/inside.json")?,
        "{{\"schema\":1,\"exit_code\":{},\"leaked_processes\":{},\"remaining_processes\":{left},\"output_limit_exceeded\":{},\"streams_complete\":{streams_ok},\"exported\":{exported},\"client_admission_failed\":{admission_failed}}}",
        code.map_or("null".into(), |n| n.to_string()),
        leaks.map_or("null".into(), |n| n.to_string()),
        exceeded.load(Ordering::Relaxed)
    )?;
    Ok(i32::from(failed))
}

fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("outer") => outer(&args[1..]),
        Some("inside") => inner(&args[1..]),
        Some("control") => deadline::run(&args[1..], false),
        Some("control-owned") => deadline::run(&args[1..], true),
        Some("record") => ipc_record::run(&args[1..]),
        _ => Err(error(
            "usage: eval-world outer|inside|control|control-owned ...",
        )),
    };
    match result {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            eprintln!("evaluation world: {error}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn namespace_handle_refuses_host_init() {
        assert!(Namespace::pin(1).is_err());
        assert!(Namespace::pin(0).is_err());
    }

    #[test]
    fn stop_uses_the_pinned_handle_not_a_changed_numeric_pid() {
        let mut child = Command::new("sleep")
            .arg("10")
            .spawn()
            .expect("owned child");
        let pinned = Namespace::pin(child.id());
        let mut namespace = match pinned {
            Ok(Some(namespace)) => namespace,
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                panic!("could not pin owned child");
            }
        };
        namespace.pid = std::process::id();
        let stopped = namespace.stop();
        let until = Instant::now() + Duration::from_secs(1);
        let status = loop {
            if let Some(status) = child.try_wait().expect("owned wait") {
                break Some(status);
            }
            if Instant::now() >= until {
                break None;
            }
            std::thread::sleep(Duration::from_millis(5));
        };
        if status.is_none() {
            let _ = child.kill();
            let _ = child.wait();
        }
        assert!(stopped.is_ok());
        assert_eq!(status.and_then(|s| s.signal()), Some(KILL));
    }

    #[test]
    fn fragmented_backend_pid_is_not_mistaken_for_a_complete_pid() {
        assert_eq!(child_pid(b"{\"child-pid\":123"), None);
        assert_eq!(child_pid(b"{\"child-pid\":1234,"), Some(1234));
        assert_eq!(child_pid(b"{\"child-pid\":1,"), None);
        assert_eq!(child_pid(b"{\"child-pid\":4294967295}"), None);
        assert_eq!(child_pid(b"{\"child-pid\":-5}"), None);
    }

    #[test]
    fn process_stat_parser_rejects_unknown_state_instead_of_claiming_exit() {
        for text in ["", "1 (name)", "1 (name) S 1 2"] {
            assert!(parse_stat(text).is_err());
        }
        let text = format!("42 (name with ) and spaces) S {}12345 0 0", "0 ".repeat(18));
        assert_eq!(parse_stat(&text).expect("stat"), ('S', "12345".into()));
        assert!(process(std::process::id()).expect("own stat").is_some());
    }

    #[test]
    fn namespace_wide_cleanup_refuses_outside_namespace_init() {
        assert_ne!(std::process::id(), 1);
        assert!(inner(&["/bin/true".into()]).is_err());
    }

    #[test]
    fn missing_launcher_refuses_before_starting_a_world() {
        let result = outer(&[
            "/must-not-write".into(),
            "1000".into(),
            i32::MAX.to_string(),
            "/must-not-execute".into(),
        ]);
        assert_eq!(
            result.expect_err("missing launcher").to_string(),
            "world launcher exited before supervision"
        );
    }
}
