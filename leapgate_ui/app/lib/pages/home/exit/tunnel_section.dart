import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart' show ConnReason;
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/tunnel_api.dart';
import 'package:flutter_hbb/leapgate/tunnel_card.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_exit_card.dart';
import '../../../widgets/lg_forward_list.dart';
import '../../../widgets/lg_page_section.dart';
import '../../../widgets/lg_tunnel_card.dart';
import '../../peer_platform.dart';
import '../../session/reasons.dart';
import '../password_row.dart' show copyWithToast;
import 'rdp_settings_dialog.dart';

// The "隧道" section of the exit page (13 §1.3) over [TunnelsModel], drawn by [LgTunnelCard]
// (`LEAPGATE.md` §10.18): a TCP tunnel card with its forwards, or an RDP card, each a full row.

/// The reason after "已停止：", and whether "Retry" can help (13 §1.3 block B): not for an old
/// version. Null without a reason.
({String? reason, bool retry}) tunnelStoppedView(
  AppLocalizations l10n,
  ConnReason? reason,
  String id,
) {
  if (reason == null) return (reason: null, retry: true);
  final (text, retry) = switch (reason.code) {
    'no_permission' => (l10n.tunnelReasonNoPermission, true),
    'peer_too_old' => (l10n.tunnelReasonPeerTooOld, false),
    'insecure_declined' => (l10n.tunnelReasonInsecureDeclined, true),
    'too_many_attempts' => (l10n.exitReasonTooManyAttempts, true),
    _ => (_firstSentence(reasonView(l10n, reason, id).text), true),
  };
  return (reason: text.isEmpty ? null : text, retry: retry);
}

/// Only its first sentence, without the full stop (01 §7.6).
String _firstSentence(String text) =>
    RegExp(r'^[^。]*?(?=。|\.(?:\s|$)|$)').firstMatch(text)?.group(0) ?? '';

/// The card's name: given when it was opened, else the remote host name, else the ID.
String tunnelCardName(TunnelCard card) => card.name ?? formatPeerId(card.id);

final _promptFocus = <String>{};

/// The user asked [id]'s [kind] card to log in (opening it, "重试", "重新连接", adding a forward):
/// its next password or code prompt takes the keyboard. A prompt that comes by itself on a lazy
/// reconnect does not (13 §1.3 block B "提问区").
void focusTunnelPromptOf(String id, TunnelKind kind) =>
    _promptFocus.add('${kind.name}:$id');

class TunnelSection extends StatelessWidget {
  const TunnelSection({
    super.key,
    required this.overlays,
    required this.cardKey,
    required this.flashes,
  });

  final TabOverlays overlays;

