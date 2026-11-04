import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart' show isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/incoming_sessions.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../../widgets/lg_tooltip.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section that are not option keys.
const _rdp = 'share-rdp';
const _folder = 'recording-folder';

/// How long "预览" removes the wallpaper (upstream's Test button).
const _previewSeconds = 5;

/// The privacy mode methods by Rust's name key; the session menu uses the same words (02 §3.3).
String _privacyName(AppLocalizations l10n, String name) =>
    name == 'privacy_mode_impl_virtual_display_tip'
        ? l10n.menuPrivacyVirtual
        : l10n.menuPrivacyMag;

/// 传入连接 › 会话 (02 §1.3.5). Coder C.
SettingsSection sessionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.sessions,
      title: l10n.settingsSectionSessions,
      locked: true,
      items: () {
        final config = appCore.options.config;
        final privacy = privacyModeImpls();
        return [
          SettingsItem(kOptionAllowAutoDisconnect, l10n.settingsSessionsAutoDisconnect,
              description: l10n.settingsSessionsAutoDisconnectNote),
          if (config.getBool(kOptionAllowAutoDisconnect))
            SettingsItem(kOptionAutoDisconnectTimeout, l10n.settingsSessionsTimeout),
          SettingsItem(kOptionKeepAwakeDuringIncomingSessions,
              l10n.settingsSessionsKeepAwake,
              description: l10n.settingsSessionsKeepAwakeNote),
          if (wallpaperSupported == true)
            SettingsItem(kOptionAllowRemoveWallpaper, l10n.settingsSessionsWallpaper,
                description: l10n.settingsSessionsWallpaperNote),
          if (isWindows && appCore.options.isInstalled)
            SettingsItem(_rdp, l10n.settingsSessionsRdp,
                description: l10n.settingsSessionsRdpNote),
          SettingsItem(kOptionAudioInput, l10n.settingsSessionsAudio,
              description: l10n.settingsSessionsAudioNote),
          SettingsItem(kOptionEnableAbr, l10n.settingsSessionsAbr,
              description: l10n.settingsSessionsAbrNote),
          if (isWindows)
            SettingsItem(kOptionDirectxCapture, l10n.settingsSessionsDirectX,
                description: l10n.settingsSessionsDirectXNote),
          if (privacy.length >= 2)
            SettingsItem(kOptionPrivacyModeImpl, l10n.settingsSessionsPrivacy,
                options: [for (final (_, name) in privacy) _privacyName(l10n, name)]),
          SettingsItem(
              kOptionAllowAutoRecordIncoming, l10n.settingsSessionsAutoRecord),
          SettingsItem(_folder, l10n.settingsSessionsRecordDir),
        ];
      },
      build: (context, ctx) => _SessionsBody(ctx: ctx),
    );

class _SessionsBody extends StatefulWidget {
  const _SessionsBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_SessionsBody> createState() => _SessionsBodyState();
}

class _SessionsBodyState extends State<_SessionsBody> {
  SoundSources? _sources;
  bool _wallpaper = wallpaperSupported ?? false;
  bool _rdpBusy = false;

