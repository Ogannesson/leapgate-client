//! The file transfer view's Rust items that need upstream's sessions and `fs`: reading a local
//! folder with the error kept, and removing a link without following it (`LEAPGATE.md` §10.15);
//! the event stream, pausing, and keeping or skipping on failure (§10.17). FT2 and M7b's rules
//! are in `libs/leapgate` (`ft_reason`, `ft`, `ft_read`).
//!
//! Built without flutter too, so the hooks in `io_loop.rs` need no `cfg`: there the switch is
//! never on and every hook leaves upstream's path alone.

#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
use crate::{
    client::{Data, Interface as _},
    common::make_fd_to_json,
    flutter::sessions,
    flutter_ffi::SessionID,
};
use crate::ui_session_interface::{InvokeUiSession, Session};
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
use base::message_proto::{FileRemoveDir, FileRemoveFile};
use base::{
    fs,
    message_proto::{FileAction, FileTransferCancel, FileTransferDigest, FileTransferError, Message},
};
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
use flutter_rust_bridge::StreamSink;
use hbb_common::{allow_err, get_version_number, log, ResultType, Stream};
use leapgate::ft::{Command, Fault, Paused};
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
use std::sync::Mutex;

/// Held so the UI's stream stays open; nothing is sent on it.
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
static SUBSCRIPTION: Mutex<Option<StreamSink<String>>> = Mutex::new(None);

/// `leapgate_ft_events`: a new subscription replaces the previous one; the first turns the
/// switch on.
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub(crate) fn set_events(sink: StreamSink<String>) {
    *SUBSCRIPTION.lock().unwrap() = Some(sink);
    leapgate::ft::enable();
}

/// On the session's own event stream as `{"name":"leapgate_ft","value":<event>}`; nothing for a
/// session that is not the app's.
fn push<T: InvokeUiSession>(handler: &Session<T>, event: &str) {
    #[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
    {
        let ui = &handler.ui_handler as &dyn std::any::Any;
        if let Some(ui) = ui.downcast_ref::<crate::flutter::FlutterHandler>() {
            ui.push_event(leapgate::ft::EVENT, &[("value", event)], &[]);
        }
    }
    #[cfg(not(any(target_os = "android", target_os = "ios", feature = "flutter")))]
    let _ = (handler, event);
}

fn cancel(id: i32) -> Message {
    let mut file_action = FileAction::new();
    file_action.set_cancel(FileTransferCancel {
        id,
        ..Default::default()
    });
    let mut msg = Message::new();
    msg.set_file_action(file_action);
    msg
}

/// `leapgate_ft_pause`, `leapgate_ft_resume`: handled in the session's loop (`command`).
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
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
        allow_err!(peer.send(&cancel(id)).await);
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

// ---- Failures (FT4, FT5) ----
// Each hook returns `true` when it handled the error, so `io_loop.rs` skips upstream's handling
// (which cancels the job, removes the file being written and sends `job_error`). The decisions
// are in the `on_*` functions, which only record what to send and to push (`Effects`).

/// What a hook sends the peer, then pushes to the UI.
#[derive(Default)]
struct Effects {
    msgs: Vec<Message>,
    events: Vec<String>,
    /// Upstream's `job_done`, for a download whose last file failed.
    done: Option<(i32, i32)>,
}

impl Effects {
    async fn apply<T: InvokeUiSession>(self, handler: &Session<T>, peer: &mut Stream) {
        for msg in &self.msgs {
            allow_err!(peer.send(msg).await);
        }
        for event in &self.events {
            push(handler, event);
        }
        if let Some((id, file_num)) = self.done {
            handler.job_done(id, file_num);
        }
    }
}

/// The upload read loop (`io_loop.rs`, the timer's `fs::handle_read_jobs`): see `ft_read`.
pub(crate) async fn read_jobs<T: InvokeUiSession>(
    handler: &Session<T>,
    jobs: &mut Vec<fs::TransferJob>,
    peer: &mut Stream,
) -> ResultType<()> {
    read_jobs_on(leapgate::ft::enabled(), handler, jobs, peer).await
}