  /// The key of a card, to scroll to it, and how often it was marked ([LgFlash.count]).
  final GlobalKey Function(String id, TunnelKind kind) cardKey;
  final int Function(String id, TunnelKind kind) flashes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LgPageSection(
      icon: LgIcons.forward,
      title: l10n.tunnelSectionTunnels,
      lede: l10n.tunnelLede,
      children: [
        ListenableBuilder(
          listenable: appCore.tunnels,
          builder: (context, _) => LgTunnelStack(
            emptyText: l10n.tunnelNoneInUse,
            semanticLabel: l10n.tunnelInUseList,
            children: [
              for (final card in appCore.tunnels.cards)
                LgFlash(
                  key: cardKey(card.id, card.kind),
                  count: flashes(card.id, card.kind),
                  child: TunnelCardView(
                    key: ObjectKey(card),
                    card: card,
                    overlays: overlays,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class TunnelCardView extends StatefulWidget {
  const TunnelCardView({super.key, required this.card, required this.overlays});

  final TunnelCard card;
  final TabOverlays overlays;

  @override
  State<TunnelCardView> createState() => _TunnelCardViewState();
}

class _TunnelCardViewState extends State<TunnelCardView> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _local = TextEditingController();
  final _host = TextEditingController();
  final _remote = TextEditingController();
  final _passwordFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _localFocus = FocusNode();
  var _remember = false;
  var _trust = false;
  var _adding = false;
  TunnelAddForwardError? _addError;
  var _errorField = LgForwardField.local;
  Timer? _ticker;
  late TunnelQuestion _question;

  TunnelCard get _card => widget.card;
  String get _focusKey => '${_card.kind.name}:${_card.id}';

  /// A TCP card that opened with no forward unfolds the add line at once (13 §1.3 block B).
  bool get _noForwards =>
      _card.kind == TunnelKind.tcp &&
      _card.addError == null &&
      _card.rows.isEmpty;

  @override
  void initState() {
    super.initState();
    _question = _card.question;
    _remember = _card.rememberPassword;
    _card.addListener(_onCard);
    for (final c in [_password, _local, _remote]) {
      c.addListener(_rebuild);
    }
    _local.addListener(() => _clearError(LgForwardField.local));
    _host.addListener(() => _clearError(LgForwardField.host));
    _remote.addListener(() => _clearError(LgForwardField.remote));
    _syncTicker();
  }

  @override
  void dispose() {
    _card.removeListener(_onCard);
    _ticker?.cancel();
    for (final c in [_password, _code, _local, _host, _remote]) {
      c.dispose();
    }
    _passwordFocus.dispose();
    _codeFocus.dispose();
    _localFocus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _clearError(LgForwardField field) {
    if (_addError != null && _errorField == field) {
      setState(() => _addError = null);
    }
  }

  /// Once the field is built.
  void _focusLater(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });

  void _onCard() {
    final question = _card.question;
    if (question != _question) {
      if (_question == TunnelQuestion.password) _password.clear();
      if (question == TunnelQuestion.password) {
        _remember = _card.rememberPassword;
      }
      if (question == TunnelQuestion.twoFactor) _code.clear();
      if (question == TunnelQuestion.password ||
          question == TunnelQuestion.twoFactor) {
        // Asked by the user, or asked again after a wrong entry (Enter took the focus away).
        if (_promptFocus.remove(_focusKey) || _card.wrongInput) {
          _focusLater(
            question == TunnelQuestion.password ? _passwordFocus : _codeFocus,
          );
        }
      } else if (question == TunnelQuestion.none) {
        _promptFocus.remove(_focusKey);
      }
      _question = question;
      _syncTicker();
    }
    setState(() {});
  }

  /// "（已等待 0:12）" goes with the seconds.
  void _syncTicker() {
    if (_card.question == TunnelQuestion.waitAccept) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _rebuild());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  String _waited() {
    final since = _card.waitingSince;
    final s = since == null ? 0 : DateTime.now().difference(since).inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _openAdd() {
    setState(() {
      _adding = true;
      _addError = null;
    });
    _focusLater(_localFocus);
  }

  void _closeAdd() {
    // With no forward there is nothing to fold back to (13 §1.3 block B).
    if (_noForwards) return;
    setState(() {
      _adding = false;
      _addError = null;
    });
    _local.clear();
    _host.clear();
    _remote.clear();
  }

  void _add() {
    final local = int.tryParse(_local.text.trim()) ?? 0;
    final remote = int.tryParse(_remote.text.trim()) ?? 0;
    focusTunnelPromptOf(_card.id, _card.kind);
    final error = _card.addForward(local, _host.text, remote);
    if (error == null) {
      _local.clear();
      _host.clear();
      _remote.clear();
      // It stays open for the next one, also when it opened for a card without forwards.
      setState(() {
        _adding = true;
        _addError = null;
      });
    } else {
      _promptFocus.remove(_focusKey);
      final localBad = local < 1 || local > 65535;
      setState(() {
        _addError = error;
        _errorField = error == TunnelAddForwardError.invalid && !localBad
            ? LgForwardField.remote
            : LgForwardField.local;
      });
    }
    // Enter took the focus out of the field.
    _focusLater(_localFocus);
  }

  void _retryRow(TunnelRow row) {
    focusTunnelPromptOf(_card.id, _card.kind);
    _card.retryRow(row);
  }

  void _retryCard() {
    focusTunnelPromptOf(_card.id, _card.kind);
    _card.retry();
  }

  LgExitStatus _rowStatus(AppLocalizations l10n, TunnelRow row) {
    final rdp = _card.kind == TunnelKind.rdp;
    return switch (row.state) {
      TunnelRowState.connecting =>
        rdp
            ? LgExitStatus(
                LgExitStatusKind.busy,
                l10n.connConnectingTo(tunnelCardName(_card)),
              )
            : LgExitStatus(LgExitStatusKind.busy, l10n.tunnelConnecting),
      TunnelRowState.inUse =>
        row.direct
            ? LgExitStatus(LgExitStatusKind.direct, l10n.exitInUseDirect)
            : LgExitStatus(
                LgExitStatusKind.relay,
                l10n.exitInUseRelay,
                // A row says it on hover (13 §1.3 block B); the RDP card under its status.
                note: rdp ? l10n.exitRelayNote : null,
              ),
      // A failed login says why under it (13 §1.3 block B).
      TunnelRowState.interrupted => LgExitStatus(
        LgExitStatusKind.warning,
        l10n.tunnelInterrupted,
        reason: rdp ? l10n.tunnelInterruptedRdp : l10n.tunnelInterruptedTcp,
        note: tunnelStoppedView(l10n, row.reason, _card.id).reason,
      ),
      TunnelRowState.stopped => () {
        final view = tunnelStoppedView(l10n, row.reason, _card.id);
        return LgExitStatus(
          LgExitStatusKind.error,
          view.reason == null ? l10n.exitStoppedPlain : l10n.exitStoppedPrefix,
          reason: view.reason,
        );
      }(),
      TunnelRowState.portBusy => LgExitStatus(
        LgExitStatusKind.error,
        l10n.exitPortBusy(row.localPort),
      ),
    };
  }

  String _noticeText(
    AppLocalizations l10n,
    TunnelRow row,
    ConnReason n,
  ) => switch (n.code) {
    'tunnel_unreachable' =>
      _card.kind == TunnelKind.rdp
          ? l10n.tunnelNoticeRdpUnreachable
          : l10n.tunnelNoticeUnreachable(
              row.forward.host,
              row.forward.remotePort,
            ),
    'no_permission' => l10n.tunnelNoticeNoPermission,
    'tunnel_too_many_channels' => l10n.tunnelNoticeTooMany,
    // "Port forward target not authorized" and what else the peer says, as it says it.
    _ => n.text,
  };

  List<LgExitNotice> _notices(AppLocalizations l10n, TunnelRow row) => [
    for (final n in row.notices)
      LgExitNotice(
        id: '${n.code} ${n.params} ${n.text}',
        text: _noticeText(l10n, row, n),
        dismissLabel: l10n.sessionNoticeDismiss,
        onDismiss: () => _card.dismissNotice(row, n),
      ),
  ];

  LgTunnelQuestion? _questionArea(
    AppLocalizations l10n,
    LgExitAction Function(
      String,
      VoidCallback?, {
      LgButtonKind kind,
      bool named,
    })
    action,
  ) {
    final card = _card;
    final cancel = action(l10n.connCancel, card.stop, named: true);
    switch (card.question) {
      case TunnelQuestion.none:
        return null;
      case TunnelQuestion.password:
        void login() =>
            card.submitPassword(_password.text, remember: _remember);
        return LgTunnelQuestion.password(
          title: l10n.connEnterPassword,
          password: LgExitPasswordArea(
            controller: _password,
            focusNode: _passwordFocus,
            semanticLabel: l10n.connPassword,
            placeholder: l10n.connPassword,
            showLabel: l10n.connShowPassword,
            hideLabel: l10n.connHidePassword,
            rememberLabel: l10n.connRememberPassword,
            remember: _remember,
            onRememberChanged: (v) => setState(() => _remember = v),
            onSubmitted: (_) => login(),
            errorText: card.wrongInput ? l10n.connWrongPassword : null,
          ),
          confirm: action(
            l10n.connConnect,
            _password.text.trim().isEmpty ? null : login,
            kind: LgButtonKind.primary,
          ),
          cancel: cancel,
        );
      case TunnelQuestion.twoFactor:
        void verify() => card.submit2fa(_code.text, trust: _trust);
        final trusted = card.trustedDevicesEnabled;
        return LgTunnelQuestion.code(
          title: l10n.exitEnterCode,
          code: LgExitCodeArea(
            controller: _code,
            focusNode: _codeFocus,
            semanticLabel: l10n.connCode,
            trustLabel: trusted ? l10n.connTrustThisDevice : null,
            trust: trusted ? _trust : null,
            onTrustChanged: (v) => setState(() => _trust = v),
            errorText: card.wrongInput ? l10n.connWrong2fa : null,
            onCompleted: (_) => verify(),
          ),
          confirm: action(l10n.connVerify, verify, kind: LgButtonKind.primary),
          cancel: cancel,
        );
      case TunnelQuestion.verifying:
        return LgTunnelQuestion.busy(text: l10n.connVerifying, cancel: cancel);
      case TunnelQuestion.waitAccept:
        return LgTunnelQuestion.busy(
          text: l10n.connWaitingAccept,
          elapsed: l10n.exitWaited(_waited()),
          cancel: cancel,
        );
      case TunnelQuestion.insecure:
        // "断开" first and the default, as the other questions' main button (13 §1.3 block B).
        return LgTunnelQuestion.insecure(
          title: l10n.tunnelInsecureTitle,
          message: l10n.connInsecure,
          confirm: LgExitAction(
            label: l10n.connDisconnect,
            kind: LgButtonKind.primary,
            autofocus: true,
            onPressed: () => card.answerInsecure(proceed: false),
          ),
          cancel: LgExitAction(
            label: l10n.connContinue,
            kind: LgButtonKind.secondary,
            onPressed: () => card.answerInsecure(proceed: true),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final card = _card;
    final name = tunnelCardName(card);
    final rdp = card.kind == TunnelKind.rdp;
    final kindName = rdp ? 'RDP' : l10n.tunnelKindTcp;

    // With several cards on the page, a screen reader tells their buttons apart by the name.
    LgExitAction action(
      String label,
      VoidCallback? onPressed, {
      LgButtonKind kind = LgButtonKind.secondary,
      bool named = false,
    }) => LgExitAction(
      label: label,
      onPressed: onPressed,
      kind: kind,
      semanticLabel: named ? l10n.exitActionFor(label, name) : null,
    );
    final stop = LgExitAction(
      label: l10n.exitStop,
      onPressed: card.stop,
      kind: LgButtonKind.secondary,
      icon: LgIcons.square,
      semanticLabel: l10n.tunnelStopLabel(kindName, name),
    );
    final remove = LgExitAction(
      label: l10n.exitRemove,
      onPressed: card.stop,
      kind: LgButtonKind.secondary,
      icon: LgIcons.trash,
      semanticLabel: l10n.tunnelRemoveLabel(kindName, name),
    );
    LgExitAction retryCard(VoidCallback onPressed) => LgExitAction(
      label: l10n.connRetry,
      onPressed: onPressed,
      kind: LgButtonKind.primary,
      icon: LgIcons.refresh,
      semanticLabel: l10n.exitActionFor(l10n.connRetry, name),
    );

    LgTunnelCard tunnelCard({
      LgTunnelQuestion? question,
      LgExitStatus? status,
      LgForwardList? forwards,
      String? emptyText,
      LgForwardAddRow? addRow,
      List<LgExitNotice> notices = const [],
      List<LgExitAction> leading = const [],
      List<LgExitAction> actions = const [],
    }) => LgTunnelCard(
      name: name,
      id: formatPeerId(card.id),
      platform: lgPlatformOf(card.platform),
      kindMark: LgTunnelKindMark(
        icon: rdp ? LgIcons.rdp : LgIcons.forward,
        label: rdp ? l10n.tunnelKindRdp(card.rdpPort) : l10n.tunnelKindTcp,
      ),
      semanticLabel: l10n.tunnelCardLabel(name, kindName),
      question: question,
      status: status,
      forwards: forwards,
      emptyText: emptyText,
      addRow: addRow,
      notices: notices,
      leadingActions: leading,
      actions: actions,
    );

    // Not added: the exit card of the device holds its port forward session (R3-Q4), or Rust
    // refused the ID.
    final addError = card.addError;
    if (addError != null) {
      final reason = switch (addError.code) {
        'already' when !rdp && appCore.exitNodes.cardOf(card.id) != null =>
          l10n.tunnelReasonExitRunning,
        'invalid_id' => l10n.exitBadId,
        'other' when addError.text.isNotEmpty => _firstSentence(addError.text),
        _ => null,
      };
      return tunnelCard(
        status: LgExitStatus(
          LgExitStatusKind.error,
          reason == null ? l10n.exitStoppedPlain : l10n.exitStoppedPrefix,
          reason: reason,
        ),
        actions: [
          if (addError.code != 'invalid_id') retryCard(_retryCard),
          remove,
        ],
      );
    }

    final question = _questionArea(l10n, action);
    if (rdp) {
      final row = card.rows.single;
      final settings = LgExitAction(
        label: l10n.tunnelRdpSettings,
        icon: LgIcons.gear,
        onPressed: () => showRdpSettings(widget.overlays, card.id, name: name),
      );
      final newRdp = LgExitAction(
        label: l10n.tunnelNewRdp,
        icon: LgIcons.rdp,
        onPressed: card.newRdp,
      );
      final view = tunnelStoppedView(l10n, row.reason, card.id);
      return tunnelCard(
        question: question,
        // The question says what the login waits for.
        status: question == null ? _rowStatus(l10n, row) : null,
        notices: _notices(l10n, row),
        leading: switch (row.state) {
          TunnelRowState.inUse ||
          TunnelRowState.interrupted => [newRdp, settings],
          TunnelRowState.stopped => [settings],
          _ => const [],
        },
        actions: switch (row.state) {
          _ when question != null => const [],
          TunnelRowState.connecting => [
            action(l10n.connCancel, card.stop, named: true),
          ],
          TunnelRowState.stopped || TunnelRowState.portBusy => [
            if (view.retry) retryCard(() => _retryRow(row)),
            remove,
          ],
          _ => [stop],
        },
      );
    }

    final adding = _adding || _noForwards;
    return tunnelCard(
      question: question,
      forwards: card.rows.isEmpty
          ? null
          : LgForwardList(
              localLabel: l10n.tunnelColLocal,
              targetLabel: l10n.tunnelColTarget,
              semanticLabel: l10n.tunnelForwardList,
              rows: [for (final row in card.rows) _row(l10n, row)],
            ),
      emptyText: l10n.tunnelNoForwards,
      addRow: adding ? _addRow(l10n) : null,
      leading: adding
          ? const []
          : [
              LgExitAction(
                label: l10n.tunnelAddForward,
                icon: LgIcons.plus,
                onPressed: _openAdd,
              ),
            ],
      actions: [card.running || question != null ? stop : remove],
    );
  }

  LgForwardRow _row(AppLocalizations l10n, TunnelRow row) {
    final port = row.localPort;
    final address = '127.0.0.1:$port';
    final notices = _notices(l10n, row);
    return LgForwardRow(
      localHost: '127.0.0.1:',
      localPort: '$port',
      targetHost: '${row.forward.host}:',
      targetPort: '${row.forward.remotePort}',
      status: _rowStatus(l10n, row),
      // Only while the listener is open (13 §1.3 block B).
      copyLabel: row.listening ? l10n.tunnelCopyAddress(port) : null,
      onCopy: row.listening ? () => copyWithToast(address) : null,
      actions: [
        if (row.state == TunnelRowState.interrupted)
          LgForwardAction(
            label: l10n.connReconnect,
            semanticLabel: l10n.tunnelReconnectLabel(port),
            onPressed: () => _retryRow(row),
          ),
        if (row.state == TunnelRowState.portBusy ||
            (row.state == TunnelRowState.stopped &&
                tunnelStoppedView(l10n, row.reason, _card.id).retry))
          LgForwardAction(
            label: l10n.connRetry,
            semanticLabel: l10n.tunnelRetryLabel(port),
            onPressed: () => _retryRow(row),
          ),
        LgForwardAction(
          label: l10n.tunnelDelete,
          kind: LgForwardButtonKind.neutral,
          semanticLabel: l10n.tunnelDeleteLabel(port),
          onPressed: () => _card.removeForward(row),
        ),
      ],
      notice: notices.isEmpty ? null : notices.first,
    );
  }

  LgForwardAddRow _addRow(AppLocalizations l10n) => LgForwardAddRow(
    localHost: '127.0.0.1:',
    localController: _local,
    localLabel: l10n.tunnelLocalPort,
    localPlaceholder: l10n.tunnelLocalPort,
    localFocusNode: _localFocus,
    hostController: _host,
    hostLabel: l10n.tunnelRemoteHost,
    hostPlaceholder: 'localhost',
    remoteController: _remote,
    remoteLabel: l10n.tunnelRemotePort,
    remotePlaceholder: l10n.tunnelRemotePort,
    addLabel: l10n.tunnelAdd,
    cancelLabel: l10n.homeCancel,
    // Both ports filled in; what they are is checked on "Add".
    onAdd: _local.text.trim().isEmpty || _remote.text.trim().isEmpty
        ? null
        : _add,
    onCancel: _closeAdd,
    errorText: switch (_addError) {
      TunnelAddForwardError.invalid => l10n.exitPortInvalid,
      TunnelAddForwardError.duplicate => l10n.tunnelPortDuplicate,
      TunnelAddForwardError.taken => l10n.exitPortTaken,
      null => null,
    },
    errorField: _errorField,
    semanticLabel: l10n.tunnelAddForward,
  );
}
