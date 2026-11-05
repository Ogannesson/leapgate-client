//! Reason codes for file transfer errors (FT2): upstream reports them as a `job_error` carrying
//! only the error text, from either side. The UI looks its wording up by code, with the original
//! text kept for display.
//!
//! OS errors are recognized by their `(os error N)` code, never by wording (Windows words them in
//! the system language). Upstream's own sentences are matched as written, so an upstream merge
//! that rewords one silently drops it to `Other`; compare the `bail!`s in `libs/base/src/fs.rs`,
//! `fs/download.rs` and the peer's file handling between the tags and update this table and its
//! tests (`LEAPGATE.md` §10.15).

use crate::reason::{clip, first_time};
use hbb_common::log;
use serde::Serialize;

/// Codes are stable: the UI's wording is keyed on them. `timeout` exists only in the UI.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Code {
    PermissionDenied,
    InUse,
    NotFound,
    DiskFull,
    FileTooLarge,
    PathTooLong,
    InvalidName,
    /// `args`: the name.
    InvalidNameWindows,
    SymlinkInPath,
    OneWay,
    /// `args`: this transfer's file count, then the limit.
    TooManyFiles,
    /// An Android peer refused a path outside the app's storage.
    AndroidScope,
    /// Not an error: the user skipped the file.
    Skipped,
    /// Not recognized: the UI shows the text.
    Other,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct FtReason {
    pub reason: Code,
    pub args: Vec<String>,
    /// The original text, clipped like C3's.
    pub text: String,
}

/// Whose error codes a text carries.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Os {
    Windows,
    Linux,
    /// Linux's errnos, bionic's wording.
    Android,
    Mac,
}

impl Os {
    /// From a peer info's `platform`; anything else counts as Windows.
    fn of(platform: &str) -> Self {
        match platform {
            "Linux" => Os::Linux,
            "Android" => Os::Android,
            "Mac OS" => Os::Mac,
            _ => Os::Windows,
        }
    }
}

const LOCAL: Os = if cfg!(windows) {
    Os::Windows
} else if cfg!(any(target_os = "macos", target_os = "ios")) {
    Os::Mac
} else if cfg!(target_os = "android") {
    Os::Android
} else {
    Os::Linux
};

/// Classifies a `job_error`'s text. `peer_platform` is the peer info's `platform`; `side` is
/// `local` or `remote` when the UI knows whose operation failed, else `unknown` (a transfer).
/// Unrecognized texts are logged once each.
pub fn classify(text: &str, peer_platform: &str, side: &str) -> FtReason {
    classify_on(LOCAL, text, Os::of(peer_platform), side)
}

fn classify_on(local: Os, text: &str, peer: Os, side: &str) -> FtReason {
    let (reason, args) = match os_error(text) {
        Some((detail, n)) => {
            let os = match side {
                "local" => local,
                "remote" => peer,
                _ => unknown_side(local, peer, detail, n),
            };
            (by_code(os, n).unwrap_or(Code::Other), vec![])
        }
        None => by_text(text),
    };
    let text = clip(text);
    if reason == Code::Other && first_time(text) {
        log::info!(
            "leapgate ft reason: unrecognized error side={:?} text={:?}",
            side,
            text
        );
    }
    FtReason {
        reason,
        args,
        text: text.to_owned(),
    }
}

/// The `(os error N)` that ends the text, and the text before it: wrappers such as
/// `validation failed: ` or `failed to validate path component '…': ` put the inner error last.
/// One elsewhere is part of a path or name.
fn os_error(text: &str) -> Option<(&str, i32)> {
    const MARK: &str = "(os error ";
    let rest = text.strip_suffix(')')?;
    let start = rest.rfind(MARK)?;
    let n = rest[start + MARK.len()..].parse().ok()?;
    Some((text[..start].trim_end(), n))
}

