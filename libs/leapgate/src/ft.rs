//! M7b (`LEAPGATE.md` §10.17): the new UI's switch for Leapgate's file transfer handling, the
//! commands it sends a session's loop, and the rules the hooks in the root crate apply. FT2 is
//! in `ft_reason`.

use hbb_common::{log, serde_json};
use std::{
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    time::UNIX_EPOCH,
};

static ENABLED: AtomicBool = AtomicBool::new(false);

/// On once the new UI subscribes to `leapgate_ft_events`. Off, every hook leaves upstream's path
/// alone: the old UI never subscribes.
pub fn enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

pub fn enable() {
    ENABLED.store(true, Ordering::Relaxed);
}

/// `Data::Leapgate`: what the UI asks a file transfer session's loop to do.
#[derive(Clone, Debug)]
pub enum Command {
    Pause { id: i32 },
    /// Only for an upload paused in this session.
    Resume { id: i32 },
}

/// The session's own event stream carries M7b's events under this name, so they keep their
/// order with upstream's `job_done` and `job_progress`.
pub const EVENT: &str = "leapgate_ft";

/// A pause that took effect: `new_id` is the job that now waits in its place (`id` itself for a
/// soft pause), `resume_from` the file it starts at (0-based).
#[derive(Debug, PartialEq)]
pub struct Paused {
    pub new_id: i32,
    pub soft: bool,
    pub resume_from: i32,
    pub restart_file: bool,
}

/// The `paused` event's `value`: one JSON object, as upstream's `load_last_job` sends its job.
/// Not the event's own fields: upstream writes the event name into `name`, which `file_failed`
/// uses for the path.
pub fn paused_event(id: i32, paused: &Paused) -> String {
    serde_json::json!({
        "kind": "paused",
        "id": id,
        "new_id": paused.new_id,
        "soft": paused.soft,
        "resume_from": paused.resume_from,
        "restart_file": paused.restart_file,
    })
    .to_string()
}

/// Whether a download already finished `target`: renamed from its `.download` and given the
/// listing's size and modified time (Unix seconds; FAT32 keeps it to 2 seconds). Upstream renames
/// a file only when the next file's digest arrives, so until the next file's first block the
/// job's file number still points at the finished file, and resuming there would ask to replace
/// it.
pub fn download_finished(target: &Path, size: u64, modified: u64) -> bool {
    if staging(target, "download").exists() {
        return false;
    }
    let Ok(meta) = std::fs::metadata(target) else {
        return false;
    };
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs());
    meta.is_file() && meta.len() == size && mtime.is_some_and(|t| t.abs_diff(modified) <= 2)
}

/// M7b-5: the resume offset is 32 bits (`OffsetBlk`), so a staged part past it cannot resume.
fn past_resume_offset(staged: u64) -> bool {
    staged > u64::from(u32::MAX)
}

/// Removes `target`'s `.download` and `.digest` when the staged part is past the resume offset,
/// so the file restarts instead of failing; `true` when it did. A leftover `.digest` alone would
/// make the restart ask to replace the file.
pub fn restart_past_resume_offset(target: &Path) -> bool {
    let download = staging(target, "download");
    let Ok(meta) = std::fs::metadata(&download) else {
        return false;
    };
    if !past_resume_offset(meta.len()) {
        return false;
    }
    for path in [download, staging(target, "digest")] {
        match std::fs::remove_file(&path) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                log::warn!("leapgate ft: cannot remove {}: {err}", path.display());
                return false;
            }
        }
    }
    true
}

fn staging(target: &Path, suffix: &str) -> std::path::PathBuf {
    format!("{}.{suffix}", target.display()).into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        path::PathBuf,
        time::{Duration, SystemTime},
    };

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("leapgate-ft-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A file renamed and stamped like upstream's `finish_download` counts as finished, to
    /// FAT32's 2 seconds; one still staged, or another file of the same name, does not.
    #[test]
    fn finished_download_is_told_from_a_staged_one() {
        let dir = scratch("finished");
        let target = dir.join("a.txt");
        let modified = 1_700_000_000;
        fs::write(&target, b"abc").unwrap();
        fs::File::options()
            .write(true)
            .open(&target)
            .unwrap()
            .set_modified(SystemTime::UNIX_EPOCH + Duration::from_secs(modified))
            .unwrap();
        assert!(download_finished(&target, 3, modified));
        assert!(!download_finished(&target, 4, modified));
        assert!(download_finished(&target, 3, modified + 1));
        assert!(download_finished(&target, 3, modified - 2));
        assert!(!download_finished(&target, 3, modified + 3));
        fs::write(dir.join("a.txt.download"), b"ab").unwrap();
        assert!(!download_finished(&target, 3, modified));
        assert!(!download_finished(&dir.join("missing"), 0, modified));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn paused_event_reads_as_documented() {
        let paused = Paused {
            new_id: 8,
            soft: false,
            resume_from: 3,
            restart_file: true,
        };
        let v: serde_json::Value = serde_json::from_str(&paused_event(7, &paused)).unwrap();
        assert_eq!(
            v,
            serde_json::json!({"kind": "paused", "id": 7, "new_id": 8, "soft": false,
                "resume_from": 3, "restart_file": true})
        );
    }

    /// A staged part of `u32::MAX` bytes resumes; one byte more restarts, with its digest gone.
    #[test]
    fn only_a_part_past_32_bits_restarts() {
        let dir = scratch("offset");
        let target = dir.join("big.bin");
        let download = dir.join("big.bin.download");
        let digest = dir.join("big.bin.digest");
        let staged = |len: u64| fs::File::create(&download).unwrap().set_len(len).unwrap();
        staged(u64::from(u32::MAX));
        fs::write(&digest, b"{}").unwrap();
        assert!(!restart_past_resume_offset(&target));
        assert!(download.exists() && digest.exists());
        staged(u64::from(u32::MAX) + 1);
        assert!(restart_past_resume_offset(&target));
        assert!(!download.exists() && !digest.exists());
        fs::remove_dir_all(&dir).unwrap();
    }
}
