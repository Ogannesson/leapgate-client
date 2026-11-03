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
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_list_chrome.dart';
import '../../../widgets/lg_people_list.dart';
import '../account/account.dart';
import '../account_category.dart';

// The team devices category (01 P1 blocks F and H, M4; `LEAPGATE.md` §10.11), after upstream's
// `common/widgets/my_group.dart`, without the device groups.

/// The people list, the tools and the states of the team devices category; the loading
/// skeleton in [view].
AccountCategoryView groupCategory(
  BuildContext context,
  TabOverlays overlays,
  PeerView view,
) {
  final l10n = AppLocalizations.of(context)!;
  final account = appCore.account;
  final group = appCore.group;
  if (!account.loggedIn) {
    return AccountCategoryView(
      state: SingleChildScrollView(
        child: LgEmptyState(
          l10n.groupSignedOut,
          icon: LgIcons.users,
          actionLabel: l10n.accountSignIn,
          actionIcon: LgIcons.login,
          onAction: () => showLoginDialog(overlays),
        ),
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
      state: SingleChildScrollView(
        child: LgEmptyState(
          error.kind == ApiErrorKind.network
              ? l10n.groupNetworkError
              : l10n.groupLoadFailed(serverText(error.text)),
          // A refusal of the server as the address book shows it.
          icon: error.kind == ApiErrorKind.network
              ? LgIcons.wifiOff
              : LgIcons.err,
          iconColor: LgTokens.of(context).colors.error,
          actionLabel: l10n.groupRetry,
          actionIcon: LgIcons.refresh,
          onAction: retry,
        ),
      ),
    );
  }
  return AccountCategoryView(
    tools: tools,
    header: error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: LgSpace.s4),
            child: LgBanner(
              tone: LgTone.error,
              slim: true,
              text: l10n.groupLoadFailed(serverText(error.text)),
              actionLabel: l10n.groupRetry,
              actionIcon: LgIcons.refresh,
              onAction: group.pull,
              dismissLabel: l10n.close,
              onDismiss: group.clearError,
            ),
          ),
    side: group.users.isEmpty ? null : _People(group: group),
    state: !group.loaded || group.loading && group.peers.isEmpty
        ? AccountLoading(view: view, label: l10n.recentLoading)
        // Never answered: the banner says why, the list says nothing more.
        : error != null && group.users.isEmpty && group.peers.isEmpty
        ? const SizedBox.shrink()
        : group.shownPeers.isEmpty
        ? SingleChildScrollView(
            child: LgEmptyState(
              group.peers.isEmpty ? l10n.groupEmpty : l10n.groupNoMatch,
              icon: LgIcons.users,
            ),
          )
        : null,
  );
}

/// The people (01 P1 block H): this user first with "（我）", a search, one person picked at a
/// time.
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
    final group = widget.group;
    final me = appCore.account.user?.name;
    final users = group.shownUsers;
    // Two people with the same display name show their user names (upstream `_buildUserItem`).
    final counts = <String, int>{};
    for (final u in users) {
      counts.update(u.displayNameOrName, (n) => n + 1, ifAbsent: () => 1);
    }
    String nameOf(AccountUser u) =>
        (counts[u.displayNameOrName] ?? 0) > 1 &&
            u.displayName.trim().isNotEmpty
        ? l10n.groupUserWithName(u.displayName, u.name)
        : u.displayNameOrName;
    return Padding(
      padding: const EdgeInsets.only(right: LgSpace.s4),
      child: SingleChildScrollView(
        child: LgPeopleList(
          people: [
            for (final u in users)
              LgPerson(
                id: u.name,
                initial: accountLetter(u.displayNameOrName),
                name: nameOf(u),
                isMe: u.name == me,
              ),
          ],
          selectedId: group.selectedUser,
          onSelect: group.selectUser,
          onClear: () => group.selectUser(null),
          searchController: _search,
          onSearchChanged: group.setSearch,
          searchPlaceholder: l10n.groupSearch,
          meLabel: l10n.groupMe,
          clearLabel: l10n.groupClearPerson,
          semanticLabel: l10n.groupPeople,
        ),
      ),
    );
  }
}
