import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_pressable.dart';
import '../../widgets/lg_status.dart';
import 'devices_page.dart';
import 'password_row.dart';

/// Pages of the home tab's navigation (01 §3.1 block C).
enum HomeSection { devices, exitNodes, settings }

/// Below this window height the left column tightens its vertical spacing so
/// that this device, the navigation and the account area fit without scrolling
/// at the 960×600 minimum (01 §2.1).
const double _shortWindow = 700;

const double _sideWidth = 240;

/// Home tab: left column (this device, navigation) and the selected page.
/// M2a fills the password row and the devices page; the account area and the
/// other pages come with later blocks.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.status});

  final LocalStatusModel status;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeSection _section = HomeSection.devices;
  final _connectBox = TextEditingController();
  final _connectBoxFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    connectBoxFocusRequests.addListener(_onFocusRequest);
  }

  @override
  void dispose() {
    connectBoxFocusRequests.removeListener(_onFocusRequest);
    _connectBox.dispose();
    _connectBoxFocus.dispose();
    super.dispose();
  }

  /// "+" on the title bar and "修改 ID" on a connection panel ([MainNavigation.showHome]).
  void _onFocusRequest() {
    final text = connectBoxFocusRequests.text;
    if (text != null) {
      _connectBox.value = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      );
    }
    // The box exists only on the devices page; focus it once that is built.
    setState(() => _section = HomeSection.devices);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _connectBoxFocus.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = switch (_section) {
      HomeSection.devices => l10n.navDevices,
      HomeSection.exitNodes => l10n.navExitNodes,
      HomeSection.settings => l10n.navSettings,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _sideWidth,
          child: _SideColumn(
            status: widget.status,
            section: _section,
            onSection: (s) => setState(() => _section = s),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LgSpace.s2,
              LgSpace.s4,
              LgSpace.s6,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: LgTokens.style(
                      20,
                      28,
                      FontWeight.w700,
                    ).copyWith(color: LgTokens.of(context).colors.text),
                  ),
                ),
                if (_section == HomeSection.devices) ...[
                  const SizedBox(height: LgSpace.s3),
                  Expanded(
                    child: DevicesPage(
                      controller: _connectBox,
                      focusNode: _connectBoxFocus,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.status,
    required this.section,
    required this.onSection,
  });

  final LocalStatusModel status;
  final HomeSection section;
  final ValueChanged<HomeSection> onSection;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final l10n = AppLocalizations.of(context)!;
    final short = MediaQuery.sizeOf(context).height < _shortWindow;
    final label = t.textS.copyWith(color: c.text2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(LgSpace.s2, 0, LgSpace.s2, LgSpace.s2),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r20),
        ),
        clipBehavior: Clip.antiAlias,
        // The whole column scrolls when the window is shorter than its content.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(LgSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.thisDevice,
                style: label.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: short ? LgSpace.s1 : LgSpace.s3),
              Text(l10n.deviceId, style: label),
              ListenableBuilder(
                listenable: status,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    status.id.isEmpty
                        ? _IdGenerating(text: l10n.idGenerating)
                        : _IdGroups(status.id),
                    SizedBox(height: short ? LgSpace.s2 : LgSpace.s3),
                    PasswordRowView(status: status),
                    SizedBox(height: short ? LgSpace.s2 : LgSpace.s5),
                    DefaultTextStyle(
                      style: t.textM,
                      child: switch (status.status) {
                        ServiceStatus.ready => LgStatusText(
                          LgStatus.online,
                          l10n.serviceReady,
                          gap: LgSpace.s2, // `.stline`
                        ),
                        ServiceStatus.connecting => LgStatusText(
                          LgStatus.connecting,
                          l10n.serviceConnecting,
                          gap: LgSpace.s2, // `.stline`
                        ),
                        ServiceStatus.notReady => LgStatusText(
                          LgStatus.warning,
                          l10n.serviceNotReady,
                          gap: LgSpace.s2, // `.stline`
                        ),
                        ServiceStatus.stopped => LgStatusText(
                          LgStatus.error,
                          l10n.serviceStopped,
                          gap: LgSpace.s2, // `.stline`
                        ),
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: short ? LgSpace.s2 : LgSpace.s5),
              for (final (i, s) in HomeSection.values.indexed) ...[
                if (i > 0) const SizedBox(height: 2),
                _NavItem(
                  icon: switch (s) {
                    HomeSection.devices => LgIcons.monitor,
                    HomeSection.exitNodes => LgIcons.exit,
                    HomeSection.settings => LgIcons.gear,
                  },
                  label: switch (s) {
                    HomeSection.devices => l10n.navDevices,
                    HomeSection.exitNodes => l10n.navExitNodes,
                    HomeSection.settings => l10n.navSettings,
                  },
                  selected: s == section,
                  onPressed: () => onSection(s),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// This device's ID in groups of three (01 §7.1) with the bar under each
/// group (`.id3` in A-P1.html).
class _IdGroups extends StatelessWidget {
  const _IdGroups(this.id);

  final String id;

  static List<String> _groups(String id) => [
    for (var i = 0; i < id.length; i += 3)
      id.substring(i, i + 3 > id.length ? id.length : i + 3),
  ];

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final style = LgTokens.style(
      28,
      32,
      FontWeight.w700,
    ).copyWith(color: c.text);
    return Semantics(
      label: _groups(id).join(' '),
      excludeSemantics: true,
      child: Wrap(
        spacing: 10,
        runSpacing: LgSpace.s1,
        children: [
          for (final group in _groups(id))
            IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(group, style: style),
                  const SizedBox(height: 2),
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.bar,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// No ID yet (`.pwt.dim.idgen`).
class _IdGenerating extends StatelessWidget {
  const _IdGenerating({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s2),
      child: Row(
        children: [
          LgSpinner(icon: LgIcons.markSpin, size: 12, color: t.colors.text2),
          const SizedBox(width: LgSpace.s2),
          Flexible(
            child: Text(
              text,
              style: t.textN.copyWith(
                color: t.colors.text2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation item (`.navi`): 24 px icon, the selected one on the nav colour.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final LgIcons icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LgPressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: label,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final bg = selected ? c.nav : null;
        final fg = selected ? c.navFg : c.text;
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.nav,
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
            decoration: BoxDecoration(
              color: overlay == null
                  ? bg
                  : Color.alphaBlend(overlay, bg ?? Colors.transparent),
              borderRadius: radius,
            ),
            child: Row(
              children: [
                LgIcon(icon, size: 24, color: fg),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
