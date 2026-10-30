use super::*;
use std::ffi::OsString;
use std::os::unix::ffi::OsStringExt;
use std::os::unix::fs::symlink;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

#[test]
fn build_outputs_copy_aliases_without_weakening_fixture_or_retained_binary_rules() {
    let world = World::new();
    let path = world.root().join("binary");
    fs::write(&path, b"selected build bytes").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    let alias = world.0.join("build-alias");
    fs::hard_link(&path, &alias).unwrap();
    assert!(world.copy("binary", false, MAX_BYTES, 1).is_err());
    assert!(snapshot_binary(&world.root(), "binary", &world.output()).is_err());
    let counts = snapshot_executable(
        &world.root(),
        "binary",
        &world.output(),
        SourceLinks::BuildOutput,
    )
    .unwrap();
    assert_eq!(counts.files, 1);
    let frozen = world.output().join("input");
    assert_eq!(fs::metadata(&frozen).unwrap().nlink(), 1);
    assert_eq!(fs::metadata(&frozen).unwrap().mode() & 0o777, 0o555);
    assert_eq!(fs::metadata(&path).unwrap().nlink(), 2);
    assert_eq!(fs::metadata(&path).unwrap().mode() & 0o777, 0o755);
    fs::write(alias, b"later build bytes").unwrap();
    assert_eq!(fs::read(&frozen).unwrap(), b"selected build bytes");
    assert!(
        snapshot_executable(
            &world.root(),
            "binary",
            &world.output(),
            SourceLinks::BuildOutput
        )
        .is_err()
    );
    assert_eq!(fs::read(frozen).unwrap(), b"selected build bytes");
}

#[test]
fn build_output_mode_retains_path_type_size_and_metadata_guards() {
    let world = World::new();
    let path = world.root().join("binary");
    fs::write(&path, b"bytes").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    symlink(&path, world.root().join("link")).unwrap();
    fs::create_dir(world.root().join("directory")).unwrap();
    for name in ["link", "../binary", "directory"] {
        assert!(
            snapshot_executable(
                &world.root(),
                name,
                &world.output(),
                SourceLinks::BuildOutput
            )
            .is_err()
        );
        assert!(!world.output().exists());
    }
    let before = fs::metadata(&path).unwrap();
    fs::hard_link(&path, world.root().join("alias")).unwrap();
    assert!(!unchanged(&before, &fs::metadata(&path).unwrap()));
    for size in [0, MAX_BINARY_BYTES + 1] {
        OpenOptions::new()
            .write(true)
            .open(&path)
            .unwrap()
            .set_len(size)
            .unwrap();
        assert!(
            snapshot_executable(
                &world.root(),
                "binary",
                &world.output(),
                SourceLinks::BuildOutput
            )
            .is_err()
        );
        assert!(!world.output().exists());
    }
    fs::write(&path, b"bytes").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    assert!(
        snapshot_executable(
            &world.root(),
            "binary",
            &world.output(),
            SourceLinks::BuildOutput
        )
        .is_err()
    );
}

#[test]
fn binary_snapshots_have_separate_bounds_and_readonly_execution() {
    let world = World::new();
    let path = world.root().join("binary");
    File::create(&path).unwrap().set_len(MAX_BYTES + 1).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    assert!(world.copy("binary", false, MAX_BYTES + 1, 1).is_err());
    let counts = snapshot_binary(&world.root(), "binary", &world.output()).unwrap();
    assert_eq!(counts.bytes, MAX_BYTES + 1);
    assert_eq!(counts.files, 1);
    assert_eq!(
        fs::metadata(world.output().join("input")).unwrap().mode() & 0o777,
        0o555
    );
    assert_eq!(fs::metadata(&path).unwrap().mode() & 0o777, 0o700);
    assert!(snapshot_binary(&world.root(), "binary", &world.output()).is_err());
    assert_eq!(
        fs::metadata(world.output().join("input")).unwrap().len(),
        MAX_BYTES + 1
    );
}

#[test]
fn binary_snapshots_refuse_unsafe_inputs_and_cleanup_partial_output() {
    let world = World::new();
    let path = world.root().join("binary");
    fs::write(&path, b"fixture").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    assert!(snapshot_binary(&world.root(), "binary", &world.output()).is_err());
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    fs::hard_link(&path, world.root().join("hardlink")).unwrap();
    assert!(snapshot_binary(&world.root(), "binary", &world.output()).is_err());
    assert!(!world.output().exists());
    fs::remove_file(world.root().join("hardlink")).unwrap();
    symlink(&path, world.root().join("symlink")).unwrap();
    assert!(snapshot_binary(&world.root(), "symlink", &world.output()).is_err());
    assert!(snapshot_binary(&world.root(), "../binary", &world.output()).is_err());
    for size in [0, MAX_BINARY_BYTES + 1] {
        OpenOptions::new()
            .write(true)
            .open(&path)
            .unwrap()
            .set_len(size)
            .unwrap();
        assert!(snapshot_binary(&world.root(), "binary", &world.output()).is_err());
        assert!(!world.output().exists());
    }
    fs::create_dir(world.root().join("directory")).unwrap();
    assert!(snapshot_binary(&world.root(), "directory", &world.output()).is_err());
}

