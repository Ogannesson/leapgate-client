import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';

/// At most this many notices show; later ones wait (01 P2 block E).
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

/// The session's notices at the top right of its tab, below the toolbar. Placeholder bars until
/// the designer's `LgNoticeStack` replaces them.
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
    final t = LgTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final n in _notices.items.take(kVisibleNotices))
          Container(
            width: 320,
            margin: const EdgeInsets.only(bottom: LgSpace.s2),
            padding: const EdgeInsets.fromLTRB(
                LgSpace.s3, LgSpace.s2, LgSpace.s1, LgSpace.s2),
            decoration: BoxDecoration(
              color: t.colors.float,
              borderRadius: BorderRadius.circular(LgRadius.r10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(noticeText(l10n, n),
                      style: t.text.copyWith(color: t.colors.text)),
                ),
                // Notices with buttons (screenshot, printing, elevation) come with M2b.
                LgIconButton(
                  icon: LgIcons.x,
                  label: l10n.close,
                  onPressed: () => _notices.dismiss(n),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
