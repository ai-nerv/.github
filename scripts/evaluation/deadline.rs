use super::*;

fn children() -> io::Result<Vec<Namespace>> {
    let pid = std::process::id();
    let text = fs::read_to_string(format!("/proc/self/task/{pid}/children"))?;
    let mut children = Vec::new();
    for word in text.split_whitespace() {
        let pid = word.parse().map_err(|_| error("invalid child identity"))?;
        if let Some(child) = Namespace::pin(pid)? {
            children.push(child);
        }
    }
    Ok(children)
}

fn cleanup() -> io::Result<bool> {
    let until = Instant::now() + Duration::from_secs(2);
    loop {
        reap();
        let owned = children()?;
        if owned.is_empty() {
            return Ok(true);
        }
        for child in owned {
            child.stop()?;
        }
        if Instant::now() >= until {
            return Ok(false);
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

struct OwnedController(Child);

impl Drop for OwnedController {
    fn drop(&mut self) {
        let _ = stop_child(&mut self.0);
        let _ = cleanup();
    }
}

fn parse_limit(bytes: &[u8], maximum: u64) -> io::Result<u64> {
    let text = std::str::from_utf8(bytes).map_err(|_| error("invalid controller deadline"))?;
    let value = text
        .strip_suffix('\n')
        .and_then(|s| s.parse::<u64>().ok())
        .filter(|n| (1..=maximum).contains(n))
        .ok_or_else(|| error("invalid controller deadline"))?;
    if text != format!("{value}\n") {
        return Err(error("noncanonical controller deadline"));
    }
    Ok(value)
}

fn read_limit(receipt: &str, maximum: u64) -> io::Result<Option<u64>> {
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(0x20000 | 0x800)
        .open(format!("{receipt}/deadline-ms"));
    let file = match file {
        Ok(file) => file,
        Err(why) if why.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(why) => return Err(why),
    };
    if !file.metadata()?.is_file() {
        return Err(error("deadline must be a regular file"));
    }
    let mut bytes = Vec::new();
    file.take(32).read_to_end(&mut bytes)?;
    parse_limit(&bytes, maximum).map(Some)
}

fn parent_of(pid: u32) -> io::Result<u32> {
    let text = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let end = text.rfind(')').ok_or_else(|| error("invalid owner stat"))?;
    text.get(end + 2..)
        .and_then(|rest| rest.split_whitespace().nth(1))
        .and_then(|word| word.parse().ok())
        .ok_or_else(|| error("invalid owner parent"))
}

pub(super) fn run(args: &[String], owned: bool) -> io::Result<i32> {
    let command = if owned { 4 } else { 3 };
    if args.len() <= command {
        return Err(error(
            "control RECEIPT TIMEOUT_MS LAUNCHER_PID [OWNER_PID] COMMAND [ARGS]",
        ));
    }
    let receipt = &args[0];
    let maximum = parse_limit(format!("{}\n", args[1]).as_bytes(), 60000)?;
    let parent: i32 = args[2].parse().map_err(|_| error("invalid launcher pid"))?;
    if parent <= 1 || unsafe { getppid() } != parent {
        return Err(error("controller launcher exited before supervision"));
    }
    let owner = if owned {
        let pid = args[3].parse().map_err(|_| error("invalid owner pid"))?;
        let owner = Namespace::pin(pid)?.ok_or_else(|| error("controller owner exited"))?;
        if parent_of(parent as u32)? != pid || owner.gone()? {
            return Err(error("controller owner is not the launcher's live parent"));
        }
        Some(owner)
    } else {
        None
    };
    signals()?;
    if unsafe { prctl(36, 1usize, 0usize, 0usize, 0usize) } != 0
        || unsafe { prctl(1, 15usize, 0usize, 0usize, 0usize) } != 0
    {
        return Err(io::Error::last_os_error());
    }
    if unsafe { getppid() } != parent {
        return Err(error("controller launcher exited before supervision"));
    }
    let mut output = new_file(&format!("{receipt}/control.json"))?;
    let started = Instant::now();
    let mut child = OwnedController(
        Command::new(&args[command])
            .args(&args[command + 1..])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?,
    );
    let identity = Namespace::pin(child.0.id())?;
    let exceeded = Arc::new(AtomicBool::new(false));
    let readers = vec![
        capture(
            child
                .0
                .stdout
                .take()
                .ok_or_else(|| error("controller stdout"))?,
            &format!("{receipt}/controller.stdout"),
            LIMIT,
            exceeded.clone(),
            None,
        )?,
        capture(
            child
                .0
                .stderr
                .take()
                .ok_or_else(|| error("controller stderr"))?,
            &format!("{receipt}/controller.stderr"),
            LIMIT,
            exceeded.clone(),
            None,
        )?,
    ];
    let mut chosen = None;
    let mut limit = maximum;
    let mut invalid_limit = false;
    let mut timed_out = false;
    let status = loop {
        if let Some(owner) = &owner
            && owner.gone()?
        {
            let _ = SIGNAL.compare_exchange(0, 15, Ordering::Relaxed, Ordering::Relaxed);
        }
        match read_limit(receipt, maximum) {
            Ok(Some(value)) if chosen.is_none() || chosen == Some(value) => {
                chosen = Some(value);
                limit = value;
            }
            Ok(None) if chosen.is_none() => {}
            _ => invalid_limit = true,
        }
        timed_out |= started.elapsed() >= Duration::from_millis(limit);
        if timed_out
            || invalid_limit
            || SIGNAL.load(Ordering::Relaxed) != 0
            || exceeded.load(Ordering::Relaxed)
        {
            if let Some(identity) = &identity {
                identity.send(15)?;
            }
            let until = Instant::now() + Duration::from_secs(2);
            loop {
                if child.0.try_wait()?.is_some() {
                    break;
                }
                if Instant::now() >= until {
                    break;
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            break stop_child(&mut child.0)?;
        }
        if let Some(status) = child.0.try_wait()? {
            break Some(status);
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let leaks = children()?
        .iter()
        .filter(|child| !child.gone().unwrap_or(false))
        .count();
    let cleaned = cleanup()?;
    let streams_ok = collected(readers);
    let elapsed = started.elapsed().as_millis();
    timed_out |= elapsed >= u128::from(limit);
    let interrupted = SIGNAL.load(Ordering::Relaxed);
    let code = status.map(exit_code);
    let confirmed = status.is_some() && cleaned && streams_ok;
    let failed = code != Some(0)
        || timed_out
        || invalid_limit
        || interrupted != 0
        || !confirmed
        || leaks != 0
        || exceeded.load(Ordering::Relaxed);
    writeln!(
        output,
        "{{\"schema\":1,\"scope\":\"evaluation-controller\",\"elapsed_ms\":{elapsed},\"limit_ms\":{limit},\"exit_code\":{},\"timed_out\":{timed_out},\"interrupted\":{interrupted},\"invalid_limit\":{invalid_limit},\"leaked_processes\":{leaks},\"cleanup_confirmed\":{confirmed},\"output_limit_exceeded\":{}}}",
        code.map_or("null".into(), |n| n.to_string()),
        exceeded.load(Ordering::Relaxed)
    )?;
    Ok(if interrupted != 0 {
        128 + interrupted
    } else if timed_out {
        124
    } else {
        i32::from(failed)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launcher_ancestry_uses_the_process_parent_field() {
        assert_eq!(parent_of(std::process::id()).unwrap(), unsafe {
            getppid() as u32
        });
    }

    #[test]
    fn canonical_deadline_cannot_exceed_the_outer_cap() {
        for bytes in [
            b"0\n".as_slice(),
            b"060\n",
            b"+60\n",
            b"60",
            b" 60\n",
            b"60001\n",
            b"60\n\n",
        ] {
            assert!(parse_limit(bytes, 60000).is_err());
        }
        assert_eq!(parse_limit(b"60000\n", 60000).unwrap(), 60000);
        assert!(parse_limit(b"1001\n", 1000).is_err());
        assert_eq!(parse_limit(b"1\n", 1000).unwrap(), 1);
    }
}
