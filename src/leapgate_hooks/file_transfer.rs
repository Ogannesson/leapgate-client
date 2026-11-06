//! The file transfer view's Rust items that need upstream's sessions and `fs`: reading a local
//! folder with the error kept, and removing a link without following it (`LEAPGATE.md` §10.15);
//! the event stream and pausing (§10.17). FT2 and M7b's rules are in `libs/leapgate` (`ft_reason`,
//! `ft`).

use crate::{
    client::{Data, Interface as _},
    common::make_fd_to_json,
    flutter::sessions,
    flutter_ffi::SessionID,
    ui_session_interface::{InvokeUiSession, Session},
};
use base::{
    fs,
    message_proto::{FileAction, FileRemoveDir, FileRemoveFile, FileTransferCancel, Message},
};
use flutter_rust_bridge::StreamSink;
use hbb_common::{allow_err, get_version_number, log, Stream};
use leapgate::ft::{Command, Paused};
use std::sync::Mutex;

/// Held so the UI's stream stays open; nothing is sent on it.
static SUBSCRIPTION: Mutex<Option<StreamSink<String>>> = Mutex::new(None);

/// `leapgate_ft_events`: a new subscription replaces the previous one; the first turns the
/// switch on.
pub(crate) fn set_events(sink: StreamSink<String>) {
    *SUBSCRIPTION.lock().unwrap() = Some(sink);
    leapgate::ft::enable();
}

/// On the session's own event stream as `{"name":"leapgate_ft","value":<event>}`; nothing for a
/// session that is not the app's.
fn push<T: InvokeUiSession>(handler: &Session<T>, event: &str) {
    let ui = &handler.ui_handler as &dyn std::any::Any;
    if let Some(ui) = ui.downcast_ref::<crate::flutter::FlutterHandler>() {
        ui.push_event(leapgate::ft::EVENT, &[("value", event)], &[]);
    }
}

/// `leapgate_ft_pause`, `leapgate_ft_resume`: handled in the session's loop (`command`).
pub(crate) fn send(session_id: SessionID, command: Command) {
    if let Some(session) = sessions::get_session_by_session_id(&session_id) {
        session.send(Data::Leapgate(command));
    }
}

/// `Data::Leapgate` in the session's loop (`io_loop.rs`).
pub(crate) async fn command<T: InvokeUiSession>(
    command: Command,
    handler: &Session<T>,
    read_jobs: &mut Vec<fs::TransferJob>,
    write_jobs: &mut Vec<fs::TransferJob>,
    peer: &mut Stream,
) {
    let version = handler.lc.read().unwrap().version;
    let Some((id, paused)) = handle(
        leapgate::ft::enabled(),
        command,
        version,
        read_jobs,
        write_jobs,
    ) else {
        return;
    };
    if !paused.soft {
        let mut file_action = FileAction::new();
        file_action.set_cancel(FileTransferCancel {
            id,
            ..Default::default()
        });
        let mut msg = Message::new();
        msg.set_file_action(file_action);
        allow_err!(peer.send(&msg).await);
    }
    push(handler, &leapgate::ft::paused_event(id, &paused));
}

/// The jobs' side of a command; `Some` for a pause that took effect. A pause needs a peer at
/// 1.4.2 or later (02), and a job that is running.
fn handle(
    enabled: bool,
    command: Command,
    version: i64,
    read_jobs: &mut [fs::TransferJob],
    write_jobs: &mut Vec<fs::TransferJob>,
) -> Option<(i32, Paused)> {
    if !enabled {
        return None;
    }
    match command {
        Command::Pause { id } => {
            if version < get_version_number("1.4.2") {
                return None;
            }
            let paused = match fs::get_job(id, read_jobs) {
                Some(job) => pause_upload(job)?,
                None => pause_download(id, write_jobs, version)?,
            };
            Some((id, paused))
        }
        Command::Resume { id } => {
            if let Some(job) = fs::get_job(id, read_jobs) {
                job.is_last_job = false;
            }
            None
        }
    }
}

