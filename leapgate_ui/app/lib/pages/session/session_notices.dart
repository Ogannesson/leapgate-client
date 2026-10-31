import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_requests.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_panel_inputs.dart';
import '../../widgets/lg_selection.dart';
import 'toolbar/dialogs.dart';

/// At most this many notices show, later ones wait (01 P2 block E): [LgNoticeStack] draws this
/// many, and a waiting notice starts its time only when it shows.
const kVisibleNotices = 3;

/// A notice without buttons goes after this long (01 P2 block E "几秒后自己消失").
const kNoticeDuration = Duration(seconds: 5);

final _logged = <String>{};

/// The text of a notice: 01 P2 block E's where it has one, otherwise upstream's text through
/// Rust's translation, logged once per key so the missing copy shows up.
String noticeText(AppLocalizations l10n, SessionNotice notice) {
  switch (notice.args['type']) {
    case 'on-uac':
      return l10n.sessionNoticeUac;
    case 'wait-uac':
      return l10n.sessionNoticeWaitUac;
    case 'on-foreground-elevated':
      return l10n.noticeForegroundElevated;
    case 'elevation-error':
      return l10n.noticeElevationFailed(translate(notice.key));
  }
  if (notice.tag == kNoticeTagScreenshotFailed) {
    return notice.key == 'screenshot-merged-screen-not-supported-tip'
        ? l10n.noticeScreenshotAllMonitors
        : l10n.noticeScreenshotFailed(translate(notice.key));
  }
  if (notice.key == kNoticePermissionRevoked) {
    return switch (notice.args['permission']) {
      'keyboard' => l10n.noticeRevokedKeyboard,
      'clipboard' => l10n.noticeRevokedClipboard,
      'audio' => l10n.noticeRevokedAudio,
      'file' => l10n.noticeRevokedFile,
      'restart' => l10n.noticeRevokedRestart,
      'recording' => l10n.noticeRevokedRecording,
      'block_input' => l10n.noticeRevokedBlockInput,
      _ => l10n.noticeRevokedPrivacyMode,
    };
  }
  final privacy = notice.args['title'] == 'Privacy mode';
  final text = switch (notice.key) {
    'screenshot-action-tip' => l10n.noticeScreenshotDone,
    'print-incoming-job-confirm-tip' => l10n.noticePrintJob,
    'Elevate successfully' => l10n.noticeElevated,
    'Please switch to Display 1 first' => l10n.noticeSwitchMonitorFirst,
    kNoticeAutoRecording => l10n.noticeAutoRecording,
    'Enter privacy mode' => l10n.sessionNoticePrivacyOn,
    'Exit privacy mode' => l10n.sessionNoticePrivacyOff,
    'Unsupported' when privacy => l10n.sessionNoticePrivacyUnsupported,
    'Peer denied' when privacy => l10n.sessionNoticePrivacyDenied,
    'Peer exit' when privacy => l10n.sessionNoticePrivacyPeerExit,
    'Turned off' when privacy => l10n.sessionNoticePrivacyTurnedOff,
    'display_is_plugged_out_msg' => l10n.sessionNoticeDisplayUnplugged,
    _ => null,
  };
  if (text != null) return text;
  // Some texts come from the remote device: as C3 does, at most 64 of them, each cut to 200
  // characters on a character boundary.
  final key = String.fromCharCodes(notice.key.runes.take(200));
  if (_logged.length < 64 && _logged.add(key)) {
    lgBind.leapgateLog(level: 3, msg: 'leapgate ui: notice without copy: $key');
  }
  return translate(notice.key);
}

/// The session's notices at the top right of its tab, below the toolbar ([LgNoticeStack]); the
/// ones without buttons go after [kNoticeDuration]. The ones with buttons (01 P2 block E:
/// screenshot, print job, elevation, a recording started by itself, privacy mode on another
/// monitor) get them here by tag and type; those that ask stay until answered or closed.
class SessionNoticesView extends StatefulWidget {
  const SessionNoticesView(
      {super.key, required this.ffi, required this.overlays});

