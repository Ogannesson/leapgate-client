//! S5: the result of the direct IP access listener, kept by the service for the settings page
//! (`LEAPGATE.md` §10.13). Upstream only logged it.

use hbb_common::ResultType;
use serde::{Deserialize, Serialize};
use std::{io::ErrorKind, sync::Mutex};

/// As the UI reads it: `{"state":"listening","port":N}`, `{"state":"failed","port":N,"error":…}`.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum Listen {
    Listening { port: i32 },
    Failed { port: i32, error: ListenError },
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ListenError {
    InUse,
    /// Windows 10013 (WSAEACCES): the port is in an excluded range, or another program holds
    /// it exclusively.
    Denied,
    Other,
}

static LAST: Mutex<Option<Listen>> = Mutex::new(None);

/// Wraps upstream's listen call: notes its result and returns it unchanged.
pub fn noted<T>(port: i32, result: ResultType<T>) -> ResultType<T> {
    *LAST.lock().unwrap() = Some(outcome(port, &result));
    result
}

/// The last listen attempt's result in this process, `None` before the first.
pub fn last() -> Option<Listen> {
    *LAST.lock().unwrap()
}

fn outcome<T>(port: i32, result: &ResultType<T>) -> Listen {
    let Err(e) = result else {
        return Listen::Listening { port };
    };
    let error = match e.downcast_ref::<std::io::Error>().map(|e| e.kind()) {
        Some(ErrorKind::AddrInUse) => ListenError::InUse,
        Some(ErrorKind::PermissionDenied) => ListenError::Denied,
        _ => ListenError::Other,
    };
    Listen::Failed { port, error }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{anyhow::anyhow, serde_json};

    fn io(kind: ErrorKind) -> ResultType<()> {
        Err(std::io::Error::from(kind).into())
    }

    #[test]
    fn listen_results_as_the_ui_reads_them() {
        let json = |l: Listen| serde_json::to_string(&l).unwrap();
        assert_eq!(
            json(outcome(21118, &Ok(()))),
            r#"{"state":"listening","port":21118}"#
        );
        assert_eq!(
            json(outcome(21118, &io(ErrorKind::AddrInUse))),
            r#"{"state":"failed","port":21118,"error":"in_use"}"#
        );
        // What Windows 10013 maps to.
        assert_eq!(
            std::io::Error::from_raw_os_error(if cfg!(windows) { 10013 } else { 13 }).kind(),
            ErrorKind::PermissionDenied
        );
        assert_eq!(
            json(outcome(21118, &io(ErrorKind::PermissionDenied))),
            r#"{"state":"failed","port":21118,"error":"denied"}"#
        );
        let other: ResultType<()> = Err(anyhow!("no socket"));
        assert_eq!(
            json(outcome(21118, &other)),
            r#"{"state":"failed","port":21118,"error":"other"}"#
        );

        assert!(noted(21118, io(ErrorKind::AddrInUse)).is_err());
        assert_eq!(
            last(),
            Some(Listen::Failed {
                port: 21118,
                error: ListenError::InUse
            })
        );
    }
}
