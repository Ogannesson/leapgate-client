import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';
import 'package:flutter_hbb/models/server_model.dart';

import '../l10n/app_localizations.dart';
import '../widgets/lg_cm_pill.dart';
import '../widgets/lg_cm_tabs.dart';

// Copy and values the CM's full window and its strip share.

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

LgCmKind cmTabKind(Client client) => switch (cmSessionKind(client)) {
  CmSessionKind.remoteDesktop => LgCmKind.remote,
  CmSessionKind.fileTransfer => LgCmKind.file,
  CmSessionKind.camera => LgCmKind.camera,
  CmSessionKind.terminal => LgCmKind.terminal,
  CmSessionKind.portForward => LgCmKind.port,
  CmSessionKind.exit => LgCmKind.exit,
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

/// The identity colour group of the visitor's device (01 §2.4).
int cmIdentity(Client client) => identityGroup(client.peerId);

/// The letter of the avatar: the first character of the name (the components put Latin letters
/// in upper case, as the account area does, 01 §3.1 block D).
String cmLetter(Client client) {
  final name = client.name.trim();
  return name.isEmpty ? '?' : name.characters.first;
}

LgCmPillPerson cmPillPerson(Client client) =>
    LgCmPillPerson(letter: cmLetter(client), identity: cmIdentity(client));

/// The visitor's picture, when the account has one (upstream `common.dart:4254-4284`,
/// `buildAvatarWidget`).
ImageProvider? cmAvatarImage(Client client) {
  final avatar = client.avatar.trim();
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
