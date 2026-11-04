import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart' show isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/outgoing.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kRenderItemTexture = kOptionTextureRender;
const kRenderItemD3d = kOptionD3DRender;

/// 传出连接 › 渲染 (02 §1.4.5). Coder D. Rust applies both to the open sessions as it saves them
/// (`src/flutter_ffi.rs` `main_set_local_option`).
SettingsSection renderingSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.rendering,
      title: l10n.settingsSectionRendering,
      items: () => [
        SettingsItem(kRenderItemTexture, l10n.settingsRenderTexture,
            description: l10n.settingsRenderTextureNote),
        if (isWindows)
          SettingsItem(kRenderItemD3d, l10n.settingsRenderD3d,
              description: l10n.settingsRenderD3dNote),
      ],
      build: (context, ctx) => _rendering(context, ctx),
    );

Widget _rendering(BuildContext context, SettingsSectionContext ctx) {
  final l10n = AppLocalizations.of(context)!;
  final local = appCore.options.local;
  return SettingsFlow([
    LgSettingsBlock(children: [
      LgSettingsRow.toggle(
        key: ctx.keyOf(kRenderItemTexture),
        name: l10n.settingsRenderTexture,
        description: l10n.settingsRenderTextureNote,
        value: textureRenderOn(),
        onChanged: (v) =>
            ctx.save(kRenderItemTexture, () => setTextureRender(local, v)),
        marked: ctx.isMarked(kRenderItemTexture),
        error: ctx.errorOf(kRenderItemTexture),
      ),
      if (isWindows)
        LgSettingsRow.toggle(
          key: ctx.keyOf(kRenderItemD3d),
          name: l10n.settingsRenderD3d,
          description: l10n.settingsRenderD3dNote,
          value: local.getBool(kOptionD3DRender),
          onChanged: (v) => ctx.save(
              kRenderItemD3d, () => local.setBool(kOptionD3DRender, v)),
          marked: ctx.isMarked(kRenderItemD3d),
          error: ctx.errorOf(kRenderItemD3d),
        ),
    ]),
  ]);
}