async fn read_jobs_on<T: InvokeUiSession>(
    on: bool,
    handler: &Session<T>,
    jobs: &mut Vec<fs::TransferJob>,
    peer: &mut Stream,
) -> ResultType<()> {
    if !on {
        return fs::handle_read_jobs(jobs, peer).await.map(|_| ());
    }
    let step = leapgate::ft_read::step(jobs).await;
    for msg in &step.out {
        peer.send(msg).await?;
    }
    for f in step.failed {
        log::info!("leapgate ft: upload {} left out file {}: {}", f.id, f.file_num, f.err);
        let event = leapgate::ft::file_failed_event(f.id, f.file_num, &f.name, &f.err, "local");
        push(handler, &event);
    }
    Ok(())
}

/// A download's digest check failed (`io_loop.rs`, before upstream cancels the job). The check
/// first renames the file before it, so either that rename failed, or this file's name or path
/// cannot be written here (a name invalid on Windows, a link in the path).
pub(crate) async fn digest_failed<T: InvokeUiSession>(
    handler: &Session<T>,
    write_jobs: &mut Vec<fs::TransferJob>,
    digest: &FileTransferDigest,
    err: &str,
    peer: &mut Stream,
) -> bool {
    let mut fx = Effects::default();
    let on = leapgate::ft::enabled();
    let claimed = on_digest_failed(on, &handler.peer_platform(), write_jobs, digest, err, &mut fx);
    fx.apply(handler, peer).await;
    claimed
}

fn on_digest_failed(
    on: bool,
    peer_platform: &str,
    write_jobs: &mut Vec<fs::TransferJob>,
    digest: &FileTransferDigest,
    err: &str,
    fx: &mut Effects,
) -> bool {
    let Some(job) = claimable(on, write_jobs, digest.id) else {
        return false;
    };
    let before = job.file_num();
    let renaming = before != digest.file_num && staged(job, before);
    let failed = if renaming { before } else { digest.file_num };
    match local_fault(peer_platform, job, err) {
        Fault::Upstream => return false,
        Fault::Stop => stop_download(write_jobs, digest.id, failed, Some((err, "local")), fx),
        Fault::File => {
            file_failed(job, failed, err, "local", fx);
            if renaming {
                stop_download(write_jobs, digest.id, digest.file_num, None, fx);
            } else {
                fx.msgs
                    .push(leapgate::ft_read::skip(digest.id, digest.file_num));
            }
        }
    }
    true
}

/// A downloaded block could not be written (`io_loop.rs`, before upstream cancels the job).
/// Writing a block of a new file first renames the one before it; whichever failed is the one
/// still staged. A full disk keeps the job (`kept`); another failure leaves the file out and the
/// UI starts again from the next one: the peer may already be reading it.
pub(crate) async fn write_failed<T: InvokeUiSession>(
    handler: &Session<T>,
    write_jobs: &mut Vec<fs::TransferJob>,
    id: i32,
    block_file_num: i32,
    err: &str,
    peer: &mut Stream,
) -> bool {
    let mut fx = Effects::default();
    let (on, platform) = (leapgate::ft::enabled(), handler.peer_platform());
    let claimed = on_write_failed(on, &platform, write_jobs, id, block_file_num, err, &mut fx);
    fx.apply(handler, peer).await;
    claimed
}

fn on_write_failed(
    on: bool,
    peer_platform: &str,
    write_jobs: &mut Vec<fs::TransferJob>,
    id: i32,
    block_file_num: i32,
    err: &str,
    fx: &mut Effects,
) -> bool {
    let Some(job) = claimable(on, write_jobs, id) else {
        return false;
    };
    let before = job.file_num();
    let failed = if before != block_file_num && staged(job, before) {
        before
    } else {
        block_file_num
    };
    match local_fault(peer_platform, job, err) {
        Fault::Upstream => return false,
        Fault::Stop => stop_download(write_jobs, id, failed, Some((err, "local")), fx),
        Fault::File => {
            file_failed(job, failed, err, "local", fx);
            stop_download(write_jobs, id, failed + 1, None, fx);
        }
    }
    true
}

