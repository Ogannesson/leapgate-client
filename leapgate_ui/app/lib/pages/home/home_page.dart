import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/remote_block.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_list_chrome.dart';
import '../../widgets/lg_pressable.dart';
import '../../widgets/lg_settings_rows.dart' show LgTextLink;
import '../../widgets/lg_status.dart';
import '../settings/dialogs/service.dart';
import '../settings/dialogs/unlock_pin.dart';
import '../settings/settings_flow.dart' show commitSettingsInput;
import '../settings/settings_page.dart';
import 'account/account.dart';
import 'devices_page.dart';
import 'exit/exit_page.dart';
import 'home_dialogs.dart';
import 'password_row.dart';

/// Pages of the home tab's navigation (01 §3.1 block C).
enum HomeSection { devices, exitNodes, settings }

/// Below this window height the left column tightens its vertical spacing so
/// that this device, the navigation and the account area fit without scrolling
/// at the 960×600 minimum (01 §2.1).
const double _shortWindow = 700;

const double _sideWidth = 240;

/// Side padding of a text button (`.btn.txt`), passed explicitly so the ID's "Copy" can be
/// moved back by exactly that much.
const double _textButtonPadding = 10;

/// Home tab: left column (this device, navigation) and the selected page.
/// M2a fills the password row and the devices page; the account area and the
/// other pages come with later blocks.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.status, required this.overlays});

  final LocalStatusModel status;

  /// The home tab's dialogs (scope null).
  final TabOverlays overlays;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  HomeSection _section = HomeSection.devices;
  final _connectBox = TextEditingController();
  final _connectBoxFocus = FocusNode();
  final _block = RemoteBlock();

  @override
  void initState() {
    super.initState();
    connectBoxFocusRequests.addListener(_onFocusRequest);
    exitPageRequests.addListener(_onExitRequest);
    settingsPageRequests.addListener(_onSettingsRequest);
    settingsUnlock.addListener(_onUnlock);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    connectBoxFocusRequests.removeListener(_onFocusRequest);
    exitPageRequests.removeListener(_onExitRequest);
    settingsPageRequests.removeListener(_onSettingsRequest);
    settingsUnlock.removeListener(_onUnlock);
    WidgetsBinding.instance.removeObserver(this);
    _connectBox.dispose();
    _connectBoxFocus.dispose();
    _block.dispose();
    super.dispose();
  }

  // As upstream `desktop_home_page.dart:882-886`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _block.check();
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
    _show(HomeSection.devices);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _connectBoxFocus.requestFocus(),
    );
  }

  /// "Use as exit node" ([useAsExit]): the exit page scrolls to the card itself.
  void _onExitRequest() => _show(HomeSection.exitNodes);

  /// Leaving the settings page hands over what was typed into it first: its number fields save
  /// when they lose the focus, which they don't once they are gone (`commitSettingsInput`).
  void _show(HomeSection section) {
    if (_section == HomeSection.settings && section != _section) {
      commitSettingsInput();
    }
    setState(() => _section = section);
  }

  /// A link to a settings section ([MainNavigation.showSettings]): the settings page takes the
  /// section and item itself.
  void _onSettingsRequest() => setState(() => _section = HomeSection.settings);

  /// The password row's "修改": the installed version unlocks first, with the settings page's
  /// lock, for this change only (01 P1 block A, R2-Q31). Already unlocked on the settings page,
  /// it stays so.
  Future<void> _changePassword(AppLocalizations l10n) async {
    final wasLocked = settingsUnlock.locked;
    final unlocked = await unlockSettings(widget.overlays, l10n);
    // UAC cancelled or failed says so under the row; a PIN dialog the user closed says nothing
    // (01 P1 block A).
    if (mounted && !unlocked && settingsUnlock.denied) {
      setState(() => _passwordDenied = true);
    }
    if (unlocked) await showPermanentPasswordDialog(widget.overlays, l10n);
    if (wasLocked) settingsUnlock.lock();
  }

  /// "修改" got no administrator permission the last time.
  bool _passwordDenied = false;

  /// The red line goes with the next unlock that goes through, here or on the settings page
  /// (01 P1 block A: "下次操作成功后消失"); the password can't be changed without one.
  void _onUnlock() {
    if (_passwordDenied && !settingsUnlock.locked) {
      setState(() => _passwordDenied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = switch (_section) {
      HomeSection.devices => l10n.navDevices,
      HomeSection.exitNodes => l10n.navExitNodes,
      HomeSection.settings => l10n.navSettings,
    };
    final page = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _sideWidth,
          child: _SideColumn(
            status: widget.status,
            section: _section,
            onSection: _show,
            onChangePassword: () => _changePassword(l10n),
            passwordError: _passwordDenied
                ? l10n.settingsUnlockPasswordNotChanged
                : null,
            overlays: widget.overlays,
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
                      status: widget.status,
                      overlays: widget.overlays,
                    ),
                  ),
                ],
                if (_section == HomeSection.exitNodes) ...[
                  // Right under the title (`LgExitPage`).
                  const SizedBox(height: LgSpace.s1),
                  Expanded(child: ExitPage(overlays: widget.overlays)),
                ],
                if (_section == HomeSection.settings) ...[
                  const SizedBox(height: LgSpace.s3),
                  Expanded(
                    child: SettingsPage(
                        overlays: widget.overlays, status: widget.status),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    // Upstream `buildRemoteBlock` (`flutter/lib/common.dart:3180-3205`) over the home tab only
    // (01 P1 block J): no clicks or keyboard focus while it covers the page.
    return MouseRegion(
      onEnter: (_) => _block.check(),
      onExit: (_) => _block.leave(),
      child: ListenableBuilder(
        listenable: _block,
        builder: (context, child) => LgBlockedOverlay(
          blocked: _block.blocked,
          message: l10n.homeLocked,
          child: child!,
        ),
        child: page,
      ),
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.status,
    required this.section,
    required this.onSection,
    required this.onChangePassword,
    required this.passwordError,
    required this.overlays,
  });

  final LocalStatusModel status;
  final HomeSection section;
  final ValueChanged<HomeSection> onSection;
  final VoidCallback? onChangePassword;
  final String? passwordError;
  final TabOverlays overlays;

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
        // The account area sits at the bottom (01 P1 block D); the rest of the column scrolls
        // when the window is shorter than its content. Not re-indented, to keep the lines above.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        Expanded(child: SingleChildScrollView(
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
                        // Double-click the ID or "Copy" under it (01 P1 block A): a text
                        // button with the icon, as in `p1-ben-both` (`.cpid`). It sits
                        // under the ID because the 240 column has no room beside it.
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onDoubleTap: () => copyWithToast(status.id),
                                child: _IdGroups(status.id),
                              ),
                              if (!short) const SizedBox(height: LgSpace.s2),
                              // Its text lines up with the ID: back by the text button's
                              // own side padding.
                              Transform.translate(
                                offset: const Offset(-_textButtonPadding, 0),
                                child: LgButton(
                                  label: l10n.homeCopy,
                                  semanticLabel: l10n.homeCopyId,
                                  icon: LgIcons.copy,
                                  kind: LgButtonKind.text,
                                  horizontalPadding: _textButtonPadding,
                                  onPressed: () => copyWithToast(status.id),
                                ),
                              ),
                            ],
                          ),
                    SizedBox(height: short ? LgSpace.s2 : LgSpace.s3),
                    PasswordRowView(
                      status: status,
                      onChange: onChangePassword,
                      error: passwordError,
                    ),
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
                    if (status.status == ServiceStatus.stopped)
                      _StartService(status: status, overlays: overlays)
                    // M6-4: with these the line keeps reading "正在连接服务器…" (02 §4.3 item 4)
                    // while no one can connect. A stopped service says so already.
                    else if (status.networkWarning case final warning?) ...[
                      const SizedBox(height: LgSpace.s1),
                      _NetworkWarning(
                        text: switch (warning) {
                          NetworkWarning.proxy => l10n.settingsServiceWarnProxy,
                          NetworkWarning.webSocket =>
                            l10n.settingsServiceWarnWebSocket,
                          NetworkWarning.udpDisabled =>
                            l10n.settingsServiceWarnUdp,
                        },
                        link: l10n.settingsSectionNetwork,
                      ),
                    ],
                    if (status.incoming.total > 0) ...[
                      const SizedBox(height: LgSpace.s2),
                      LgControlledNote(
                        text: status.incoming.controlled
                            ? l10n.homeRemoteControlled(status.incoming.total)
                            : l10n.homeIncomingSessions(status.incoming.total),
                        viewLabel: l10n.homeShowCm,
                        onView: status.showConnectionManager,
                      ),
                    ],
                    // The hint card (01 P1 block B): the system error, or installing or
                    // upgrading (M8).
                    if (status.systemError.isNotEmpty) ...[
                      SizedBox(height: short ? LgSpace.s2 : LgSpace.s3),
                      LgLocalNotice(tone: LgTone.error, text: status.systemError),
                    ] else if (status.installCard case final card?) ...[
                      SizedBox(height: short ? LgSpace.s2 : LgSpace.s3),
                      _InstallNotice(status: status, card: card),
                    ],
                  ],
                ),
              ),
              SizedBox(height: short ? LgSpace.s2 : LgSpace.s5),
              for (final (i, s) in HomeSection.values.indexed) ...[
                if (i > 0) const SizedBox(height: 2),
                if (s == HomeSection.exitNodes)
                  // The exit nodes running and whether one waits for the user (M5-8); no
                  // mark while the exit page shows.
                  ListenableBuilder(
                    listenable: appCore.backgroundListenable,
                    builder: (context, _) {
                      final count = appCore.backgroundCount;
                      final attention =
                          appCore.backgroundAttention && s != section;
                      return _NavItem(
                        icon: LgIcons.exit,
                        label: l10n.navExitNodes,
                        selected: s == section,
                        onPressed: () => onSection(s),
                        count: count,
                        attention: attention,
                        semanticLabel: count == 0
                            ? null
                            : attention
                                ? l10n.exitNavLabelAttention(count)
                                : l10n.exitNavLabel(count),
                      );
                    },
                  )
                else
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
        )),
        // 01 P1 block D (M4, coder A; `LEAPGATE.md` §10.11).
        accountArea(context, overlays),
          ],
        ),
      ),
    );
  }
}

