//! The new UI's tunnel cards (M9c, `LEAPGATE.md` §10.18): a TCP tunnel card runs every saved port
//! forward of a device, an RDP card the one RDP forward. `leapgate_tunnel_session_add` registers a
//! card and adds a port forward (or RDP) session without arguments; upstream's `io_loop` hands
//! that session, and only that one, to `run` (the hook at the top of its port forward branch).
//! Each row logs in on its own connection as soon as it listens, and reports its state on one
//! event stream for all cards. The old UI never registers and keeps upstream's loop.

use crate::{
    client::{Data, Interface},
    ui_session_interface::{InvokeUiSession, Session},
};
#[cfg(feature = "flutter")]
use flutter_rust_bridge::StreamSink;
use hbb_common::{log, tokio::sync::mpsc, SessionID};
use leapgate::tunnel::{self, Kind, State};
use std::{
    collections::BTreeMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
};

/// Sent by the new UI's exports only.
#[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
pub(crate) enum Ctl {
    /// A row's local port, 0 for RDP.
    Retry(i32),
}

struct Card {
    /// Tells this card from a later one for the same device whose session was added while this
    /// one was still closing.
    gen: u64,
    /// The card's session, carried by every event and matched by `take`.
    session_id: SessionID,
    /// Each row's last state event, by local port, sent again to a new subscriber.
    rows: BTreeMap<i32, String>,
    #[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
    ctl: mpsc::UnboundedSender<Ctl>,
    /// Taken by the card's `run`.
    ctl_rx: Option<mpsc::UnboundedReceiver<Ctl>>,
}

/// Keyed on the device ID and the kind: a device's TCP and RDP cards are apart, and apart from
/// its exit card (`exit::cards`).
static CARDS: Mutex<BTreeMap<(String, Kind), Card>> = Mutex::new(BTreeMap::new());
static NEXT_GEN: AtomicU64 = AtomicU64::new(0);
#[cfg(feature = "flutter")]
static EVENTS: Mutex<Option<StreamSink<String>>> = Mutex::new(None);

/// What `run` takes from the registry.
pub(crate) struct Taken {
    kind: Kind,
    gen: u64,
    ctl: mpsc::UnboundedReceiver<Ctl>,
}

/// `leapgate_tunnel_session_add`: a port forward (or RDP) session without arguments, so
/// `io_loop` takes the no-argument branch and the hook hands it to `run`.
#[cfg(feature = "flutter")]
pub(crate) fn session_add(
    session_id: &crate::flutter_ffi::SessionID,
    id: &str,
    rdp: bool,
    password: String,
    is_shared_password: bool,
    conn_token: Option<String>,
    force_relay: bool,
) -> String {
    use hbb_common::rendezvous_proto::ConnType;
    let (kind, conn_type) = if rdp {
        (Kind::Rdp, ConnType::RDP)
    } else {
        (Kind::Tcp, ConnType::PORT_FORWARD)
    };
    super::exit::cards::add_session(
        session_id,
        id,
        conn_type,
        Vec::new(),
        password,
        is_shared_password,
        conn_token,
        force_relay,
        || register(id, kind, *session_id),
    )
}

/// Replaces a card left by a session that never started.
fn register(id: &str, kind: Kind, session_id: SessionID) {
    let (ctl, ctl_rx) = mpsc::unbounded_channel();
    let card = Card {
        gen: NEXT_GEN.fetch_add(1, Ordering::Relaxed),
        session_id,
        rows: BTreeMap::new(),
        ctl,
        ctl_rx: Some(ctl_rx),
    };
    CARDS.lock().unwrap().insert((id.to_owned(), kind), card);
}

/// The hook in `io_loop`: the card registered for this very session, or `None` for any other
/// port forward session (an exit card's, the old UI's, one added after the card's).
pub(crate) fn take<T: InvokeUiSession>(handler: &Session<T>) -> Option<Taken> {
    #[cfg(feature = "flutter")]
    {
        use crate::flutter::sessions;
        let kind = if handler.is_rdp() { Kind::Rdp } else { Kind::Tcp };
        // A session's `lc` is its own: the registered ID's session is this one when they share it.
        take_if(&handler.get_id(), kind, |session_id| {
            sessions::get_session_by_session_id(session_id)
                .is_some_and(|s| std::sync::Arc::ptr_eq(&s.lc, &handler.lc))
        })
    }
    #[cfg(not(feature = "flutter"))]
    {
        let _ = handler;
        None
    }
}