/// M7b-4: the read loop skips a waiting job, so the peer hears nothing and keeps its side as it
/// is. Closing the view saves the job like any other unfinished one.
fn pause_upload(job: &mut fs::TransferJob) -> Option<Paused> {
    if job.is_last_job {
        return None;
    }
    job.is_last_job = true;
    Some(Paused {
        new_id: job.id(),
        soft: true,
        resume_from: job.file_num(),
        restart_file: false,
    })
}

/// Drops the job, keeping its `.download` and `.digest`, and puts a waiting job with a new ID in
/// its place, as `Data::AddJob` would: blocks still on their way for the old ID would land in a
/// job of the same ID and cancel it ("Wrong file number"). The caller tells the peer to cancel.
fn pause_download(
    id: i32,
    write_jobs: &mut Vec<fs::TransferJob>,
    version: i64,
) -> Option<Paused> {
    let job = fs::get_job_immutable(id, write_jobs)?;
    if job.is_last_job || job.r#type != fs::JobType::Generic {
        return None;
    }
    let fs::DataSource::FilePath(to) = &job.data_source else {
        return None;
    };
    let to = to.clone();
    let file_num = job.file_num();
    let finished = job
        .files()
        .get(file_num as usize)
        .zip(job.download_target(file_num).ok())
        .is_some_and(|(entry, target)| {
            leapgate::ft::download_finished(&target, entry.size, entry.modified_time)
        });
    let resume_from = file_num + i32::from(finished);
    let target = job.download_target(resume_from).ok();
    let mut new_job = fs::TransferJob::new_write(
        fs::get_next_job_id(),
        job.r#type,
        job.remote.clone(),
        fs::DataSource::FilePath(to),
        resume_from,
        job.show_hidden,
        job.is_remote,
        fs::can_enable_overwrite_detection(version),
    );
    new_job.is_last_job = true;
    // Closes the staged file before it may be removed.
    drop(fs::remove_job(id, write_jobs));
    let restart_file = target.is_some_and(|t| leapgate::ft::restart_past_resume_offset(&t));
    log::info!(
        "leapgate ft: paused download {id} as {} from file {resume_from}",
        new_job.id()
    );
    let paused = Paused {
        new_id: new_job.id(),
        soft: false,
        resume_from,
        restart_file,
    };
    write_jobs.push(new_job);
    Some(paused)
}

/// M7a-4: what upstream's `session_read_local_dir_sync` returns, or `{"error","reason"}` where
/// it returns an empty string.
pub(crate) fn read_local_dir(path: String, show_hidden: bool) -> String {
    match fs::read_dir(&fs::get_path(&path), show_hidden) {
        Ok(fd) => make_fd_to_json(fd.id, path, &fd.entries),
        Err(err) => {
            let reason = leapgate::ft_reason::classify(&err.to_string(), "", "local");
            serde_json::json!({ "error": reason.text, "reason": reason.reason }).to_string()
        }
    }
}

/// M7a-3: removes the link itself, never what it points to (upstream's folder removal recurses
/// into a folder link's target). The result comes as `job_done` / `job_error` for `act_id`.
pub(crate) fn remove_link(
    session_id: SessionID,
    act_id: i32,
    path: String,
    is_remote: bool,
    is_dir_link: bool,
) {
    let Some(session) = sessions::get_session_by_session_id(&session_id) else {
        return;
    };
    if is_remote {
        let mut msg = Message::new();
        msg.set_file_action(link_action(
            act_id,
            path,
            is_dir_link,
            &session.peer_platform(),
        ));
        session.send(Data::Message(msg));
    } else {
        match remove_local_link(&path) {
            Ok(()) => session.ui_handler.job_done(act_id, 0),
            Err(err) => session.ui_handler.job_error(act_id, err.to_string(), 0),
        }
    }
}