/// "安装" on the portable version, "升级" over an older installed one (01 P1 block B, M8-1):
/// busy while the installer runs, the reason under the button when it failed. On success
/// this process exits.
class _InstallNotice extends StatelessWidget {
  const _InstallNotice({required this.status, required this.card});

  final LocalStatusModel status;
  final InstallCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final install = card == InstallCard.install;
    final failure =
        status.installFailure?.card == card ? status.installFailure : null;
    return LgLocalNotice(
      tone: LgTone.info,
      text: install ? l10n.homeInstallText : l10n.homeUpgradeText,
      actionLabel: switch ((install, status.installing)) {
        (true, false) => l10n.homeInstallButton,
        (true, true) => l10n.homeInstalling,
        (false, false) => l10n.homeUpgradeButton,
        (false, true) => l10n.homeUpgrading,
      },
      onAction: () => status.install(card),
      actionBusy: status.installing,
      actionError: switch (failure) {
        null => null,
        InstallFailure(uacDenied: true) =>
          install ? l10n.homeInstallUacDenied : l10n.homeUpgradeUacDenied,
        InstallFailure(text: '') =>
          install ? l10n.homeInstallFailed : l10n.homeUpgradeFailed,
        InstallFailure(:final text) => install
            ? l10n.homeInstallFailedText(text)
            : l10n.homeUpgradeFailedText(text),
      },
    );
  }
}

