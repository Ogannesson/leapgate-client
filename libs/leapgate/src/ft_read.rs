//! M7b-1 (`LEAPGATE.md` §10.17): the upload read loop for the new UI. Upstream's
//! `fs::handle_read_jobs` with two changes: a local file that cannot be opened or read is not
//! reported to the peer (whose CM would end the whole job) but left out, with a skip for the part
//! already sent, and handed to the UI; and a job is not read in the tick its file failed to open,
//! where upstream finds it "completed" and ends it. The peer's side stays upstream's.

use base::{
    fs::{self, TransferJob},
    message_proto::{
        file_transfer_send_confirm_request, FileResponse, FileTransferDigest,
        FileTransferSendConfirmRequest, Message,
    },
};

/// A local file left out of an upload.
#[derive(Debug, PartialEq)]
pub struct ReadFailure {
    pub id: i32,
    pub file_num: i32,
    pub name: String,
    pub err: String,
}

/// What a tick produced: the messages for the peer, in order, and the files left out.
#[derive(Debug, Default)]
pub struct Step {
    pub out: Vec<Message>,
    pub failed: Vec<ReadFailure>,
}

/// One tick of upstream's loop: every job that is not waiting opens its current file (and sends
/// its digest); the first such job, and only it, reads a block. An error that did not move the
/// job past its file (nothing seen in practice) goes to the peer as upstream sends it.
pub async fn step(jobs: &mut Vec<TransferJob>) -> Step {
    let mut step = Step::default();
    let mut not_open = Vec::new();
    for job in jobs.iter_mut().filter(|job| !job.is_last_job) {
        let file_num = job.file_num();
        match job.init_data_stream_for_cm().await {
            Ok(Some((last_modified, file_size))) => {
                step.out.push(digest(job, last_modified, file_size))
            }
            Ok(None) => {}
            Err(err) => {
                not_open.push(job.id());
                step.left_out(job, file_num, err.to_string());
            }
        }
    }
    let mut finished = None;
    if let Some(job) = jobs.iter_mut().find(|job| !job.is_last_job) {
        if !not_open.contains(&job.id()) {
            let file_num = job.file_num();
            match job.read().await {
                Err(err) => {
                    if job.file_num() != file_num {
                        step.out.push(skip(job.id(), file_num));
                    }
                    step.left_out(job, file_num, err.to_string());
                }
                Ok(Some(block)) => step.out.push(fs::new_block(block)),
                Ok(None) if job.job_completed() => {
                    finished = Some(job.id());
                    step.out.push(match job.job_error() {
                        Some(err) => fs::new_error(job.id(), err, job.file_num()),
                        None => fs::new_done(job.id(), job.file_num()),
                    });
                }
                // Waiting for the peer's confirmation.
                Ok(None) => {}
            }
        }
    }
    if let Some(id) = finished {
        fs::remove_job(id, jobs);
    }
    step
}

impl Step {
    /// Upstream moves a job past a file it fails to open or read; one it did not move keeps
    /// upstream's report.
    fn left_out(&mut self, job: &TransferJob, file_num: i32, err: String) {
        if job.file_num() == file_num {
            self.out.push(fs::new_error(job.id(), err, job.file_num()));
            return;
        }
        let name = job
            .files()
            .get(file_num as usize)
            .map(|entry| entry.name.clone())
            .unwrap_or_default();
        self.failed.push(ReadFailure {
            id: job.id(),
            file_num,
            name,
            err,
        });
    }
}

/// As upstream's `send_current_digest`.
fn digest(job: &TransferJob, last_modified: u64, file_size: u64) -> Message {
    let mut resp = FileResponse::new();
    resp.set_digest(FileTransferDigest {
        id: job.id(),
        file_num: job.file_num(),
        last_modified,
        file_size,
        is_resume: job.is_resume,
        ..Default::default()
    });
    let mut msg = Message::new();
    msg.set_file_response(resp);
    msg
}

/// Tells the peer to drop the part of `file_num` it has written; a peer already past it ignores
/// it.
pub fn skip(id: i32, file_num: i32) -> Message {
    fs::new_send_confirm(FileTransferSendConfirmRequest {
        id,
        file_num,
        union: Some(file_transfer_send_confirm_request::Union::Skip(true)),
        ..Default::default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::{file_response, message};
    use hbb_common::tokio;
    use std::{fs as sfs, path::PathBuf};

    fn scratch(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("leapgate-ft-read-{name}-{}", std::process::id()));
        let _ = sfs::remove_dir_all(&dir);
        sfs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A running upload of `names` under `dir`, without overwrite detection, so it reads at
    /// once.
    fn upload(id: i32, dir: &PathBuf, names: &[&str]) -> TransferJob {
        for name in names {
            sfs::write(dir.join(name), name.as_bytes()).unwrap();
        }
        let mut job = TransferJob::new_read(
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
    }

    enum Out {
        Block(i32, i32, usize),
        Done(i32),
    }

    /// What went to the peer; an error or a skip fails the test.
    fn out(step: &Step) -> Vec<Out> {
        step.out
            .iter()
            .map(|msg| match &msg.union {
                Some(message::Union::FileResponse(r)) => match &r.union {
                    Some(file_response::Union::Block(b)) => {
                        Out::Block(b.id, b.file_num, b.data.len())
                    }
                    Some(file_response::Union::Done(d)) => Out::Done(d.id),
                    other => panic!("{other:?}"),
                },
                other => panic!("{other:?}"),
            })
            .collect()
    }

    /// A file gone before it is opened is left out: no error goes to the peer, the job is not
    /// ended in that tick, and the next tick goes on with the next file.
    #[tokio::test(crate = "hbb_common::tokio")]
    async fn a_file_that_cannot_be_opened_is_left_out() {
        let dir = scratch("open");
        let mut jobs = vec![upload(1, &dir, &["a.txt", "b.txt"])];
        let name = jobs[0].files()[0].name.clone();
        sfs::remove_file(dir.join(&name)).unwrap();
        let first = step(&mut jobs).await;
        assert!(first.out.is_empty(), "{:?}", first.out);
        assert_eq!(
            first.failed,
            [ReadFailure {
                id: 1,
                file_num: 0,
                name,
                err: first.failed[0].err.clone(),
            }]
        );
        assert_eq!(jobs.len(), 1);
        let mut sent = Vec::new();
        for _ in 0..3 {
            sent.extend(out(&step(&mut jobs).await));
        }
        assert!(matches!(
            sent.as_slice(),
            [Out::Block(1, 1, 5), Out::Block(1, 1, 0), Out::Done(1)]
        ));
        assert!(jobs.is_empty());
        sfs::remove_dir_all(&dir).unwrap();
    }

    /// The first job that is not waiting is the one read, as upstream reads it: a paused job
    /// ahead of it is passed over, and the jobs behind it wait their turn.
    #[tokio::test(crate = "hbb_common::tokio")]
    async fn the_first_job_not_waiting_is_read() {
        let (a, b, c) = (scratch("first-a"), scratch("first-b"), scratch("first-c"));
        let mut jobs = vec![
            upload(10, &a, &["a"]),
            upload(11, &b, &["bb"]),
            upload(12, &c, &["ccc"]),
        ];
        jobs[0].is_last_job = true;
        let sent = out(&step(&mut jobs).await);
        assert!(matches!(sent.as_slice(), [Out::Block(11, 0, 2)]));
        for dir in [a, b, c] {
            sfs::remove_dir_all(&dir).unwrap();
        }
    }
}
