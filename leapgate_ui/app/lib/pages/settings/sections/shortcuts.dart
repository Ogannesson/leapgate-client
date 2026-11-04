import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/settings/shortcuts.dart';
import 'package:flutter_hbb/models/shortcut_model.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../../widgets/lg_shortcuts.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kShortcutItemEnable = 'shortcuts-enabled';
const kShortcutItemPassThrough = 'shortcuts-pass-through';
const kShortcutItemList = 'shortcuts-list';

/// The list's groups as the new toolbar menus have them (02 §1.4.6), each operation by the
/// name it has in its menu.
List<(String, List<(String, String)>)> _groups(AppLocalizations l10n) => [
      (l10n.toolbarMonitor, [
        (kShortcutActionSwitchDisplayNext, l10n.settingsShortcutNextMonitor),
        (kShortcutActionSwitchDisplayPrev, l10n.settingsShortcutPrevMonitor),
        (kShortcutActionSwitchDisplayAll, l10n.toolbarAllMonitors),
      ]),
      (l10n.toolbarDisplay, [
        (kShortcutActionViewModeOriginal, l10n.toolbarScaleOriginal),
        (kShortcutActionViewModeAdaptive, l10n.toolbarScaleAdaptive),
        (kShortcutActionViewModeCustom, l10n.menuCustomScale),
        (kShortcutActionImageQualityBest, l10n.toolbarQualityBest),
        (kShortcutActionImageQualityBalanced, l10n.toolbarQualityBalanced),
        (kShortcutActionImageQualityLow, l10n.toolbarQualityLow),
        for (final (id, name) in [
          (kShortcutActionCodecAuto, l10n.menuCodecAuto),
          (kShortcutActionCodecVp8, 'VP8'),
          (kShortcutActionCodecVp9, 'VP9'),
          (kShortcutActionCodecAv1, 'AV1'),
          (kShortcutActionCodecH264, 'H264'),
          (kShortcutActionCodecH265, 'H265'),
        ])
          (id, l10n.settingsShortcutCodec(name)),
        (kShortcutActionPlugOutAllVirtualDisplays, l10n.settingsShortcutPlugOutAll),
        (kShortcutActionToggleShowRemoteCursor, l10n.menuShowRemoteCursor),
        (kShortcutActionToggleFollowRemoteCursor, l10n.menuFollowRemoteCursor),
        (kShortcutActionToggleFollowRemoteWindow, l10n.menuFollowRemoteWindow),
        (kShortcutActionToggleZoomCursor, l10n.menuZoomCursor),
        (kShortcutActionToggleTrueColor, l10n.menuTrueColor),
        (kShortcutActionToggleQualityMonitor, l10n.routeShowQuality),
      ]),
      (l10n.toolbarInput, [
        for (final (id, name) in [
          (kShortcutActionKeyboardModeLegacy, l10n.menuKeyboardLegacy),
          (kShortcutActionKeyboardModeMap, l10n.menuKeyboardMap),
          (kShortcutActionKeyboardModeTranslate, l10n.menuKeyboardTranslate),
        ])
          (id, l10n.settingsShortcutKeyboardMode(name)),
        (kShortcutActionToggleViewOnly, l10n.menuViewOnly),
        (kShortcutActionToggleShowMyCursor, l10n.menuShowMyCursor),
        (kShortcutActionToggleSwapCtrlCmd, l10n.menuSwapCtrlCmd),
        (kShortcutActionToggleRelativeMouseMode, l10n.menuRelativeMouse),
        (kShortcutActionToggleReverseMouseWheel, l10n.menuReverseWheel),
        (kShortcutActionToggleSwapLeftRightMouse, l10n.menuSwapMouseButtons),
      ]),
      (l10n.toolbarActions, [
        (kShortcutActionSendCtrlAltDel, l10n.toolbarCtrlAltDel),
        (kShortcutActionInsertLock, l10n.menuLock),
        (kShortcutActionRestartRemote, l10n.toolbarRestart),
        (kShortcutActionToggleBlockInput, l10n.settingsShortcutBlockInput),
        (kShortcutActionSendClipboardKeystrokes, l10n.menuTypeClipboard),
        (kShortcutActionRefresh, l10n.menuRefresh),
        (kShortcutActionScreenshot, l10n.menuScreenshot),
        (kShortcutActionSwitchSides, l10n.menuSwitchSides),
        (kShortcutActionToggleRecording, l10n.settingsShortcutRecording),
      ]),
      (l10n.toolbarSession, [
        (kShortcutActionToggleMute, l10n.menuMute),
        (kShortcutActionToggleDisableClipboard, l10n.menuSyncClipboard),
        (kShortcutActionToggleEnableFileCopyPaste, l10n.menuFileCopyPaste),
        (kShortcutActionToggleLockAfterSessionEnd, l10n.menuLockAfterEnd),
        (kShortcutActionPrivacyMode1, l10n.settingsShortcutPrivacy(l10n.menuPrivacyMag)),
        (kShortcutActionPrivacyMode2,
            l10n.settingsShortcutPrivacy(l10n.menuPrivacyVirtual)),
      ]),
      (l10n.chatMenu, [
        (kShortcutActionToggleChat, l10n.chatText),
        (kShortcutActionToggleVoiceCall, l10n.chatVoiceCall),
      ]),
      (l10n.settingsShortcutGroupWindow, [
        (kShortcutActionPinToolbar, l10n.settingsShortcutPinToolbar),
        (kShortcutActionToggleToolbar, l10n.settingsShortcutToggleToolbar),
        (kShortcutActionToggleFullscreen, l10n.settingsShortcutFullscreen),
        (kShortcutActionCloseTab, l10n.closeTab),
        (kShortcutActionSwitchTabNext, l10n.settingsShortcutNextTab),
        (kShortcutActionSwitchTabPrev, l10n.settingsShortcutPrevTab),
      ]),
    ];

