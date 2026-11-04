import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_settings_layout.dart';
import '../../widgets/lg_settings_search.dart';
import 'dialogs/unlock_pin.dart';
import 'settings_flow.dart';
import 'settings_registry.dart';
import 'settings_section_state.dart';
import 'settings_status.dart';

/// The section shown last in this run; the first opening shows 访问与密码 (02 §1.2.1).
SettingsSectionId _remembered = SettingsSectionId.access;

/// Locked sections whose items are not all under the lock: they grey the rest themselves, and
/// the page leaves them usable (服务与 ID: starting and stopping the service asks for
/// administrator permission itself, 02 §1.2.6).
const _dimsItself = {SettingsSectionId.service};

/// One search result: where the item is and how to show it (02 §1.2.4).
class _Hit {
  const _Hit(this.section, this.item, this.detail);

  final SettingsSection section;

  /// Null when the section's own title matched: the hit opens the section and marks nothing.
  final SettingsItem? item;

  /// The description, or the option names when one of those matched.
  final String detail;
}

/// Sections whose title, and items whose name, description or option names contain [query],
/// ignoring case; in the sections' order, which is the groups' order, each section before its
/// items.
List<_Hit> _search(List<SettingsSection> sections, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  bool has(String s) => s.toLowerCase().contains(q);
  return [
    for (final section in sections) ...[
      if (has(section.title)) _Hit(section, null, ''),
      for (final item in section.items())
        if (has(item.name) || has(item.description) || item.options.any(has))
          _Hit(
            section,
            item,
            item.options.any(has) ? item.options.join(' · ') : item.description,
          ),
    ],
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
    _onRequest();
  }

  @override
  void dispose() {
    settingsPageRequests.removeListener(_onRequest);
    settingsUnlock.removeListener(_onLock);
    WidgetsBinding.instance.removeObserver(this);
    // Another page of the home tab (02 §1.2.6); the main window locks on the rest. What was
    // typed is handed over before the home page switches (`commitSettingsInput`): here the
    // fields are gone already.
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

  /// Opens [section], read afresh; with [item], scrolls to it and marks it (02 §1.2.4). What
  /// was typed into the section on screen is handed over first.
  void _open(SettingsSectionId section, {String? item}) {
    commitSettingsInput();
    _query.clear();
    _hit = 0;
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

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _hit = (_hit + by).clamp(0, count - 1));
  }

  void _openHit(_Hit hit) => _open(hit.section.id, item: hit.item?.id);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sections = settingsSections(l10n).where((s) => s.visible()).toList();
    final section = sections.firstWhere(
      (s) => s.id == _current,
      orElse: () => sections.first,
    );
    final hits = _search(sections, _query.text);
    final locked = settingsUnlock.locked;
    return SettingsStatus(
      status: widget.status,
      child: LgSettingsLayout(
        navigation: LgSettingsNav(
          semanticLabel: l10n.settingsSearchSections,
          search: LgSettingsSearchField(
            controller: _query,
            focusNode: _searchFocus,
            placeholder: l10n.settingsSearchPlaceholder,
            clearLabel: l10n.settingsSearchClear,
            onChanged: (_) => setState(() => _hit = 0),
            onMove: (by) => _move(by, hits.length),
            onSubmitted: (_) {
              if (hits.isNotEmpty) {
                _openHit(hits[_hit.clamp(0, hits.length - 1)]);
              }
            },
          ),
          children: [
            for (final group in SettingsGroup.values)
              if (sections.any((s) => s.id.group == group))
                LgSettingsNavGroup(
                  title: settingsGroupTitle(l10n, group),
                  items: [
                    for (final s in sections.where((s) => s.id.group == group))
                      LgSettingsNavItem(
                        label: s.title,
                        selected: s.id == section.id,
                        locked: s.locked && locked,
                        lockedLabel: l10n.settingsUnlockLockedMark,
                        onPressed: () => _open(s.id),
                      ),
                  ],
                ),
          ],
        ),
        content: _query.text.trim().isEmpty
            ? _content(l10n, section)
            : LgSettingsContent(
                children: [
                  LgSettingsSearchResults(
                    results: [
                      for (final h in hits)
                        if (h.item case final item?)
                          LgSettingsSearchResult(
                            path:
                                '${settingsGroupTitle(l10n, h.section.id.group)} › ${h.section.title}',
                            name: item.name,
                            description: h.detail.isEmpty ? null : h.detail,
                          )
                        else
                          // The section itself: its group above its name (the component has no
                          // row with the path alone).
                          LgSettingsSearchResult(
                            path: settingsGroupTitle(l10n, h.section.id.group),
                            name: h.section.title,
                          ),
                    ],
                    query: _query.text,
                    selectedIndex: hits.isEmpty
                        ? -1
                        : _hit.clamp(0, hits.length - 1),
                    onOpen: (i) => _openHit(hits[i]),
                    emptyText: l10n.settingsSearchNone,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _content(AppLocalizations l10n, SettingsSection section) {
    _lockable = section.locked;
    final locked = section.locked && settingsUnlock.locked;
    final state = _state ??= SettingsSectionState(
      overlays: widget.overlays,
      saveFailedText: l10n.settingsSaveFailed,
      locked: locked,
    );
    // The language may have changed since the section was opened.
    state.saveFailedText = l10n.settingsSaveFailed;
    return LgSettingsContent(
      controller: _scroll,
      title: section.title,
      locked: locked && !_dimsItself.contains(section.id),
      lockBar: locked
          ? LgSettingsLockBar(
              text: l10n.settingsUnlockLocked,
              unlockLabel: l10n.settingsUnlock,
              error: settingsUnlock.denied ? l10n.settingsUnlockDenied : null,
              onUnlock: () => unlockSettings(widget.overlays, l10n),
            )
          : null,
      children: [
        ListenableBuilder(
          listenable: state,
          builder: (context, _) => section.build(context, state),
        ),
      ],
    );
  }
}