#[test]
fn binary_snapshot_exact_limit_is_inclusive_without_relaxing_fixture_limits() {
    let world = World::new();
    let path = world.root().join("binary");
    File::create(&path)
        .unwrap()
        .set_len(MAX_BINARY_BYTES)
        .unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    assert!(world.copy("binary", false, MAX_BYTES, 1).is_err());
    assert!(world.copy("binary", false, MAX_BINARY_BYTES, 1).is_err());
    assert!(!world.output().exists());
    let counts = snapshot_binary(&world.root(), "binary", &world.output()).unwrap();
    assert_eq!(counts.bytes, MAX_BINARY_BYTES);
    assert_eq!(
        fs::metadata(world.output().join("input")).unwrap().len(),
        MAX_BINARY_BYTES
    );
}

pub(super) struct World(PathBuf);

impl World {
    pub(super) fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "nerv-eval-input-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::DirBuilder::new()
            .mode(0o700)
            .create(&path)
            .expect("private fixture");
        fs::create_dir(path.join("root")).expect("root");
        Self(path)
    }

    pub(super) fn root(&self) -> PathBuf {
        self.0.join("root")
    }
    pub(super) fn output(&self) -> PathBuf {
        self.0.join("output")
    }

    fn copy(&self, path: &str, tree: bool, bytes: u64, files: u64) -> io::Result<Counts> {
        snapshot(
            &self.root(),
            path,
            &self.output(),
            tree,
            Limits { bytes, files },
        )
    }
}

impl Drop for World {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).expect("fixture cleanup");
    }
}

