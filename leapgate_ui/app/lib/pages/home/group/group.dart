import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/group.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_device_card.dart';
import '../../../widgets/lg_list_chrome.dart';
import '../../../widgets/lg_pressable.dart';
import '../../../widgets/lg_text_field.dart';
import '../account/account.dart';
import '../account_category.dart';

// The team devices category (01 P1 blocks F and H, M4; `LEAPGATE.md` §10.11), after upstream's
// `common/widgets/my_group.dart`, without the device groups. Placeholders until the designer's
// components (M4 integration); the states and texts are final.

/// The people list, the tools and the states of the team devices category.
AccountCategoryView groupCategory(BuildContext context, TabOverlays overlays) {
  final l10n = AppLocalizations.of(context)!;
  final account = appCore.account;
  final group = appCore.group;
  if (!account.loggedIn) {
    return AccountCategoryView(
      state: _StatePane(
        text: l10n.groupSignedOut,
        action: l10n.accountSignIn,
        onAction: () => showLoginDialog(overlays),
      ),
    );
  }
  // The check of the user failed: the others did not pull (upstream `netWorkErrorWidget`).
  final accountError = account.error;
  final retry = accountError != null ? account.refresh : group.pull;
  final tools = [
    LgListToolButton(
      icon: LgIcons.refresh,
      label: l10n.homeRefresh,
      onPressed: group.loading ? null : retry,
    ),
  ];
  final error = accountError ?? group.error;
  if (error != null &&
      (accountError != null || error.kind == ApiErrorKind.network)) {
    return AccountCategoryView(
      tools: tools,
      state: _StatePane(
        text: error.kind == ApiErrorKind.network
            ? l10n.groupNetworkError
            : l10n.groupLoadFailed(error.text),
        action: l10n.groupRetry,
        onAction: retry,
      ),
    );
  }
  return AccountCategoryView(
    tools: tools,
    header: error == null
        ? null
        : _ErrorBanner(
            text: l10n.groupLoadFailed(error.text),
            retry: l10n.groupRetry,
            onRetry: group.pull,
            closeLabel: l10n.close,
            onClose: group.clearError,
          ),
    side: group.users.isEmpty ? null : _People(group: group),
    state: !group.loaded || group.loading && group.peers.isEmpty
        ? _Loading(label: l10n.recentLoading)
        : group.shownPeers.isEmpty
        ? SingleChildScrollView(
            child: LgEmptyState(l10n.groupEmpty, icon: LgIcons.users),
          )
        : null,
  );
}

/// One sentence and a button in place of the list: signed out, network error.
class _StatePane extends StatelessWidget {
  const _StatePane({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LgSpace.s8),
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center, style: t.text),
            const SizedBox(height: LgSpace.s3),
            LgButton(label: action, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

/// The loading skeleton in the current view, as the other categories.
class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: PeerTabs(appCore.options).view == PeerView.cards
        ? LgDeviceCardGrid(
            semanticLabel: label,
            children: const [
              LgDeviceCardSkeleton(),
              LgDeviceCardSkeleton(),
              LgDeviceCardSkeleton(),
            ],
          )
        : LgDeviceSkeleton(semanticLabel: label),
  );
}

/// The server's error above the list, which keeps what it had (01 P1 block F).
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.text,
    required this.retry,
    required this.onRetry,
    required this.closeLabel,
    required this.onClose,
  });

  final String text;
  final String retry;
  final VoidCallback onRetry;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: LgSpace.s2),
    child: Row(
      children: [
        Expanded(
          child: LgBanner(tone: LgTone.error, text: text),
        ),
        LgButton(label: retry, kind: LgButtonKind.text, onPressed: onRetry),
        LgIconButton(icon: LgIcons.x, label: closeLabel, onPressed: onClose),
      ],
    ),
  );
}

/// The people (01 P1 block H): this user first with "我", a search, one person picked at a time.
class _People extends StatefulWidget {
  const _People({required this.group});

  final GroupModel group;

  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  late final _search = TextEditingController(text: widget.group.search);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final group = widget.group;
    final me = appCore.account.user?.name;
    final users = group.shownUsers;
    // Two people with the same display name show their user names (upstream `_buildUserItem`).
    final counts = <String, int>{};
    for (final u in users) {
      counts.update(u.displayNameOrName, (n) => n + 1, ifAbsent: () => 1);
    }
    return Padding(
      padding: const EdgeInsets.only(right: LgSpace.s3),
      child: SizedBox(
        width: 180,
        child: Semantics(
          container: true,
          label: l10n.groupPeople,
          child: Column(
            children: [
              LgTextField(
                controller: _search,
                dense: true,
                placeholder: l10n.groupSearch,
                semanticLabel: l10n.groupSearch,
                leading: LgIcon(LgIcons.search, size: 16, color: c.text2),
                onChanged: group.setSearch,
              ),
              const SizedBox(height: LgSpace.s2),
              Expanded(
                child: ListView(
                  children: [
                    for (final u in users)
                      _person(
                        t,
                        l10n,
                        name:
                            (counts[u.displayNameOrName] ?? 0) > 1 &&
                                u.displayName.trim().isNotEmpty
                            ? '${u.displayName} (@${u.name})'
                            : u.displayNameOrName,
                        isMe: u.name == me,
                        selected: group.selectedUser == u.name,
                        onPressed: () => group.selectUser(
                          group.selectedUser == u.name ? null : u.name,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _person(
    LgTokens t,
    AppLocalizations l10n, {
    required String name,
    required bool isMe,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final c = t.colors;
    return Row(
      children: [
        Expanded(
          child: LgPressable(
            onPressed: onPressed,
            selected: selected,
            semanticLabel: isMe ? '$name ${l10n.groupMe}' : name,
            builder: (context, states) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LgSpace.s2,
                vertical: LgSpace.s1,
              ),
              color: selected ? c.surface2 : null,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: c.surface2,
                    child: Text(accountLetter(name), style: t.textS),
                  ),
                  const SizedBox(width: LgSpace.s2),
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: t.text,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: LgSpace.s1),
                    Text(l10n.groupMe, style: t.textS.copyWith(color: c.text2)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (selected)
          LgIconButton(
            icon: LgIcons.x,
            label: l10n.groupClearPerson,
            onPressed: () => widget.group.selectUser(null),
          ),
      ],
    );
  }
}