/// A Windows peer removes a folder link or junction with `remove_dir` (non-recursive
/// `FileRemoveDir`); a file link, or any link on another peer, is unlinked with `FileRemoveFile`.
fn link_action(act_id: i32, path: String, is_dir_link: bool, peer_platform: &str) -> FileAction {
    let mut file_action = FileAction::new();
    if is_dir_link && peer_platform == "Windows" {
        file_action.set_remove_dir(FileRemoveDir {
            id: act_id,
            path,
            recursive: false,
            ..Default::default()
        });
    } else {
        file_action.set_remove_file(FileRemoveFile {
            id: act_id,
            path,
            file_num: 0,
            ..Default::default()
        });
    }
    file_action
}

/// Windows tells a folder link or junction by the link's own attributes, not by the listing: a
/// broken one lists as a file link (`entry_type` 5). Elsewhere any link is unlinked.
fn remove_local_link(path: &str) -> std::io::Result<()> {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
        if std::fs::symlink_metadata(path)?.file_attributes() & FILE_ATTRIBUTE_DIRECTORY != 0 {
            return std::fs::remove_dir(path);
        }
    }
    std::fs::remove_file(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs as sfs, path::PathBuf};

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("leapgate-ft-{name}-{}", std::process::id()));
        let _ = sfs::remove_dir_all(&dir);
        sfs::create_dir_all(&dir).unwrap();
        dir
    }

    fn entries(json: &str) -> Vec<(String, bool)> {
        let v: serde_json::Value = serde_json::from_str(json).unwrap();
        let mut entries: Vec<_> = v["entries"]
            .as_array()
            .unwrap()
            .iter()
            .map(|e| {
                (
                    e["name"].as_str().unwrap().to_owned(),
                    e["is_hidden"].as_bool().unwrap(),
                )
            })
            .collect();
        entries.sort();
        entries
    }

    /// FT1: each entry carries `is_hidden`.
    #[test]
    fn read_local_dir_marks_hidden_entries() {
        let dir = scratch("read");
        sfs::write(dir.join("a.txt"), b"a").unwrap();
        #[cfg(windows)]
        let hidden = {
            use std::os::windows::fs::OpenOptionsExt;
            const FILE_ATTRIBUTE_HIDDEN: u32 = 0x2;
            sfs::OpenOptions::new()
                .write(true)
                .create(true)
                .attributes(FILE_ATTRIBUTE_HIDDEN)
                .open(dir.join("h.txt"))
                .unwrap();
            "h.txt"
        };
        #[cfg(not(windows))]
        let hidden = {
            sfs::write(dir.join(".h"), b"h").unwrap();
            ".h"
        };
        let path = dir.to_string_lossy().into_owned();
        let mut expected = vec![("a.txt".to_owned(), false), (hidden.to_owned(), true)];
        expected.sort();
        assert_eq!(entries(&read_local_dir(path.clone(), true)), expected);
        assert_eq!(
            entries(&read_local_dir(path, false)),
            [("a.txt".to_owned(), false)]
        );
        sfs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn read_local_dir_failure_keeps_the_error() {
        let dir = scratch("missing");
        let missing = dir.join("missing").to_string_lossy().into_owned();
        let v: serde_json::Value = serde_json::from_str(&read_local_dir(missing, true)).unwrap();
        assert_eq!(v["reason"], "not_found");
        assert!(v["error"].as_str().unwrap().contains("(os error "), "{v}");
        sfs::remove_dir_all(&dir).unwrap();
    }

    /// Upstream's folder removal empties a folder link's or junction's target and leaves the
    /// target folder (Windows, 02 §4.3 item 15). Removing the link leaves the target as it was.
    #[test]
    fn remove_local_link_keeps_the_target() {
        let dir = scratch("link");
        let target = dir.join("target");
        sfs::create_dir(&target).unwrap();
        sfs::create_dir(target.join("sub")).unwrap();
        sfs::write(target.join("f.txt"), b"x").unwrap();
        let removed = |link: &PathBuf| {
            remove_local_link(&link.to_string_lossy()).unwrap();
            assert!(sfs::symlink_metadata(link).is_err(), "{link:?} still there");
        };
        let check = |link: PathBuf| {
            removed(&link);
            assert_eq!(sfs::read(target.join("f.txt")).unwrap(), b"x");
            assert!(target.join("sub").is_dir());
        };
        #[cfg(windows)]
        {
            use std::os::windows::fs::{symlink_dir, symlink_file};
            // Symbolic links need admin or developer mode (ERROR_PRIVILEGE_NOT_HELD).
            let made = |result: std::io::Result<()>, what: &str| match result {
                Ok(()) => true,
                Err(e) if e.raw_os_error() == Some(1314) => {
                    eprintln!("skipped the {what}: no privilege to create symbolic links");
                    false
                }
                Err(e) => panic!("{what}: {e}"),
            };
            let junction = |link: &PathBuf, target: &PathBuf| {
                let status = std::process::Command::new("cmd")
                    .args(["/C", "mklink", "/J"])
                    .arg(link)
                    .arg(target)
                    .stdout(std::process::Stdio::null())
                    .status()
                    .unwrap();
                assert!(status.success());
            };
            let link = dir.join("dir-symlink");
            if made(symlink_dir(&target, &link), "folder symbolic link") {
                check(link);
            }
            let link = dir.join("file-symlink");
            if made(
                symlink_file(target.join("f.txt"), &link),
                "file symbolic link",
            ) {
                check(link);
            }
            let link = dir.join("junction");
            junction(&link, &target);
            check(link);
            // Broken ones, which upstream lists as file links.
            let gone = dir.join("gone");
            sfs::create_dir(&gone).unwrap();
            let broken_symlink = dir.join("broken-symlink");
            let made_symlink = made(symlink_dir(&gone, &broken_symlink), "folder symbolic link");
            let broken_junction = dir.join("broken-junction");
            junction(&broken_junction, &gone);
            sfs::remove_dir(&gone).unwrap();
            if made_symlink {
                removed(&broken_symlink);
            }
            removed(&broken_junction);
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            let link = dir.join("dir-symlink");
            symlink(&target, &link).unwrap();
            check(link);
            let link = dir.join("file-symlink");
            symlink(target.join("f.txt"), &link).unwrap();
            check(link);
        }
        sfs::remove_dir_all(&dir).unwrap();
    }

    /// A remote folder link is removed without recursing: a non-recursive `RemoveDir` on a
    /// Windows peer, `RemoveFile` elsewhere.
    #[test]
    fn remote_link_removal_never_recurses() {
        use base::message_proto::file_action::Union;
        match link_action(7, r"C:\a\link".to_owned(), true, "Windows").union {
            Some(Union::RemoveDir(d)) => {
                assert_eq!(
                    (d.id, d.path.as_str(), d.recursive),
                    (7, r"C:\a\link", false)
                )
            }
            other => panic!("{other:?}"),
        }
        for (is_dir_link, platform) in [
            (false, "Windows"),
            (true, "Linux"),
            (true, "Mac OS"),
            (true, "Android"),
            (true, ""),
        ] {
            match link_action(7, "/a/link".to_owned(), is_dir_link, platform).union {
                Some(Union::RemoveFile(f)) => {
                    assert_eq!((f.id, f.path.as_str(), f.file_num), (7, "/a/link", 0))
                }
                other => panic!("{platform}: {other:?}"),
            }
        }
    }

    const MODIFIED: u64 = 1_700_000_000;

    fn entry(name: &str, size: u64) -> base::message_proto::FileEntry {
        base::message_proto::FileEntry {
            name: name.to_owned(),
            size,
            modified_time: MODIFIED,
            ..Default::default()
        }
    }

    fn running_download(id: i32, dir: &PathBuf) -> fs::TransferJob {
        let mut job = fs::TransferJob::new_write(
            id,
            fs::JobType::Generic,
            "/remote/folder".to_owned(),
            fs::DataSource::FilePath(dir.clone()),
            0,
            false,
            true,
            true,
        )
        .with_files(vec![entry("a.txt", 3), entry("b.txt", 5)])
        .unwrap();
        job.is_last_job = false;
        job
    }

    fn running_upload(id: i32, dir: &PathBuf) -> fs::TransferJob {
        sfs::write(dir.join("up.txt"), b"up").unwrap();
        let mut job = fs::TransferJob::new_read(
            id,
            fs::JobType::Generic,
            "/remote/folder".to_owned(),
            fs::DataSource::FilePath(dir.clone()),
            0,
            false,
            false,
            true,
        )
        .unwrap();
        job.is_last_job = false;
        job
    }

    fn pause(id: i32) -> Command {
        Command::Pause { id }
    }

    fn v142() -> i64 {
        get_version_number("1.4.2")
    }

    /// With the switch off (the old UI), a command changes nothing.
    #[test]
    fn switch_off_claims_nothing() {
        let dir = scratch("off");
        let mut reads = vec![running_upload(1, &dir)];
        let mut writes = vec![running_download(2, &dir.join("down"))];
        for command in [pause(1), pause(2), Command::Resume { id: 1 }] {
            assert!(handle(false, command, v142(), &mut reads, &mut writes).is_none());
        }
        assert!(!reads[0].is_last_job);
        assert_eq!((writes.len(), writes[0].id(), writes[0].is_last_job), (1, 2, false));
        let older = get_version_number("1.4.1");
        assert!(handle(true, pause(2), older, &mut reads, &mut writes).is_none());
        assert_eq!(writes[0].id(), 2);
        sfs::remove_dir_all(&dir).unwrap();
    }

    /// A paused download waits under a new ID and resumes at the file it was writing, or past
    /// one it had just renamed (resuming there would ask to replace it).
    #[test]
    fn paused_download_resumes_past_a_finished_file() {
        let dir = scratch("pause-down");
        let finished = dir.join("a.txt");
        sfs::write(&finished, b"abc").unwrap();
        sfs::File::options()
            .write(true)
            .open(&finished)
            .unwrap()
            .set_modified(
                std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(MODIFIED),
            )
            .unwrap();
        let staged = scratch("pause-down-staged");
        sfs::write(staged.join("a.txt.download"), b"ab").unwrap();
        for (dir, resume_from) in [(&dir, 1), (&staged, 0)] {
            let mut writes = vec![running_download(10, dir)];
            let old = writes[0].gen_meta();
            let (id, paused) = handle(true, pause(10), v142(), &mut [], &mut writes).unwrap();
            assert_eq!(id, 10);
            assert_eq!(
                (paused.soft, paused.resume_from, paused.restart_file),
                (false, resume_from, false)
            );
            assert_ne!(paused.new_id, 10);
            assert_eq!(writes.len(), 1);
            let job = &writes[0];
            assert_eq!(
                (job.id(), job.is_last_job, job.file_num()),
                (paused.new_id, true, resume_from)
            );
            assert!(job.files().is_empty());
            let new = job.gen_meta();
            assert_eq!(
                (new.remote, new.to, new.show_hidden, new.is_remote, job.r#type),
                (old.remote, old.to, old.show_hidden, old.is_remote, fs::JobType::Generic)
            );
        }
        assert!(staged.join("a.txt.download").exists());
        sfs::remove_dir_all(&dir).unwrap();
        sfs::remove_dir_all(&staged).unwrap();
    }

    /// An upload pauses in place and resumes the same job.
    #[test]
    fn upload_pauses_softly_and_resumes() {
        let dir = scratch("pause-up");
        let mut reads = vec![running_upload(20, &dir)];
        let (_, paused) = handle(true, pause(20), v142(), &mut reads, &mut vec![]).unwrap();
        assert_eq!(
            paused,
            Paused {
                new_id: 20,
                soft: true,
                resume_from: 0,
                restart_file: false
            }
        );
        assert!(reads[0].is_last_job);
        assert!(handle(true, pause(20), v142(), &mut reads, &mut vec![]).is_none());
        assert!(handle(true, Command::Resume { id: 20 }, v142(), &mut reads, &mut vec![]).is_none());
        assert!(!reads[0].is_last_job);
        sfs::remove_dir_all(&dir).unwrap();
    }
}