/// `is_session` is asked without `CARDS` held: it takes upstream's session locks.
#[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
fn take_if(id: &str, kind: Kind, is_session: impl FnOnce(&SessionID) -> bool) -> Option<Taken> {
    let key = (id.to_owned(), kind);
    let (gen, session_id) = {
        let cards = CARDS.lock().unwrap();
        let card = cards.get(&key)?;
        (card.gen, card.session_id)
    };
    if !is_session(&session_id) {
        return None;
    }
    let mut cards = CARDS.lock().unwrap();
    let card = cards.get_mut(&key).filter(|card| card.gen == gen)?;
    Some(Taken {
        kind,
        gen,
        ctl: card.ctl_rx.take()?,
    })
}

/// `leapgate_tunnel_retry`: `false` without such a card or row.
#[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
pub(crate) fn retry(session_id: &SessionID, port: i32) -> bool {
    CARDS
        .lock()
        .unwrap()
        .values()
        .find(|card| card.session_id == *session_id)
        .filter(|card| card.rows.contains_key(&port))
        .map_or(false, |card| card.ctl.send(Ctl::Retry(port)).is_ok())
}

/// Each row's last state first, then every change. A new subscription replaces the old one.
#[cfg(feature = "flutter")]
pub(crate) fn set_events(sink: StreamSink<String>) {
    let cards = CARDS.lock().unwrap();
    for event in cards.values().flat_map(|card| card.rows.values()) {
        sink.add(event.clone());
    }
    *EVENTS.lock().unwrap() = Some(sink);
}

/// A card's or a row's (`port`) event. A notice is not kept for a new subscriber.
fn push(id: &str, kind: Kind, gen: u64, port: Option<i32>, state: &State) {
    let key = (id.to_owned(), kind);
    let mut cards = CARDS.lock().unwrap();
    let Some(card) = cards.get_mut(&key).filter(|card| card.gen == gen) else {
        return;
    };
    let event = tunnel::event(id, &card.session_id.to_string(), kind, port, state);
    #[cfg(feature = "flutter")]
    if let Some(sink) = EVENTS.lock().unwrap().as_ref() {
        sink.add(event.clone());
    }
    match (state, port) {
        (State::Closed, _) => {
            cards.remove(&key);
        }
        (State::Removed, Some(port)) => {
            card.rows.remove(&port);
        }
        (State::Notice { .. }, _) | (_, None) => {}
        (_, Some(port)) => {
            card.rows.insert(port, event);
        }
    }
}

/// The card's loop, in the session's thread and runtime, in place of upstream's.
pub(crate) async fn run<T: InvokeUiSession>(
    handler: Session<T>,
    card: Taken,
    mut receiver: mpsc::UnboundedReceiver<Data>,
    _key: &str,
    _token: &str,
) {
    let id = handler.get_id();
    let Taken { kind, gen, ctl: _ctl } = card;
    log::info!("leapgate tunnel: {:?} card started", kind);
    loop {
        match receiver.recv().await {
            Some(Data::Close) | None => break,
            _ => {}
        }
    }
    log::info!("leapgate tunnel: {:?} card closed", kind);
    push(&id, kind, gen, None, &State::Closed);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn take_claims_only_the_registered_session_once() {
        let (id, sid, other) = ("tunnel-take", SessionID::new_v4(), SessionID::new_v4());
        register(id, Kind::Tcp, sid);
        // Another session of the device (an exit card's, one added later) is not the card's.
        assert!(take_if(id, Kind::Tcp, |s| *s == other).is_none());
        assert!(take_if(id, Kind::Rdp, |s| *s == sid).is_none());
        assert!(take_if(id, Kind::Tcp, |s| *s == sid).is_some());
        assert!(take_if(id, Kind::Tcp, |s| *s == sid).is_none(), "taken twice");
        CARDS.lock().unwrap().remove(&(id.to_owned(), Kind::Tcp));
    }

    #[test]
    fn retry_reaches_a_row_of_the_card_only() {
        let (id, sid) = ("tunnel-retry", SessionID::new_v4());
        register(id, Kind::Tcp, sid);
        let gen = CARDS.lock().unwrap()[&(id.to_owned(), Kind::Tcp)].gen;
        assert!(!retry(&sid, 8080), "no such row yet");
        push(id, Kind::Tcp, gen, Some(8080), &State::PortInUse);
        assert!(retry(&sid, 8080));
        assert!(!retry(&sid, 8081));
        assert!(!retry(&SessionID::new_v4(), 8080));
        push(id, Kind::Tcp, gen, Some(8080), &State::Removed);
        assert!(!retry(&sid, 8080), "removed");
        push(id, Kind::Tcp, gen, None, &State::Closed);
        assert!(!CARDS.lock().unwrap().contains_key(&(id.to_owned(), Kind::Tcp)));
    }
}