/// A transfer's error can come from either side: the peer echoes the controller's read error
/// back unchanged (10 §4.3). Unix texts are English and fixed, so one that is the Unix side's
/// wording for `n` is that side's; anything else is the other side's.
fn unknown_side(local: Os, peer: Os, detail: &str, n: i32) -> Os {
    if local == peer {
        return local;
    }
    let (unix, other) = if peer != Os::Windows {
        (peer, local)
    } else {
        (local, peer)
    };
    if strerror(unix, n).is_some_and(|s| detail.ends_with(s)) {
        unix
    } else {
        other
    }
}

fn by_code(os: Os, n: i32) -> Option<Code> {
    use Code::*;
    Some(match os {
        Os::Windows => match n {
            // 19: write protected
            5 | 1920 | 19 => PermissionDenied,
            32 | 33 => InUse,
            // 21: drive not ready
            2 | 3 | 15 | 21 => NotFound,
            112 | 39 => DiskFull,
            223 | 665 => FileTooLarge,
            206 => PathTooLong,
            123 | 161 => InvalidName,
            _ => return None,
        },
        Os::Linux | Os::Android => match n {
            // 30: read-only file system
            13 | 1 | 30 => PermissionDenied,
            26 | 16 => InUse,
            2 | 20 => NotFound,
            28 | 122 => DiskFull,
            27 => FileTooLarge,
            36 => PathTooLong,
            22 | 84 => InvalidName,
            40 => SymlinkInPath,
            _ => return None,
        },
        Os::Mac => match n {
            13 | 1 | 30 => PermissionDenied,
            26 | 16 => InUse,
            2 | 20 => NotFound,
            28 | 69 => DiskFull,
            27 => FileTooLarge,
            63 => PathTooLong,
            22 | 92 => InvalidName,
            62 => SymlinkInPath,
            _ => return None,
        },
    })
}

/// The English wording (glibc, bionic's `bionic_errdefs.h`, macOS libc) of the errnos in
/// `by_code`, and of the file errnos whose numbers are also Windows codes there (5, 19, 21, 32,
/// 39, 123).
fn strerror(os: Os, n: i32) -> Option<&'static str> {
    use Os::{Android, Linux, Mac};
    Some(match (os, n) {
        (Os::Windows, _) => return None,
        (Android, 5) => "I/O error",
        (Android, 40) => "Too many symbolic links encountered",
        (Android, 84) => "Illegal byte sequence",
        (Android, 122) => "Quota exceeded",
        (_, 1) => "Operation not permitted",
        (_, 2) => "No such file or directory",
        (_, 5) => "Input/output error",
        (_, 13) => "Permission denied",
        (Linux | Android, 16) => "Device or resource busy",
        (Mac, 16) => "Resource busy",
        (Linux | Android, 19) => "No such device",
        (Mac, 19) => "Operation not supported by device",
        (_, 20) => "Not a directory",
        (_, 21) => "Is a directory",
        (_, 22) => "Invalid argument",
        (_, 26) => "Text file busy",
        (_, 27) => "File too large",
        (_, 28) => "No space left on device",
        (_, 30) => "Read-only file system",
        (_, 32) => "Broken pipe",
        (Linux | Android, 36) => "File name too long",
        (Linux | Android, 39) => "Directory not empty",
        (Linux, 40) => "Too many levels of symbolic links",
        (Linux, 84) => "Invalid or incomplete multibyte or wide character",
        (Linux, 122) => "Disk quota exceeded",
        (Linux | Android, 123) => "No medium found",
        (Mac, 62) => "Too many levels of symbolic links",
        (Mac, 63) => "File name too long",
        (Mac, 69) => "Disc quota exceeded",
        (Mac, 92) => "Illegal byte sequence",
        _ => return None,
    })
}

