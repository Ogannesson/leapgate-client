// The small dialogs the toolbar menus open (01 §4.4), over this session's tab only. Each does
// what upstream's does: `flutter/lib/common/widgets/dialog.dart` (`showRequestElevationDialog`
// :1160-1328, `showSetOSPassword` :1434-1513, `showAuditDialog` :1561-1588,
// `showConfirmSwitchSidesDialog` :1807-1826), `common/widgets/toolbar.dart:281-445` (Wayland
// keyboard), `desktop/widgets/kb_layout_type_chooser.dart:203-226` and the custom resolution
// of `desktop/widgets/remote_toolbar.dart:2463-2504`. Upstream's "Why this happens" link to
// its issue tracker is left out (01 §5.5).

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_text_field.dart';

const kKbLayoutIso = 'ISO';
const kKbLayoutNotIso = 'Not ISO';

/// The dialog layer of [ffi]'s tab; Escape closes it like "Cancel".
Future<T?> _show<T>(
  TabOverlays overlays,
  FFI ffi,
  Widget Function(void Function(T? result) close) dialog,
) => overlays.show<T>(
  ffi.id,
  (context, close) =>
      LgDialogScrim(onEscape: () => close(null), child: dialog(close)),
);

/// Width and height for a virtual display; null when cancelled.
Future<(int, int)?> showCustomResolutionDialog(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n, {
  int? width,
  int? height,
}) => _show<(int, int)>(
  overlays,
  ffi,
  (close) =>
      _CustomResolution(l10n: l10n, width: width, height: height, close: close),
);

class _CustomResolution extends StatefulWidget {
  const _CustomResolution({
    required this.l10n,
    this.width,
    this.height,
    required this.close,
  });

  final AppLocalizations l10n;
  final int? width;
  final int? height;
  final void Function((int, int)?) close;

  @override
  State<_CustomResolution> createState() => _CustomResolutionState();
}

class _CustomResolutionState extends State<_CustomResolution> {
  late final _w = TextEditingController(text: widget.width?.toString() ?? '');
  late final _h = TextEditingController(text: widget.height?.toString() ?? '');
  bool _invalid = false;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  /// Digits only, at most 4 (upstream's input formatters, `remote_toolbar.dart:2496-2500`).
  static int? _parse(String text) {
    final t = text.trim();
    return RegExp(r'^\d{1,4}$').hasMatch(t) ? int.parse(t) : null;
  }

  void _apply() {
    final w = _parse(_w.text);
    final h = _parse(_h.text);
    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(() => _invalid = true);
      return;
    }
    widget.close((w, h));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return LgConfirmDialog(
      title: l10n.menuDlgCustomResTitle,
      width: 360,
      actions: [
        LgDialogAction(
          label: l10n.connCancel,
          onPressed: () => widget.close(null),
        ),
        LgDialogAction(
          label: l10n.menuDlgApply,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _apply,
        ),
      ],
      children: [
        Row(
          children: [
            Expanded(
              child: LgTextField(
                controller: _w,
                autofocus: true,
                placeholder: l10n.menuDlgWidth,
                semanticLabel: l10n.menuDlgWidth,
                onSubmitted: (_) => _apply(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('×'),
            ),
            Expanded(
              child: LgTextField(
                controller: _h,
                placeholder: l10n.menuDlgHeight,
                semanticLabel: l10n.menuDlgHeight,
                onSubmitted: (_) => _apply(),
              ),
            ),
          ],
        ),
        if (_invalid) LgFieldError(l10n.menuDlgResInvalid),
      ],
    );
  }
}

/// ANSI or ISO, for a macOS peer (`kb_layout_type_chooser.dart:203-226`); saved on choosing.
Future<void> showKbLayoutDialog(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n,
) => _show<void>(overlays, ffi, (close) => _KbLayout(l10n: l10n, close: close));

class _KbLayout extends StatefulWidget {
  const _KbLayout({required this.l10n, required this.close});

  final AppLocalizations l10n;
  final void Function(void) close;

  @override
  State<_KbLayout> createState() => _KbLayoutState();
}

class _KbLayoutState extends State<_KbLayout> {
  String _type = bind.getLocalKbLayoutType();

