//! The ends of the `Data::Leapgate` IPC variant (`LEAPGATE.md` §10.10). The messages live in
//! `leapgate::ipc`.

use crate::{
    ipc::{self, Data},
    server::{AuthConnType, AUTHED_CONNS},
};
#[cfg(feature = "flutter")]
use flutter_rust_bridge::StreamSink;
use hbb_common::{allow_err, log, tokio};
use leapgate::ipc::{Counts, Kind, Msg};

#[cfg(feature = "flutter")]
static CM_EVENTS: std::sync::Mutex<Option<StreamSink<String>>> = std::sync::Mutex::new(None);

/// Service end, from upstream's `ipc::handle`.
pub(crate) async fn handle(msg: Msg, stream: &mut ipc::Connection) {
    if let Msg::IncomingCounts { counts: None } = msg {
        let counts = Some(incoming_counts());
        allow_err!(stream.send(&Data::Leapgate(Msg::IncomingCounts { counts })).await);
    }
}

fn incoming_counts() -> Counts {
    let authed: Vec<(i32, Kind)> = AUTHED_CONNS
        .lock()
        .unwrap()
        .iter()
        .map(|c| {
            let kind = match c.conn_type {
                AuthConnType::Remote => Kind::Remote,
                AuthConnType::FileTransfer => Kind::FileTransfer,
                AuthConnType::PortForward => Kind::PortForward,
                AuthConnType::ViewCamera => Kind::Camera,
                AuthConnType::Terminal => Kind::Terminal,
            };
            (c.conn_id, kind)
        })
        .collect();
    leapgate::ipc::incoming_counts(authed, &crate::Connection::alive_conns())
}

/// Main window end of C1: asks the service once. `None` when it does not answer.
#[tokio::main(flavor = "current_thread")]
pub(crate) async fn query_incoming_counts() -> Option<Counts> {
    let mut c = ipc::connect(1000, "").await.ok()?;
    c.send(&Data::Leapgate(Msg::IncomingCounts { counts: None }))
        .await
        .ok()?;
    match c.next_timeout(1000).await {
        Ok(Some(Data::Leapgate(Msg::IncomingCounts { counts }))) => counts,
        _ => None,
    }
}

/// CM end, from upstream's CM IPC loop: the main window's messages go to the CM page as events.
pub(crate) fn on_cm(msg: Msg) {
    #[cfg(feature = "flutter")]
    if matches!(msg, Msg::ShowCm | Msg::UiMode { .. }) {
        if let Some(sink) = CM_EVENTS.lock().unwrap().as_ref() {
            if let Ok(event) = serde_json::to_string(&msg) {
                sink.add(event);
            }
        }
    }
    #[cfg(not(feature = "flutter"))]
    let _ = msg;
}

#[cfg(feature = "flutter")]
pub(crate) fn set_cm_events(sink: StreamSink<String>) {
    *CM_EVENTS.lock().unwrap() = Some(sink);
}