/// Upstream's own sentences, which carry no error code.
fn by_text(text: &str) -> (Code, Vec<String>) {
    use Code::*;
    // A Windows peer's CM wraps a read job's setup error.
    let text = text.strip_prefix("validation failed: ").unwrap_or(text);
    // Prefixes first: the rest of these is a name, which may end like the suffixes below.
    if let Some(name) = text.strip_prefix("invalid Windows download file name: ") {
        return (InvalidNameWindows, vec![name.to_owned()]);
    }
    if let Some(counts) = text.strip_prefix("file transfer rejected: too many files (") {
        return match too_many_files(counts) {
            Some((count, limit)) => (TooManyFiles, vec![count, limit]),
            None => (Other, vec![]),
        };
    }
    let code = if text.starts_with("invalid download file name")
        || text.starts_with("invalid file name in remote directory listing: ")
    {
        InvalidName
    } else {
        match text {
            "symlink path component is not allowed" => SymlinkInPath,
            "invalid file name component"
            | "path traversal detected in file name"
            | "absolute path detected in file name"
            | "empty file name in multi-file transfer"
            | "Invalid path" => InvalidName,
            "Not exists" => NotFound,
            "one-way-file-transfer-tip" => OneWay,
            "Permission denied" => AndroidScope,
            "skipped" => Skipped,
            _ if text.ends_with(" not exists") => NotFound,
            _ if text.ends_with(" cannot be empty") || text.ends_with(" contains null bytes") => {
                InvalidName
            }
            _ => Other,
        }
    };
    (code, vec![])
}

