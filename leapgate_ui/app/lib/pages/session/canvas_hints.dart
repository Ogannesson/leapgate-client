import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:get/get.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_session_toolbar.dart';
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

/// Placeholder for the designer's hint (`x-rel`).
class _RelativeMouseHint extends StatelessWidget {
  const _RelativeMouseHint();

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.only(top: LgSpace.s3),
          padding: const EdgeInsets.symmetric(
            horizontal: LgSpace.s4,
            vertical: LgSpace.s2,
          ),
          decoration: BoxDecoration(
            color: t.colors.float,
            borderRadius: BorderRadius.circular(LgRadius.r12),
            boxShadow: t.colors.shadow,
          ),
          child: Text(
            AppLocalizations.of(context)!.toolbarRelativeMouseHint,
            style: t.text.copyWith(color: t.colors.text),
          ),
        ),
      ),
    );
  }
}

/// Back, home, recent apps and hide, at the bottom centre, dragged anywhere over the image.
/// Placeholder for the designer's bar.
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
    final t = LgTokens.of(context);
    final input = widget.ffi.inputModel;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: _moved,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => _moved += d.delta),
          child: Semantics(
            container: true,
            label: l10n.toolbarAndroidNav,
            child: Container(
              margin: const EdgeInsets.only(bottom: 80),
              padding: const EdgeInsets.all(LgSpace.s1),
              decoration: BoxDecoration(
                color: t.colors.float,
                borderRadius: BorderRadius.circular(LgRadius.r16),
                boxShadow: t.colors.shadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LgToolbarButton(
                    icon: LgIcons.navBack,
                    label: l10n.menuNavBack,
                    onPressed: input.onMobileBack,
                  ),
                  LgToolbarButton(
                    icon: LgIcons.navHome,
                    label: l10n.menuNavHome,
                    onPressed: input.onMobileHome,
                  ),
                  LgToolbarButton(
                    icon: LgIcons.navRecents,
                    label: l10n.menuNavRecents,
                    onPressed: input.onMobileApps,
                  ),
                  LgToolbarButton(
                    icon: LgIcons.chevD,
                    label: l10n.toolbarHideNav,
                    dim: true,
                    onPressed: () => setAndroidNavBarShown(false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