/// 传出连接 › 快捷键 (02 §1.4.6). Coder D. Upstream's switches, its separate list page and its
/// recording dialog in one section; the bindings are read and written by
/// `leapgate/settings/shortcuts.dart`. A session's menus read the bindings when they open.
SettingsSection shortcutsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.shortcuts,
      title: l10n.settingsSectionShortcuts,
      items: () => [
        SettingsItem(kShortcutItemEnable, l10n.settingsShortcutEnable),
        if (ShortcutModel.isEnabled()) ...[
          SettingsItem(kShortcutItemPassThrough, l10n.settingsShortcutPassThrough,
              description: l10n.settingsShortcutPassThroughNote),
          SettingsItem(kShortcutItemList, l10n.settingsShortcutList),
        ],
      ],
      build: (context, ctx) => _shortcuts(context, ctx),
    );

Future<bool> _done(Future<void> write) async {
  await write;
  return true;
}

Widget _shortcuts(BuildContext context, SettingsSectionContext ctx) {
  final l10n = AppLocalizations.of(context)!;
  final enabled = ShortcutModel.isEnabled();
  final passThrough = ShortcutModel.isPassThrough();
  final enable = LgSettingsBlock(children: [
    LgSettingsRow.toggle(
      key: ctx.keyOf(kShortcutItemEnable),
      name: l10n.settingsShortcutEnable,
      value: enabled,
      onChanged: (v) => ctx.save(
          kShortcutItemEnable, () => _done(ShortcutModel.setEnabled(v))),
      marked: ctx.isMarked(kShortcutItemEnable),
      error: ctx.errorOf(kShortcutItemEnable),
    ),
    if (enabled)
      LgSettingsRow.toggle(
        key: ctx.keyOf(kShortcutItemPassThrough),
        name: l10n.settingsShortcutPassThrough,
        description: l10n.settingsShortcutPassThroughNote,
        value: passThrough,
        indented: true,
        onChanged: (v) => ctx.save(kShortcutItemPassThrough,
            () => _done(ShortcutModel.setPassThrough(v))),
        marked: ctx.isMarked(kShortcutItemPassThrough),
        error: ctx.errorOf(kShortcutItemPassThrough),
      ),
  ]);
  if (!enabled) return SettingsFlow([enable]);

  final bindings = shortcutBindings();
  final shown = shortcutActionsForPlatform();
  final groups = _groups(l10n);
  String nameOf(String id) => groups
          .expand((g) => g.$2)
          .where((a) => a.$1 == id)
          .firstOrNull
          ?.$2 ??
      id;

  Future<void> edit(String id, String name) async {
    final result = await _record(ctx.overlays, l10n,
        recorder: ShortcutRecorder(actionId: id, bindings: bindings),
        action: name,
        nameOf: nameOf);
    if (result == null) return;
    await ctx.save(
        kShortcutItemList,
        () => _done(setShortcutBinding(id,
            binding: result.binding, clearActionId: result.replaces)));
  }

  Future<void> reset() async {
    final ok = await ctx.overlays.show<bool>(
          null,
          (context, close) => LgDialogScrim(
            onEscape: () => close(false),
            child: LgConfirmDialog(
              title: l10n.settingsShortcutResetTitle,
              body: l10n.settingsShortcutResetBody,
              actions: [
                LgDialogAction(
                    label: l10n.homeCancel, onPressed: () => close(false)),
                LgDialogAction(
                  label: l10n.settingsShortcutReset,
                  kind: LgButtonKind.primary,
                  isDefault: true,
                  onPressed: () => close(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok) {
      await ctx.save(kShortcutItemList, () => _done(resetShortcutBindings()));
    }
  }

  return SettingsFlow([
    enable,
    LgSettingsListHeader(
      key: ctx.keyOf(kShortcutItemList),
      title: l10n.settingsShortcutList,
      trailing: [LgButton(label: l10n.settingsShortcutReset, onPressed: reset)],
    ),
    if (passThrough) LgSettingsNote(l10n.settingsShortcutPaused),
    for (final (title, actions) in groups)
      if (actions.where((a) => shown.contains(a.$1)).toList()
          case final rows when rows.isNotEmpty)
        LgShortcutGroup(
          title: title,
          disabled: passThrough,
          rows: [
            for (final (id, name) in rows)
              _row(l10n, id, name, bindings,
                  onEdit: () => edit(id, name),
                  onClear: () => ctx.save(
                      kShortcutItemList, () => _done(setShortcutBinding(id)))),
          ],
        ),
  ]);
}

LgShortcutRow _row(AppLocalizations l10n, String id, String name,
    List<Map<String, dynamic>> bindings,
    {required VoidCallback onEdit, required VoidCallback onClear}) {
  final binding = bindings.where((b) => b['action'] == id).firstOrNull;
  return LgShortcutRow(
    action: name,
    keys: binding == null ? const [] : bindingKeyLabels(binding),
    unsetLabel: l10n.menuNotSet,
    editLabel: l10n.homeChange,
    editSemanticLabel: l10n.settingsShortcutEditLabel(name),
    onEdit: onEdit,
    clearLabel: l10n.settingsShortcutClear,
    clearSemanticLabel: l10n.settingsShortcutClearLabel(name),
    onClear: onClear,
  );
}

/// What the recording dialog gives back: the binding, and the action that loses it.
typedef _Recorded = ({Map<String, dynamic> binding, String? replaces});

Future<_Recorded?> _record(TabOverlays overlays, AppLocalizations l10n,
        {required ShortcutRecorder recorder,
        required String action,
        required String Function(String id) nameOf}) =>
    overlays.show<_Recorded>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(null),
        child: _RecordDialog(
            recorder: recorder, action: action, nameOf: nameOf, onClose: close),
      ),
    );

/// The recording dialog (02 §1.4.6): every key goes to the recording, Esc cancels.
class _RecordDialog extends StatefulWidget {
  const _RecordDialog(
      {required this.recorder,
      required this.action,
      required this.nameOf,
      required this.onClose});

  final ShortcutRecorder recorder;
  final String action;
  final String Function(String id) nameOf;
  final void Function(_Recorded? result) onClose;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose(null);
      } else {
        setState(() => widget.recorder.onKeyDown(event));
      }
    }
    return KeyEventResult.handled;
  }

  void _confirm() {
    final r = widget.recorder;
    final binding = r.binding;
    if (binding == null) return;
    widget.onClose((binding: binding, replaces: r.conflictActionId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = widget.recorder;
    final state = r.state;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LgShortcutRecordDialog(
        title: l10n.settingsShortcutRecordTitle(widget.action),
        state: switch (state) {
          ShortcutRecordState.waiting => LgShortcutRecordState.waiting,
          ShortcutRecordState.unsupported => LgShortcutRecordState.unsupported,
          ShortcutRecordState.missingModifier =>
            LgShortcutRecordState.missingModifier,
          ShortcutRecordState.conflict => LgShortcutRecordState.conflict,
          ShortcutRecordState.valid => LgShortcutRecordState.valid,
        },
        keys: r.keyLabels,
        statusText: switch (state) {
          ShortcutRecordState.waiting => l10n.settingsShortcutPressKeys,
          ShortcutRecordState.unsupported =>
            l10n.settingsShortcutUnsupported(r.unsupportedKey!),
          ShortcutRecordState.missingModifier =>
            l10n.settingsShortcutNeedModifier,
          ShortcutRecordState.conflict =>
            l10n.settingsShortcutConflict(widget.nameOf(r.conflictActionId!)),
          ShortcutRecordState.valid => null,
        },
        cancelLabel: l10n.homeCancel,
        confirmLabel: state == ShortcutRecordState.conflict
            ? l10n.settingsShortcutReplace
            : l10n.menuDlgSave,
        onCancel: () => widget.onClose(null),
        onConfirm: _confirm,
      ),
    );
  }
}
