import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/address_book.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';

import '../../../l10n/app_localizations.dart';

// What the address book's texts and colours are made of (01 P1 block G, §7.6).

/// [book]'s name: the personal one in the UI's language.
String abBookName(AppLocalizations l10n, AbProfile book) =>
    appCore.addressBook.isPersonal(book) ? l10n.abPersonal : book.name;

/// "只读 / 可编辑 / 完全控制", and "所有者：‹名字›" for a shared book (01 P1 block G).
String abBookRights(AppLocalizations l10n, AbProfile book) {
  final ab = appCore.addressBook;
  if (ab.isPersonal(book)) return l10n.abRuleFullControl;
  final rule = switch (ShareRule.fromValue(book.rule)) {
    ShareRule.fullControl => l10n.abRuleFullControl,
    ShareRule.readWrite => l10n.abRuleReadWrite,
    _ => l10n.abRuleRead,
  };
  return book.owner.isEmpty ? rule : '$rule · ${l10n.abOwner(book.owner)}';
}

/// The second sentence of an error: what the server said, or that it could not be reached.
String abReason(AppLocalizations l10n, ApiError error) =>
    error.kind == ApiErrorKind.network
    ? l10n.abNetworkReason
    : l10n.abServerSaid(error.text.isEmpty ? error.kind.name : error.text);

/// A tag's colour in the current book; upstream's default when it has none.
Color abTagColor(String tag) =>
    Color(appCore.addressBook.tagColor(tag) ?? abDefaultTagColor(tag));
