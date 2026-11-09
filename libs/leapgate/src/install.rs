//! The home page's "安装" and "升级" cards (M8, `LEAPGATE.md` §10.16) and the install dialog
//! (M9a, §10.18). The install itself is upstream's `platform::install_me`, called from
//! `src/leapgate_hooks/install.rs`.

use hbb_common::serde_json::{self, Value};

/// `install_me`'s options for "安装", from the install dialog's three checkboxes: the words
/// upstream's `install_me` looks for (`contains`).
pub fn options(start_menu: bool, desktop_shortcut: bool, printer: bool) -> String {
    [
        (start_menu, "startmenu"),
        (desktop_shortcut, "desktopicon"),
        (printer, "printer"),
    ]
    .iter()
    .filter_map(|&(on, word)| on.then_some(word))
    .collect::<Vec<_>>()
    .join(" ")
}

/// `install_me`'s options for "升级", from the installed ones (`get_install_options`, a JSON
/// object of registry values), read the way upstream's install page reads them
/// (`flutter/lib/desktop/pages/install_page.dart` `_InstallPageBodyState`): a shortcut is on
/// unless recorded as "0", the printer only when recorded as "1".
pub fn upgrade_options(installed: &str) -> String {
    let installed: Value = serde_json::from_str(installed).unwrap_or_default();
    let recorded = |key: &str| installed.get(key).and_then(Value::as_str);
    let mut options = Vec::new();
    if recorded("STARTMENUSHORTCUTS") != Some("0") {
        options.push("startmenu");
    }
    if recorded("DESKTOPSHORTCUTS") != Some("0") {
        options.push("desktopicon");
    }
    if recorded("PRINTER") == Some("1") {
        options.push("printer");
    }
    options.join(" ")
}

/// A failed install as the UI gets it: `{"result":"uac_denied"|"failed","text":…}`. The
/// elevation's error keeps Windows' HRESULT in its text, the user cancelling it being
/// `HRESULT_FROM_WIN32(ERROR_CANCELLED)`; the message beside it is in the system's language.
pub fn failure(text: &str) -> String {
    let result = if text.contains("0x800704C7") {
        "uac_denied"
    } else {
        "failed"
    };
    serde_json::json!({ "result": result, "text": text }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upgrade_keeps_the_installed_choices() {
        assert_eq!(
            upgrade_options(r#"{"STARTMENUSHORTCUTS":"1","DESKTOPSHORTCUTS":"0","PRINTER":"1"}"#),
            "startmenu printer"
        );
        // Nothing recorded: upstream's page starts with both shortcuts on.
        assert_eq!(upgrade_options("{}"), "startmenu desktopicon");
        assert_eq!(
            upgrade_options(r#"{"STARTMENUSHORTCUTS":"0","DESKTOPSHORTCUTS":"0","PRINTER":"0"}"#),
            ""
        );
    }

    #[test]
    fn install_options_are_the_checked_boxes() {
        assert_eq!(options(true, true, true), "startmenu desktopicon printer");
        assert_eq!(options(false, true, false), "desktopicon");
        assert_eq!(options(false, false, false), "");
    }

    #[test]
    fn a_cancelled_elevation_is_uac_denied() {
        let text = "Installer handoff failed; protected directory may remain at C:\\x: \
                    The operation was canceled by the user. (0x800704C7)";
        let failure: Value = serde_json::from_str(&failure(text)).unwrap();
        assert_eq!(failure["result"], "uac_denied");
        assert_eq!(failure["text"], text);
    }

    #[test]
    fn other_failures_keep_their_text() {
        let text = "Cannot install the EXE package over an existing MSI installation";
        let failure: Value = serde_json::from_str(&failure(text)).unwrap();
        assert_eq!(failure["result"], "failed");
        assert_eq!(failure["text"], text);
    }
}