  Future<void> _choose(String v) async {
    await bind.setLocalKbLayoutType(kbLayoutType: v);
    if (mounted) setState(() => _type = bind.getLocalKbLayoutType());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return LgConfirmDialog(
      title: l10n.menuDlgKbTitle,
      actions: [
        LgDialogAction(
          label: l10n.menuDlgClose,
          isDefault: true,
          onPressed: () => widget.close(null),
        ),
      ],
      children: [
        LgRadio<String>(
          value: kKbLayoutNotIso,
          groupValue: _type,
          onChanged: _choose,
          label: 'ANSI',
          description: l10n.menuDlgKbAnsi,
        ),
        LgRadio<String>(
          value: kKbLayoutIso,
          groupValue: _type,
          onChanged: _choose,
          label: 'ISO',
          description: l10n.menuDlgKbIso,
        ),
      ],
    );
  }
}

/// The saved OS password; with [login] it is also typed in on saving (`dialog.dart:1434-1513`).
Future<void> showOsPasswordDialog(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n, {
  required bool login,
}) async {
  final password = await ffi.options.get('os-password') ?? '';
  final autoLogin = (await ffi.options.get('auto-login') ?? '') != '';
  await _show<void>(
    overlays,
    ffi,
    (close) => _OsPassword(
      ffi: ffi,
      l10n: l10n,
      login: login,
      password: password,
      autoLogin: autoLogin,
      close: close,
    ),
  );
}

class _OsPassword extends StatefulWidget {
  const _OsPassword({
    required this.ffi,
    required this.l10n,
    required this.login,
    required this.password,
    required this.autoLogin,
    required this.close,
  });

  final FFI ffi;
  final AppLocalizations l10n;
  final bool login;
  final String password;
  final bool autoLogin;
  final void Function(void) close;

  @override
  State<_OsPassword> createState() => _OsPasswordState();
}

class _OsPasswordState extends State<_OsPassword> {
  late final _controller = TextEditingController(text: widget.password);
  late bool _autoLogin = widget.autoLogin;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final ffi = widget.ffi;
    final text = _controller.text.trim();
    ffi.options.set('os-password', text);
    ffi.options.set('auto-login', _autoLogin ? 'Y' : '');
    if (text != '' && widget.login) {
      bind.sessionInputOsPassword(sessionId: ffi.sessionId, value: text);
    }
    widget.close(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return LgConfirmDialog(
      title: l10n.menuDlgOsPasswordTitle,
      actions: [
        LgDialogAction(
          label: l10n.connCancel,
          onPressed: () => widget.close(null),
        ),
        LgDialogAction(
          label: widget.login ? l10n.menuDlgEnter : l10n.menuDlgSave,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _submit,
        ),
      ],
      children: [
        LgTextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          placeholder: l10n.menuDlgPassword,
          semanticLabel: l10n.menuDlgPassword,
          onSubmitted: (_) => _submit(),
        ),
        LgCheckbox(
          value: _autoLogin,
          onChanged: (v) => setState(() => _autoLogin = v),
          label: l10n.menuDlgAutoLogin,
        ),
        Text(l10n.menuDlgAutoLoginNote),
      ],
    );
  }
}

/// How to ask for elevation (01 P2 block E): the remote user confirms, or an administrator
/// account is sent. Also opened from the elevation notice's "请求提升权限".
Future<void> showRequestElevationDialog(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n,
) => _show<void>(
  overlays,
  ffi,
  (close) => _Elevation(ffi: ffi, l10n: l10n, close: close),
);

class _Elevation extends StatefulWidget {
  const _Elevation({
    required this.ffi,
    required this.l10n,
    required this.close,
  });

  final FFI ffi;
  final AppLocalizations l10n;
  final void Function(void) close;

  @override
  State<_Elevation> createState() => _ElevationState();
}