/// "启动服务" while the service is stopped: the settings page's way (02 §1.3.8, §3.3), with the
/// red line under it when administrator permission was not granted.
class _StartService extends StatefulWidget {
  const _StartService({required this.status, required this.overlays});

  final LocalStatusModel status;
  final TabOverlays overlays;

  @override
  State<_StartService> createState() => _StartServiceState();
}

class _StartServiceState extends State<_StartService> {
  bool _busy = false;
  String? _error;

  Future<void> _start(AppLocalizations l10n) async {
    setState(() => _busy = true);
    final result = await toggleService(
      widget.overlays,
      l10n,
      widget.status,
      stop: false,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LgButton(
          label: l10n.homeStartService,
          icon: appCore.options.isInstalled ? LgIcons.uac : null,
          kind: LgButtonKind.text,
          busy: _busy,
          onPressed: _busy ? null : () => _start(l10n),
        ),
        if (_error != null)
          Text(_error!, style: t.textS.copyWith(color: t.colors.error)),
      ],
    );
  }
}

/// The warning under the service line (M6-4, 01 P1 block A): why other devices can't connect,
/// and the link to 通用 › 网络和服务器.
class _NetworkWarning extends StatelessWidget {
  const _NetworkWarning({required this.text, required this.link});

  final String text;
  final String link;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: LgIcon(LgIcons.warn, size: 16, color: c.warning),
            ),
            const SizedBox(width: LgSpace.s2),
            Expanded(
              child: Text(text, style: t.textS.copyWith(color: c.text)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16 + LgSpace.s2, top: 2),
          child: LgTextLink(
            label: link,
            onPressed: () =>
                mainNavigation.showSettings(SettingsSectionId.network),
          ),
        ),
      ],
    );
  }
}

/// This device's ID in groups of three (01 §7.1) with the bar under each
/// group (`.id3` in A-P1.html).
class _IdGroups extends StatelessWidget {
  const _IdGroups(this.id);

  final String id;

  /// From the right, as everywhere else: a 10-digit ID is "1 078 877 965".
  static List<String> _groups(String id) => formatPeerId(id).split(' ');

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
      // One line, smaller if a 10-digit ID does not fit the column.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, group) in _groups(id).indexed) ...[
              if (i > 0) const SizedBox(width: 10),
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
          ],
        ),
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
    this.count = 0,
    this.attention = false,
    this.semanticLabel,
  });

  final LgIcons icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  // The exit nodes' number and mark (M5-8); placeholders until designer's nav item.
  final int count;
  final bool attention;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LgPressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: semanticLabel ?? label,
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
            // With a number, [semanticLabel] says it all.
            child: ExcludeSemantics(
              excluding: semanticLabel != null,
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
                // The mockup's `.navi` gap is 12; the number pulls 8 back (4 px from
                // the text), the reminder mark 6 on both sides (6 px each way). A
                // name that does not fit ends in "…" ahead of this.
                if (count > 0) ...[
                  SizedBox(width: attention ? 6 : LgSpace.s1),
                  LgCountMark(count, alert: attention, gap: 6),
                ],
              ],
            ),
            ),
          ),
        );
      },
    );
  }
}
