import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_feedback.dart';

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
  }
  final privacy = notice.args['title'] == 'Privacy mode';
  final text = switch (notice.key) {
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
/// ones without buttons go after [kNoticeDuration].
class SessionNoticesView extends StatefulWidget {
  const SessionNoticesView({super.key, required this.ffi});

  final FFI ffi;

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
      if (n.actions.isEmpty) {
        _timers.putIfAbsent(n, () => Timer(kNoticeDuration, () {
              _timers.remove(n);
              _notices.dismiss(n);
            }));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _notices.items;
    // Notices with buttons (screenshot, printing, elevation) come with M2b.
    return LgNoticeStack(
      dismissLabel: l10n.close,
      notices: [
        for (final n in items)
          LgNotice(
            id: '${identityHashCode(n)}',
            text: noticeText(l10n, n),
            tone: _toneOf(n),
          ),
      ],
      onDismiss: (id) => _notices
          .dismiss(items.firstWhere((n) => '${identityHashCode(n)}' == id)),
    );
  }
}

/// Something that did not go as asked (privacy mode refused or lost, a monitor gone) is a
/// warning; the rest informs.
LgTone _toneOf(SessionNotice n) =>
    n.key == 'display_is_plugged_out_msg' ||
            (n.args['type'] ?? '').contains('error')
        ? LgTone.warning
        : LgTone.info;