  /// Seconds left of "预览", 0 when none is running.
  int _previewLeft = 0;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _read();
    readWallpaperSupport().then((v) {
      if (mounted && v != _wallpaper) setState(() => _wallpaper = v);
    });
  }

  @override
  void didUpdateWidget(_SessionsBody old) {
    super.didUpdateWidget(old);
    // The page builds the section again when it reads the values again.
    _read();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final sources = await readSoundSources(appCore.options.config);
    if (mounted) setState(() => _sources = sources);
  }

  void _preview() {
    previewWallpaper(_previewSeconds);
    setState(() => _previewLeft = _previewSeconds);
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _previewLeft--);
      if (_previewLeft <= 0) timer.cancel();
    });
  }

  /// Asks for administrator permission itself, so it is not under the lock (02 §1.2.6).
  Future<void> _setRdp(AppLocalizations l10n, bool on) async {
    setState(() => _rdpBusy = true);
    final ok = await setShareRdp(on);
    if (!mounted) return;
    widget.ctx.setError(_rdp, ok ? null : l10n.settingsSessionsRdpDenied);
    setState(() => _rdpBusy = false);
  }

  Future<void> _saveMinutes(AppLocalizations l10n, String typed) async {
    final value = parseAutoDisconnectMinutes(typed);
    if (value == null) {
      widget.ctx.setError(
          kOptionAutoDisconnectTimeout, l10n.settingsSessionsTimeoutInvalid);
      return;
    }
    await widget.ctx.save(kOptionAutoDisconnectTimeout,
        () => appCore.options.config.set(kOptionAutoDisconnectTimeout, value));
  }

  Future<void> _changeFolder(RecordingFolder folder) async {
    final path = await FilePicker.platform.getDirectoryPath(
        initialDirectory: folder.exists ? folder.path : null);
    if (path == null) return;
    await widget.ctx
        .save(_folder, () => setRecordingFolder(appCore.options.local, path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final config = appCore.options.config;
    final open = !ctx.locked;
    final installed = appCore.options.isInstalled;

    Widget toggle(String key, String name, {String? note, bool indented = false}) =>
        LgSettingsRow.toggle(
          key: ctx.keyOf(key),
          name: name,
          description: note,
          indented: indented,
          value: config.getBool(key),
          onChanged:
              open ? (v) => ctx.save(key, () => config.setBool(key, v)) : null,
          marked: ctx.isMarked(key),
          error: ctx.errorOf(key),
        );

    final autoDisconnect = config.getBool(kOptionAllowAutoDisconnect);
    final minutesError = ctx.errorOf(kOptionAutoDisconnectTimeout);
    final wallpaperOn = config.getBool(kOptionAllowRemoveWallpaper);
    final sources = _sources;
    final privacy = privacyModeImpls();
    final service = serviceRecordsIncoming();
    final folder = readRecordingFolder(service: service);

    return SettingsFlow([
      LgSettingsSubtitle(l10n.settingsSessionsDuring),
      LgSettingsBlock(
        disabled: ctx.locked,
        children: [
          toggle(kOptionAllowAutoDisconnect, l10n.settingsSessionsAutoDisconnect,
              note: l10n.settingsSessionsAutoDisconnectNote),
          if (autoDisconnect)
            LgSettingsRow(
              key: ctx.keyOf(kOptionAutoDisconnectTimeout),
              name: l10n.settingsSessionsTimeout,
              indented: true,
              wide: true,
              marked: ctx.isMarked(kOptionAutoDisconnectTimeout),
              error: minutesError,
              errorAtEnd: true,
              control: LgSettingsNumberField(
                text: config.get(kOptionAutoDisconnectTimeout),
                unit: l10n.settingsSessionsMinutes,
                placeholder: '10',
                semanticLabel:
                    '${l10n.settingsSessionsTimeout} ${l10n.settingsSessionsMinutes}',
                errorText: minutesError,
                enabled: open,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (typed) => _saveMinutes(l10n, typed),
                onReverted: () =>
                    ctx.setError(kOptionAutoDisconnectTimeout, null),
              ),
            ),
          toggle(kOptionKeepAwakeDuringIncomingSessions,
              l10n.settingsSessionsKeepAwake,
              note: l10n.settingsSessionsKeepAwakeNote),
          if (_wallpaper)
            LgSettingsRow(
              key: ctx.keyOf(kOptionAllowRemoveWallpaper),
              name: l10n.settingsSessionsWallpaper,
              description: l10n.settingsSessionsWallpaperNote,
              nameNamesControl: true,
              marked: ctx.isMarked(kOptionAllowRemoveWallpaper),
              error: ctx.errorOf(kOptionAllowRemoveWallpaper),
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (wallpaperOn) ...[
                    LgButton(
                      label: _previewLeft > 0
                          ? l10n.settingsSessionsPreviewing(_previewLeft)
                          : l10n.settingsSessionsPreview,
                      kind: LgButtonKind.secondary,
                      onPressed: open && _previewLeft == 0 ? _preview : null,
                    ),
                    const SizedBox(width: 12),
                  ],
                  LgSwitch(
                    value: wallpaperOn,
                    semanticLabel: l10n.settingsSessionsWallpaper,
                    onChanged: open
                        ? (v) => ctx.save(kOptionAllowRemoveWallpaper,
                            () => config.setBool(kOptionAllowRemoveWallpaper, v))
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
      // Outside the lock (02 §1.2.6): it asks for administrator permission each time.
      if (isWindows && installed)
        LgSettingsBlock(
          children: [
            LgSettingsRow(
              key: ctx.keyOf(_rdp),
              name: l10n.settingsSessionsRdp,
              description: l10n.settingsSessionsRdpNote,
              nameNamesControl: true,
              marked: ctx.isMarked(_rdp),
              error: ctx.errorOf(_rdp),
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LgIcon(LgIcons.uac, size: 20),
                  const SizedBox(width: 8),
                  LgSwitch(
                    value: shareRdp(),
                    semanticLabel: l10n.settingsSessionsRdp,
                    onChanged: _rdpBusy ? null : (v) => _setRdp(l10n, v),
                  ),
                ],
              ),
            ),
          ],
        ),
      LgSettingsSubtitle(l10n.settingsSessionsMedia),
      LgSettingsBlock(
        disabled: ctx.locked,
        children: [
          if (sources != null && !sources.isEmpty)
            LgSettingsRow(
              key: ctx.keyOf(kOptionAudioInput),
              name: l10n.settingsSessionsAudio,
              description: l10n.settingsSessionsAudioNote,
              wide: true,
              marked: ctx.isMarked(kOptionAudioInput),
              error: ctx.errorOf(kOptionAudioInput),
              control: SizedBox(
                width: 260,
                child: LgSelectField<String>(
                  dense: true,
                  semanticLabel: l10n.settingsSessionsAudio,
                  items: [
                    if (sources.loopback) LgSelectItem('', l10n.chatSystemSound),
                    for (final d in sources.devices) LgSelectItem(d, d),
                  ],
                  // '' is the default: "系统声音" where there is one.
                  value: sources.current.isEmpty && !sources.loopback
                      ? null
                      : sources.current,
                  onChanged: open
                      ? (v) => ctx.save(
                          kOptionAudioInput, () => config.set(kOptionAudioInput, v))
                      : null,
                ),
              ),
            ),
          toggle(kOptionEnableAbr, l10n.settingsSessionsAbr,
              note: l10n.settingsSessionsAbrNote),
          if (isWindows)
            toggle(kOptionDirectxCapture, l10n.settingsSessionsDirectX,
                note: l10n.settingsSessionsDirectXNote),
          if (privacy.length >= 2)
            LgSettingsRow(
              key: ctx.keyOf(kOptionPrivacyModeImpl),
              name: l10n.settingsSessionsPrivacy,
              wide: true,
              marked: ctx.isMarked(kOptionPrivacyModeImpl),
              error: ctx.errorOf(kOptionPrivacyModeImpl),
              control: LgSegmented<String>(
                segments: [
                  for (final (key, name) in privacy)
                    LgSegment(key, _privacyName(l10n, name)),
                ],
                selected: privacyModeImpl(config),
                onChanged: open
                    ? (v) => ctx.save(kOptionPrivacyModeImpl,
                        () => config.set(kOptionPrivacyModeImpl, v))
                    : null,
              ),
            ),
        ],
      ),
      LgSettingsSubtitle(l10n.settingsSessionsRecording),
      LgSettingsBlock(
        disabled: ctx.locked,
        children: [
          toggle(kOptionAllowAutoRecordIncoming, l10n.settingsSessionsAutoRecord),
          LgSettingsRow(
            key: ctx.keyOf(_folder),
            name: l10n.settingsSessionsRecordDir,
            description: service
                ? l10n.settingsSessionsRecordDirService
                : l10n.settingsSessionsRecordDirShared,
            body: Text(folder.path),
            wide: true,
            marked: ctx.isMarked(_folder),
            error: ctx.errorOf(_folder),
            control:
                _folderActions(l10n, folder, open: open, changeable: !service),
          ),
        ],
      ),
    ]);
  }

  Widget _folderActions(AppLocalizations l10n, RecordingFolder folder,
      {required bool open, required bool changeable}) {
    final actions = LgSettingsValueActions(
      actions: [
        LgSettingsAction(
          label: l10n.settingsSessionsOpen,
          semanticLabel: l10n.settingsSessionsOpenLabel,
          onPressed: open && folder.exists ? () => openFolder(folder.path) : null,
        ),
        if (changeable)
          LgSettingsAction(
            label: l10n.settingsSessionsChange,
            semanticLabel: l10n.settingsSessionsChangeLabel,
            onPressed: open ? () => _changeFolder(folder) : null,
          ),
      ],
    );
    return folder.exists
        ? actions
        : LgTooltip(message: l10n.settingsSessionsFolderMissing, child: actions);
  }
}
