import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/settings/about.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';
import '../settings_status.dart';

/// Item ids of this section.
const kAboutItemVersion = 'version';
const kAboutItemBuildDate = 'build-date';
const kAboutItemFingerprint = 'fingerprint';
const kAboutItemId = 'id';
const kAboutItemLinks = 'links';

/// 通用 › 关于 (02 §1.5.5, R2-Q18). Coder D. The privacy statement and website links wait for
/// the brand decisions (01 §5.7); the slogan too.
SettingsSection aboutSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.about,
      title: l10n.settingsSectionAbout,
      items: () => [
        SettingsItem(kAboutItemVersion, l10n.settingsAboutVersion),
        SettingsItem(kAboutItemBuildDate, l10n.settingsAboutBuildDate),
        SettingsItem(kAboutItemFingerprint, l10n.settingsAboutFingerprint),
        SettingsItem(kAboutItemId, l10n.settingsAboutId),
        SettingsItem(kAboutItemLinks, l10n.settingsAboutLinks,
            options: [l10n.settingsAboutSource]),
      ],
      build: (context, ctx) => _About(ctx: ctx),
    );

class _About extends StatefulWidget {
  const _About({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  late final Future<AboutInfo> _info = readAbout();

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    appCore.toasts.show('Copied');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final id = SettingsStatus.of(context).id;
    return FutureBuilder(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        final fingerprint = info.fingerprint.trim();
        final year = DateTime.now().year;
        return SettingsFlow([
          LgSettingsAboutHeader(name: l10n.settingsAboutName),
          LgSettingsBlock(children: [
            LgSettingsInfoRow(
              key: ctx.keyOf(kAboutItemVersion),
              label: l10n.settingsAboutVersion,
              value: info.version,
              caption: l10n.settingsAboutBasedOn(info.upstreamVersion),
              copyLabel: l10n.homeCopy,
              copySemanticLabel: l10n.settingsAboutCopyVersion,
              onCopy: () => _copy(info.version),
              marked: ctx.isMarked(kAboutItemVersion),
            ),
            LgSettingsInfoRow(
              key: ctx.keyOf(kAboutItemBuildDate),
              label: l10n.settingsAboutBuildDate,
              value: info.buildDate,
              marked: ctx.isMarked(kAboutItemBuildDate),
            ),
            LgSettingsInfoRow(
              key: ctx.keyOf(kAboutItemFingerprint),
              label: l10n.settingsAboutFingerprint,
              value: fingerprint.isEmpty
                  ? l10n.settingsAboutUnavailable
                  : fingerprintLines(fingerprint),
              mono: fingerprint.isNotEmpty,
              copyLabel: l10n.homeCopy,
              copySemanticLabel: l10n.settingsAboutCopyFingerprint,
              onCopy: fingerprint.isEmpty ? null : () => _copy(fingerprint),
              marked: ctx.isMarked(kAboutItemFingerprint),
            ),
            if (id.isNotEmpty)
              LgSettingsInfoRow(
                key: ctx.keyOf(kAboutItemId),
                label: l10n.settingsAboutId,
                value: formatPeerId(id),
                copyLabel: l10n.homeCopy,
                copySemanticLabel: l10n.settingsAboutCopyId,
                onCopy: () => _copy(id),
                marked: ctx.isMarked(kAboutItemId),
              ),
            LgSettingsInfoRow(
              key: ctx.keyOf(kAboutItemLinks),
              label: l10n.settingsAboutLinks,
              marked: ctx.isMarked(kAboutItemLinks),
              child: Align(
                alignment: Alignment.centerLeft,
                child: LgTextLink(
                  label: l10n.settingsAboutSource,
                  onPressed: () => openUrl(kLeapgateSourceUrl),
                ),
              ),
            ),
          ]),
          // Upstream's copyright line as it is, with the license of a configured build
          // (DSP:2618-2637).
          LgSettingsFootnote([
            'Copyright © $year Purslane Tech Pte. Ltd.',
            if (info.license.isNotEmpty) info.license,
          ].join('\n')),
        ]);
      },
    );
  }
}