/// The peer's `FileTransferError` (`io_loop.rs`, before upstream removes the job).
///
/// Download: the peer could not read a file. Its number in the error is one past the file (the
/// peer moves on before reporting). Whether the peer reads on afterwards depends on it (a
/// Windows CM ends the job), so this side stops: the file before it, complete, is renamed, the
/// failed one keeps its staged part, and the UI starts again from the next file. An error before
/// any file is listed is the peer refusing the job: upstream's.
///
/// Upload: the peer could not write a file, and keeps its job. The file is skipped on both sides
/// (the peer drops its part); a full disk stops this side's job and leaves the peer's, so a retry
/// resumes where the peer stopped. An error before the first file was confirmed is upstream's.
pub(crate) async fn peer_error<T: InvokeUiSession>(
    handler: &Session<T>,
    read_jobs: &mut Vec<fs::TransferJob>,
    write_jobs: &mut Vec<fs::TransferJob>,
    e: &FileTransferError,
    peer: &mut Stream,
) -> bool {
    let mut fx = Effects::default();
    let (on, platform) = (leapgate::ft::enabled(), handler.peer_platform());
    let claimed = on_peer_error(on, &platform, read_jobs, write_jobs, e, &mut fx);
    fx.apply(handler, peer).await;
    claimed
}

fn on_peer_error(
    on: bool,
    peer_platform: &str,
    read_jobs: &mut Vec<fs::TransferJob>,
    write_jobs: &mut Vec<fs::TransferJob>,
    e: &FileTransferError,
    fx: &mut Effects,
) -> bool {
    if !on {
        return false;
    }
    let id = e.id;
    let reason = leapgate::ft_reason::classify(&e.error, peer_platform, "remote");
    let fault = single_file(leapgate::ft::fault(reason.reason), write_jobs, read_jobs, id);
    if let Some(job) = claimable(on, write_jobs, id) {
        let failed = e.file_num - 1;
        if fault == Fault::Upstream || failed < 0 || failed as usize >= job.files().len() {
            return false;
        }
        if fault == Fault::Stop {
            stop_download(write_jobs, id, failed, Some((&e.error, "remote")), fx);
            return true;
        }
        if job.file_num() < failed {
            if let Err(err) = job.finish_download() {
                file_failed(job, job.file_num(), &err.to_string(), "local", fx);
            }
        }
        file_failed(job, failed, &e.error, "remote", fx);
        stop_download(write_jobs, id, failed + 1, None, fx);
        return true;
    }
    let Some(job) = fs::get_job(id, read_jobs).filter(|j| j.r#type == fs::JobType::Generic) else {
        // A job stopped here, which the peer goes on erring for.
        return leapgate::ft::stopped(id);
    };
    let failed = e.file_num;
    let first_unconfirmed = job.file_num() == 0 && !job.file_confirmed();
    if fault == Fault::Upstream
        || failed < 0
        || failed as usize >= job.files().len()
        || first_unconfirmed
    {
        return false;
    }
    if !leapgate::ft::first_report(id, failed) {
        return true;
    }
    if fault == Fault::Stop {
        fs::remove_job(id, read_jobs);
        leapgate::ft::stop(id);
        log::info!("leapgate ft: upload {id} kept at file {failed}: {}", e.error);
        let event = leapgate::ft::kept_event(id, failed, &e.error, "remote", false);
        fx.events.push(event);
        return true;
    }
    if job.file_num() == failed {
        job.set_file_skipped();
    }
    fx.msgs.push(leapgate::ft_read::skip(id, failed));
    file_failed(job, failed, &e.error, "remote", fx);
    true
}

