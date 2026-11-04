import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_pressable.dart';
import '../../widgets/lg_text_field.dart';
import 'dialogs/unlock_pin.dart';
import 'settings_parts.dart';
import 'settings_registry.dart';
import 'settings_section_state.dart';

/// The section shown last in this run; the first opening shows 访问与密码 (02 §1.2.1).
SettingsSectionId _remembered = SettingsSectionId.access;

/// The navigation column's width (02 §1.2.2: about 180).
const double _navWidth = 180;

/// The section content's widest (02 §1.2.2: about 640).
const double _contentWidth = 640;

/// One search result: where the item is and how to show it (02 §1.2.4).
class _Hit {
  const _Hit(this.section, this.item, this.detail);

  final SettingsSection section;
  final SettingsItem item;

  /// The description, or the option names when one of those matched.
  final String detail;
}

/// Items of the [sections] whose name, description or option names contain [query], ignoring
/// case; in the sections' order, which is the groups' order.
List<_Hit> _search(List<SettingsSection> sections, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  bool has(String s) => s.toLowerCase().contains(q);
  return [
    for (final section in sections)
      for (final item in section.items())
        if (has(item.name) || has(item.description) || item.options.any(has))
          _Hit(
            section,
            item,
            item.options.any(has) ? item.options.join(' · ') : item.description,
          ),
  ];
}