/// `<count> files exceeds limit of <limit>). Adjust …`
fn too_many_files(rest: &str) -> Option<(String, String)> {
    let (count, rest) = rest.split_once(" files exceeds limit of ")?;
    let (limit, _) = rest.split_once(')')?;
    Some((
        count.parse::<u64>().ok()?.to_string(),
        limit.parse::<u64>().ok()?.to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use Code::*;

    fn code(text: &str, peer: Os, side: &str) -> (Code, Vec<String>) {
        let r = classify_on(Os::Windows, text, peer, side);
        (r.reason, r.args)
    }

    /// Each text as upstream builds it, with where. Line numbers are as of leapgate-client
    /// `0b89071ff`; `base` is `libs/base/src`. Side as the UI passes it for that operation.
    #[test]
    fn upstream_texts() {
        let none = || Vec::<String>::new();
        let cases: Vec<((&str, Os, &str), (Code, Vec<String>))> = vec![
            // Any std/tokio fs call through `?` (base/fs.rs, base/fs/download.rs): io::Error's
            // Display, Windows wording in the system language
            (
                ("拒绝访问。 (os error 5)", Os::Windows, "local"),
                (PermissionDenied, none()),
            ),
            (
                ("Access is denied. (os error 5)", Os::Windows, "remote"),
                (PermissionDenied, none()),
            ),
            (
                ("Permission denied (os error 13)", Os::Linux, "remote"),
                (PermissionDenied, none()),
            ),
            // Measured between two Chinese Windows (02 §4.3 item 22), `err` as pushed in
            // `job_error`: download of a file the peer may not read, of a file the peer has
            // open exclusively, upload into a folder the peer may not write, upload of a file
            // open exclusively here (the peer echoes it back)
            (
                ("拒绝访问。 (os error 5)", Os::Windows, "unknown"),
                (PermissionDenied, none()),
            ),
            (
                (
                    "另一个程序正在使用此文件，进程无法访问。 (os error 32)",
                    Os::Windows,
                    "unknown",
                ),
                (InUse, none()),
            ),
            // base/fs.rs:543 `validate_no_symlink_components`
            (
                ("symlink path component is not allowed", Os::Windows, "unknown"),
                (SymlinkInPath, none()),
            ),
            // base/fs.rs:551 `validate_no_symlink_components`: the inner io error decides
            (
                (
                    r"failed to validate path component 'C:\Users\a\b': 系统找不到指定的路径。 (os error 3)",
                    Os::Windows,
                    "unknown",
                ),
                (NotFound, none()),
            ),
            // base/fs.rs:560 `validate_no_symlink_components`
            (
                ("invalid file name component", Os::Windows, "unknown"),
                (InvalidName, none()),
            ),
            // base/fs.rs:473/480/487/491/496 `validate_file_name_no_traversal`
            (
                ("file name contains null bytes", Os::Windows, "unknown"),
                (InvalidName, none()),
            ),
            (
                ("path traversal detected in file name", Os::Windows, "unknown"),
                (InvalidName, none()),
            ),
            (
                ("absolute path detected in file name", Os::Windows, "unknown"),
                (InvalidName, none()),
            ),
            // base/fs.rs:509 `validate_file_name_no_traversal`
            (
                ("empty file name in multi-file transfer", Os::Windows, "unknown"),
                (InvalidName, none()),
            ),
            // base/fs.rs:519/522 `validate_fs_path_argument`, called by 1445 `remove_file`,
            // 1452 `create_dir`, 1459 `rename_file`
            (
                ("file path cannot be empty", Os::Windows, "remote"),
                (InvalidName, none()),
            ),
            (
                ("directory path contains null bytes", Os::Windows, "local"),
                (InvalidName, none()),
            ),
            // base/fs.rs:1461 `rename_file`
            (
                ("new file name cannot be empty", Os::Windows, "remote"),
                (InvalidName, none()),
            ),
            // base/fs.rs:1468/1473 `rename_file` (Debug-quoted path; "directoy" as upstream)
            (
                (
                    r#"Parent directoy of "C:\\a\\b.txt" not exists"#,
                    Os::Windows,
                    "local",
                ),
                (NotFound, none()),
            ),
            (
                (r#""/home/a/b.txt" not exists"#, Os::Linux, "remote"),
                (NotFound, none()),
            ),
            // an "(os error N)" inside the path is no error code
            (
                (r#""/home/a (os error 5)/b.txt" not exists"#, Os::Linux, "remote"),
                (NotFound, none()),
            ),
            // base/fs.rs:207/249 `get_recursive_files`, `TransferJob::new_read`
            (("Not exists", Os::Windows, "remote"), (NotFound, none())),
            // ui_cm_interface.rs:1385 `start_read_job`: a Windows peer's CM wraps it
            (
                ("validation failed: Not exists", Os::Windows, "unknown"),
                (NotFound, none()),
            ),
            (
                (
                    "validation failed: 拒绝访问。 (os error 5)",
                    Os::Windows,
                    "unknown",
                ),
                (PermissionDenied, none()),
            ),
            // base/fs.rs:621 `TransferJob::new_write`
            (("Invalid path", Os::Windows, "unknown"), (InvalidName, none())),
            // base/fs/download.rs:44 `validate_listing` (refusing the peer's listing)
            (
                (
                    r"invalid file name in remote directory listing: a\b",
                    Os::Linux,
                    "remote",
                ),
                (InvalidName, none()),
            ),
            // base/fs/download.rs:59 `validate_component`, 92 `validated_target`
            (
                ("invalid download file name: ..", Os::Linux, "unknown"),
                (InvalidName, none()),
            ),
            (
                ("invalid download file name", Os::Linux, "unknown"),
                (InvalidName, none()),
            ),
            // base/fs/download.rs:66 `validate_component`; the name may end like a suffix rule
            (
                (
                    "invalid Windows download file name: a?b not exists",
                    Os::Linux,
                    "unknown",
                ),
                (InvalidNameWindows, vec!["a?b not exists".to_owned()]),
            ),
            // server/connection.rs:3577 `on_message`: a translation key, not a sentence
            (
                ("one-way-file-transfer-tip", Os::Windows, "unknown"),
                (OneWay, none()),
            ),
            // ui_cm_interface.rs:118 `check_file_count_limit`, called by 1329, 1551 and
            // server/connection.rs:3684, 5635
            (
                (
                    "file transfer rejected: too many files (120000 files exceeds limit of 100000). Adjust 'file-transfer-max-files' option to increase limit.",
                    Os::Windows,
                    "unknown",
                ),
                (
                    TooManyFiles,
                    vec!["120000".to_owned(), "100000".to_owned()],
                ),
            ),
            // server/connection.rs:3630/3651, ui_cm_interface.rs:1014/1034 (Android peer, no
            // error code)
            (
                ("Permission denied", Os::Linux, "remote"),
                (AndroidScope, none()),
            ),
            // base/fs.rs:1122 `TransferJob::job_error`
            (("skipped", Os::Windows, "unknown"), (Skipped, none())),
        ];
        for ((text, peer, side), expected) in cases {
            assert_eq!(code(text, peer, side), expected, "{text}");
        }
    }

    /// Upstream's internal errors stay `Other`.
    #[test]
    fn internal_errors_are_other() {
        for text in [
            // base/fs/download.rs:74/78/88/159/161
            "download destination has no parent",
            "invalid download destination",
            "download file has no parent",
            "Wrong file number",
            "download destination is not a file path",
            // base/fs/download.rs:118/145/263/271: resume staging files
            "download resume staging path is not a regular file",
            "hard-linked download resume staging file is not allowed",
            "download resume metadata is not a regular file",
            "download resume offset does not match staging file size",
            // base/fs/download.rs:227/259/317
            "download overwrite requires confirmation",
            // base/fs/download.rs:284/298
            "Wrong id",
            "download file stream is missing",
            // server/connection.rs:5394, 5569
            "internal error",
            "deserialize failed for /a/b: unexpected EOF",
            // ui_cm_interface.rs:1357/1396/1566
            "serialize failed: x",
            "validation task failed: task 7 panicked",
            "task failed: task 7 was cancelled",
            // an error code no table has
            "The semaphore timeout period has expired. (os error 121)",
            // a count rule whose numbers do not parse
            "file transfer rejected: too many files (many files exceeds limit of 10).",
        ] {
            assert_eq!(code(text, Os::Windows, "unknown").0, Other, "{text}");
        }
    }

    /// Every number in `LEAPGATE.md` §10.15's table, as that side reports it.
    #[test]
    fn error_codes_per_platform() {
        let unix = |disk_full, path_too_long, invalid_name, symlink| {
            [
                (PermissionDenied, vec![13, 1, 30]),
                (InUse, vec![26, 16]),
                (NotFound, vec![2, 20]),
                (DiskFull, disk_full),
                (FileTooLarge, vec![27]),
                (PathTooLong, path_too_long),
                (InvalidName, invalid_name),
                (SymlinkInPath, symlink),
            ]
        };
        let windows = [
            (PermissionDenied, vec![5, 1920, 19]),
            (InUse, vec![32, 33]),
            (NotFound, vec![2, 3, 15, 21]),
            (DiskFull, vec![112, 39]),
            (FileTooLarge, vec![223, 665]),
            (PathTooLong, vec![206]),
            (InvalidName, vec![123, 161]),
        ];
        let linux = || unix(vec![28, 122], vec![36], vec![22, 84], vec![40]);
        let mac = unix(vec![28, 69], vec![63], vec![22, 92], vec![62]);
        for (platform, table) in [
            ("Windows", windows.to_vec()),
            ("Linux", linux().to_vec()),
            ("Android", linux().to_vec()),
            ("Mac OS", mac.to_vec()),
        ] {
            for (expected, numbers) in table {
                for n in numbers {
                    let text = format!("x (os error {n})");
                    assert_eq!(
                        code(&text, Os::of(platform), "remote").0,
                        expected,
                        "{n} on {platform}"
                    );
                }
            }
        }
        // Windows has no errno for a symlink in the path: upstream's sentence stands in.
        assert_eq!(
            code(
                "symlink path component is not allowed",
                Os::Windows,
                "remote"
            )
            .0,
            SymlinkInPath
        );
    }

    /// A transfer's error (`unknown`) on a Windows controller with a non-Windows peer: the
    /// numbers collide, the wording tells the sides apart.
    #[test]
    fn unknown_side_by_wording() {
        let cases = [
            // the peer's: 5 is EIO there, not ACCESS_DENIED
            ("Input/output error (os error 5)", Os::Linux, Other),
            ("Input/output error (os error 5)", Os::Mac, Other),
            // bionic words some errnos differently from glibc
            ("I/O error (os error 5)", Os::Android, Other),
            (
                "Too many symbolic links encountered (os error 40)",
                Os::Android,
                SymlinkInPath,
            ),
            ("Quota exceeded (os error 122)", Os::Android, DiskFull),
            // the peer's: 123 is ENOMEDIUM, not INVALID_NAME
            ("No medium found (os error 123)", Os::Linux, Other),
            // the peer's: 13 is INVALID_DATA, 28 OUT_OF_PAPER on Windows
            (
                "Permission denied (os error 13)",
                Os::Linux,
                PermissionDenied,
            ),
            ("No space left on device (os error 28)", Os::Mac, DiskFull),
            (
                "validation failed: Is a directory (os error 21)",
                Os::Linux,
                Other,
            ),
            // the controller's own read error echoed back by the peer
            (
                "Access is denied. (os error 5)",
                Os::Linux,
                PermissionDenied,
            ),
            ("拒绝访问。 (os error 5)", Os::Mac, PermissionDenied),
            ("设备未就绪。 (os error 21)", Os::Linux, NotFound),
            // a Windows peer: one table for both sides
            ("拒绝访问。 (os error 5)", Os::Windows, PermissionDenied),
            // known limit: a Linux peer's translated wording falls to the Windows table
            ("权限不够 (os error 13)", Os::Linux, Other),
        ];
        for (text, peer, expected) in cases {
            assert_eq!(
                code(text, peer, "unknown").0,
                expected,
                "{text} from {peer:?}"
            );
        }
        // Known sides skip the wording.
        assert_eq!(
            code("Input/output error (os error 5)", Os::Linux, "local").0,
            PermissionDenied
        );
    }

    #[test]
    fn peer_platform_names() {
        let remote = |platform| classify("Permission denied (os error 13)", platform, "remote");
        assert_eq!(remote("Linux").reason, PermissionDenied);
        assert_eq!(remote("Android").reason, PermissionDenied);
        assert_eq!(remote("Mac OS").reason, PermissionDenied);
        // 13 is INVALID_DATA on Windows, also for an empty or unknown platform
        assert_eq!(remote("Windows").reason, Other);
        assert_eq!(remote("").reason, Other);
    }

    #[test]
    fn text_is_clipped_for_every_code() {
        let path = "目".repeat(300);
        let text =
            format!("failed to validate path component '{path}': Access is denied. (os error 5)");
        let r = classify_on(Os::Windows, &text, Os::Windows, "local");
        assert_eq!(r.reason, PermissionDenied);
        assert_eq!(r.text, clip(&text));
        assert_eq!(r.text.chars().count(), 200);
        let r = classify_on(Os::Windows, &path, Os::Windows, "local");
        assert_eq!((r.reason, r.text.chars().count()), (Other, 200));
        assert_eq!(
            classify_on(Os::Windows, "skipped", Os::Windows, "unknown").text,
            "skipped"
        );
    }

    #[test]
    fn json_shape() {
        let json = |text| {
            hbb_common::serde_json::to_string(&classify_on(
                Os::Windows,
                text,
                Os::Windows,
                "unknown",
            ))
            .unwrap()
        };
        assert_eq!(
            json("拒绝访问。 (os error 5)"),
            r#"{"reason":"permission_denied","args":[],"text":"拒绝访问。 (os error 5)"}"#
        );
        assert_eq!(
            json("invalid Windows download file name: a:b"),
            r#"{"reason":"invalid_name_windows","args":["a:b"],"text":"invalid Windows download file name: a:b"}"#
        );
        assert_eq!(
            json("file transfer rejected: too many files (3 files exceeds limit of 2). Adjust"),
            r#"{"reason":"too_many_files","args":["3","2"],"text":"file transfer rejected: too many files (3 files exceeds limit of 2). Adjust"}"#
        );
    }
}
