//! Bounded descriptor-relative snapshots of offline evaluation inputs.

#[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
compile_error!("evaluation input snapshots currently require Linux x86_64");

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};

mod ipc_archive;
mod json_input;
mod prefix_input;

const DIRECTORY: i32 = 0x10000;
const NOFOLLOW: i32 = 0x20000;
const NONBLOCK: i32 = 0x800;
const PATH_ONLY: i32 = 0x200000;
const MAX_BYTES: u64 = 16 * 1024 * 1024;
const MAX_BINARY_BYTES: u64 = 64 * 1024 * 1024;
const MAX_FILES: u64 = 256;
const MAX_ENTRIES: u64 = 512;

fn refused(message: &str) -> io::Error {
    io::Error::other(message)
}

fn descriptor(file: &File) -> PathBuf {
    PathBuf::from(format!("/proc/self/fd/{}", file.as_raw_fd()))
}

fn opened(path: &Path, directory: bool) -> io::Result<File> {
    let pinned = OpenOptions::new()
        .read(true)
        .custom_flags(NOFOLLOW | PATH_ONLY | if directory { DIRECTORY } else { 0 })
        .open(path)?;
    let metadata = pinned.metadata()?;
    if !metadata.is_dir() && !metadata.is_file() {
        return Err(refused("input is not a regular file or directory"));
    }
    OpenOptions::new()
        .read(true)
        .custom_flags(NONBLOCK)
        .open(descriptor(&pinned))
}

fn relative(root: &File, path: &str, directory: bool) -> io::Result<File> {
    if path.is_empty()
        || path.len() > 4096
        || path
            .split('/')
            .any(|p| p.is_empty() || p == "." || p == "..")
    {
        return Err(refused("invalid relative input path"));
    }
    let components: Vec<_> = Path::new(path).components().collect();
    if components.len() > 16
        || components
            .iter()
            .any(|p| !matches!(p, Component::Normal(_)))
    {
        return Err(refused("invalid relative input components"));
    }
    let mut held = root.try_clone()?;
    for (index, component) in components.iter().enumerate() {
        held = opened(
            &descriptor(&held).join(component.as_os_str()),
            index + 1 != components.len() || directory,
        )?;
    }
    Ok(held)
}

fn unchanged(before: &fs::Metadata, after: &fs::Metadata) -> bool {
    before.dev() == after.dev()
        && before.ino() == after.ino()
        && before.mode() == after.mode()
        && before.uid() == after.uid()
        && before.gid() == after.gid()
        && before.nlink() == after.nlink()
        && before.len() == after.len()
        && before.mtime() == after.mtime()
        && before.mtime_nsec() == after.mtime_nsec()
        && before.ctime() == after.ctime()
        && before.ctime_nsec() == after.ctime_nsec()
}

#[derive(Default, Debug, PartialEq, Eq)]
struct Counts {
    bytes: u64,
    files: u64,
    entries: u64,
}

struct Limits {
    bytes: u64,
    files: u64,
}

enum SourceLinks {
    Single,
    BuildOutput,
}

fn copy_file(
    mut source: File,
    destination: &Path,
    limits: &Limits,
    counts: &mut Counts,
    links: SourceLinks,
) -> io::Result<()> {
    let before = source.metadata()?;
    if !before.is_file()
        || before.nlink() == 0
        || (matches!(links, SourceLinks::Single) && before.nlink() != 1)
    {
        return Err(refused("input has an invalid file type or link count"));
    }
    let room = limits
        .bytes
        .checked_sub(counts.bytes)
        .ok_or_else(|| refused("input byte limit"))?;
    if before.len() > room || counts.files >= limits.files {
        return Err(refused("input byte or file limit"));
    }
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(NOFOLLOW)
        .open(destination)?;
    let mut buffer = [0; 8192];
    let mut copied = 0u64;
    loop {
        let amount = source.read(&mut buffer)?;
        if amount == 0 {
            break;
        }
        copied += amount as u64;
        if copied > before.len() || copied > room {
            return Err(refused("input grew during snapshot"));
        }
        output.write_all(&buffer[..amount])?;
    }
    if copied != before.len() || !unchanged(&before, &source.metadata()?) {
        return Err(refused("input changed during snapshot"));
    }
    output.sync_all()?;
    counts.files += 1;
    counts.bytes += copied;
    Ok(())
}