class _ElevationState extends State<_Elevation> {
  bool _logon = false;
  final _user = TextEditingController();
  final _password = TextEditingController();
  String? _userError;
  String? _passwordError;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final ffi = widget.ffi;
    final l10n = widget.l10n;
    if (_logon) {
      if (_user.text.isEmpty) {
        setState(() => _userError = l10n.menuDlgEmptyUsername);
        return;
      }
      if (_password.text.isEmpty) {
        setState(() => _passwordError = l10n.menuDlgEmptyPassword);
        return;
      }
      bind.sessionElevateWithLogon(
        sessionId: ffi.sessionId,
        username: _user.text,
        password: _password.text,
      );
    } else {
      bind.sessionElevateDirect(sessionId: ffi.sessionId);
    }
    widget.close(null);
    // Upstream then shows its wait dialog (`showWaitUacDialog`), as the `wait-uac` message does.
    ffi.notices.dismissTag('on-uac');
    ffi.notices.dismissTag('on-foreground-elevated');
    ffi.notices.add(
      SessionNotice(
        'wait_accept_uac_tip',
        args: const {'type': 'wait-uac', 'title': 'Wait'},
        tag: 'wait-uac',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    void choose(bool logon) => setState(() => _logon = logon);
    return LgConfirmDialog(
      title: l10n.menuRequestElevation,
      actions: [
        LgDialogAction(
          label: l10n.connCancel,
          onPressed: () => widget.close(null),
        ),
        LgDialogAction(
          label: l10n.menuDlgRequest,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _submit,
        ),
      ],
      children: [
        LgRadio<bool>(
          value: false,
          groupValue: _logon,
          onChanged: choose,
          label: l10n.menuDlgElevAsk,
          description: l10n.menuDlgElevAskNote,
        ),
        LgRadio<bool>(
          value: true,
          groupValue: _logon,
          onChanged: choose,
          label: l10n.menuDlgElevLogon,
        ),
        if (_logon) ...[
          Text(l10n.menuDlgElevNote),
          LgTextField(
            controller: _user,
            placeholder: l10n.menuDlgUsernameHint,
            semanticLabel: l10n.menuDlgUsername,
            errorText: _userError,
            onChanged: (_) => setState(() => _userError = null),
          ),
          LgTextField(
            controller: _password,
            obscureText: true,
            placeholder: l10n.menuDlgPassword,
            semanticLabel: l10n.menuDlgPassword,
            errorText: _passwordError,
            onChanged: (_) => setState(() => _passwordError = null),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ],
    );
  }
}

/// True when the user confirmed switching sides.
Future<bool> confirmSwitchSides(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n,
) async {
  final ok = await _show<bool>(
    overlays,
    ffi,
    (close) => LgConfirmDialog(
      title: l10n.menuDlgSwitchSidesTitle,
      body: l10n.menuDlgSwitchSidesBody,
      actions: [
        LgDialogAction(label: l10n.connCancel, onPressed: () => close(null)),
        LgDialogAction(
          label: l10n.menuDlgSwitch,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => close(true),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Whether to type on a Wayland peer, and whether to remember it (`toolbar.dart:281-445`);
/// null when cancelled.
Future<({bool remember})?> askWaylandKeyboard(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n,
) => _show<({bool remember})>(
  overlays,
  ffi,
  (close) => _Wayland(l10n: l10n, close: close),
);

class _Wayland extends StatefulWidget {
  const _Wayland({required this.l10n, required this.close});

  final AppLocalizations l10n;
  final void Function(({bool remember})?) close;

  @override
  State<_Wayland> createState() => _WaylandState();
}

class _WaylandState extends State<_Wayland> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return LgConfirmDialog(
      title: l10n.menuDlgWaylandTitle,
      body: l10n.menuDlgWaylandBody,
      actions: [
        LgDialogAction(
          label: l10n.connCancel,
          onPressed: () => widget.close(null),
        ),
        LgDialogAction(
          label: l10n.menuDlgAllow,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => widget.close((remember: _remember)),
        ),
      ],
      children: [
        LgCheckbox(
          value: _remember,
          onChanged: (v) => setState(() => _remember = v),
          label: l10n.menuDlgRemember,
        ),
      ],
    );
  }
}

/// A note to the server's audit record of this session (`dialog.dart:1561-1588`).
Future<void> showNoteDialog(
  TabOverlays overlays,
  FFI ffi,
  AppLocalizations l10n,
) async {
  final controller = TextEditingController(
    text: bind.sessionGetLastAuditNote(sessionId: ffi.sessionId),
  );
  final note = await _show<String>(
    overlays,
    ffi,
    (close) => LgConfirmDialog(
      title: l10n.menuAddNote,
      actions: [
        LgDialogAction(label: l10n.connCancel, onPressed: () => close(null)),
        LgDialogAction(
          label: l10n.menuDlgSubmit,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => close(controller.text),
        ),
      ],
      children: [
        LgTextField(
          controller: controller,
          autofocus: true,
          placeholder: l10n.menuDlgNoteHint,
          semanticLabel: l10n.menuDlgNoteHint,
          onSubmitted: close,
        ),
      ],
    ),
  );
  controller.dispose();
  if (note != null) bind.sessionSendNote(sessionId: ffi.sessionId, note: note);
}
