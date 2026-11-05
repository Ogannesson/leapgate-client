// The title bar of a view (02 §2.2 block A, `.vt` in A-P7-文件传输.html): the narrow bar under the
// session tabs that the file, terminal and camera views carry. From the left: the view switch
// (the same control as on the remote desktop toolbar; "文件传输" shows the ring of the overall
// progress), the connection method with its details, and, at the far end, "断开". The parts are
// given; this draws the bar they stand in.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';

class LgViewBar extends StatelessWidget {
  const LgViewBar({
    super.key,
    required this.viewSwitch,
    required this.disconnectLabel,
    required this.onDisconnect,
    this.route,
    this.compact = false,
  });

  /// An [LgToolbarMenuButton] with `highlighted` (and `progress` or `alert` while files move).
  final Widget viewSwitch;

  /// An [LgToolbarRouteButton]; null until the connection method is known.
  final Widget? route;

  /// "断开". Disconnects this view only (02 §2.2 block A).
  final String disconnectLabel;
  final VoidCallback onDisconnect;

  /// The bar of the smallest window, a button and 8 px high where the ordinary one is a toolbar
  /// high (`.frame.mn .vt`); the page passes it by the height of the window. The detail mode's
  /// bar is lower than that already and stays as it is.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      height: compact
          ? math.min(t.sizes.bar, t.sizes.button + LgSpace.s2)
          : t.sizes.bar,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          viewSwitch,
          if (route != null) ...[const SizedBox(width: LgSpace.s2), route!],
          const Spacer(),
          LgButton(
            label: disconnectLabel,
            icon: LgIcons.power,
            kind: LgButtonKind.danger,
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }
}
