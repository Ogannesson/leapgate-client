import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:get/get.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_canvas_parts.dart';
import 'toolbar/input_menu.dart';

/// What the input settings put over the image (01 P2 block C): the relative mouse hint at
/// the top centre, where the hidden toolbar was (upstream shows it at the end of the tab bar,
/// `desktop/pages/remote_tab_page.dart`), and the Android navigation bar
/// (`common/widgets/overlay.dart:173-260`, `common.dart:982-1016`), switched in the "输入"
/// menu. Fills the image area and places itself; where it draws nothing, pointer events reach
/// the image below.
class CanvasHints extends StatelessWidget {
  const CanvasHints({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ffi.ffiModel,
        appCore.options.flutter.listenable(kOptionShowMobileAction),
      ]),
      builder: (context, _) => Obx(() {
        final relative = ffi.inputModel.relativeMouseMode.value;
        final nav = androidNavBarApplies(ffi) && androidNavBarShown();
        return Stack(
          fit: StackFit.expand,
          children: [
            if (relative) const _RelativeMouseHint(),
            if (nav) _AndroidNavBar(ffi: ffi),
          ],
        );
      }),
    );
  }
}

/// `x-rel`: at the top centre, where the toolbar was.
class _RelativeMouseHint extends StatelessWidget {
  const _RelativeMouseHint();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: LgSpace.s3),
        child: LgCanvasHint(
          text: AppLocalizations.of(context)!.toolbarRelativeMouseHint,
        ),
      ),
    ),
  );
}

/// Back, home and recent apps, at the bottom centre, dragged anywhere over the image by its
/// grip. Hidden with "显示导航浮条" in the "输入" menu.
class _AndroidNavBar extends StatefulWidget {
  const _AndroidNavBar({required this.ffi});

  final FFI ffi;

  @override
  State<_AndroidNavBar> createState() => _AndroidNavBarState();
}

class _AndroidNavBarState extends State<_AndroidNavBar> {
  /// Offset from the bottom centre.
  Offset _moved = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final input = widget.ffi.inputModel;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: _moved,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: Semantics(
            container: true,
            label: l10n.toolbarAndroidNav,
            child: LgAndroidNavBar(
              backLabel: l10n.menuNavBack,
              homeLabel: l10n.menuNavHome,
              recentsLabel: l10n.menuNavRecents,
              dragLabel: l10n.toolbarMoveNav,
              onBack: input.onMobileBack,
              onHome: input.onMobileHome,
              onRecents: input.onMobileApps,
              onDrag: (delta) => setState(() => _moved += delta),
            ),
          ),
        ),
      ),
    );
  }
}