#[test]
fn snapshots_exact_bytes_in_private_files_without_changing_source() {
    let world = World::new();
    fs::create_dir(world.root().join("fixture")).unwrap();
    fs::create_dir(world.root().join("fixture/sub")).unwrap();
    let bytes = b"full\0bytes\r\n\xff";
    fs::write(world.root().join("fixture/sub/source"), bytes).unwrap();
    fs::write(world.root().join("fixture/empty"), b"").unwrap();
    let counts = world.copy("fixture", true, bytes.len() as u64, 2).unwrap();
    assert_eq!(counts.files, 2);
    assert_eq!(counts.bytes, bytes.len() as u64);
    assert_eq!(fs::read(world.output().join("sub/source")).unwrap(), bytes);
    assert_eq!(
        fs::read(world.root().join("fixture/sub/source")).unwrap(),
        bytes
    );
    assert_eq!(
        fs::metadata(world.output()).unwrap().permissions().mode() & 0o777,
        0o700
    );
    assert_eq!(
        fs::metadata(world.output().join("sub/source"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
}

#[test]
fn rejects_absolute_parent_empty_and_excessively_deep_paths() {
    let world = World::new();
    fs::write(world.root().join("source"), "safe").unwrap();
    for path in [
        "",
        "/source",
        "../source",
        "./source",
        "a/../source",
        "a//source",
        "source/",
        "a/./source",
    ] {
        assert!(world.copy(path, false, 100, 1).is_err(), "{path:?}");
        assert!(!world.output().exists());
    }
    assert!(world.copy(&"x/".repeat(17), false, 100, 1).is_err());
    assert!(world.copy(&"x".repeat(4097), false, 100, 1).is_err());
}

#[test]
fn refuses_symlinks_at_root_parent_leaf_and_inside_tree() {
    let world = World::new();
    fs::create_dir(world.0.join("outside")).unwrap();
    fs::write(world.0.join("outside/private"), "outside").unwrap();
    symlink(world.0.join("outside"), world.root().join("alias")).unwrap();
    symlink(world.0.join("outside/private"), world.root().join("leaf")).unwrap();
    assert!(world.copy("alias/private", false, 100, 1).is_err());
    assert!(world.copy("leaf", false, 100, 1).is_err());
    assert!(world.copy("alias", true, 100, 1).is_err());
    fs::create_dir(world.root().join("fixture")).unwrap();
    symlink(
        world.0.join("outside/private"),
        world.root().join("fixture/leaf"),
    )
    .unwrap();
    assert!(world.copy("fixture", true, 100, 1).is_err());
    assert!(!world.output().exists());
    symlink(world.root(), world.0.join("root-link")).unwrap();
    assert!(
        snapshot(
            &world.0.join("root-link"),
            "leaf",
            &world.output(),
            false,
            Limits {
                bytes: 100,
                files: 1
            }
        )
        .is_err()
    );
    assert_eq!(
        fs::read_to_string(world.0.join("outside/private")).unwrap(),
        "outside"
    );
}

#[test]
fn refuses_hardlinks_and_nonregular_inputs_without_blocking() {
    let world = World::new();
    fs::write(world.root().join("source"), "safe").unwrap();
    fs::hard_link(world.root().join("source"), world.root().join("link")).unwrap();
    assert!(world.copy("link", false, 100, 1).is_err());
    assert!(!world.output().exists());
    let socket = std::os::unix::net::UnixListener::bind(world.root().join("socket")).unwrap();
    assert!(world.copy("socket", false, 100, 1).is_err());
    assert!(world.copy("source", true, 100, 1).is_err());
    drop(socket);
}

#[test]
fn exact_file_and_byte_limits_are_inclusive_and_overflow_refuses() {
    let world = World::new();
    fs::create_dir(world.root().join("fixture")).unwrap();
    for index in 0..256 {
        fs::write(world.root().join(format!("fixture/{index}")), "x").unwrap();
    }
    assert_eq!(world.copy("fixture", true, 256, 256).unwrap().files, 256);
    fs::remove_dir_all(world.output()).unwrap();
    assert!(world.copy("fixture", true, 255, 256).is_err());
    assert!(!world.output().exists());
    assert!(world.copy("fixture", true, 256, 255).is_err());
    assert!(!world.output().exists());
    let oversized = File::create(world.root().join("large")).unwrap();
    oversized.set_len(MAX_BYTES + 1).unwrap();
    assert!(world.copy("large", false, MAX_BYTES, 1).is_err());
    assert!(!world.output().exists());
    assert!(world.copy("large", false, MAX_BYTES + 1, 1).is_err());
    assert!(world.copy("fixture", true, 256, 257).is_err());
}

#[test]
fn never_replaces_or_removes_an_existing_destination() {
    let world = World::new();
    fs::write(world.root().join("source"), "new").unwrap();
    fs::create_dir(world.output()).unwrap();
    fs::write(world.output().join("sentinel"), "keep").unwrap();
    assert!(world.copy("source", false, 100, 1).is_err());
    assert_eq!(
        fs::read_to_string(world.output().join("sentinel")).unwrap(),
        "keep"
    );
    fs::remove_dir_all(world.output()).unwrap();
    symlink(world.root(), world.output()).unwrap();
    assert!(world.copy("source", false, 100, 1).is_err());
    assert!(world.output().is_symlink());
    assert_eq!(
        fs::read_to_string(world.root().join("source")).unwrap(),
        "new"
    );
}

#[test]
fn pinned_root_does_not_follow_a_replaced_path_binding() {
    let world = World::new();
    fs::write(world.root().join("source"), "original").unwrap();
    let pinned = opened(&world.root(), true).unwrap();
    fs::rename(world.root(), world.0.join("old-root")).unwrap();
    fs::create_dir(world.root()).unwrap();
    fs::write(world.root().join("source"), "replacement").unwrap();
    let mut selected = relative(&pinned, "source", false).unwrap();
    let mut text = String::new();
    selected.read_to_string(&mut text).unwrap();
    assert_eq!(text, "original");
}

#[test]
fn rejects_excessive_directory_entries_depth_and_unrepresentable_names() {
    let world = World::new();
    fs::create_dir(world.root().join("fixture")).unwrap();
    for index in 0..513 {
        fs::create_dir(world.root().join(format!("fixture/{index}"))).unwrap();
    }
    assert!(world.copy("fixture", true, 100, 1).is_err());
    assert!(!world.output().exists());
    fs::remove_dir_all(world.root().join("fixture")).unwrap();
    fs::create_dir_all(
        world
            .root()
            .join(format!("fixture/{}", "nested/".repeat(17))),
    )
    .unwrap();
    assert!(world.copy("fixture", true, 100, 1).is_err());
    assert!(!world.output().exists());
    fs::remove_dir_all(world.root().join("fixture")).unwrap();
    fs::create_dir(world.root().join("fixture")).unwrap();
    fs::write(
        world
            .root()
            .join("fixture")
            .join(OsString::from_vec(vec![0xff])),
        "bad",
    )
    .unwrap();
    assert!(world.copy("fixture", true, 100, 1).is_err());
    assert!(!world.output().exists());
}

#[test]
fn metadata_changes_are_not_accepted_as_an_unchanged_snapshot() {
    let world = World::new();
    fs::write(world.root().join("source"), "before").unwrap();
    let file = opened(&world.root().join("source"), false).unwrap();
    let before = file.metadata().unwrap();
    assert!(unchanged(&before, &file.metadata().unwrap()));
    fs::write(world.root().join("source"), "after-length-change").unwrap();
    assert!(!unchanged(&before, &file.metadata().unwrap()));
}