  final FFI ffi;

  /// Where the printer choice and the elevation dialog open: over this tab.
  final TabOverlays overlays;

  @override
  State<SessionNoticesView> createState() => _SessionNoticesViewState();
}

class _SessionNoticesViewState extends State<SessionNoticesView> {
  final _timers = <SessionNotice, Timer>{};

  SessionNotices get _notices => widget.ffi.notices;

  @override
  void initState() {
    super.initState();
    _notices.addListener(_onChange);
    _onChange();
  }

  @override
  void dispose() {
    _notices.removeListener(_onChange);
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  /// Times the shown notices that have no buttons; a queued one starts its time when it shows.
  void _onChange() {
    final shown = _notices.items.take(kVisibleNotices).toSet();
    _timers.removeWhere((n, t) {
      if (shown.contains(n)) return false;
      t.cancel();
      return true;
    });
    for (final n in shown) {
      if (n.actions.isEmpty && !_asks(n)) {
        _timers.putIfAbsent(n, () => Timer(kNoticeDuration, () {
              _timers.remove(n);
              _notices.dismiss(n);
            }));
      }
    }
    if (mounted) setState(() {});
  }

  /// "记住此选择" of each print job notice.
  final _rememberPrint = <SessionNotice, bool>{};

  SessionRequests get _requests => widget.ffi.requests;

  TabOverlays get _overlays => widget.overlays;

  /// The buttons of a notice that asks, by its tag or type; the others' own actions.
  List<LgNoticeAction> _buttonsOf(AppLocalizations l10n, SessionNotice n) {
    final tag = n.tag ?? '';
    final type = n.args['type'];
    if (tag == kNoticeTagScreenshot) {
      return [
        LgNoticeAction(l10n.noticeSaveAs, _saveScreenshot),
        LgNoticeAction(l10n.noticeCopyToClipboard, _requests.copyScreenshot),
      ];
    }
    if (tag.startsWith(kNoticeTagPrinterPrefix)) {
      final remember = _rememberPrint[n] ?? false;
      return [
        LgNoticeAction(l10n.noticeUseDefaultPrinter,
            () => _answerPrint(n, remember: remember)),
        LgNoticeAction(l10n.noticeChoosePrinter, () => _choosePrinter(n)),
        LgNoticeAction(l10n.noticeDontPrint,
            () => _answerPrint(n, print: false, remember: remember)),
      ];
    }
    if (type == 'on-uac' || type == 'on-foreground-elevated') {
      // Upstream's "Wait" only closes it (`common/widgets/dialog.dart:1339`).
      return [
        LgNoticeAction(l10n.noticeWait, () => _notices.dismiss(n)),
        LgNoticeAction(l10n.noticeRequestElevation, _requestElevation),
      ];
    }
    if (type == 'elevation-error' && n.key != 'No permission') {
      return [LgNoticeAction(l10n.connRetry, _requestElevation)];
    }
    if (tag == kNoticeTagAutoRecord) {
      return [LgNoticeAction(l10n.noticeStop, _requests.toggleRecording)];
    }
    if (tag == kNoticeTagPrivacySwitchDisplay) {
      return [
        LgNoticeAction(
            l10n.noticeSwitchToMonitor1, _requests.switchToFirstMonitor)
      ];
    }
    return [
      for (final a in n.actions) LgNoticeAction(translate(a.key), a.onPressed)
    ];
  }

  Future<void> _answerPrint(SessionNotice n,
      {bool print = true, String printer = '', bool remember = false}) {
    _rememberPrint.remove(n);
    return _requests.answerPrintJob(n,
        print: print, printer: printer, remember: remember);
  }

  /// Upstream's file dialog for "Save as…" (`models/model.dart:502-508`). The notice goes first,
  /// as upstream closed its dialog first, so a second click cannot open a second file dialog.
  Future<void> _saveScreenshot() async {
    _notices.dismissTag(kNoticeTagScreenshot);
    final l10n = AppLocalizations.of(context)!;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: l10n.noticeSaveAs,
      fileName: 'screenshot_$ts.png',
      allowedExtensions: ['png'],
      type: FileType.custom,
    );
    await _requests.saveScreenshot(path);
  }

