import 'package:flutter/widgets.dart';

/// What the address book or the team devices category puts on the devices page (M4,
/// `LEAPGATE.md` §10.11). The devices come from the core model's `shownPeers`; the page lists
/// them in the chosen view and sort order, as the other categories.
class AccountCategoryView {
  const AccountCategoryView({
    this.tools = const [],
    this.header,
    this.side,
    this.state,
  });

  /// After the page's own tools ("View", "Sort", "Select"): refresh, the tag filter switch.
  final List<Widget> tools;

  /// Above the list: the book switcher, the tag bar, the error banner.
  final Widget? header;

  /// Left of the list: the people of the team devices.
  final Widget? side;

  /// In place of the list: signed out, loading, no address book on the server, network error,
  /// empty. Null lists the devices.
  final Widget? state;
}
