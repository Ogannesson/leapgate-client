//! The file transfer view's Rust items (`LEAPGATE.md` §10.15) that need upstream's sessions and
//! `fs`: reading a local folder with the error kept, and removing a link without following it.
//! FT2 itself is in `libs/leapgate` (`ft_reason`).

use crate::{
    client::{Data, Interface as _},
    common::make_fd_to_json,
    flutter::sessions,
    flutter_ffi::SessionID,
    ui_session_interface::InvokeUiSession as _,
};
use base::{
    fs,
    message_proto::{FileAction, FileRemoveDir, FileRemoveFile, Message},
};

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
/// into a folder link's target). A Windows peer removes a folder link or junction with
/// `remove_dir` (non-recursive `FileRemoveDir`); a file link, or any link on a Unix peer, is
/// unlinked with `FileRemoveFile`. The result comes as `job_done` / `job_error` for `act_id`.
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
        let mut file_action = FileAction::new();
        if is_dir_link && session.peer_platform() == "Windows" {
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
        let mut msg = Message::new();
        msg.set_file_action(file_action);
        session.send(Data::Message(msg));
    } else {
        match remove_local_link(&path, is_dir_link) {
            Ok(()) => session.ui_handler.job_done(act_id, 0),
            Err(err) => session.ui_handler.job_error(act_id, err.to_string(), 0),
        }
    }
}

fn remove_local_link(path: &str, is_dir_link: bool) -> std::io::Result<()> {
    if cfg!(windows) && is_dir_link {
        std::fs::remove_dir(path)
    } else {
        std::fs::remove_file(path)
    }
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
        let check = |link: PathBuf, is_dir_link: bool| {
            remove_local_link(&link.to_string_lossy(), is_dir_link).unwrap();
            assert!(
                sfs::symlink_metadata(&link).is_err(),
                "{link:?} still there"
            );
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
            let link = dir.join("dir-symlink");
            if made(symlink_dir(&target, &link), "folder symbolic link") {
                check(link, true);
            }
            let link = dir.join("file-symlink");
            if made(
                symlink_file(target.join("f.txt"), &link),
                "file symbolic link",
            ) {
                check(link, false);
            }
            let link = dir.join("junction");
            let status = std::process::Command::new("cmd")
                .args(["/C", "mklink", "/J"])
                .arg(&link)
                .arg(&target)
                .stdout(std::process::Stdio::null())
                .status()
                .unwrap();
            assert!(status.success());
            check(link, true);
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            let link = dir.join("dir-symlink");
            symlink(&target, &link).unwrap();
            check(link, true);
            let link = dir.join("file-symlink");
            symlink(target.join("f.txt"), &link).unwrap();
            check(link, false);
        }
        sfs::remove_dir_all(&dir).unwrap();
    }
}