  /// "选择打印机": the printers in a small dialog over this tab, with "记住此选择" (upstream's
  /// print job dialog, `models/model.dart:552-722`).
  Future<void> _choosePrinter(SessionNotice n) async {
    final l10n = AppLocalizations.of(context)!;
    final printers = _requests.printers();
    var chosen = printers.names.contains(printers.selected)
        ? printers.selected
        : printers.names.firstOrNull;
    var remember = _rememberPrint[n] ?? false;
    final ok = await _overlays.show<bool>(
      widget.ffi.id,
      (context, close) => StatefulBuilder(
        builder: (context, setState) => LgDialogScrim(
          onEscape: () => close(null),
          child: LgConfirmDialog(
            title: l10n.noticeChoosePrinter,
            actions: [
              LgDialogAction(
                  label: l10n.connCancel, onPressed: () => close(null)),
              LgDialogAction(
                label: l10n.noticePrint,
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: chosen == null ? null : () => close(true),
              ),
            ],
            children: [
              LgSelectField<String>(
                items: [for (final p in printers.names) LgSelectItem(p, p)],
                value: chosen,
                semanticLabel: l10n.noticePrinter,
                onChanged: (v) => setState(() => chosen = v),
              ),
              LgCheckbox(
                value: remember,
                label: l10n.noticeRememberChoice,
                onChanged: (v) => setState(() => remember = v),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && chosen != null) {
      await _answerPrint(n, printer: chosen!, remember: remember);
    }
  }

  void _requestElevation() => showRequestElevationDialog(
      _overlays, widget.ffi, AppLocalizations.of(context)!);

  /// Closing the screenshot notice drops the image in Rust.
  void _dismiss(SessionNotice n) {
    if (n.tag == kNoticeTagScreenshot) {
      _requests.discardScreenshot();
    } else {
      _notices.dismiss(n);
    }
    _rememberPrint.remove(n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _notices.items;
    return LgNoticeStack(
      dismissLabel: l10n.sessionNoticeDismiss,
      notices: [
        for (final n in items)
          LgNotice(
            id: '${identityHashCode(n)}',
            text: noticeText(l10n, n),
            tone: _toneOf(n),
            icon: (n.tag ?? '').startsWith(kNoticeTagPrinterPrefix)
                ? LgIcons.printer
                : null,
            actions: _buttonsOf(l10n, n),
            check: (n.tag ?? '').startsWith(kNoticeTagPrinterPrefix)
                ? LgNoticeCheck(
                    label: l10n.noticeRememberChoice,
                    value: _rememberPrint[n] ?? false,
                    onChanged: (v) => setState(() => _rememberPrint[n] = v),
                  )
                : null,
          ),
      ],
      onDismiss: (id) =>
          _dismiss(items.firstWhere((n) => '${identityHashCode(n)}' == id)),
    );
  }
}

/// The notices that ask something stay until answered or closed (01 P2 block E). The automatic
/// recording one goes by itself: the toolbar's record button stops it too.
bool _asks(SessionNotice n) {
  final tag = n.tag ?? '';
  final type = n.args['type'];
  return tag == kNoticeTagScreenshot ||
      tag.startsWith(kNoticeTagPrinterPrefix) ||
      tag == kNoticeTagPrivacySwitchDisplay ||
      type == 'on-uac' ||
      type == 'on-foreground-elevated' ||
      (type == 'elevation-error' && n.key != 'No permission');
}

/// Something that did not go as asked (privacy mode refused or lost, a monitor gone) is a
/// warning; the rest informs.
LgTone _toneOf(SessionNotice n) =>
    n.key == 'display_is_plugged_out_msg' ||
            (n.args['type'] ?? '').contains('error')
        ? LgTone.warning
        : LgTone.info;