/// A running generic download, with the switch on.
fn claimable(on: bool, write_jobs: &[fs::TransferJob], id: i32) -> Option<&fs::TransferJob> {
    if !on {
        return None;
    }
    fs::get_job_immutable(id, write_jobs).filter(|job| job.r#type == fs::JobType::Generic)
}

/// A single file's failure is its job's: upstream's.
fn single_file(fault: Fault, write_jobs: &[fs::TransferJob], read_jobs: &[fs::TransferJob], id: i32) -> Fault {
    let files = fs::get_job_immutable(id, write_jobs)
        .or_else(|| fs::get_job_immutable(id, read_jobs))
        .map_or(0, |job| job.files().len());
    match fault {
        Fault::File if files <= 1 => Fault::Upstream,
        fault => fault,
    }
}

fn local_fault(peer_platform: &str, job: &fs::TransferJob, err: &str) -> Fault {
    let reason = leapgate::ft_reason::classify(err, peer_platform, "local");
    match leapgate::ft::fault(reason.reason) {
        Fault::File if job.files().len() <= 1 => Fault::Upstream,
        fault => fault,
    }
}

fn staged(job: &fs::TransferJob, file_num: i32) -> bool {
    job.download_target(file_num)
        .is_ok_and(|target| leapgate::ft::staged(&target))
}

fn entry(job: &fs::TransferJob, file_num: i32) -> String {
    job.files()
        .get(file_num as usize)
        .map(|entry| entry.name.clone())
        .unwrap_or_default()
}

fn file_failed(job: &fs::TransferJob, file_num: i32, err: &str, side: &str, fx: &mut Effects) {
    let id = job.id();
    log::info!("leapgate ft: job {id} left out file {file_num} ({side}): {err}");
    let name = entry(job, file_num);
    fx.events
        .push(leapgate::ft::file_failed_event(id, file_num, &name, err, side));
}

/// Drops the download, keeping its staged files, and tells the peer to stop. `kept` carries the
/// error and its side for a job that stops for good (`kept`); without it the UI starts again
/// from `resume_from` (`continue_from`), or the job is over when no file is left.
fn stop_download(
    write_jobs: &mut Vec<fs::TransferJob>,
    id: i32,
    resume_from: i32,
    kept: Option<(&str, &str)>,
    fx: &mut Effects,
) {
    let Some(job) = fs::remove_job(id, write_jobs) else {
        return;
    };
    let files = job.files().len() as i32;
    let target = job.download_target(resume_from).ok();
    // Closes the staged file before it may be removed.
    drop(job);
    let restart_file = target.is_some_and(|t| leapgate::ft::restart_past_resume_offset(&t));
    fx.msgs.push(cancel(id));
    leapgate::ft::stop(id);
    match kept {
        Some((err, side)) => {
            log::info!("leapgate ft: download {id} kept at file {resume_from}: {err}");
            let event = leapgate::ft::kept_event(id, resume_from, err, side, restart_file);
            fx.events.push(event);
        }
        None if resume_from >= files => fx.done = Some((id, files)),
        None => {
            log::info!("leapgate ft: download {id} continues from file {resume_from}");
            let event = leapgate::ft::continue_from_event(id, resume_from, restart_file);
            fx.events.push(event);
        }
    }
}

/// M7a-4: what upstream's `session_read_local_dir_sync` returns, or `{"error","reason"}` where
/// it returns an empty string.
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
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
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
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
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
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
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
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

#[cfg(all(test, any(target_os = "android", target_os = "ios", feature = "flutter")))]
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
        let mut fx = Effects::default();
        let digest = FileTransferDigest {
            id: 2,
            file_num: 1,
            ..Default::default()
        };
        let denied = "Access is denied. (os error 5)";
        assert!(!on_digest_failed(false, "Windows", &mut writes, &digest, denied, &mut fx));
        assert!(!on_write_failed(false, "Windows", &mut writes, 2, 1, denied, &mut fx));
        for (id, file_num) in [(1, 0), (2, 2)] {
            let e = peer_err(id, file_num, denied);
            assert!(!on_peer_error(false, "Windows", &mut reads, &mut writes, &e, &mut fx));
        }
        assert!(fx.msgs.is_empty() && fx.events.is_empty() && fx.done.is_none());
        assert_eq!((reads.len(), writes.len()), (1, 1));
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

    // ---- Failures ----

    const DENIED: &str = "Access is denied. (os error 5)";
    #[cfg(windows)]
    const LOCAL_DISK_FULL: &str = "There is not enough space on the disk. (os error 112)";
    #[cfg(not(windows))]
    const LOCAL_DISK_FULL: &str = "No space left on device (os error 28)";

    fn peer_err(id: i32, file_num: i32, error: &str) -> FileTransferError {
        FileTransferError {
            id,
            file_num,
            error: error.to_owned(),
            ..Default::default()
        }
    }

    fn block(id: i32, file_num: i32, data: &[u8]) -> base::message_proto::FileTransferBlock {
        base::message_proto::FileTransferBlock {
            id,
            file_num,
            data: data.to_vec().into(),
            ..Default::default()
        }
    }

    /// A download of `a.txt`, `b.txt`, `c.txt` into `dir`.
    fn download3(id: i32, dir: &PathBuf) -> fs::TransferJob {
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
        .with_files(vec![entry("a.txt", 3), entry("b.txt", 5), entry("c.txt", 4)])
        .unwrap();
        job.is_last_job = false;
        job
    }

    fn events(fx: &Effects) -> Vec<serde_json::Value> {
        fx.events
            .iter()
            .map(|e| serde_json::from_str(e).unwrap())
            .collect()
    }

    /// `cancel N` or `skip N:F` per message to the peer.
    fn sent(fx: &Effects) -> Vec<String> {
        use base::message_proto::{file_action, message};
        fx.msgs
            .iter()
            .map(|msg| match &msg.union {
                Some(message::Union::FileAction(a)) => match &a.union {
                    Some(file_action::Union::Cancel(c)) => format!("cancel {}", c.id),
                    Some(file_action::Union::SendConfirm(c)) if c.skip() => {
                        format!("skip {}:{}", c.id, c.file_num)
                    }
                    other => panic!("{other:?}"),
                },
                other => panic!("{other:?}"),
            })
            .collect()
    }

    fn big(path: PathBuf) {
        sfs::File::create(path)
            .unwrap()
            .set_len(u64::from(u32::MAX) + 1)
            .unwrap();
    }

    /// The peer could not read `b.txt` (it reports file 2). Whether this side was still on
    /// `a.txt`, complete (it is renamed), or already writing `b.txt` (its part stays staged),
    /// the download stops and starts again at `c.txt`; a staged `c.txt` past 4 GiB restarts.
    #[tokio::test]
    async fn a_peer_read_failure_continues_past_the_file() {
        let on_a = scratch("peer-read-a");
        let mut writes = vec![download3(30, &on_a)];
        writes[0].write(block(30, 0, b"abc")).await.unwrap();
        big(on_a.join("c.txt.download"));
        let on_b = scratch("peer-read-b");
        let mut on_b_writes = vec![download3(31, &on_b)];
        on_b_writes[0].write(block(31, 0, b"abc")).await.unwrap();
        on_b_writes[0].write(block(31, 1, b"bb")).await.unwrap();
        for (dir, writes, id, restart) in [(&on_a, &mut writes, 30, true), (&on_b, &mut on_b_writes, 31, false)] {
            let mut fx = Effects::default();
            let e = peer_err(id, 2, DENIED);
            assert!(on_peer_error(true, "Windows", &mut vec![], writes, &e, &mut fx));
            assert!(writes.is_empty());
            assert_eq!(sfs::read(dir.join("a.txt")).unwrap(), b"abc");
            assert!(!dir.join("a.txt.download").exists());
            assert_eq!(dir.join("b.txt.download").exists(), id == 31);
            assert!(!dir.join("c.txt.download").exists());
            assert_eq!(sent(&fx), [format!("cancel {id}")]);
            let ev = events(&fx);
            assert_eq!(
                (&ev[0]["kind"], &ev[0]["file_num"], &ev[0]["name"], &ev[0]["side"]),
                (&"file_failed".into(), &1.into(), &"b.txt".into(), &"remote".into())
            );
            assert_eq!(
                ev[1],
                serde_json::json!({"kind": "continue_from", "id": id, "resume_from": 2,
                    "restart_file": restart})
            );
            assert!(fx.done.is_none());
            // The peer erring on for the stopped job is claimed without a word.
            let mut fx = Effects::default();
            assert!(on_peer_error(true, "Windows", &mut vec![], writes, &e, &mut fx));
            assert!(fx.msgs.is_empty() && fx.events.is_empty());
        }
        sfs::remove_dir_all(&on_a).unwrap();
        sfs::remove_dir_all(&on_b).unwrap();
    }

    /// A failed block of a new file is the rename of the file before it while that one is still
    /// staged, else the new file's own; a full disk keeps the job, its staged part past 4 GiB
    /// restarting.
    #[tokio::test]
    async fn a_failed_rename_is_told_from_a_failed_write() {
        let dir = scratch("write");
        // `a.txt` written and staged: the rename failed.
        let mut writes = vec![download3(40, &dir)];
        writes[0].write(block(40, 0, b"abc")).await.unwrap();
        let mut fx = Effects::default();
        assert!(on_write_failed(true, "Windows", &mut writes, 40, 1, DENIED, &mut fx));
        let ev = events(&fx);
        assert_eq!((&ev[0]["file_num"], &ev[0]["side"]), (&0.into(), &"local".into()));
        assert_eq!((&ev[1]["kind"], &ev[1]["resume_from"]), (&"continue_from".into(), &1.into()));
        assert!(dir.join("a.txt.download").exists());
        // Nothing staged before `b.txt`: its own write failed.
        let fresh = scratch("write-fresh");
        let mut writes = vec![download3(41, &fresh)];
        let mut fx = Effects::default();
        assert!(on_write_failed(true, "Windows", &mut writes, 41, 1, DENIED, &mut fx));
        let ev = events(&fx);
        assert_eq!((&ev[0]["file_num"], &ev[1]["resume_from"]), (&1.into(), &2.into()));
        // The last file: no file is left, the job is done.
        let mut writes = vec![download3(42, &fresh)];
        let mut fx = Effects::default();
        assert!(on_write_failed(true, "Windows", &mut writes, 42, 2, DENIED, &mut fx));
        assert_eq!((events(&fx).len(), fx.done), (1, Some((42, 3))));
        // A full disk.
        let mut writes = vec![download3(43, &fresh)];
        big(fresh.join("b.txt.download"));
        let mut fx = Effects::default();
        assert!(on_write_failed(true, "Windows", &mut writes, 43, 1, LOCAL_DISK_FULL, &mut fx));
        assert_eq!(sent(&fx), ["cancel 43"]);
        let ev = events(&fx);
        assert_eq!(ev.len(), 1);
        assert_eq!(
            (&ev[0]["kind"], &ev[0]["resume_from"], &ev[0]["side"], &ev[0]["restart_file"]),
            (&"kept".into(), &1.into(), &"local".into(), &true.into())
        );
        assert!(!fresh.join("b.txt.download").exists());
        sfs::remove_dir_all(&dir).unwrap();
        sfs::remove_dir_all(&fresh).unwrap();
    }

    /// A name this side cannot write is skipped where the peer waits for its confirmation; the
    /// job goes on. A failed rename of the file before it stops and starts again at this one.
    #[tokio::test]
    async fn a_digest_failure_skips_the_file_or_continues() {
        let dir = scratch("digest");
        let mut writes = vec![download3(50, &dir)];
        let digest = FileTransferDigest {
            id: 50,
            file_num: 1,
            ..Default::default()
        };
        let mut fx = Effects::default();
        let invalid = "invalid Windows download file name: b.txt";
        assert!(on_digest_failed(true, "Windows", &mut writes, &digest, invalid, &mut fx));
        assert_eq!(sent(&fx), ["skip 50:1"]);
        assert_eq!(events(&fx)[0]["file_num"], 1);
        assert_eq!(writes.len(), 1);
        writes[0].write(block(50, 0, b"abc")).await.unwrap();
        let mut fx = Effects::default();
        assert!(on_digest_failed(true, "Windows", &mut writes, &digest, DENIED, &mut fx));
        assert_eq!(sent(&fx), ["cancel 50"]);
        let ev = events(&fx);
        assert_eq!((&ev[0]["file_num"], &ev[1]["resume_from"]), (&0.into(), &1.into()));
        assert!(writes.is_empty());
        sfs::remove_dir_all(&dir).unwrap();
    }

    /// The peer could not write a file of an upload: it is skipped on both sides, once however
    /// often the peer reports it. A full disk stops this side's job; a single file's failure,
    /// or one before the first file was confirmed, is upstream's.
    #[tokio::test]
    async fn a_peer_write_failure_skips_the_file() {
        let dir = scratch("peer-write");
        for name in ["a.txt", "b.txt"] {
            sfs::write(dir.join(name), name).unwrap();
        }
        let upload = |id| {
            let mut job = fs::TransferJob::new_read(
                id,
                fs::JobType::Generic,
                "/remote".to_owned(),
                fs::DataSource::FilePath(dir.clone()),
                0,
                false,
                false,
                false,
            )
            .unwrap();
            job.is_last_job = false;
            job
        };
        let mut reads = vec![upload(60)];
        let mut fx = Effects::default();
        assert!(!on_peer_error(true, "Windows", &mut reads, &mut vec![], &peer_err(60, 0, DENIED), &mut fx));
        // Past the first file, reading the second.
        reads[0].init_data_stream_for_cm().await.unwrap();
        while reads[0].file_num() == 0 {
            reads[0].read().await.unwrap();
        }
        reads[0].init_data_stream_for_cm().await.unwrap();
        let e = peer_err(60, 1, DENIED);
        let mut fx = Effects::default();
        assert!(on_peer_error(true, "Windows", &mut reads, &mut vec![], &e, &mut fx));
        assert_eq!(sent(&fx), ["skip 60:1"]);
        assert_eq!(
            (&events(&fx)[0]["file_num"], &events(&fx)[0]["side"]),
            (&1.into(), &"remote".into())
        );
        assert_eq!((reads.len(), reads[0].file_num()), (1, 2));
        let mut fx = Effects::default();
        assert!(on_peer_error(true, "Windows", &mut reads, &mut vec![], &e, &mut fx));
        assert!(fx.msgs.is_empty() && fx.events.is_empty());
        // A full disk.
        let mut reads = vec![upload(61)];
        reads[0].init_data_stream_for_cm().await.unwrap();
        while reads[0].file_num() == 0 {
            reads[0].read().await.unwrap();
        }
        let mut fx = Effects::default();
        let full = "There is not enough space on the disk. (os error 112)";
        assert!(on_peer_error(true, "Windows", &mut reads, &mut vec![], &peer_err(61, 1, full), &mut fx));
        assert!(reads.is_empty() && fx.msgs.is_empty());
        assert_eq!((&events(&fx)[0]["kind"], &events(&fx)[0]["resume_from"]), (&"kept".into(), &1.into()));
        // A single file.
        let single = scratch("peer-write-single");
        let mut reads = vec![running_upload(62, &single)];
        reads[0].set_file_confirmed(true);
        let mut fx = Effects::default();
        assert!(!on_peer_error(true, "Windows", &mut reads, &mut vec![], &peer_err(62, 0, DENIED), &mut fx));
        sfs::remove_dir_all(&dir).unwrap();
        sfs::remove_dir_all(&single).unwrap();
    }

    /// With the switch off the read loop is upstream's, which reports a file it cannot open to
    /// the peer; on, nothing goes to the peer.
    #[tokio::test]
    async fn the_read_loop_reports_to_the_peer_only_with_the_switch_off() {
        use hbb_common::{protobuf::Message as _, tcp::FramedStream, tokio::net::TcpListener};
        let handler = Session::<crate::flutter::FlutterHandler>::default();
        for (on, id) in [(false, 70), (true, 71)] {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let a = hbb_common::tokio::net::TcpStream::connect(addr).await.unwrap();
            let (b, _) = listener.accept().await.unwrap();
            let mut ours = Stream::Tcp(FramedStream::from(a, addr));
            let mut theirs = Stream::Tcp(FramedStream::from(b, addr));
            let dir = scratch(&format!("loop-{on}"));
            for name in ["a.txt", "b.txt"] {
                sfs::write(dir.join(name), name).unwrap();
            }
            let mut job = fs::TransferJob::new_read(
                id,
                fs::JobType::Generic,
                "/remote".to_owned(),
                fs::DataSource::FilePath(dir.clone()),
                0,
                false,
                false,
                true,
            )
            .unwrap();
            job.is_last_job = false;
            let mut jobs = vec![job];
            for name in ["a.txt", "b.txt"] {
                sfs::remove_file(dir.join(name)).unwrap();
            }
            read_jobs_on(on, &handler, &mut jobs, &mut ours).await.unwrap();
            let got = hbb_common::timeout(300, theirs.next()).await;
            match (on, got) {
                (false, Ok(Some(Ok(bytes)))) => {
                    let msg = Message::parse_from_bytes(&bytes).unwrap();
                    assert!(msg.has_file_response() && msg.file_response().has_error(), "{msg:?}");
                }
                (true, Err(_)) => {}
                (on, got) => panic!("switch {on}: {got:?}"),
            }
            sfs::remove_dir_all(&dir).unwrap();
        }
    }
}
