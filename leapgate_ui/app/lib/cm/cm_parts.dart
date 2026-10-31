import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';
import 'package:flutter_hbb/models/server_model.dart';

import '../icons/lg_icon.dart';
import '../l10n/app_localizations.dart';
import '../theme/lg_tokens.dart';

// Copy and small pieces the CM's full window and its strip share. The pieces are placeholders
// until the CM components (A-P3.html) replace them.

/// The session type line of the header (01 §3.3).
String cmKindLabel(AppLocalizations l10n, Client client) =>
    switch (cmSessionKind(client)) {
      CmSessionKind.remoteDesktop => l10n.cmTypeRemoteDesktop,
      CmSessionKind.fileTransfer => l10n.cmTypeFileTransfer,
      CmSessionKind.camera => l10n.cmTypeCamera,
      CmSessionKind.terminal => l10n.cmTypeTerminal,
      CmSessionKind.portForward => l10n.cmTypePortForward(client.portForward),
      CmSessionKind.exit => l10n.cmTypeExit,
    };

/// The strip's line for a single visitor (01 §3.3 "贴边小条").
String cmStripLabel(AppLocalizations l10n, Client client) =>
    switch (cmSessionKind(client)) {
      CmSessionKind.remoteDesktop => l10n.cmPillRemoteDesktop(client.name),
      CmSessionKind.fileTransfer => l10n.cmPillFileTransfer(client.name),
      CmSessionKind.camera => l10n.cmPillCamera(client.name),
      CmSessionKind.terminal => l10n.cmPillTerminal(client.name),
      CmSessionKind.portForward => l10n.cmPillPortForward(client.name),
      CmSessionKind.exit => l10n.cmPillExit(client.name),
    };

LgIcons cmKindIcon(Client client) => switch (cmSessionKind(client)) {
  CmSessionKind.remoteDesktop => LgIcons.monitor,
  CmSessionKind.fileTransfer => LgIcons.folder,
  CmSessionKind.camera => LgIcons.camera,
  CmSessionKind.terminal => LgIcons.terminal,
  CmSessionKind.portForward => LgIcons.forward,
  CmSessionKind.exit => LgIcons.exit,
};

String cmPermissionLabel(AppLocalizations l10n, CmPermission p) => switch (p) {
  CmPermission.keyboard => l10n.cmPermKeyboard,
  CmPermission.clipboard => l10n.cmPermClipboard,
  CmPermission.audio => l10n.cmPermAudio,
  CmPermission.file => l10n.cmPermFile,
  CmPermission.restart => l10n.cmPermRestart,
  CmPermission.recording => l10n.cmPermRecording,
  CmPermission.blockInput => l10n.cmPermBlockInput,
  CmPermission.privacyMode => l10n.cmPermPrivacyMode,
};

/// The connected time as `00:12:34`.
String cmDuration(int seconds) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
}

/// The visitor's avatar, or the first character of the name (upper case for Latin letters, as
/// the account area does, 01 §3.1 block D). Upstream `server_page.dart:590-618` and
/// `common.dart:4254-4284` (`buildAvatarWidget`).
class CmAvatar extends StatelessWidget {
  const CmAvatar({super.key, required this.client, required this.size});

  final Client client;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final identity = t.colors.identity[identityGroup(client.peerId)];
    final name = client.name.trim();
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: identity.tint,
        borderRadius: BorderRadius.circular(LgRadius.r10),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: LgTokens.style(
          size / 2,
          size / 2 + 4,
          FontWeight.w700,
        ).copyWith(color: identity.ink),
      ),
    );
    final image = _image(client.avatar.trim());
    if (image == null) return initial;
    return ClipRRect(
      borderRadius: BorderRadius.circular(LgRadius.r10),
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => initial,
      ),
    );
  }

  static ImageProvider? _image(String avatar) {
    if (avatar.startsWith('data:image/')) {
      final comma = avatar.indexOf(',');
      if (comma > 0) {
        try {
          return MemoryImage(base64Decode(avatar.substring(comma + 1)));
        } catch (_) {}
      }
    } else if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return NetworkImage(avatar);
    }
    return null;
  }
}

/// "无法远程执行此操作" where a click of the remote user was dropped (01 §3.3).
class CmBlockedHint extends StatelessWidget {
  const CmBlockedHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LgSpace.s2,
          vertical: LgSpace.s1,
        ),
        decoration: BoxDecoration(
          color: t.colors.warningBg,
          borderRadius: BorderRadius.circular(LgRadius.r6),
        ),
        child: Text(text, style: t.textS.copyWith(color: t.colors.text)),
      ),
    );
  }
}