fn copy_tree(
    source: File,
    destination: &Path,
    depth: usize,
    limits: &Limits,
    counts: &mut Counts,
) -> io::Result<()> {
    if depth > 16 {
        return Err(refused("input directory depth limit"));
    }
    let before = source.metadata()?;
    if !before.is_dir() {
        return Err(refused("input is not a directory"));
    }
    let mut names = Vec::new();
    for entry in fs::read_dir(descriptor(&source))? {
        counts.entries += 1;
        if counts.entries > MAX_ENTRIES {
            return Err(refused("input entry limit"));
        }
        let name = entry?.file_name();
        if name.to_str().is_none_or(|name| name.contains(['\n', '\r'])) {
            return Err(refused("input filename cannot be represented"));
        }
        names.push(name);
    }
    names.sort();
    for name in names {
        let child = opened(&descriptor(&source).join(&name), false)?;
        let metadata = child.metadata()?;
        let path = destination.join(&name);
        if metadata.is_dir() {
            fs::DirBuilder::new().mode(0o700).create(&path)?;
            copy_tree(child, &path, depth + 1, limits, counts)?;
        } else {
            copy_file(child, &path, limits, counts, SourceLinks::Single)?;
        }
    }
    if !unchanged(&before, &source.metadata()?) {
        return Err(refused("input directory changed during snapshot"));
    }
    Ok(())
}

fn snapshot(
    root: &Path,
    path: &str,
    destination: &Path,
    tree: bool,
    limits: Limits,
) -> io::Result<Counts> {
    if limits.bytes == 0
        || limits.bytes > MAX_BYTES
        || limits.files == 0
        || limits.files > MAX_FILES
    {
        return Err(refused("invalid snapshot limits"));
    }
    let root = opened(root, true)?;
    let source = relative(&root, path, tree)?;
    fs::DirBuilder::new().mode(0o700).create(destination)?;
    let mut counts = Counts::default();
    let result = if tree {
        copy_tree(source, destination, 0, &limits, &mut counts)
    } else {
        copy_file(
            source,
            &destination.join("input"),
            &limits,
            &mut counts,
            SourceLinks::Single,
        )
    };
    if let Err(error) = result {
        fs::remove_dir_all(destination)?;
        return Err(error);
    }
    Ok(counts)
}

fn snapshot_binary(root: &Path, path: &str, destination: &Path) -> io::Result<Counts> {
    snapshot_executable(root, path, destination, SourceLinks::Single)
}

fn snapshot_executable(
    root: &Path,
    path: &str,
    destination: &Path,
    links: SourceLinks,
) -> io::Result<Counts> {
    let root = opened(root, true)?;
    let source = relative(&root, path, false)?;
    let metadata = source.metadata()?;
    if !metadata.is_file() || metadata.mode() & 0o111 == 0 || metadata.len() == 0 {
        return Err(refused("binary must be a nonempty executable file"));
    }
    let retained = source.try_clone()?;
    fs::DirBuilder::new().mode(0o700).create(destination)?;
    let mut counts = Counts::default();
    let result = copy_file(
        source,
        &destination.join("input"),
        &Limits {
            bytes: MAX_BINARY_BYTES,
            files: 1,
        },
        &mut counts,
        links,
    )
    .and_then(|()| {
        if !unchanged(&metadata, &retained.metadata()?) {
            return Err(refused("binary changed during snapshot"));
        }
        fs::set_permissions(destination.join("input"), fs::Permissions::from_mode(0o555))
    });
    if let Err(error) = result {
        fs::remove_dir_all(destination)?;
        return Err(error);
    }
    Ok(counts)
}

fn run() -> io::Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|mode| mode == "ipc-unpack") {
        return ipc_archive::run(&args);
    }
    if args.first().is_some_and(|mode| mode == "prefix") {
        return prefix_input::run(&args);
    }
    if args
        .first()
        .is_some_and(|mode| mode == "json" || mode == "json-wire")
    {
        return json_input::run(&args);
    }
    let binary = args.len() == 4 && matches!(args[0].as_str(), "binary" | "build-binary");
    if !binary && (args.len() != 6 || !matches!(args[0].as_str(), "file" | "tree")) {
        return Err(refused(
            "usage: eval-input file|tree ROOT RELATIVE DESTINATION MAX_BYTES MAX_FILES; eval-input binary|build-binary ROOT RELATIVE DESTINATION",
        ));
    }
    let counts = if binary {
        if args[0] == "build-binary" {
            snapshot_executable(
                Path::new(&args[1]),
                &args[2],
                Path::new(&args[3]),
                SourceLinks::BuildOutput,
            )?
        } else {
            snapshot_binary(Path::new(&args[1]), &args[2], Path::new(&args[3]))?
        }
    } else {
        snapshot(
            Path::new(&args[1]),
            &args[2],
            Path::new(&args[3]),
            args[0] == "tree",
            Limits {
                bytes: args[4].parse().map_err(|_| refused("invalid byte limit"))?,
                files: args[5].parse().map_err(|_| refused("invalid file limit"))?,
            },
        )?
    };
    println!(
        "{{\"files\":{},\"bytes\":{},\"entries\":{}}}",
        counts.files, counts.bytes, counts.entries
    );
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("evaluation input: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
#[path = "input_tests.rs"]
mod tests;