/// The settings page of the home tab (02 §1.2): the section navigation with the search box, and
/// the section, its lock bar on the installed version, or the search results.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.overlays, required this.status});

  final TabOverlays overlays;
  final LocalStatusModel status;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  SettingsSectionId _current = _remembered;

  /// The shown section's context; a new one for each section opened (keys, marks and red lines
  /// belong to one section).
  SettingsSectionState? _state;

  /// Whether the shown section is one the lock covers.
  bool _lockable = false;
  final _scroll = ScrollController();
  final _query = TextEditingController();
  final _searchFocus = FocusNode();

  /// The result the arrow keys are on.
  int _hit = 0;

  @override
  void initState() {
    super.initState();
    settingsPageRequests.addListener(_onRequest);
    settingsUnlock.addListener(_onLock);
    WidgetsBinding.instance.addObserver(this);
    _query.addListener(() => setState(() => _hit = 0));
    _onRequest();
  }

  @override
  void dispose() {
    settingsPageRequests.removeListener(_onRequest);
    settingsUnlock.removeListener(_onLock);
    WidgetsBinding.instance.removeObserver(this);
    // Another page of the home tab (02 §1.2.6); the main window locks on the rest.
    settingsUnlock.lock();
    _state?.dispose();
    _scroll.dispose();
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The page reads the values again when the window comes back (09 §4.2).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _onLock() {
    _state?.locked = _lockable && settingsUnlock.locked;
    setState(() {});
  }

  /// [MainNavigation.showSettings] and the home page's links.
  void _onRequest() {
    final request = settingsPageRequests.take();
    if (request == null) return;
    _open(request.section, item: request.item);
  }

  /// Opens [section], read afresh; with [item], scrolls to it and marks it (02 §1.2.4).
  void _open(SettingsSectionId section, {String? item}) {
    _query.clear();
    if (section != _current) {
      _state?.dispose();
      _state = null;
      _current = _remembered = section;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    setState(() {});
    if (item == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _state;
      if (!mounted || state == null || _current != section) return;
      final target = state.keyOf(item).currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .2,
          duration: const Duration(milliseconds: 200),
        );
      }
      state.mark(item);
    });
  }

  Future<void> _unlock(AppLocalizations l10n) async {
    await unlockSettings(widget.overlays, l10n);
  }

  KeyEventResult _onSearchKey(List<_Hit> hits, KeyEvent event) {
    if (!_searchFocus.hasPrimaryFocus ||
        event is KeyUpEvent ||
        _query.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowUp:
        if (hits.isEmpty) return KeyEventResult.handled;
        final by = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
        setState(() => _hit = (_hit + by).clamp(0, hits.length - 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (event is KeyDownEvent && hits.isNotEmpty) {
          final hit = hits[_hit.clamp(0, hits.length - 1)];
          _open(hit.section.id, item: hit.item.id);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (_query.text.isEmpty) return KeyEventResult.ignored;
        _query.clear();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sections = settingsSections(l10n).where((s) => s.visible()).toList();
    final section = sections.firstWhere(
      (s) => s.id == _current,
      orElse: () => sections.first,
    );
    final hits = _search(sections, _query.text);
    return SettingsStatus(
      status: widget.status,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _navWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: (_, event) => _onSearchKey(hits, event),
                  child: LgTextField(
                    controller: _query,
                    focusNode: _searchFocus,
                    placeholder: l10n.settingsSearchPlaceholder,
                    semanticLabel: l10n.settingsSearchPlaceholder,
                    dense: true,
                    leading: const LgIcon(LgIcons.search, size: 18),
                  ),
                ),
                const SizedBox(height: LgSpace.s3),
                Expanded(child: _nav(l10n, sections, section)),
              ],
            ),
          ),
          const SizedBox(width: LgSpace.s5),
          Expanded(
            child: _query.text.trim().isEmpty
                ? _content(l10n, section)
                : _results(l10n, hits),
          ),
        ],
      ),
    );
  }

  Widget _nav(
    AppLocalizations l10n,
    List<SettingsSection> sections,
    SettingsSection current,
  ) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final locked = settingsUnlock.locked;
    return ListView(
      children: [
        for (final group in SettingsGroup.values)
          if (sections.any((s) => s.id.group == group)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LgSpace.s3,
                LgSpace.s2,
                LgSpace.s3,
                LgSpace.s1,
              ),
              child: Text(
                settingsGroupTitle(l10n, group),
                style: t.textS.copyWith(
                  color: c.text2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final s in sections.where((s) => s.id.group == group))
              LgPressable(
                onPressed: () => _open(s.id),
                selected: s.id == current.id,
                semanticLabel: s.title,
                builder: (context, states) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LgSpace.s3,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: s.id == current.id ? c.nav : null,
                    borderRadius: BorderRadius.circular(LgRadius.r12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          style: t.text.copyWith(
                            color: s.id == current.id ? c.navFg : c.text,
                          ),
                        ),
                      ),
                      if (s.locked && locked)
                        LgIcon(LgIcons.lock, size: 14, color: c.text2),
                    ],
                  ),
                ),
              ),
          ],
      ],
    );
  }

  Widget _content(AppLocalizations l10n, SettingsSection section) {
    final t = LgTokens.of(context);
    final c = t.colors;
    _lockable = section.locked;
    final locked = section.locked && settingsUnlock.locked;
    final state = _state ??= SettingsSectionState(
      overlays: widget.overlays,
      saveFailedText: l10n.settingsSaveFailed,
      locked: locked,
    );
    return SingleChildScrollView(
      controller: _scroll,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  section.title,
                  style: LgTokens.style(
                    18,
                    26,
                    FontWeight.w700,
                  ).copyWith(color: c.text),
                ),
              ),
              const SizedBox(height: LgSpace.s3),
              if (locked) ...[
                Container(
                  padding: const EdgeInsets.all(LgSpace.s3),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(LgRadius.r12),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(l10n.settingsUnlockLocked)),
                      LgButton(
                        label: l10n.settingsUnlock,
                        icon: LgIcons.uac,
                        kind: LgButtonKind.primary,
                        onPressed: () => _unlock(l10n),
                      ),
                    ],
                  ),
                ),
                if (settingsUnlock.denied)
                  Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s1),
                    child: Text(
                      l10n.settingsUnlockDenied,
                      style: t.textS.copyWith(color: c.error),
                    ),
                  ),
                const SizedBox(height: LgSpace.s3),
              ],
              ListenableBuilder(
                listenable: state,
                builder: (context, _) => section.build(context, state),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(AppLocalizations l10n, List<_Hit> hits) {
    final t = LgTokens.of(context);
    final c = t.colors;
    if (hits.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: Text(
          l10n.settingsSearchNone,
          style: t.text.copyWith(color: c.text2),
        ),
      );
    }
    final current = _hit.clamp(0, hits.length - 1);
    return ListView(
      children: [
        for (final (i, hit) in hits.indexed)
          LgPressable(
            focusable: false,
            onPressed: () => _open(hit.section.id, item: hit.item.id),
            semanticLabel: hit.item.name,
            selected: i == current,
            builder: (context, states) => Container(
              padding: const EdgeInsets.all(LgSpace.s2),
              decoration: BoxDecoration(
                color: i == current || states.contains(WidgetState.hovered)
                    ? c.hover
                    : null,
                borderRadius: BorderRadius.circular(LgRadius.r12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${settingsGroupTitle(l10n, hit.section.id.group)} › ${hit.section.title}',
                    style: t.textS.copyWith(color: c.text2),
                  ),
                  Text(hit.item.name, style: t.text.copyWith(color: c.text)),
                  if (hit.detail.isNotEmpty)
                    Text(hit.detail, style: t.textS.copyWith(color: c.text2)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
