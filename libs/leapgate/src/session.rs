//! Per-session state the new UI keeps in Rust, keyed by the UI's session ID.

use hbb_common::SessionID;
use std::{collections::BTreeSet, sync::Mutex};

/// Session tabs the new UI has hidden (V1). Only hidden ones are stored, so showing a tab again
/// leaves nothing behind.
static HIDDEN: Mutex<BTreeSet<SessionID>> = Mutex::new(BTreeSet::new());

/// `alive` says whether a session still exists. Upstream's `session_close` has no hook, so
/// entries of tabs closed while hidden are dropped here. It runs without `HIDDEN` held:
/// `all_hidden` is called with the session handlers' lock held, and `alive` takes that lock.
pub fn set_visible(id: SessionID, visible: bool, alive: impl Fn(&SessionID) -> bool) {
    let hidden: Vec<SessionID> = HIDDEN.lock().unwrap().iter().copied().collect();
    let closed: Vec<SessionID> = hidden
        .into_iter()
        .filter(|h| *h != id && !alive(h))
        .collect();
    let mut hidden = HIDDEN.lock().unwrap();
    for h in &closed {
        hidden.remove(h);
    }
    if visible {
        hidden.remove(&id);
    } else {
        hidden.insert(id);
    }
}

/// True when every one of a peer session's UI sessions is hidden, so its frames go nowhere.
pub fn all_hidden<'a>(ids: impl IntoIterator<Item = &'a SessionID>) -> bool {
    let hidden = HIDDEN.lock().unwrap();
    if hidden.is_empty() {
        return false;
    }
    let mut any = false;
    for id in ids {
        if !hidden.contains(id) {
            return false;
        }
        any = true;
    }
    any
}

#[cfg(test)]
mod tests {
    use super::*;

    // One test: HIDDEN is shared by the whole test binary.
    #[test]
    fn hidden_tabs_get_no_frames() {
        let (a, b, gone) = (
            SessionID::new_v4(),
            SessionID::new_v4(),
            SessionID::new_v4(),
        );
        let alive = |id: &SessionID| *id != gone;
        assert!(!all_hidden([&a]), "visible by default");
        assert!(!all_hidden([]), "no UI session at all");
        set_visible(a, false, alive);
        assert!(all_hidden([&a]));
        assert!(!all_hidden([&a, &b]), "another window still shows it");
        set_visible(b, false, alive);
        assert!(all_hidden([&a, &b]));
        set_visible(a, true, alive);
        assert!(!all_hidden([&a]));
        set_visible(gone, false, |_| true);
        set_visible(b, true, alive);
        assert!(HIDDEN.lock().unwrap().is_empty(), "closed tab dropped");
    }
}
