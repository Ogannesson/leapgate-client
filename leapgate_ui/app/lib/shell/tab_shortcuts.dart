import 'package:flutter/material.dart';

/// Shortcuts that work on every tab: next and previous tab, the home tab counted first (01
/// §2.1). Comes with the session shortcuts in M2b.
class TabShortcuts extends StatelessWidget {
  const TabShortcuts({
    super.key,
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
