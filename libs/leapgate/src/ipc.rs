//! Leapgate's messages between its own processes. Upstream's IPC carries them all in one
//! `Data::Leapgate` variant (`LEAPGATE.md` §10.10). Append new messages; never reorder or
//! repurpose one, since the two ends can be different builds.

use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, sync::Mutex};

/// Serialized as the CM's UI events too: `{"name":"show_cm"}`, `{"name":"ui_mode","mode":…}`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "name", rename_all = "snake_case")]
pub enum Msg {
    /// Main window to service: `None` asks, the reply carries the counts (C1).
    IncomingCounts { counts: Option<Counts> },
    /// Main window to CM: bring the CM window to the front (C2).
    ShowCm,
    /// Main window to CM: the UI mode changed (S7).
    UiMode { mode: String },
    /// Main window to service: `None` asks; the reply carries the direct IP access listener's
    /// last result, `None` when there is none yet (S5).
    DirectListen { listen: Option<crate::direct::Listen> },
}

/// Authorized incoming connections by type. Exits are not counted in `port_forward`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Counts {
    pub remote: usize,
    pub file_transfer: usize,
    pub port_forward: usize,
    pub exit: usize,
    pub camera: usize,
    pub terminal: usize,
}

/// Upstream's authorized connection types (`AuthConnType`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Remote,
    FileTransfer,
    PortForward,
    Camera,
    Terminal,
}

/// Connections that logged in as an exit. Upstream's connection table has one type for every
/// port forward, so exits are told apart by their connection ID.
static EXIT_CONNS: Mutex<BTreeSet<i32>> = Mutex::new(BTreeSet::new());

/// Called when a connection logs in as an exit. IDs whose connection is no longer `alive` are
/// dropped first, so the table stays bounded even when nobody asks for the counts.
pub fn note_exit_conn(id: i32, alive: &[i32]) {
    let mut exits = EXIT_CONNS.lock().unwrap();
    exits.retain(|id| alive.contains(id));
    exits.insert(id);
}

/// Counts `authed` (upstream's authorized connections). Upstream has no hook where a connection
/// ends, so exit IDs whose connection is no longer `alive` are dropped here.
pub fn incoming_counts(authed: impl IntoIterator<Item = (i32, Kind)>, alive: &[i32]) -> Counts {
    let mut exits = EXIT_CONNS.lock().unwrap();
    let mut counts = Counts::default();
    for (id, kind) in authed {
        let n = match kind {
            Kind::Remote => &mut counts.remote,
            Kind::FileTransfer => &mut counts.file_transfer,
            Kind::PortForward if exits.contains(&id) => &mut counts.exit,
            Kind::PortForward => &mut counts.port_forward,
            Kind::Camera => &mut counts.camera,
            Kind::Terminal => &mut counts.terminal,
        };
        *n += 1;
    }
    exits.retain(|id| alive.contains(id));
    counts
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::serde_json::{self, json};

    #[test]
    fn msg_round_trips_and_cm_events_read_as_documented() {
        let counts = Counts {
            remote: 1,
            exit: 2,
            ..Default::default()
        };
        for msg in [
            Msg::IncomingCounts { counts: None },
            Msg::IncomingCounts {
                counts: Some(counts),
            },
            Msg::ShowCm,
            Msg::UiMode {
                mode: "detailed".to_owned(),
            },
            Msg::DirectListen { listen: None },
            Msg::DirectListen {
                listen: Some(crate::direct::Listen::Failed {
                    port: 21118,
                    error: crate::direct::ListenError::Denied,
                }),
            },
        ] {
            let s = serde_json::to_string(&msg).unwrap();
            assert_eq!(serde_json::from_str::<Msg>(&s).unwrap(), msg);
        }
        assert_eq!(
            serde_json::to_value(Msg::ShowCm).unwrap(),
            json!({"name": "show_cm"})
        );
        assert_eq!(
            serde_json::to_value(Msg::UiMode {
                mode: "simple".to_owned()
            })
            .unwrap(),
            json!({"name": "ui_mode", "mode": "simple"})
        );
        assert_eq!(
            serde_json::to_value(counts).unwrap(),
            json!({"remote": 1, "file_transfer": 0, "port_forward": 0, "exit": 2, "camera": 0, "terminal": 0})
        );
    }

    // One test: EXIT_CONNS is shared by the whole test binary.
    #[test]
    fn counts_by_type_with_exits_apart() {
        use Kind::*;
        assert_eq!(incoming_counts([], &[]), Counts::default());

        note_exit_conn(3, &[3]);
        note_exit_conn(5, &[3, 5]);
        let authed = [
            (1, Remote),
            (2, Remote),
            (3, PortForward),
            (4, PortForward),
            (5, PortForward),
            (6, FileTransfer),
            (7, Camera),
            (8, Terminal),
        ];
        let alive = [1, 2, 3, 4, 5, 6, 7, 8];
        let expected = Counts {
            remote: 2,
            file_transfer: 1,
            port_forward: 1,
            exit: 2,
            camera: 1,
            terminal: 1,
        };
        assert_eq!(incoming_counts(authed, &alive), expected);
        assert_eq!(incoming_counts(authed, &alive), expected, "a query keeps live exits");

        // Exit 5 has ended: its ID is dropped, so the table does not grow with every exit.
        assert_eq!(incoming_counts([(3, PortForward)], &[3]).exit, 1);
        let after = incoming_counts([(3, PortForward), (5, PortForward)], &[3, 5]);
        assert_eq!((after.exit, after.port_forward), (1, 1));

        // An exit is noted just before it is authorized: a query in between must not drop it.
        note_exit_conn(9, &[3, 9]);
        assert_eq!(incoming_counts([(3, PortForward)], &[3, 9]).exit, 1);
        let after = incoming_counts([(3, PortForward), (9, PortForward)], &[3, 9]);
        assert_eq!((after.exit, after.port_forward), (2, 0));

        // Noting an exit drops the ended ones too, with no query in between.
        note_exit_conn(10, &[10]);
        let after = incoming_counts([(3, PortForward), (10, PortForward)], &[3, 10]);
        assert_eq!((after.exit, after.port_forward), (1, 1));
    }
}
